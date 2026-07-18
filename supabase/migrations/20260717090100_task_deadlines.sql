-- Kabanchiki: optional task deadlines (D1).
-- Stored in UTC like every other timestamp; existing tasks keep NULL.
-- reminded/notified marks power the D4 reminders (24h-before + overdue).

alter table public.tasks
    add column if not exists deadline_at timestamptz,
    add column if not exists deadline_reminded_at timestamptz,
    add column if not exists overdue_notified_at timestamptz;

-- Upcoming-deadline scans (reminders + overdue sweep).
create index if not exists tasks_deadline_idx on public.tasks (deadline_at)
    where deadline_at is not null;

-- Journal: deadline changes are content edits.
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
        new.reward_type, new.difficulty, new.deadline_at)
       is distinct from
       (old.title, old.description, old.requirements, old.reward_amount,
        old.reward_type, old.difficulty, old.deadline_at) then
        perform public.log_event('updated', 'task', new.id, new.title, new.child_id,
            jsonb_strip_nulls(jsonb_build_object(
                'old_title', case when new.title is distinct from old.title
                                  then old.title end,
                'deadline', case when new.deadline_at is distinct from old.deadline_at
                                 then coalesce(new.deadline_at::text, 'removed') end)));
    end if;
    return new;
end;
$$;
