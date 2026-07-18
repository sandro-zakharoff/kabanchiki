-- Deterministic money tests: wrapped in one transaction so now() is frozen and
-- every duration is exact. Rolls back at the end (repeatable).
\set ON_ERROR_STOP on
begin;

-- helper: assert two numerics equal
create or replace function pg_temp.assert_eq(p_got numeric, p_want numeric, p_label text)
returns void language plpgsql as $$
begin
    if p_got is distinct from p_want then
        raise exception 'FAIL % : got % want %', p_label, p_got, p_want;
    end if;
    raise notice 'ok  % = %', p_label, p_got;
end; $$;

-- test child
insert into auth.users (id, aud, role, email, created_at, updated_at)
values ('11111111-1111-1111-1111-111111111111', 'authenticated', 'authenticated',
        'kid1@test.local', now(), now());
insert into public.profiles (id, username, display_name)
values ('11111111-1111-1111-1111-111111111111', 'kid1', 'Kid One');

-- ---- job accrual (rate 60/h => 1/min) ----
insert into public.jobs (id, title, hourly_rate, status)
values ('22222222-2222-2222-2222-222222222222', 'Test job', 60, 'running');
insert into public.job_members (job_id, child_id, joined_at)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111',
        now() - interval '2 hours');
-- closed session: 30 minutes of work => 30.00
insert into public.job_sessions (job_id, started_at, ended_at)
values ('22222222-2222-2222-2222-222222222222', now() - interval '60 min', now() - interval '30 min');

select pg_temp.assert_eq(public.job_member_unsettled_money(
    '22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111'),
    30.00, 'unsettled money after 30min closed');

select pg_temp.assert_eq(public.settle_job_member(
    '22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111'),
    30.00, 'settle delta #1');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'),
    30.00, 'ledger after settle #1');
-- idempotent: re-settle posts 0
select pg_temp.assert_eq(public.settle_job_member(
    '22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111'),
    0.00, 'settle delta #2 (idempotent)');
select pg_temp.assert_eq((select count(*)::numeric from public.ledger_entries
    where child_id='11111111-1111-1111-1111-111111111111' and kind='job'),
    1, 'exactly one job ledger row');

-- open running session: 10 more minutes => live tail 10.00
insert into public.job_sessions (job_id, started_at, ended_at)
values ('22222222-2222-2222-2222-222222222222', now() - interval '10 min', null);
select pg_temp.assert_eq(public.assignee_balance('11111111-1111-1111-1111-111111111111'),
    40.00, 'live balance = ledger 30 + tail 10');
select pg_temp.assert_eq(public.settle_job_member(
    '22222222-2222-2222-2222-222222222222','11111111-1111-1111-1111-111111111111'),
    10.00, 'settle delta #3 (running tail)');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'),
    40.00, 'ledger after settle #3');

-- ---- task credit on approve ----
insert into public.tasks (id, child_id, title, reward_type, reward_amount, status,
    earned_amount, completion_mode)
values ('33333333-3333-3333-3333-333333333333','11111111-1111-1111-1111-111111111111',
    'Test task', 'fixed', 25, 'submitted', 25, 'simple');
select public.task_review('33333333-3333-3333-3333-333333333333','approve', null);
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'),
    65.00, 'ledger after task approve (+25)');
select pg_temp.assert_eq((select count(*)::numeric from public.ledger_entries
    where source_type='task' and source_id='33333333-3333-3333-3333-333333333333'),
    1, 'exactly one task ledger row');

-- idempotency of ledger_post dedupe (simulate a retry)
select pg_temp.assert_eq(coalesce(public.ledger_post(
    '11111111-1111-1111-1111-111111111111', 25, 'task', 'task',
    '33333333-3333-3333-3333-333333333333', 'retry', 'task:33333333-3333-3333-3333-333333333333', now()),
    -1)::numeric, -1, 'dedupe: retry returns null');
select pg_temp.assert_eq(public.ledger_balance('11111111-1111-1111-1111-111111111111'),
    65.00, 'ledger unchanged after dedupe retry');

-- ---- reconciliation invariant: balance == sum(ledger) after settle ----
select pg_temp.assert_eq(public.reconcile_assignee('11111111-1111-1111-1111-111111111111'),
    public.assignee_balance('11111111-1111-1111-1111-111111111111'),
    'reconcile == live balance (all settled)');

-- ---- rate change must NOT reprice already-earned time ----
insert into auth.users (id, aud, role, email, created_at, updated_at)
values ('44444444-4444-4444-4444-444444444444','authenticated','authenticated','kid2@test.local', now(), now());
insert into public.profiles (id, username, display_name)
values ('44444444-4444-4444-4444-444444444444','kid2','Kid Two');
insert into public.jobs (id, title, hourly_rate, status)
values ('55555555-5555-5555-5555-555555555555','Rate job', 60, 'running');
insert into public.job_members (job_id, child_id, joined_at)
values ('55555555-5555-5555-5555-555555555555','44444444-4444-4444-4444-444444444444', now() - interval '4 hours');
-- 30 min at rate 60 => 30
insert into public.job_sessions (job_id, started_at, ended_at)
values ('55555555-5555-5555-5555-555555555555', now() - interval '60 min', now() - interval '30 min');
select public.settle_job_member('55555555-5555-5555-5555-555555555555','44444444-4444-4444-4444-444444444444');
select pg_temp.assert_eq(public.ledger_balance('44444444-4444-4444-4444-444444444444'), 30.00, 'rate: booked 30 at old rate');
-- raise rate to 120 (fires the settle-on-rate-change trigger; 0 unsettled here)
update public.jobs set hourly_rate = 120 where id = '55555555-5555-5555-5555-555555555555';
-- another 30 min, now at rate 120 => 60
insert into public.job_sessions (job_id, started_at, ended_at)
values ('55555555-5555-5555-5555-555555555555', now() - interval '30 min', now());
select public.settle_job_member('55555555-5555-5555-5555-555555555555','44444444-4444-4444-4444-444444444444');
-- 30 (old) + 60 (new) = 90, NOT 120 (which repricing would give)
select pg_temp.assert_eq(public.ledger_balance('44444444-4444-4444-4444-444444444444'), 90.00, 'rate: 30@60 + 60@120 = 90 (no repricing)');

select '===== ALL ACCRUAL TESTS PASSED =====' as result;
rollback;
