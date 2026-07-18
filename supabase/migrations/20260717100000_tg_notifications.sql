-- Kabanchiki: Telegram notifications for owners (A1).
--
-- Assignee actions recorded in public.events fan out into tg_outbox; a
-- pg_net webhook calls the tg-notify Edge Function which messages every
-- linked, active owner with inline quick actions. The tg-bot Edge Function
-- (Telegram webhook) executes those actions through bot_act(), which
-- attributes the journal entry to the owner who pressed the button.

-- ---------------------------------------------------------------- outbox

create table public.tg_outbox (
    id bigint generated always as identity primary key,
    event_id bigint references public.events (id) on delete set null,
    kind text not null,
    payload jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    sent_at timestamptz,
    attempts int not null default 0,
    last_error text
);

alter table public.tg_outbox enable row level security;
-- no policies: service_role only

create index tg_outbox_unsent_idx on public.tg_outbox (created_at)
    where sent_at is null;

-- ---------------------------------------------------------------- fan-out

-- Assignee actions the owner wants to hear about right away.
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

create trigger events_tg_outbox after insert on public.events
for each row execute function public.trg_events_tg_outbox();

-- ---------------------------------------------------------------- actor override

-- Bot button presses run as service_role, but the journal must show the owner
-- who pressed the button: bot_act() stores their id in a transaction-local
-- setting, and event_actor() honours it first.
create or replace function public.event_actor(out kind text, out id uuid, out name text)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_uid uuid := auth.uid();
    v_override text := current_setting('app.actor_id', true);
begin
    if v_uid is null and coalesce(v_override, '') <> '' then
        v_uid := v_override::uuid;
    end if;
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

-- Executes a quick action on behalf of a linked owner. service_role only:
-- the Telegram webhook function has already verified the sender.
create or replace function public.bot_act(
    p_parent_id uuid,
    p_action text,
    p_target uuid,
    p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not exists (select 1 from public.parents
                    where id = p_parent_id and not disabled) then
        raise exception 'NOT_PARENT';
    end if;
    perform set_config('app.actor_id', p_parent_id::text, true);

    case p_action
        when 'task_approve' then perform public.task_review(p_target, 'approve', null);
        when 'task_rework'  then perform public.task_review(p_target, 'rework', p_note);
        when 'task_reject'  then perform public.task_review(p_target, 'reject', p_note);
        when 'wd_approve'   then perform public.admin_decide_withdrawal(p_target, true);
        when 'wd_decline'   then perform public.admin_decide_withdrawal(p_target, false);
        else raise exception 'UNKNOWN_ACTION';
    end case;
end;
$$;

revoke execute on function public.bot_act(uuid, text, uuid, text)
    from public, anon, authenticated;

-- ---------------------------------------------------------------- webhook + retry

-- The pg_net trigger is installed by the deployment template after the
-- project ref and WEBHOOK_SECRET have been supplied outside Git. Keeping
-- those values out of migrations prevents infrastructure credentials from
-- entering source history.

-- Retry sweep: touch unsent rows so the webhook fires again (max 5 tries,
-- rows younger than a day).
create extension if not exists pg_cron;
select cron.schedule(
    'tg-outbox-retry',
    '*/5 * * * *',
    $$update public.tg_outbox
         set last_error = coalesce(last_error, '')
       where sent_at is null
         and attempts between 1 and 4
         and created_at > now() - interval '1 day'$$
);

-- ---------------------------------------------------------------- webhook secret

-- Telegram's setWebhook secret_token, generated when the desktop registers
-- the webhook; tg-bot compares it against the request header.
alter table public.app_secrets
    add column if not exists telegram_webhook_secret text;
