-- Kabanchiki: audit journal.
-- Every significant mutation lands in public.events via AFTER triggers, so the
-- journal covers ALL platforms (desktop, Android, Mini App) automatically —
-- clients cannot forget to log. Parents read it; children have no access.

create table public.events (
    id bigint generated always as identity primary key,
    created_at timestamptz not null default now(),
    actor_kind text not null check (actor_kind in ('parent', 'child', 'system')),
    actor_id uuid,
    actor_name text not null default '',
    action text not null,
    entity text not null check (entity in ('task', 'job', 'withdrawal', 'bonus', 'child')),
    entity_id uuid,
    entity_title text not null default '',
    child_id uuid,                       -- affected assignee, for filtering
    details jsonb not null default '{}'::jsonb
);

create index events_created_idx on public.events (created_at desc);
create index events_child_idx on public.events (child_id, created_at desc);

alter table public.events enable row level security;
create policy "parents read events" on public.events
    for select to authenticated using (public.is_parent(auth.uid()));

alter table public.events replica identity full;
alter publication supabase_realtime add table public.events;

-- ============================================================ helpers

-- Who is doing this? parent / child / system (service_role or unauthenticated).
create or replace function public.event_actor(out kind text, out id uuid, out name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        kind := 'system'; id := null; name := '';
        return;
    end if;
    select 'parent', p.id, coalesce(nullif(p.display_name, ''), p.email, '')
      into kind, id, name
      from public.parents p where p.id = v_uid;
    if found then return; end if;
    select 'child', c.id, c.display_name
      into kind, id, name
      from public.profiles c where c.id = v_uid;
    if found then return; end if;
    kind := 'system'; id := v_uid; name := '';
end;
$$;

create or replace function public.log_event(
    p_action text,
    p_entity text,
    p_entity_id uuid,
    p_title text,
    p_child uuid,
    p_details jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    a record;
    v_id bigint;
begin
    select * into a from public.event_actor();
    insert into public.events (actor_kind, actor_id, actor_name, action, entity,
                               entity_id, entity_title, child_id, details)
    values (a.kind, a.id, a.name, p_action, p_entity,
            p_entity_id, coalesce(p_title, ''), p_child, coalesce(p_details, '{}'::jsonb))
    returning id into v_id;
    -- cheap retention: keep the latest ~5000 rows
    if v_id % 200 = 0 then
        delete from public.events where id <= v_id - 5000;
    end if;
end;
$$;

-- ============================================================ tasks

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
            jsonb_build_object('reward', new.reward_amount, 'reward_type', new.reward_type));
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('deleted', 'task', old.id, old.title, old.child_id);
        return old;
    end if;

    -- UPDATE: one event per meaningful change
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

    if new.payment_status is distinct from old.payment_status then
        perform public.log_event('payment_changed', 'task', new.id, new.title, new.child_id,
            jsonb_build_object('from', old.payment_status, 'to', new.payment_status,
                               'amount', new.earned_amount));
    end if;

    -- content edits (parent edited the task in place)
    if (new.title, new.description, new.requirements, new.reward_amount,
        new.reward_type, new.difficulty)
       is distinct from
       (old.title, old.description, old.requirements, old.reward_amount,
        old.reward_type, old.difficulty) then
        perform public.log_event('updated', 'task', new.id, new.title, new.child_id,
            case when new.title is distinct from old.title
                 then jsonb_build_object('old_title', old.title) else '{}'::jsonb end);
    end if;
    return new;
end;
$$;

create trigger events_tasks after insert or update or delete on public.tasks
for each row execute function public.trg_events_tasks();

-- ============================================================ jobs

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
    if (new.title, new.hourly_rate, new.min_withdrawal, new.description)
       is distinct from
       (old.title, old.hourly_rate, old.min_withdrawal, old.description) then
        perform public.log_event('updated', 'job', new.id, new.title, null);
    end if;
    return new;
end;
$$;

create trigger events_jobs after insert or update or delete on public.jobs
for each row execute function public.trg_events_jobs();

create or replace function public.trg_events_job_members()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_title text;
begin
    select title into v_title from public.jobs
     where id = coalesce(new.job_id, old.job_id);
    if tg_op = 'INSERT' then
        perform public.log_event('assigned', 'job', new.job_id, coalesce(v_title, ''), new.child_id);
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('unassigned', 'job', old.job_id, coalesce(v_title, ''), old.child_id);
        return old;
    end if;
    return new;
end;
$$;

create trigger events_job_members after insert or delete on public.job_members
for each row execute function public.trg_events_job_members();

-- ============================================================ withdrawals

create or replace function public.trg_events_withdrawals()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_title text;
begin
    select title into v_title from public.jobs
     where id = coalesce(new.job_id, old.job_id);
    if tg_op = 'INSERT' then
        perform public.log_event('requested', 'withdrawal', new.id, coalesce(v_title, ''),
            new.child_id, jsonb_build_object('amount', new.amount));
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('deleted', 'withdrawal', old.id, coalesce(v_title, ''),
            old.child_id, jsonb_build_object('amount', old.amount));
        return old;
    end if;

    if new.status is distinct from old.status then
        perform public.log_event(
            case when new.status = 'approved' then 'approved' else 'declined' end,
            'withdrawal', new.id, coalesce(v_title, ''), new.child_id,
            jsonb_build_object('amount', new.amount));
    end if;
    if new.payment_status is distinct from old.payment_status then
        perform public.log_event('payment_changed', 'withdrawal', new.id, coalesce(v_title, ''),
            new.child_id,
            jsonb_build_object('from', old.payment_status, 'to', new.payment_status,
                               'amount', new.amount));
    end if;
    return new;
end;
$$;

create trigger events_withdrawals after insert or update or delete on public.withdrawals
for each row execute function public.trg_events_withdrawals();

-- ============================================================ bonuses

create or replace function public.trg_events_bonuses()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        perform public.log_event('granted', 'bonus', new.id, coalesce(new.note, ''),
            new.child_id, jsonb_build_object('amount', new.amount));
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('deleted', 'bonus', old.id, coalesce(old.note, ''),
            old.child_id, jsonb_build_object('amount', old.amount));
        return old;
    end if;
    if (new.amount, new.note) is distinct from (old.amount, old.note) then
        perform public.log_event('updated', 'bonus', new.id, coalesce(new.note, ''),
            new.child_id,
            jsonb_build_object('amount', new.amount, 'old_amount', old.amount));
    end if;
    return new;
end;
$$;

create trigger events_bonuses after insert or update or delete on public.bonuses
for each row execute function public.trg_events_bonuses();

-- ============================================================ profiles (children)

create or replace function public.trg_events_profiles()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        perform public.log_event('created', 'child', new.id, new.display_name, new.id);
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('deleted', 'child', old.id, old.display_name, old.id);
        return old;
    end if;
    if new.blocked is distinct from old.blocked then
        perform public.log_event(
            case when new.blocked then 'blocked' else 'unblocked' end,
            'child', new.id, new.display_name, new.id);
    end if;
    if new.display_name is distinct from old.display_name then
        perform public.log_event('updated', 'child', new.id, new.display_name, new.id,
            jsonb_build_object('old_name', old.display_name));
    end if;
    return new;
end;
$$;

create trigger events_profiles after insert or update or delete on public.profiles
for each row execute function public.trg_events_profiles();
