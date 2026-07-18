\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_eq(p_got numeric, p_want numeric, p_label text)
returns void language plpgsql as $$
begin
    if p_got is distinct from p_want then raise exception 'FAIL % : got % want %', p_label, p_got, p_want; end if;
    raise notice 'ok  % = %', p_label, p_got;
end; $$;

create or replace function pg_temp.assert_raises(p_sql text, p_label text)
returns void language plpgsql as $$
begin
    begin execute p_sql; exception when others then raise notice 'ok  % raised %', p_label, sqlerrm; return; end;
    raise exception 'FAIL % : expected an error, none raised', p_label;
end; $$;

-- auth context helpers
create or replace function pg_temp.as_child() returns void language sql as
$$ select set_config('request.jwt.claims', '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}', true); $$;
create or replace function pg_temp.as_admin() returns void language sql as
$$ select set_config('request.jwt.claims', '', true); $$;   -- null uid == service_role path

-- child + config
insert into auth.users (id, aud, role, email, created_at, updated_at)
values ('11111111-1111-1111-1111-111111111111','authenticated','authenticated','kid1@test.local', now(), now());
insert into public.profiles (id, username, display_name)
values ('11111111-1111-1111-1111-111111111111','kid1','Kid One');
update public.app_config
   set min_withdrawal = 10, withdrawals_enabled = true, auto_approve_below = 0,
       require_receipt_for_card = false;

-- sanity: auth context works
select pg_temp.as_child();
do $$ begin if auth.uid() <> '11111111-1111-1111-1111-111111111111' then raise exception 'auth ctx broken: %', auth.uid(); end if; end $$;

-- fund the balance with a bonus (+100) — exercises the bonus->ledger trigger
select pg_temp.as_admin();
insert into public.bonuses (child_id, amount, note)
values ('11111111-1111-1111-1111-111111111111', 100, 'seed');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 100.00, 'balance after bonus');

-- ---- request 30 (child) ----
select pg_temp.as_child();
select public.request_withdrawal(30) as wd1 \gset
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 70.00, 'balance reserved (100-30)');
select pg_temp.assert_eq((select amount from public.withdrawals where id=:'wd1'), 30.00, 'wd1 amount');
select pg_temp.assert_eq((select (status='requested')::int from public.withdrawals where id=:'wd1'), 1, 'wd1 requested');

-- over-withdraw and below-minimum are refused
select pg_temp.assert_raises('select public.request_withdrawal(200)', 'over-balance refused');
select pg_temp.assert_raises('select public.request_withdrawal(5)',   'below-minimum refused');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 70.00, 'balance unchanged after refused');

-- ---- admin approve + pay cash + child confirm ----
select pg_temp.as_admin();
select public.admin_withdrawal_approve(:'wd1');
select pg_temp.assert_eq((select (status='approved')::int from public.withdrawals where id=:'wd1'), 1, 'wd1 approved');
select public.admin_withdrawal_pay(:'wd1', 'cash', 'здача 0');
select pg_temp.assert_eq((select (status='paid' and method='cash')::int from public.withdrawals where id=:'wd1'), 1, 'wd1 paid cash');
select pg_temp.as_child();
select public.confirm_withdrawal(:'wd1');
select pg_temp.assert_eq((select (status='confirmed')::int from public.withdrawals where id=:'wd1'), 1, 'wd1 confirmed');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 70.00, 'balance after payout still 70');

-- ---- request 20 then admin reject -> refund ----
select pg_temp.as_child();
select public.request_withdrawal(20) as wd2 \gset
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 50.00, 'balance reserved (70-20)');
select pg_temp.as_admin();
select public.admin_withdrawal_reject(:'wd2', 'недостатньо коштів у касі');
select pg_temp.assert_eq((select (status='rejected')::int from public.withdrawals where id=:'wd2'), 1, 'wd2 rejected');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 70.00, 'balance refunded (back to 70)');

-- reject refund is idempotent (dedupe on withdrawal-refund key)
select pg_temp.assert_eq(coalesce(public.ledger_post(
    '11111111-1111-1111-1111-111111111111', 20, 'reversal','withdrawal', :'wd2',
    'dup', 'withdrawal-refund:' || :'wd2', now()), -1)::numeric, -1, 'refund dedupe');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 70.00, 'balance unchanged after dup refund');

-- ---- ledger sum matches (100 -30 -20 +20 = 70) ----
select pg_temp.assert_eq((select sum(amount) from public.ledger_entries
    where child_id='11111111-1111-1111-1111-111111111111'), 70.00, 'ledger sum == 70');

select '===== ALL PAYOUT TESTS PASSED =====' as result;
rollback;
