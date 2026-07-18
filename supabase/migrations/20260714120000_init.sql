-- Kabanchiki: core schema
-- Server is the single source of truth for time and money.
-- Children interact ONLY through SECURITY DEFINER RPCs; direct writes are denied by RLS.
-- The parent desktop app uses the service_role key and bypasses RLS.

-- ============================================================ enums

create type public.task_reward_type as enum ('fixed', 'hourly');
create type public.proof_requirement as enum ('none', 'optional', 'required');
create type public.task_status as enum ('new', 'declined', 'in_progress', 'paused', 'done');
create type public.job_status as enum ('idle', 'running', 'archived');
create type public.withdrawal_status as enum ('pending', 'approved', 'declined');

-- ============================================================ tables

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
    display_name text not null,
    avatar_color text not null default '#CDB1B1',
    role text not null default 'child' check (role in ('child')),
    created_at timestamptz not null default now()
);

create table public.devices (
    id uuid primary key default gen_random_uuid(),
    profile_id uuid not null references public.profiles (id) on delete cascade,
    fcm_token text not null unique,
    platform text not null default 'android',
    updated_at timestamptz not null default now()
);
create index devices_profile_idx on public.devices (profile_id);

create table public.tasks (
    id uuid primary key default gen_random_uuid(),
    child_id uuid not null references public.profiles (id) on delete cascade,
    title text not null check (length(title) between 1 and 200),
    description text not null default '',
    photo_path text,
    reward_type public.task_reward_type not null default 'fixed',
    reward_amount numeric(12, 2) not null check (reward_amount >= 0),
    difficulty smallint not null default 1 check (difficulty between 1 and 5),
    requirements text not null default '',
    proof_text public.proof_requirement not null default 'none',
    proof_photo public.proof_requirement not null default 'none',
    status public.task_status not null default 'new',
    proof_text_content text,
    proof_photo_path text,
    decline_reason text,
    total_seconds integer not null default 0,
    earned_amount numeric(12, 2),
    created_at timestamptz not null default now(),
    started_at timestamptz,
    completed_at timestamptz
);
create index tasks_child_idx on public.tasks (child_id, created_at desc);

create table public.task_intervals (
    id uuid primary key default gen_random_uuid(),
    task_id uuid not null references public.tasks (id) on delete cascade,
    started_at timestamptz not null default now(),
    ended_at timestamptz check (ended_at is null or ended_at >= started_at)
);
create index task_intervals_task_idx on public.task_intervals (task_id);
-- at most one open interval per task
create unique index task_intervals_open_uniq on public.task_intervals (task_id) where ended_at is null;

create table public.jobs (
    id uuid primary key default gen_random_uuid(),
    title text not null check (length(title) between 1 and 200),
    description text not null default '',
    hourly_rate numeric(12, 2) not null check (hourly_rate >= 0),
    min_withdrawal numeric(12, 2) not null check (min_withdrawal >= 0),
    status public.job_status not null default 'idle',
    created_at timestamptz not null default now()
);

create table public.job_members (
    job_id uuid not null references public.jobs (id) on delete cascade,
    child_id uuid not null references public.profiles (id) on delete cascade,
    earnings_reset_at timestamptz not null default now(),
    total_withdrawn numeric(12, 2) not null default 0,
    joined_at timestamptz not null default now(),
    primary key (job_id, child_id)
);
create index job_members_child_idx on public.job_members (child_id);

create table public.job_sessions (
    id uuid primary key default gen_random_uuid(),
    job_id uuid not null references public.jobs (id) on delete cascade,
    started_at timestamptz not null default now(),
    ended_at timestamptz check (ended_at is null or ended_at >= started_at)
);
create index job_sessions_job_idx on public.job_sessions (job_id);
create unique index job_sessions_open_uniq on public.job_sessions (job_id) where ended_at is null;

create table public.withdrawals (
    id uuid primary key default gen_random_uuid(),
    job_id uuid not null references public.jobs (id) on delete cascade,
    child_id uuid not null references public.profiles (id) on delete cascade,
    amount numeric(12, 2) not null check (amount > 0),
    period_from timestamptz not null,
    period_to timestamptz not null,
    status public.withdrawal_status not null default 'pending',
    requested_at timestamptz not null default now(),
    decided_at timestamptz
);
create index withdrawals_child_idx on public.withdrawals (child_id, requested_at desc);
create index withdrawals_status_idx on public.withdrawals (status);
-- at most one pending withdrawal per (job, child)
create unique index withdrawals_pending_uniq on public.withdrawals (job_id, child_id) where status = 'pending';

-- Outbox: DB triggers append events, a Database Webhook calls the send-push
-- Edge Function for each insert. recipient_id is always a child profile.
create table public.notifications_outbox (
    id bigint generated always as identity primary key,
    recipient_id uuid not null references public.profiles (id) on delete cascade,
    event_type text not null,
    payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    sent_at timestamptz
);

-- ============================================================ time & money helpers

-- Seconds a child has earned in a job since their last approved withdrawal.
create or replace function public.job_earned_seconds(p_job_id uuid, p_child_id uuid)
returns bigint
language sql
stable
set search_path = public, pg_temp
as $$
    select coalesce(sum(
        greatest(0, extract(epoch from
            coalesce(s.ended_at, now()) - greatest(s.started_at, m.earnings_reset_at)
        ))
    ), 0)::bigint
    from public.job_sessions s
    join public.job_members m on m.job_id = s.job_id and m.child_id = p_child_id
    where s.job_id = p_job_id
      and coalesce(s.ended_at, now()) > greatest(s.started_at, m.earnings_reset_at);
$$;

-- Live snapshot per (job, child). security_invoker: children see only their rows via RLS.
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
    exists(select 1 from public.withdrawals w
            where w.job_id = m.job_id and w.child_id = m.child_id and w.status = 'pending') as has_pending_withdrawal,
    now() as snapshot_at
from public.job_members m
join public.jobs j on j.id = m.job_id;

-- Clock sync for clients: they tick locally from this offset.
create or replace function public.server_now()
returns timestamptz
language sql
stable
as $$ select now(); $$;

grant execute on function public.server_now() to authenticated;

-- ============================================================ child RPCs

create or replace function public.task_start(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
begin
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

-- Amount is computed server-side: the client cannot forge it.
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

-- Register/refresh the FCM token of this child's device.
create or replace function public.register_device(p_fcm_token text, p_platform text default 'android')
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'NOT_AUTHENTICATED';
    end if;
    insert into public.devices (profile_id, fcm_token, platform)
    values (auth.uid(), p_fcm_token, p_platform)
    on conflict (fcm_token)
    do update set profile_id = excluded.profile_id, updated_at = now();
end;
$$;

grant execute on function
    public.task_start(uuid),
    public.task_pause(uuid),
    public.task_complete(uuid, text, text),
    public.task_decline(uuid, text),
    public.request_withdrawal(uuid),
    public.register_device(text, text)
to authenticated;

-- ============================================================ parent (service_role) RPCs

create or replace function public.admin_decide_withdrawal(p_withdrawal_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    w public.withdrawals;
begin
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
           decided_at = now()
     where id = w.id;

    if p_approve then
        -- Balance restarts from the moment of the request; the shared timer is untouched.
        update public.job_members
           set earnings_reset_at = w.period_to,
               total_withdrawn = total_withdrawn + w.amount
         where job_id = w.job_id and child_id = w.child_id;
    end if;
end;
$$;

create or replace function public.admin_job_start(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    j public.jobs;
begin
    select * into j from public.jobs where id = p_job_id for update;
    if not found then
        raise exception 'JOB_NOT_FOUND';
    end if;
    if j.status <> 'idle' then
        raise exception 'INVALID_STATUS';
    end if;
    update public.jobs set status = 'running' where id = j.id;
    insert into public.job_sessions (job_id) values (j.id);
end;
$$;

create or replace function public.admin_job_stop(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    j public.jobs;
begin
    select * into j from public.jobs where id = p_job_id for update;
    if not found then
        raise exception 'JOB_NOT_FOUND';
    end if;
    if j.status <> 'running' then
        raise exception 'INVALID_STATUS';
    end if;
    update public.job_sessions set ended_at = now()
     where job_id = j.id and ended_at is null;
    update public.jobs set status = 'idle' where id = j.id;
end;
$$;

create or replace function public.admin_job_archive(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    update public.job_sessions set ended_at = now()
     where job_id = p_job_id and ended_at is null;
    update public.jobs set status = 'archived' where id = p_job_id;
end;
$$;

revoke execute on function
    public.admin_decide_withdrawal(uuid, boolean),
    public.admin_job_start(uuid),
    public.admin_job_stop(uuid),
    public.admin_job_archive(uuid)
from public, anon, authenticated;

-- ============================================================ outbox triggers

create or replace function public.trg_task_created()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (new.child_id, 'task_created', jsonb_build_object(
        'task_id', new.id,
        'title', new.title,
        'reward_type', new.reward_type,
        'reward_amount', new.reward_amount,
        'difficulty', new.difficulty
    ));
    return new;
end;
$$;
create trigger task_created_outbox after insert on public.tasks
for each row execute function public.trg_task_created();

create or replace function public.trg_job_assigned()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    j public.jobs;
begin
    select * into j from public.jobs where id = new.job_id;
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (new.child_id, 'job_assigned', jsonb_build_object(
        'job_id', j.id,
        'title', j.title,
        'hourly_rate', j.hourly_rate,
        'min_withdrawal', j.min_withdrawal
    ));
    return new;
end;
$$;
create trigger job_assigned_outbox after insert on public.job_members
for each row execute function public.trg_job_assigned();

create or replace function public.trg_job_session_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    j public.jobs;
    v_event text;
begin
    if tg_op = 'INSERT' then
        v_event := 'job_started';
    elsif tg_op = 'UPDATE' and old.ended_at is null and new.ended_at is not null then
        v_event := 'job_stopped';
    else
        return new;
    end if;
    select * into j from public.jobs where id = new.job_id;
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    select m.child_id, v_event, jsonb_build_object('job_id', j.id, 'title', j.title)
      from public.job_members m
     where m.job_id = new.job_id;
    return new;
end;
$$;
create trigger job_session_outbox after insert or update on public.job_sessions
for each row execute function public.trg_job_session_change();

create or replace function public.trg_withdrawal_decided()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    j public.jobs;
begin
    if old.status = 'pending' and new.status in ('approved', 'declined') then
        select * into j from public.jobs where id = new.job_id;
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (new.child_id, 'withdrawal_decided', jsonb_build_object(
            'withdrawal_id', new.id,
            'job_id', new.job_id,
            'job_title', j.title,
            'amount', new.amount,
            'status', new.status
        ));
    end if;
    return new;
end;
$$;
create trigger withdrawal_decided_outbox after update on public.withdrawals
for each row execute function public.trg_withdrawal_decided();

-- ============================================================ RLS

alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.tasks enable row level security;
alter table public.task_intervals enable row level security;
alter table public.jobs enable row level security;
alter table public.job_members enable row level security;
alter table public.job_sessions enable row level security;
alter table public.withdrawals enable row level security;
alter table public.notifications_outbox enable row level security;
-- no policies on notifications_outbox: service_role only

create policy "own profile" on public.profiles
    for select to authenticated using (id = auth.uid());

create policy "own devices" on public.devices
    for select to authenticated using (profile_id = auth.uid());

create policy "own tasks" on public.tasks
    for select to authenticated using (child_id = auth.uid());

create policy "own task intervals" on public.task_intervals
    for select to authenticated using (
        exists(select 1 from public.tasks t where t.id = task_id and t.child_id = auth.uid())
    );

create policy "member jobs" on public.jobs
    for select to authenticated using (
        exists(select 1 from public.job_members m where m.job_id = id and m.child_id = auth.uid())
    );

create policy "own membership" on public.job_members
    for select to authenticated using (child_id = auth.uid());

create policy "member job sessions" on public.job_sessions
    for select to authenticated using (
        exists(select 1 from public.job_members m where m.job_id = job_id and m.child_id = auth.uid())
    );

create policy "own withdrawals" on public.withdrawals
    for select to authenticated using (child_id = auth.uid());

-- ============================================================ realtime

alter table public.tasks replica identity full;
alter table public.jobs replica identity full;
alter table public.job_members replica identity full;
alter table public.job_sessions replica identity full;
alter table public.withdrawals replica identity full;

alter publication supabase_realtime add table
    public.tasks,
    public.jobs,
    public.job_members,
    public.job_sessions,
    public.withdrawals;
