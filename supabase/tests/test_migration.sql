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
    raise exception 'FAIL % : expected an error', p_label;
end; $$;

-- two assignees
insert into auth.users (id, aud, role, email, created_at, updated_at) values
 ('11111111-1111-1111-1111-111111111111','authenticated','authenticated','k1@t.local', now(), now()),
 ('22222222-2222-2222-2222-222222222222','authenticated','authenticated','k2@t.local', now(), now());
insert into public.profiles (id, username, display_name) values
 ('11111111-1111-1111-1111-111111111111','kid1','Kid One'),
 ('22222222-2222-2222-2222-222222222222','kid2','Kid Two');
insert into public.jobs (id, title, hourly_rate, status)
 values ('33333333-3333-3333-3333-333333333333','J', 60, 'idle');
insert into public.job_members (job_id, child_id, joined_at) values
 ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111', now() - interval '2 hours'),
 ('33333333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222', now() - interval '2 hours');

-- simulate what the 100050 capture would have produced from old data
insert into public.balance_migration_snapshot_jobs (job_id, child_id, old_balance, elapsed_seconds) values
 ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111', 30.00, 3600),
 ('33333333-3333-3333-3333-333333333333','22222222-2222-2222-2222-222222222222', 45.00, 5400);
insert into public.balance_migration_snapshot_tasks (task_id, child_id, title, earned, paid, completed_at) values
 ('44444444-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111','T-unpaid', 25.00, false, now() - interval '1 day'),
 ('44444444-0000-0000-0000-000000000002','11111111-1111-1111-1111-111111111111','T-paid',   10.00, true,  now() - interval '2 day');
insert into public.balance_migration_snapshot_bonuses (bonus_id, child_id, amount, note, created_at) values
 ('55555555-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111', 50.00, 'seed bonus', now() - interval '3 day');
insert into public.balance_migration_snapshot_withdrawals (id, child_id, amount, requested_at) values
 ('66666666-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111', 20.00, now() - interval '1 hour');

-- expected kid1 = 30 + 25 + 50 - 20 = 85 ; kid2 = 45
select pg_temp.assert_eq((select net from public.balance_migration_dryrun()
    where child_id='11111111-1111-1111-1111-111111111111'), 85.00, 'dryrun kid1 net');
select pg_temp.assert_eq((select net from public.balance_migration_dryrun()
    where child_id='22222222-2222-2222-2222-222222222222'), 45.00, 'dryrun kid2 net');

-- apply
select public.run_balance_migration();
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 85.00, 'ledger kid1');
select pg_temp.assert_eq(public.ledger_balance('22222222-2222-2222-2222-222222222222'), 45.00, 'ledger kid2');
-- balance == ledger (no live tail: no sessions, settled clamps)
select pg_temp.assert_eq(public.assignee_balance('11111111-1111-1111-1111-111111111111'), 85.00, 'balance==ledger kid1');
-- paid task was skipped (only the unpaid one credited)
select pg_temp.assert_eq((select count(*)::numeric from public.ledger_entries where kind='task'
    and child_id='11111111-1111-1111-1111-111111111111'), 1, 'only unpaid task credited');
-- job baselines set
select pg_temp.assert_eq((select credited_amount from public.job_members
    where child_id='11111111-1111-1111-1111-111111111111'), 30.00, 'job credited set');

-- idempotency guard
select pg_temp.assert_raises('select public.run_balance_migration()', 're-run guarded');

-- verify: every assignee balance matches its ledger
select pg_temp.assert_eq((select count(*)::numeric from public.balance_migration_verify() where not matches),
    0, 'verify: all balances match ledger');

-- rollback restores zero
select public.rollback_balance_migration();
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 0.00, 'rollback kid1 -> 0');
select pg_temp.assert_eq((select credited_amount from public.job_members
    where child_id='11111111-1111-1111-1111-111111111111'), 0.00, 'rollback resets job credited');
-- can re-run after rollback
select public.run_balance_migration();
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'), 85.00, 're-run after rollback');

select '===== ALL MIGRATION TESTS PASSED =====' as result;
rollback;
