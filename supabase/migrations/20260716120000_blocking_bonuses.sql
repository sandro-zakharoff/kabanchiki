-- Kabanchiki: assignee blocking + manual bonuses.

-- ============================================================ blocking

alter table public.profiles add column if not exists blocked boolean not null default false;

create or replace function public.is_blocked(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select coalesce((select blocked from public.profiles where id = p_uid), false);
$$;

-- Recreate the mutating child RPCs with a block guard at the top. A blocked
-- assignee can no longer start/pause/complete/decline tasks or request payouts.

create or replace function public.task_start(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.status not in ('new', 'paused') then
        raise exception 'INVALID_STATUS';
    end if;
    insert into public.task_intervals (task_id) values (t.id);
    update public.tasks
       set status = 'in_progress', started_at = coalesce(started_at, now())
     where id = t.id;
end;
$$;

create or replace function public.task_pause(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.status <> 'in_progress' then
        raise exception 'INVALID_STATUS';
    end if;
    update public.task_intervals set ended_at = now()
     where task_id = t.id and ended_at is null;
    update public.tasks
       set status = 'paused',
           total_seconds = (select coalesce(sum(extract(epoch from i.ended_at - i.started_at)), 0)::int
                              from public.task_intervals i
                             where i.task_id = t.id and i.ended_at is not null)
     where id = t.id;
end;
$$;

create or replace function public.task_complete(
    p_task_id uuid,
    p_proof_text text default null,
    p_proof_photo_path text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    v_seconds integer;
    v_earned numeric(12, 2);
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.status not in ('in_progress', 'paused') then
        raise exception 'INVALID_STATUS';
    end if;
    if t.proof_text = 'required' and (p_proof_text is null or length(trim(p_proof_text)) = 0) then
        raise exception 'PROOF_TEXT_REQUIRED';
    end if;
    if t.proof_photo = 'required' and (p_proof_photo_path is null or length(trim(p_proof_photo_path)) = 0) then
        raise exception 'PROOF_PHOTO_REQUIRED';
    end if;

    update public.task_intervals set ended_at = now()
     where task_id = t.id and ended_at is null;

    select coalesce(sum(extract(epoch from i.ended_at - i.started_at)), 0)::int
      into v_seconds
      from public.task_intervals i
     where i.task_id = t.id and i.ended_at is not null;

    if t.reward_type = 'fixed' then
        v_earned := t.reward_amount;
    else
        v_earned := round(v_seconds / 3600.0 * t.reward_amount, 2);
    end if;

    update public.tasks
       set status = 'done',
           completed_at = now(),
           total_seconds = v_seconds,
           earned_amount = v_earned,
           proof_text_content = nullif(trim(coalesce(p_proof_text, '')), ''),
           proof_photo_path = nullif(trim(coalesce(p_proof_photo_path, '')), '')
     where id = t.id;
end;
$$;

create or replace function public.task_decline(p_task_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.status <> 'new' then
        raise exception 'INVALID_STATUS';
    end if;
    update public.tasks
       set status = 'declined',
           decline_reason = nullif(trim(coalesce(p_reason, '')), ''),
           completed_at = now()
     where id = t.id;
end;
$$;

create or replace function public.request_withdrawal(p_job_id uuid)
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
    v_now timestamptz := now();
    v_id uuid;
begin
    if public.is_blocked(v_child) then raise exception 'BLOCKED'; end if;
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
    v_balance := round(v_seconds / 3600.0 * j.hourly_rate, 2);
    if v_balance < j.min_withdrawal or v_balance <= 0 then
        raise exception 'BELOW_MINIMUM';
    end if;

    insert into public.withdrawals (job_id, child_id, amount, period_from, period_to)
    values (p_job_id, v_child, v_balance, m.earnings_reset_at, v_now)
    returning id into v_id;
    return v_id;
end;
$$;

-- ============================================================ bonuses

create table if not exists public.bonuses (
    id uuid primary key default gen_random_uuid(),
    child_id uuid not null references public.profiles (id) on delete cascade,
    amount numeric(12, 2) not null check (amount > 0),
    note text not null default '',
    created_at timestamptz not null default now()
);
create index if not exists bonuses_child_idx on public.bonuses (child_id, created_at desc);

alter table public.bonuses enable row level security;

create policy "own bonuses" on public.bonuses
    for select to authenticated using (child_id = auth.uid());

alter table public.bonuses replica identity full;
alter publication supabase_realtime add table public.bonuses;

create or replace function public.trg_bonus_granted()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (new.child_id, 'bonus_granted', jsonb_build_object(
        'bonus_id', new.id,
        'amount', new.amount,
        'note', new.note
    ));
    return new;
end;
$$;

create trigger bonus_granted_outbox after insert on public.bonuses
for each row execute function public.trg_bonus_granted();
