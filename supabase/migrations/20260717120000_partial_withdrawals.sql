-- Kabanchiki: partial withdrawals (B2).
--
-- Assignees can now withdraw a chosen amount (>= the job minimum, <= current
-- balance) instead of always cashing out everything. The remainder keeps
-- accruing. Additive design: withdrawn_since_reset defaults to 0, so existing
-- members behave exactly as before until the first partial approval.

alter table public.job_members
    add column if not exists withdrawn_since_reset numeric(12, 2) not null default 0;

-- Balance now subtracts what was already paid out since the last full reset.
-- Rebuild the whole view (Postgres can't add a column to an existing view).
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
    greatest(0, round(public.job_earned_seconds(m.job_id, m.child_id) / 3600.0 * j.hourly_rate, 2)
                - m.withdrawn_since_reset) as balance,
    (select s.started_at from public.job_sessions s
      where s.job_id = m.job_id and s.ended_at is null limit 1) as running_since,
    exists(select 1 from public.withdrawals w
            where w.job_id = m.job_id and w.child_id = m.child_id and w.status = 'pending') as has_pending_withdrawal,
    now() as snapshot_at
from public.job_members m
join public.jobs j on j.id = m.job_id;

-- request_withdrawal now takes an optional amount (null = whole balance).
-- Drop the old 1-arg version so PostgREST never faces two overloads.
drop function if exists public.request_withdrawal(uuid);

create or replace function public.request_withdrawal(
    p_job_id uuid,
    p_amount numeric default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_child uuid := auth.uid();
    j public.jobs;
    m public.job_members;
    v_seconds bigint;
    v_balance numeric(12, 2);
    v_amount numeric(12, 2);
    v_now timestamptz := now();
    v_id uuid;
begin
    if public.is_blocked(v_child) then
        raise exception 'BLOCKED';
    end if;
    select * into j from public.jobs where id = p_job_id;
    if not found then
        raise exception 'JOB_NOT_FOUND';
    end if;
    select * into m from public.job_members
     where job_id = p_job_id and child_id = v_child for update;
    if not found then
        raise exception 'NOT_A_MEMBER';
    end if;
    if exists(select 1 from public.withdrawals
               where job_id = p_job_id and child_id = v_child and status = 'pending') then
        raise exception 'WITHDRAWAL_PENDING';
    end if;

    v_seconds := public.job_earned_seconds(p_job_id, v_child);
    v_balance := greatest(0, round(v_seconds / 3600.0 * j.hourly_rate, 2) - m.withdrawn_since_reset);
    if v_balance < j.min_withdrawal or v_balance <= 0 then
        raise exception 'BELOW_MINIMUM';
    end if;

    v_amount := coalesce(p_amount, v_balance);   -- null = withdraw everything
    if v_amount < j.min_withdrawal then
        raise exception 'BELOW_MINIMUM';
    end if;
    if v_amount > v_balance then
        raise exception 'ABOVE_BALANCE';
    end if;

    insert into public.withdrawals (job_id, child_id, amount, period_from, period_to)
    values (p_job_id, v_child, v_amount, m.earnings_reset_at, v_now)
    returning id into v_id;
    return v_id;
end;
$$;

grant execute on function public.request_withdrawal(uuid, numeric) to authenticated;

-- Approval handles partial vs full:
--   full  (amount covers the whole balance) -> reset time, clear the counter
--          (short recompute windows, same as before)
--   part  -> just add to withdrawn_since_reset; the remainder keeps accruing
create or replace function public.admin_decide_withdrawal(p_withdrawal_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    w public.withdrawals;
    j public.jobs;
    m public.job_members;
    v_seconds bigint;
    v_balance numeric(12, 2);
begin
    -- guard: service_role (null uid) OR a parent may decide
    if auth.uid() is not null and not public.is_parent(auth.uid()) then
        raise exception 'NOT_PARENT';
    end if;

    select * into w from public.withdrawals where id = p_withdrawal_id for update;
    if not found then
        raise exception 'WITHDRAWAL_NOT_FOUND';
    end if;
    if w.status <> 'pending' then
        raise exception 'ALREADY_DECIDED';
    end if;

    update public.withdrawals
       set status = case when p_approve then 'approved'::public.withdrawal_status
                         else 'declined'::public.withdrawal_status end,
           payment_status = case when p_approve then 'awaiting'::public.payment_status
                                 else 'unpaid'::public.payment_status end,
           decided_at = now()
     where id = w.id;

    if p_approve then
        select * into j from public.jobs where id = w.job_id;
        select * into m from public.job_members
         where job_id = w.job_id and child_id = w.child_id for update;
        v_seconds := public.job_earned_seconds(w.job_id, w.child_id);
        v_balance := greatest(0, round(v_seconds / 3600.0 * j.hourly_rate, 2) - m.withdrawn_since_reset);

        if w.amount >= v_balance then
            -- full cash-out: balance restarts from the request moment.
            update public.job_members
               set earnings_reset_at = w.period_to,
                   withdrawn_since_reset = 0,
                   total_withdrawn = total_withdrawn + w.amount
             where job_id = w.job_id and child_id = w.child_id;
        else
            -- partial: the rest keeps accruing.
            update public.job_members
               set withdrawn_since_reset = withdrawn_since_reset + w.amount,
                   total_withdrawn = total_withdrawn + w.amount
             where job_id = w.job_id and child_id = w.child_id;
        end if;
    end if;
end;
$$;

alter table public.job_member_stats owner to postgres;
