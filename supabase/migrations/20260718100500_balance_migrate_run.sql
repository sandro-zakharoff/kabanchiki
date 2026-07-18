-- Kabanchiki: gated reconstruction of personal balances from the snapshot.
-- These functions are NOT run automatically. The owner reviews
-- balance_migration_dryrun(), and only then run_balance_migration() posts the
-- ledger entries in one transaction. rollback_balance_migration() undoes it.
-- Everything is idempotent / reversible and service_role-only.

-- ---- dry-run: per-assignee breakdown, writes nothing ----
create or replace function public.balance_migration_dryrun()
returns table (
    child_id   uuid,
    child_name text,
    jobs       numeric,
    tasks      numeric,
    bonuses    numeric,
    reserved   numeric,
    net        numeric
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select p.id, p.display_name,
        coalesce((select sum(old_balance) from public.balance_migration_snapshot_jobs where child_id = p.id), 0),
        coalesce((select sum(earned) from public.balance_migration_snapshot_tasks where child_id = p.id and not paid), 0),
        coalesce((select sum(amount) from public.balance_migration_snapshot_bonuses where child_id = p.id), 0),
        coalesce((select sum(amount) from public.balance_migration_snapshot_withdrawals where child_id = p.id), 0),
        coalesce((select sum(old_balance) from public.balance_migration_snapshot_jobs where child_id = p.id), 0)
      + coalesce((select sum(earned) from public.balance_migration_snapshot_tasks where child_id = p.id and not paid), 0)
      + coalesce((select sum(amount) from public.balance_migration_snapshot_bonuses where child_id = p.id), 0)
      - coalesce((select sum(amount) from public.balance_migration_snapshot_withdrawals where child_id = p.id), 0)
    from public.profiles p
    order by p.display_name;
$$;

-- ---- apply: post the ledger, set job accrual baselines. Idempotent + guarded. ----
create or replace function public.run_balance_migration()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    r record;
    v_id bigint;
    v_count int := 0;
begin
    if exists (select 1 from public.balance_migration_posted) then
        raise exception 'ALREADY_RUN (roll back first if you must re-run)';
    end if;

    -- Jobs: credit the accrued balance; mark all past time as settled so future
    -- accrual only credits NEW work (no double count).
    for r in select * from public.balance_migration_snapshot_jobs loop
        if r.old_balance <> 0 then
            v_id := public.ledger_post(r.child_id, r.old_balance, 'job', 'job', r.job_id,
                'перенесення балансу роботи', 'migrate-job:' || r.job_id::text || ':' || r.child_id::text, now());
            if v_id is not null then insert into public.balance_migration_posted values (v_id); v_count := v_count + 1; end if;
        end if;
        update public.job_members
           set settled_seconds = r.elapsed_seconds, credited_amount = r.old_balance
         where job_id = r.job_id and child_id = r.child_id;
    end loop;

    -- Tasks: done-and-unpaid rewards -> balance, with original dates.
    for r in select * from public.balance_migration_snapshot_tasks where not paid loop
        v_id := public.ledger_post(r.child_id, r.earned, 'task', 'task', r.task_id,
            r.title, 'task:' || r.task_id::text, coalesce(r.completed_at, now()));
        if v_id is not null then insert into public.balance_migration_posted values (v_id); v_count := v_count + 1; end if;
    end loop;

    -- Bonuses: every existing grant, with original dates.
    for r in select * from public.balance_migration_snapshot_bonuses loop
        v_id := public.ledger_post(r.child_id, r.amount, 'bonus', 'bonus', r.bonus_id,
            r.note, 'bonus:' || r.bonus_id::text, coalesce(r.created_at, now()));
        if v_id is not null then insert into public.balance_migration_posted values (v_id); v_count := v_count + 1; end if;
    end loop;

    -- Pending withdrawals: reserve the requested amount (debit).
    for r in select * from public.balance_migration_snapshot_withdrawals loop
        v_id := public.ledger_post(r.child_id, -r.amount, 'withdrawal', 'withdrawal', r.id,
            'резерв виводу (перенесення)', 'withdrawal:' || r.id::text, coalesce(r.requested_at, now()));
        if v_id is not null then insert into public.balance_migration_posted values (v_id); v_count := v_count + 1; end if;
    end loop;

    return format('balance migration applied: %s ledger entries posted', v_count);
end;
$$;

-- ---- rollback: delete posted entries, reset job baselines ----
create or replace function public.rollback_balance_migration()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count int;
begin
    delete from public.ledger_entries
     where id in (select entry_id from public.balance_migration_posted);
    get diagnostics v_count = row_count;
    update public.job_members set settled_seconds = 0, credited_amount = 0;
    delete from public.balance_migration_posted;
    return format('rolled back: %s ledger entries removed', v_count);
end;
$$;

-- ---- verify: cached balance equals the ledger sum for every assignee ----
create or replace function public.balance_migration_verify()
returns table (child_id uuid, child_name text, balance numeric, matches boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
    return query
    select p.id, p.display_name,
        public.reconcile_assignee(p.id),
        public.reconcile_assignee(p.id) = public.ledger_balance(p.id)
    from public.profiles p order by p.display_name;
end;
$$;

revoke all on function public.balance_migration_dryrun() from public, anon, authenticated;
revoke all on function public.run_balance_migration() from public, anon, authenticated;
revoke all on function public.rollback_balance_migration() from public, anon, authenticated;
revoke all on function public.balance_migration_verify() from public, anon, authenticated;
