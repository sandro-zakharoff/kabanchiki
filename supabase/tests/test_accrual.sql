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

select pg_temp.assert_eq(public.job_member_unsettled_acorns(
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

-- ============================================================ acorns are indivisible

-- ---- the money columns are integer, so a fraction cannot even be stored ----
select pg_temp.assert_eq((
    select count(*)::numeric from information_schema.columns
     where table_schema = 'public' and data_type <> 'integer'
       and (table_name, column_name) in (values
           ('ledger_entries', 'amount'), ('withdrawals', 'amount'), ('bonuses', 'amount'),
           ('tasks', 'reward_amount'), ('tasks', 'earned_amount'), ('jobs', 'hourly_rate'),
           ('job_members', 'credited_amount'),
           ('app_config', 'min_withdrawal'), ('app_config', 'auto_approve_below'))),
    0, 'every money column is integer');

-- ---- fractional input is refused, not silently rounded ----
do $$
begin
    perform public.acorns_exact(10.5);
    raise exception 'accepted a fraction';
exception when others then
    if sqlerrm <> 'FRACTIONAL_AMOUNT' then raise; end if;
    raise notice 'ok  acorns_exact rejects 10.5';
end; $$;

do $$
begin
    perform public.ledger_post('11111111-1111-1111-1111-111111111111', 1.5, 'adjustment',
                               'manual', null, 'fraction', null, now());
    raise exception 'accepted a fraction';
exception when others then
    if sqlerrm <> 'FRACTIONAL_AMOUNT' then raise; end if;
    raise notice 'ok  ledger_post rejects 1.5';
end; $$;

-- ============================================================ the remainder must not evaporate
--
-- A job paying 1 acorn/hour worked in six 10-minute slices. Each slice on its own
-- is worth 1/6 of an acorn: flooring per settlement would credit 0 six times over
-- and the whole hour of work would vanish. The accumulator has to carry it.

insert into auth.users (id, aud, role, email, created_at, updated_at)
values ('77777777-7777-7777-7777-777777777777','authenticated','authenticated','kid3@test.local', now(), now());
insert into public.profiles (id, username, display_name)
values ('77777777-7777-7777-7777-777777777777','kid3','Kid Three');
insert into public.jobs (id, title, hourly_rate, status)
values ('66666666-6666-6666-6666-666666666666','Slow job', 1, 'running');
insert into public.job_members (job_id, child_id, joined_at)
values ('66666666-6666-6666-6666-666666666666','77777777-7777-7777-7777-777777777777',
        now() - interval '10 hours');

-- five slices: still 0 whole acorns, but nothing may be lost
do $$
declare i int;
begin
    for i in 1..5 loop
        insert into public.job_sessions (job_id, started_at, ended_at)
        values ('66666666-6666-6666-6666-666666666666',
                now() - interval '120 min' + ((i - 1) * interval '10 min'),
                now() - interval '120 min' + (i * interval '10 min'));
        perform public.settle_job_member('66666666-6666-6666-6666-666666666666',
                                         '77777777-7777-7777-7777-777777777777');
    end loop;
end; $$;

select pg_temp.assert_eq(public.ledger_balance('77777777-7777-7777-7777-777777777777'),
    0, 'five 10-min slices at 1/h: nothing whole yet');
select pg_temp.assert_eq((select accrued_acorn_seconds from public.job_members
     where job_id='66666666-6666-6666-6666-666666666666'
       and child_id='77777777-7777-7777-7777-777777777777'),
    3000, 'but all 3000 acorn-seconds are banked, not rounded away');

-- the sixth slice completes the hour: the carried remainder matures into 1 acorn
insert into public.job_sessions (job_id, started_at, ended_at)
values ('66666666-6666-6666-6666-666666666666', now() - interval '70 min', now() - interval '60 min');
select pg_temp.assert_eq(public.settle_job_member(
    '66666666-6666-6666-6666-666666666666','77777777-7777-7777-7777-777777777777'),
    1, 'sixth slice matures the carried remainder into 1 acorn');
select pg_temp.assert_eq(public.ledger_balance('77777777-7777-7777-7777-777777777777'),
    1, 'a full hour at 1/h pays exactly 1, however often it was settled');

-- ---- the live tail is exactly what the next settlement will post ----
-- (otherwise the ticking balance in the clients jumps when the cron fires)
insert into public.job_sessions (job_id, started_at, ended_at)
values ('66666666-6666-6666-6666-666666666666', now() - interval '90 min', null);
select pg_temp.assert_eq(
    public.job_member_unsettled_acorns('66666666-6666-6666-6666-666666666666',
                                       '77777777-7777-7777-7777-777777777777'),
    1, 'live tail after 90 more min at 1/h');
select pg_temp.assert_eq(public.settle_job_member(
    '66666666-6666-6666-6666-666666666666','77777777-7777-7777-7777-777777777777'),
    1, 'settle posts exactly the tail that was shown — no jump');

-- ---- a carried remainder keeps the price it was earned at ----
--
-- 30 min at 1/h (half an acorn, carried) then 30 min at 5/h (two and a half).
-- Correct total is 3. Re-pricing the whole hour at 5/h would pay 5.
insert into auth.users (id, aud, role, email, created_at, updated_at)
values ('88888888-8888-8888-8888-888888888888','authenticated','authenticated','kid4@test.local', now(), now());
insert into public.profiles (id, username, display_name)
values ('88888888-8888-8888-8888-888888888888','kid4','Kid Four');
insert into public.jobs (id, title, hourly_rate, status)
values ('99999999-9999-9999-9999-999999999999','Raise job', 1, 'running');
insert into public.job_members (job_id, child_id, joined_at)
values ('99999999-9999-9999-9999-999999999999','88888888-8888-8888-8888-888888888888',
        now() - interval '10 hours');
insert into public.job_sessions (job_id, started_at, ended_at)
values ('99999999-9999-9999-9999-999999999999', now() - interval '60 min', now() - interval '30 min');
select public.settle_job_member('99999999-9999-9999-9999-999999999999','88888888-8888-8888-8888-888888888888');
select pg_temp.assert_eq(public.ledger_balance('88888888-8888-8888-8888-888888888888'),
    0, 'half an acorn earned: nothing paid yet, remainder carried');

update public.jobs set hourly_rate = 5 where id = '99999999-9999-9999-9999-999999999999';
insert into public.job_sessions (job_id, started_at, ended_at)
values ('99999999-9999-9999-9999-999999999999', now() - interval '30 min', now());
select public.settle_job_member('99999999-9999-9999-9999-999999999999','88888888-8888-8888-8888-888888888888');
select pg_temp.assert_eq(public.ledger_balance('88888888-8888-8888-8888-888888888888'),
    3, 'carried 0.5@1 + 2.5@5 = 3 (not 5: the remainder kept its old price)');

select '===== ALL ACCRUAL TESTS PASSED =====' as result;
rollback;
