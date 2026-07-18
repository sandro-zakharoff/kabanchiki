-- Parent-initiated payout: admin_create_withdrawal + the shared pay/confirm flow.
\set ON_ERROR_STOP on
begin;
create or replace function pg_temp.assert_eq(g numeric, w numeric, l text)
returns void language plpgsql as $$
begin if g is distinct from w then raise exception 'FAIL % : got % want %', l, g, w; end if;
raise notice 'ok  % = %', l, g; end; $$;
create or replace function pg_temp.assert_raises(s text, l text)
returns void language plpgsql as $$
begin begin execute s; exception when others then raise notice 'ok  % raised %', l, sqlerrm; return; end;
raise exception 'FAIL % : expected error', l; end; $$;
create or replace function pg_temp.as_child() returns void language sql as
$$ select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true); $$;
create or replace function pg_temp.as_admin() returns void language sql as
$$ select set_config('request.jwt.claims','',true); $$;

insert into auth.users (id, aud, role, email, created_at, updated_at)
values ('11111111-1111-1111-1111-111111111111','authenticated','authenticated','k@t.local', now(), now());
insert into public.profiles (id, username, display_name)
values ('11111111-1111-1111-1111-111111111111','kid','Kid');

-- fund balance +100 via bonus
select pg_temp.as_admin();
insert into public.bonuses (child_id, amount, note) values ('11111111-1111-1111-1111-111111111111', 100, 'seed');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 100.00, 'balance 100');

-- ---- parent initiates a 30 payout (approved + reserved) ----
select public.admin_create_withdrawal('11111111-1111-1111-1111-111111111111', 30) as w1 \gset
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 70.00, 'reserved -30 => 70');
select pg_temp.assert_eq((select (status='approved')::int from public.withdrawals where id=:'w1'), 1, 'w1 approved');
-- pay cash -> child confirms
select public.admin_withdrawal_pay(:'w1', 'cash', 'решта 0');
select pg_temp.assert_eq((select (status='paid' and method='cash')::int from public.withdrawals where id=:'w1'), 1, 'w1 paid cash');
select pg_temp.as_child();
select public.confirm_withdrawal(:'w1');
select pg_temp.assert_eq((select (status='confirmed')::int from public.withdrawals where id=:'w1'), 1, 'w1 confirmed');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 70.00, 'balance 70 after payout');

-- ---- guards ----
select pg_temp.as_admin();
select pg_temp.assert_raises('select public.admin_create_withdrawal(''11111111-1111-1111-1111-111111111111'', 200)', 'over-balance refused');
select pg_temp.assert_raises('select public.admin_create_withdrawal(''11111111-1111-1111-1111-111111111111'', 0)', 'zero refused');
-- a child cannot call it
select pg_temp.as_child();
select pg_temp.assert_raises('select public.admin_create_withdrawal(''11111111-1111-1111-1111-111111111111'', 10)', 'child refused (NOT_PARENT)');

-- ---- null amount = whole balance ----
select pg_temp.as_admin();
select public.admin_create_withdrawal('11111111-1111-1111-1111-111111111111', null) as w2 \gset
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 0.00, 'null => whole balance reserved => 0');
select pg_temp.assert_eq((select amount from public.withdrawals where id=:'w2'), 70.00, 'w2 = full 70');

select '===== ALL PAYOUT (PARENT) TESTS PASSED =====' as result;
rollback;
