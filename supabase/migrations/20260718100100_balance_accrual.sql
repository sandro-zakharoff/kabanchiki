-- Kabanchiki: money now flows into the personal ledger.
--
--  * Jobs (Роботи): hourly earnings are credited to the assignee's balance as
--    they accrue, via idempotent "settlement" (a cumulative credited_amount so
--    rounding never drifts and re-settling is a no-op).
--  * Tasks (Завдання): approving a task credits its reward to the balance
--    exactly once (dedupe key). payment_status is removed entirely.
--  * jobs.min_withdrawal is removed (a global minimum replaces it — settings).

-- ============================================================ job accrual
--
-- Accrual is tracked in SECONDS, not cumulative money, so that changing a job's
-- hourly rate prices past time at the OLD rate and only future time at the new
-- rate (no retroactive repricing). settled_seconds is the seconds already
-- credited; the unsettled remainder is priced at the current rate and credited
-- on settlement. Deltas are therefore never negative.

alter table public.job_members
    add column if not exists credited_amount numeric(12, 2) not null default 0,   -- money booked so far
    add column if not exists settled_seconds bigint         not null default 0;   -- seconds booked so far

-- Total seconds a member has worked since they joined (across all sessions).
create or replace function public.job_member_elapsed_seconds(p_job_id uuid, p_child_id uuid)
returns bigint
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_from timestamptz; v_seconds bigint;
begin
    select m.joined_at into v_from from public.job_members m
     where m.job_id = p_job_id and m.child_id = p_child_id;
    if not found then return 0; end if;
    select coalesce(sum(greatest(0, extract(epoch from
             coalesce(s.ended_at, now()) - greatest(s.started_at, v_from)))), 0)::bigint
      into v_seconds
      from public.job_sessions s
     where s.job_id = p_job_id
       and coalesce(s.ended_at, now()) > greatest(s.started_at, v_from);
    return v_seconds;
end;
$$;

-- Money not yet credited: the unsettled seconds priced at the CURRENT rate.
create or replace function public.job_member_unsettled_money(p_job_id uuid, p_child_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_rate numeric(12, 2); v_settled bigint; v_elapsed bigint;
begin
    select j.hourly_rate, m.settled_seconds into v_rate, v_settled
      from public.job_members m join public.jobs j on j.id = m.job_id
     where m.job_id = p_job_id and m.child_id = p_child_id;
    if not found then return 0; end if;
    v_elapsed := public.job_member_elapsed_seconds(p_job_id, p_child_id);
    return round(greatest(0, v_elapsed - v_settled) / 3600.0 * v_rate, 2);
end;
$$;

-- Crystallise a member's unsettled accrual into one ledger entry. Idempotent:
-- once settled_seconds catches up to elapsed, repeat calls post 0.
create or replace function public.settle_job_member(p_job_id uuid, p_child_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    m public.job_members;
    v_elapsed bigint;
    v_rate numeric(12, 2);
    v_money numeric(12, 2);
begin
    select * into m from public.job_members
     where job_id = p_job_id and child_id = p_child_id for update;
    if not found then return 0; end if;
    select hourly_rate into v_rate from public.jobs where id = p_job_id;
    v_elapsed := public.job_member_elapsed_seconds(p_job_id, p_child_id);
    if v_elapsed <= m.settled_seconds then return 0; end if;
    v_money := round((v_elapsed - m.settled_seconds) / 3600.0 * v_rate, 2);
    if v_money <> 0 then
        perform public.ledger_post(p_child_id, v_money, 'job', 'job', p_job_id, '', null, now());
    end if;
    update public.job_members
       set settled_seconds = v_elapsed, credited_amount = credited_amount + v_money
     where job_id = p_job_id and child_id = p_child_id;
    return v_money;
end;
$$;

create or replace function public.settle_job(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r record;
begin
    for r in select child_id from public.job_members where job_id = p_job_id loop
        perform public.settle_job_member(p_job_id, r.child_id);
    end loop;
end;
$$;

-- Settle every member of every running job. Called by the settle-jobs cron so
-- the ledger stays fresh while a job runs (earnings "reflected as they accrue").
create or replace function public.settle_all_jobs()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r record;
begin
    for r in select job_id, child_id from public.job_members loop
        perform public.settle_job_member(r.job_id, r.child_id);
    end loop;
end;
$$;

revoke all on function public.settle_job_member(uuid, uuid) from public, anon, authenticated;
revoke all on function public.settle_job(uuid) from public, anon, authenticated;
revoke all on function public.settle_all_jobs() from public, anon, authenticated;

-- When a member is removed, capture their final earnings before the row goes.
create or replace function public.trg_job_member_final_settle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_money numeric(12, 2);
begin
    v_money := public.job_member_unsettled_money(old.job_id, old.child_id);
    if v_money <> 0 then
        perform public.ledger_post(old.child_id, v_money, 'job', 'job', old.job_id,
            'final', null, now());
    end if;
    return old;
end;
$$;
create trigger job_member_final_settle before delete on public.job_members
for each row execute function public.trg_job_member_final_settle();

-- ============================================================ balance

-- Full live balance = credited ledger + uncredited job accrual (ticks live).
create or replace function public.assignee_balance(p_child uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_tail numeric(12, 2);
begin
    if auth.uid() is not null
       and not public.is_parent(auth.uid())
       and auth.uid() <> p_child then
        raise exception 'FORBIDDEN';
    end if;
    select coalesce(sum(public.job_member_unsettled_money(m.job_id, m.child_id)), 0)
      into v_tail
      from public.job_members m where m.child_id = p_child;
    return public.ledger_balance(p_child) + coalesce(v_tail, 0);
end;
$$;
grant execute on function public.assignee_balance(uuid) to authenticated;

-- Reconciliation: settle all of a child's jobs, then the balance equals the
-- ledger sum exactly (the invariant "balance = sum of operations").
create or replace function public.reconcile_assignee(p_child uuid)
returns numeric
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r record;
begin
    for r in select job_id from public.job_members where child_id = p_child loop
        perform public.settle_job_member(r.job_id, p_child);
    end loop;
    return public.ledger_balance(p_child);
end;
$$;
revoke all on function public.reconcile_assignee(uuid) from public, anon, authenticated;

-- ============================================================ job_member_stats (reshaped)

drop view if exists public.job_member_stats;
create view public.job_member_stats
with (security_invoker = true) as
select
    m.job_id,
    m.child_id,
    j.title,
    j.description,
    j.hourly_rate,
    j.status,
    m.joined_at,
    m.credited_amount,
    (select coalesce(sum(extract(epoch from coalesce(s.ended_at, now()) - s.started_at)), 0)
       from public.job_sessions s where s.job_id = m.job_id)::bigint as total_seconds,
    public.job_member_elapsed_seconds(m.job_id, m.child_id) as earned_seconds,
    (m.credited_amount + public.job_member_unsettled_money(m.job_id, m.child_id)) as earned_total,
    (select s.started_at from public.job_sessions s
      where s.job_id = m.job_id and s.ended_at is null limit 1) as running_since,
    (select max(s.ended_at) from public.job_sessions s
      where s.job_id = m.job_id and s.ended_at is not null) as last_stopped_at,
    now() as snapshot_at
from public.job_members m
join public.jobs j on j.id = m.job_id;
alter table public.job_member_stats owner to postgres;

drop function if exists public.job_earned_seconds(uuid, uuid);

-- ============================================================ settle on job stop / archive

create or replace function public.admin_job_stop(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare j public.jobs;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into j from public.jobs where id = p_job_id for update;
    if not found then raise exception 'JOB_NOT_FOUND'; end if;
    if j.status <> 'running' then raise exception 'INVALID_STATUS'; end if;
    update public.job_sessions set ended_at = now() where job_id = j.id and ended_at is null;
    update public.jobs set status = 'idle' where id = j.id;
    perform public.settle_job(j.id);              -- crystallise earnings on stop
end;
$$;

create or replace function public.admin_job_archive(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    update public.job_sessions set ended_at = now() where job_id = p_job_id and ended_at is null;
    update public.jobs set status = 'archived' where id = p_job_id;
    perform public.settle_job(p_job_id);          -- final crystallisation
end;
$$;

-- ============================================================ tasks: credit on approve

create or replace function public.task_review(
    p_task_id uuid,
    p_action text,
    p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into t from public.tasks where id = p_task_id for update;
    if not found then raise exception 'TASK_NOT_FOUND'; end if;
    if t.status <> 'submitted' then raise exception 'INVALID_STATUS'; end if;

    if p_action = 'approve' then
        update public.tasks set status = 'done', completed_at = now(), decline_reason = null
         where id = t.id;
        -- Credit the reward to the personal balance, exactly once.
        perform public.ledger_post(t.child_id, t.earned_amount, 'task', 'task', t.id,
            t.title, 'task:' || t.id::text, now());
    elsif p_action = 'reject' then
        update public.tasks
           set status = 'declined', decline_reason = v_note, earned_amount = null, completed_at = now()
         where id = t.id;
    elsif p_action = 'rework' then
        update public.tasks set status = 'new', decline_reason = v_note, completed_at = null
         where id = t.id;
    else
        raise exception 'INVALID_ACTION';
    end if;

    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (t.child_id, 'task_reviewed', jsonb_build_object(
        'task_id', t.id, 'title', t.title, 'action', p_action,
        'note', v_note, 'amount', t.earned_amount));
end;
$$;

-- ============================================================ drop payment_status (tasks)

drop function if exists public.task_set_payment(uuid, text);

-- events trigger without the payment axis
create or replace function public.trg_events_tasks()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_action text;
    v_details jsonb := '{}'::jsonb;
begin
    if tg_op = 'INSERT' then
        perform public.log_event('created', 'task', new.id, new.title, new.child_id,
            jsonb_strip_nulls(jsonb_build_object(
                'reward', new.reward_amount, 'reward_type', new.reward_type,
                'deadline', new.deadline_at)));
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('deleted', 'task', old.id, old.title, old.child_id);
        return old;
    end if;

    if new.status is distinct from old.status then
        v_action := case
            when new.status = 'in_progress' and old.status in ('new', 'paused') then 'started'
            when new.status = 'paused' then 'paused'
            when new.status = 'submitted' then 'submitted'
            when new.status = 'done' and old.status = 'submitted' then 'approved'
            when new.status = 'done' then 'completed'
            when new.status = 'declined' and old.status = 'submitted' then 'rejected'
            when new.status = 'declined' then 'declined'
            when new.status = 'new' and old.status = 'submitted' then 'rework'
            else 'status_changed'
        end;
        v_details := jsonb_build_object('from', old.status, 'to', new.status);
        if new.decline_reason is not null and new.decline_reason <> '' then
            v_details := v_details || jsonb_build_object('note', new.decline_reason);
        end if;
        if v_action in ('approved', 'completed') and new.earned_amount is not null then
            v_details := v_details || jsonb_build_object('earned', new.earned_amount);
        end if;
        perform public.log_event(v_action, 'task', new.id, new.title, new.child_id, v_details);
    end if;

    if (new.title, new.description, new.requirements, new.reward_amount,
        new.reward_type, new.difficulty, new.deadline_at)
       is distinct from
       (old.title, old.description, old.requirements, old.reward_amount,
        old.reward_type, old.difficulty, old.deadline_at) then
        perform public.log_event('updated', 'task', new.id, new.title, new.child_id,
            jsonb_strip_nulls(jsonb_build_object(
                'old_title', case when new.title is distinct from old.title then old.title end,
                'deadline', case when new.deadline_at is distinct from old.deadline_at
                                 then coalesce(new.deadline_at::text, 'removed') end)));
    end if;
    return new;
end;
$$;

alter table public.tasks drop column if exists payment_status;
alter table public.tasks drop column if exists paid_at;

-- ============================================================ drop min_withdrawal (jobs)

-- events trigger without min_withdrawal
create or replace function public.trg_events_jobs()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        perform public.log_event('created', 'job', new.id, new.title, null,
            jsonb_build_object('hourly_rate', new.hourly_rate));
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('deleted', 'job', old.id, old.title, null);
        return old;
    end if;

    if new.status is distinct from old.status then
        perform public.log_event(
            case when new.status = 'running' then 'started'
                 when new.status = 'archived' then 'archived'
                 else 'stopped' end,
            'job', new.id, new.title, null,
            jsonb_build_object('from', old.status, 'to', new.status));
    end if;
    if (new.title, new.hourly_rate, new.description)
       is distinct from
       (old.title, old.hourly_rate, old.description) then
        perform public.log_event('updated', 'job', new.id, new.title, null);
    end if;
    return new;
end;
$$;

-- job_assigned outbox without min_withdrawal
create or replace function public.trg_job_assigned()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare j public.jobs;
begin
    select * into j from public.jobs where id = new.job_id;
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (new.child_id, 'job_assigned', jsonb_build_object(
        'job_id', j.id, 'title', j.title, 'hourly_rate', j.hourly_rate));
    return new;
end;
$$;

alter table public.jobs drop column if exists min_withdrawal;
