-- Kabanchiki: capture the OLD money state before later migrations drop the
-- columns it lives in (tasks.payment_status, job_members.withdrawn_since_reset,
-- the old withdrawals shape). This runs read-only — it changes no balances.
-- The gated reconstruction (…_balance_migrate_run) reads these snapshots and
-- posts the ledger entries once the owner has approved the dry-run.
--
-- On a fresh database these capture nothing (there is no old data yet).

create table public.balance_migration_snapshot_jobs (
    job_id          uuid,
    child_id        uuid,
    old_balance     numeric(12, 2) not null,   -- accrued, not-yet-withdrawn
    elapsed_seconds bigint not null,            -- worked seconds since joined_at
    primary key (job_id, child_id)
);

create table public.balance_migration_snapshot_tasks (
    task_id      uuid primary key,
    child_id     uuid not null,
    title        text not null default '',
    earned       numeric(12, 2) not null,
    paid         boolean not null,              -- already paid out in the old model
    completed_at timestamptz
);

create table public.balance_migration_snapshot_bonuses (
    bonus_id   uuid primary key,
    child_id   uuid not null,
    amount     numeric(12, 2) not null,
    note       text not null default '',
    created_at timestamptz
);

create table public.balance_migration_snapshot_withdrawals (
    id           uuid primary key,
    child_id     uuid not null,
    amount       numeric(12, 2) not null,
    requested_at timestamptz
);

-- ledger ids posted by the reconstruction, for a precise rollback
create table public.balance_migration_posted (
    entry_id bigint primary key
);

alter table public.balance_migration_snapshot_jobs        enable row level security;
alter table public.balance_migration_snapshot_tasks       enable row level security;
alter table public.balance_migration_snapshot_bonuses     enable row level security;
alter table public.balance_migration_snapshot_withdrawals enable row level security;
alter table public.balance_migration_posted               enable row level security;
-- no policies: service_role only

-- ---- capture (old columns/functions still present at this migration) ----

-- Jobs: accrued balance = earned-since-reset − withdrawn-since-reset (>= 0),
-- and total worked seconds since the member joined (basis for settled_seconds).
insert into public.balance_migration_snapshot_jobs (job_id, child_id, old_balance, elapsed_seconds)
select m.job_id, m.child_id,
    greatest(0, round(public.job_earned_seconds(m.job_id, m.child_id) / 3600.0 * j.hourly_rate, 2)
                - m.withdrawn_since_reset),
    (select coalesce(sum(greatest(0, extract(epoch from
              coalesce(s.ended_at, now()) - greatest(s.started_at, m.joined_at)))), 0)::bigint
       from public.job_sessions s
      where s.job_id = m.job_id
        and coalesce(s.ended_at, now()) > greatest(s.started_at, m.joined_at))
from public.job_members m
join public.jobs j on j.id = m.job_id;

-- Tasks: done tasks with an earned amount. paid ones are already settled.
insert into public.balance_migration_snapshot_tasks (task_id, child_id, title, earned, paid, completed_at)
select id, child_id, title, earned_amount, (payment_status = 'paid'), completed_at
from public.tasks
where status = 'done' and earned_amount is not null;

-- Bonuses: every existing grant (the ledger trigger only fires on new rows).
insert into public.balance_migration_snapshot_bonuses (bonus_id, child_id, amount, note, created_at)
select id, child_id, amount, coalesce(note, ''), created_at
from public.bonuses;

-- Withdrawals: only still-pending requests need reserving; approved/paid ones
-- were already netted out of the old per-job balance.
insert into public.balance_migration_snapshot_withdrawals (id, child_id, amount, requested_at)
select id, child_id, amount, requested_at
from public.withdrawals
where status = 'pending';
