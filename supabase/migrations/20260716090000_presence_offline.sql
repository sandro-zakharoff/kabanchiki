-- Presence (online/offline in the parent app) and offline handling for tasks.

-- ============================================================ presence

alter table public.profiles add column if not exists last_seen_at timestamptz;

create or replace function public.touch_presence()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'NOT_AUTHENTICATED';
    end if;
    update public.profiles set last_seen_at = now() where id = auth.uid();
end;
$$;

grant execute on function public.touch_presence() to authenticated;

-- ============================================================ offline gap for regular tasks
--
-- The child's device reports the moment connectivity was lost. The open work
-- interval is closed retroactively at that moment (offline time never counts
-- for regular tasks). If the network came back within the client-side limit
-- the app resumes with p_resume=true (a fresh interval opens now); after a
-- long outage it pauses the task with p_resume=false.

create or replace function public.task_apply_offline_gap(
    p_task_id uuid,
    p_offline_from timestamptz,
    p_resume boolean
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    i public.task_intervals;
    v_from timestamptz := p_offline_from;
begin
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.status <> 'in_progress' then
        return; -- already paused/completed elsewhere; nothing to fix
    end if;
    select * into i from public.task_intervals
     where task_id = t.id and ended_at is null;
    if not found then
        return;
    end if;

    v_from := greatest(v_from, i.started_at);
    v_from := least(v_from, now());

    update public.task_intervals set ended_at = v_from where id = i.id;
    update public.tasks
       set status = case when p_resume then 'in_progress'::public.task_status
                         else 'paused'::public.task_status end,
           total_seconds = (select coalesce(sum(extract(epoch from x.ended_at - x.started_at)), 0)::int
                              from public.task_intervals x
                             where x.task_id = t.id and x.ended_at is not null)
     where id = t.id;

    if p_resume then
        insert into public.task_intervals (task_id) values (t.id);
    end if;
end;
$$;

grant execute on function public.task_apply_offline_gap(uuid, timestamptz, boolean) to authenticated;

-- ============================================================ job stats: when was the job last stopped

drop view if exists public.job_member_stats;

create view public.job_member_stats
with (security_invoker = true) as
select
    m.job_id,
    m.child_id,
    j.title,
    j.description,
    j.hourly_rate,
    j.min_withdrawal,
    j.status,
    m.earnings_reset_at,
    m.total_withdrawn,
    (select coalesce(sum(extract(epoch from coalesce(s.ended_at, now()) - s.started_at)), 0)
       from public.job_sessions s where s.job_id = m.job_id)::bigint as total_seconds,
    public.job_earned_seconds(m.job_id, m.child_id) as earned_seconds,
    round(public.job_earned_seconds(m.job_id, m.child_id) / 3600.0 * j.hourly_rate, 2) as balance,
    (select s.started_at from public.job_sessions s
      where s.job_id = m.job_id and s.ended_at is null limit 1) as running_since,
    (select max(s.ended_at) from public.job_sessions s
      where s.job_id = m.job_id) as last_stopped_at,
    exists(select 1 from public.withdrawals w
            where w.job_id = m.job_id and w.child_id = m.child_id and w.status = 'pending') as has_pending_withdrawal,
    now() as snapshot_at
from public.job_members m
join public.jobs j on j.id = m.job_id;
