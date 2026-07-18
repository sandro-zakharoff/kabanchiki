-- Kabanchiki: deadline reminders (D4).
--
-- A pg_cron job every 10 minutes:
--   1. active task, deadline within 24h, not yet reminded -> FCM to the
--      assignee (notifications_outbox 'deadline_soon') + mark reminded.
--   2. active task, deadline passed, not yet notified -> journal event
--      'overdue' (which the events->tg_outbox trigger fans out to owners) +
--      mark notified.
-- Marks make each reminder fire once; editing the deadline clears them.

create or replace function public.run_deadline_reminders()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
begin
    -- 1. upcoming (within 24h)
    for t in
        select * from public.tasks
         where deadline_at is not null
           and deadline_reminded_at is null
           and status in ('new', 'in_progress', 'paused')
           and deadline_at > now()
           and deadline_at <= now() + interval '24 hours'
    loop
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (t.child_id, 'deadline_soon', jsonb_build_object(
            'task_id', t.id, 'title', t.title, 'deadline', t.deadline_at));
        update public.tasks set deadline_reminded_at = now() where id = t.id;
    end loop;

    -- 2. overdue
    for t in
        select * from public.tasks
         where deadline_at is not null
           and overdue_notified_at is null
           and status in ('new', 'in_progress', 'paused')
           and deadline_at <= now()
    loop
        -- journal event; the events -> tg_outbox trigger notifies owners.
        insert into public.events (actor_kind, actor_name, action, entity,
                                   entity_id, entity_title, child_id, details)
        values ('system', '', 'overdue', 'task', t.id, t.title, t.child_id,
                jsonb_build_object('deadline', t.deadline_at));
        update public.tasks set overdue_notified_at = now() where id = t.id;
    end loop;
end;
$$;

revoke execute on function public.run_deadline_reminders() from public, anon, authenticated;

-- Editing a task's deadline re-arms the reminders for the new time.
create or replace function public.trg_reset_deadline_marks()
returns trigger
language plpgsql
as $$
begin
    if new.deadline_at is distinct from old.deadline_at then
        new.deadline_reminded_at := null;
        new.overdue_notified_at := null;
    end if;
    return new;
end;
$$;

create trigger reset_deadline_marks before update on public.tasks
for each row execute function public.trg_reset_deadline_marks();

-- The overdue journal event should also reach owners via the bot: extend the
-- events -> tg_outbox fan-out to include system 'overdue' task events.
create or replace function public.trg_events_tg_outbox()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if (new.actor_kind = 'child'
        and ((new.entity = 'task' and new.action in ('started', 'submitted', 'declined', 'completed'))
             or (new.entity = 'withdrawal' and new.action = 'requested')))
       or (new.actor_kind = 'system' and new.entity = 'task' and new.action = 'overdue')
    then
        insert into public.tg_outbox (event_id, kind, payload)
        values (new.id, new.entity || '_' || new.action, jsonb_strip_nulls(jsonb_build_object(
            'action', new.action,
            'entity', new.entity,
            'entity_id', new.entity_id,
            'title', new.entity_title,
            'actor', new.actor_name,
            'child_id', new.child_id,
            'amount', new.details->'amount',
            'note', new.details->>'note',
            'at', new.created_at
        )));
    end if;
    return new;
end;
$$;

create extension if not exists pg_cron;
select cron.schedule('deadline-reminders', '*/10 * * * *',
                     $$select public.run_deadline_reminders()$$);
