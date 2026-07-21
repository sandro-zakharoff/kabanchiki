#!/usr/bin/env bash
# End-to-end check of the hryvnia -> acorn DATA migration (20260721120000).
#
# The SQL unit tests run against an already-converted schema, so they cannot
# cover the conversion itself. This does: it rewinds the local database to the
# migration right before the switch, plants realistic fractional balances
# (including a running job with an unsettled tail), applies the real migration
# file, and then checks the invariants that protect real money:
#
#   * balance = sum(ledger)                     — still exact, in whole acorns
#   * every balance lands on round(old balance) — no silent drift
#   * the drift is carried by ONE visible ledger entry, not by edited history
#   * nothing anywhere is fractional afterwards
#
#   bash supabase/tests/migration_acorn_check.sh
set -euo pipefail

DB_CONTAINER="${DB_CONTAINER:-supabase_db_kabanchiki}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
BEFORE=20260720120000
MIGRATION="$REPO/supabase/migrations/20260721120000_acorn_currency.sql"

psql() { docker exec -i "$DB_CONTAINER" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

echo "==> rewinding local db to $BEFORE (pre-acorn)"
( cd "$REPO" && npx --yes supabase@latest db reset --local --version "$BEFORE" >/dev/null 2>&1 )

echo "==> planting fractional hryvnia data"
psql <<'SQL'
insert into auth.users (id, aud, role, email, created_at, updated_at) values
  ('aaaaaaaa-0000-0000-0000-000000000001','authenticated','authenticated','m1@test.local', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000002','authenticated','authenticated','m2@test.local', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000003','authenticated','authenticated','m3@test.local', now(), now());
insert into public.profiles (id, username, display_name) values
  ('aaaaaaaa-0000-0000-0000-000000000001','mig1','Migrant One'),
  ('aaaaaaaa-0000-0000-0000-000000000002','mig2','Migrant Two'),
  ('aaaaaaaa-0000-0000-0000-000000000003','mig3','Migrant Three');

-- Two children close to the real production balances (~883.28), built from many
-- fractional entries so per-entry rounding drift is real and has to be absorbed.
insert into public.ledger_entries (child_id, amount, kind, source_type, note) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 500.00, 'task','task','a'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 183.33, 'job', 'job', 'b'),
  ('aaaaaaaa-0000-0000-0000-000000000001', 100.45, 'job', 'job', 'c'),
  ('aaaaaaaa-0000-0000-0000-000000000001',  99.50, 'bonus','bonus','d'),
  ('aaaaaaaa-0000-0000-0000-000000000002', 900.28, 'task','task','a'),
  ('aaaaaaaa-0000-0000-0000-000000000002', -17.00, 'withdrawal','withdrawal','b'),
  -- a child whose entries each round up: the drift must NOT reach the balance
  ('aaaaaaaa-0000-0000-0000-000000000003',   0.60, 'bonus','bonus','a'),
  ('aaaaaaaa-0000-0000-0000-000000000003',   0.60, 'bonus','bonus','b'),
  ('aaaaaaaa-0000-0000-0000-000000000003',   0.60, 'bonus','bonus','c'),
  ('aaaaaaaa-0000-0000-0000-000000000003',   0.60, 'bonus','bonus','d'),
  ('aaaaaaaa-0000-0000-0000-000000000003',   0.60, 'bonus','bonus','e');

-- a running job with a fractional rate and an unsettled tail
insert into public.jobs (id, title, hourly_rate, status)
values ('bbbbbbbb-0000-0000-0000-000000000001','Legacy job', 37.50, 'running');
insert into public.job_members (job_id, child_id, joined_at)
values ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001',
        now() - interval '5 hours');
insert into public.job_sessions (job_id, started_at, ended_at)
values ('bbbbbbbb-0000-0000-0000-000000000001', now() - interval '95 min', null);

-- The shape production actually has: a job settled several times already, so
-- credited_amount and settled_seconds are non-zero and the ledger already holds
-- fractional 'job' rows. This is what the migration must not disturb — the
-- credited_amount recompute reads these very rows back.
insert into public.jobs (id, title, hourly_rate, status)
values ('bbbbbbbb-0000-0000-0000-000000000002','Settled job', 41.30, 'running');
insert into public.job_members (job_id, child_id, joined_at, credited_amount, settled_seconds)
values ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000002',
        now() - interval '20 hours', 123.90, 10800);
insert into public.job_sessions (job_id, started_at, ended_at) values
  ('bbbbbbbb-0000-0000-0000-000000000002', now() - interval '19 hours', now() - interval '16 hours'),
  ('bbbbbbbb-0000-0000-0000-000000000002', now() - interval '40 min', null);
insert into public.ledger_entries (child_id, amount, kind, source_type, source_id, note) values
  ('aaaaaaaa-0000-0000-0000-000000000002', 82.60, 'job', 'job', 'bbbbbbbb-0000-0000-0000-000000000002', ''),
  ('aaaaaaaa-0000-0000-0000-000000000002', 41.30, 'job', 'job', 'bbbbbbbb-0000-0000-0000-000000000002', '');

-- fractional settings and open payouts
update public.app_config set min_withdrawal = 10.50, auto_approve_below = 5.25;
insert into public.withdrawals (child_id, amount, status)
values ('aaaaaaaa-0000-0000-0000-000000000002', 12.75, 'requested');
insert into public.tasks (child_id, title, reward_type, reward_amount, status, completion_mode)
values ('aaaaaaaa-0000-0000-0000-000000000002','Legacy task','fixed', 33.33, 'new', 'simple');

create table public.acorn_check_before as
select p.id as child_id, public.assignee_balance(p.id) as live_before
  from public.profiles p;
SQL

echo "==> applying the acorn migration"
psql < "$MIGRATION" > /dev/null

echo "==> checking invariants"
psql <<'SQL'
do $$
declare r record; v_fail int := 0; v_ledger integer; v_entries int;
begin
    for r in
        select b.child_id, b.live_before, a.ledger_before, a.target, a.adjustment
          from public.acorn_check_before b
          left join public.acorn_migration_audit a on a.child_id = b.child_id
    loop
        v_ledger := public.ledger_balance(r.child_id);

        -- the audit must exist for anyone who had a ledger
        if r.ledger_before is null and v_ledger <> 0 then
            raise warning 'FAIL % : no audit row but ledger %', r.child_id, v_ledger;
            v_fail := v_fail + 1;
            continue;
        end if;
        if r.ledger_before is null then continue; end if;

        -- balance = sum(ledger), and it is exactly the committed target
        if v_ledger <> r.target then
            raise warning 'FAIL % : ledger % <> target %', r.child_id, v_ledger, r.target;
            v_fail := v_fail + 1;
        end if;
        -- the target is the honest rounding of what was there before
        if r.target <> round(r.ledger_before) then
            raise warning 'FAIL % : target % <> round(before %)', r.child_id, r.target, r.ledger_before;
            v_fail := v_fail + 1;
        end if;
        -- drift is carried by a visible entry, never absorbed into history
        select count(*) into v_entries from public.ledger_entries
         where child_id = r.child_id and dedupe_key = 'acorn-rounding:' || r.child_id::text;
        if r.adjustment <> 0 and v_entries <> 1 then
            raise warning 'FAIL % : adjustment % but % rounding entries', r.child_id, r.adjustment, v_entries;
            v_fail := v_fail + 1;
        end if;
        if r.adjustment = 0 and v_entries <> 0 then
            raise warning 'FAIL % : no drift but a rounding entry exists', r.child_id;
            v_fail := v_fail + 1;
        end if;

        -- What the child actually SEES must survive: the live balance (ledger
        -- plus the running job tail) has to land on the rounding of what it was.
        -- A tolerance of 1 covers the seconds a running job accrues between the
        -- snapshot and the migration; it still catches any real loss.
        if abs(public.assignee_balance(r.child_id) - round(r.live_before)) > 1 then
            raise warning 'FAIL % : visible balance % -> % (was %)',
                r.child_id, r.live_before, public.assignee_balance(r.child_id), round(r.live_before);
            v_fail := v_fail + 1;
        end if;

        raise notice 'ok  % : ledger % -> %, visible % -> % (rounding entry %)',
            r.child_id, r.ledger_before, v_ledger,
            round(r.live_before), public.assignee_balance(r.child_id), coalesce(r.adjustment, 0);
    end loop;

    -- the live balance (ledger + running job tail) must be whole too
    if exists (select 1 from public.profiles p
                where public.assignee_balance(p.id) <> trunc(public.assignee_balance(p.id))) then
        raise warning 'FAIL: a live balance is fractional';
        v_fail := v_fail + 1;
    end if;

    if v_fail > 0 then
        raise exception '% MIGRATION CHECKS FAILED', v_fail;
    end if;
    raise notice '===== MIGRATION DATA CHECKS PASSED =====';
end; $$;
SQL

echo "==> settling the running job: the live balance must not move"
psql <<'SQL'
do $$
declare v_before integer; v_after integer;
begin
    v_before := public.assignee_balance('aaaaaaaa-0000-0000-0000-000000000001');
    perform public.settle_all_jobs();
    v_after  := public.assignee_balance('aaaaaaaa-0000-0000-0000-000000000001');
    if v_before <> v_after then
        raise exception 'FAIL: balance jumped on settle: % -> %', v_before, v_after;
    end if;
    if v_after <> public.ledger_balance('aaaaaaaa-0000-0000-0000-000000000001') then
        raise exception 'FAIL: after settling, balance <> sum(ledger)';
    end if;
    raise notice 'ok  settle does not move the balance (% acorns)', v_after;
end; $$;
SQL

echo "==> restoring a clean local database"
( cd "$REPO" && npx --yes supabase@latest db reset --local >/dev/null 2>&1 )
echo "PASS  acorn data migration"
