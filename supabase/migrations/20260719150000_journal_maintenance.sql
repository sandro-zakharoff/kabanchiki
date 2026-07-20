-- Kabanchiki: journal hygiene + history maintenance.
--
-- 1. Ledger notes written by the payout RPCs are Ukrainian (they are shown
--    verbatim in every client), and the two English rows already written are
--    translated in place.
-- 2. events.child_id gains a real FK to profiles ON DELETE CASCADE, so deleting
--    an assignee erases their journal too (orphaned rows from previously
--    deleted children are detached first).
-- 3. Owner-only maintenance RPCs: clear the journal, the location history and
--    the already-delivered notification queues — optionally only entries older
--    than a given moment. Money data (ledger, withdrawals) is deliberately NOT
--    touchable: балансы must stay reconstructable.

-- ============================================================ ukrainian ledger notes

create or replace function public.confirm_withdrawal(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare w public.withdrawals;
begin
    select * into w from public.withdrawals
     where id = p_id and child_id = auth.uid() for update;
    if not found then raise exception 'WITHDRAWAL_NOT_FOUND'; end if;
    if w.status <> 'paid' then raise exception 'INVALID_STATUS'; end if;
    update public.withdrawals set status = 'confirmed', confirmed_at = now() where id = w.id;
    -- Money confirmed received: debit the balance now (idempotent on the id).
    perform public.ledger_post(w.child_id, -w.amount, 'withdrawal', 'withdrawal', w.id,
        'готівку отримано', 'withdrawal:' || w.id::text, now());
end;
$$;
grant execute on function public.confirm_withdrawal(uuid) to authenticated;

create or replace function public.admin_withdrawal_pay(
    p_id uuid, p_method text, p_comment text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    w public.withdrawals;
    v_comment text := nullif(trim(coalesce(p_comment, '')), '');
    v_require_receipt boolean;
    v_has_receipt boolean;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if p_method not in ('card', 'cash') then raise exception 'INVALID_METHOD'; end if;
    select * into w from public.withdrawals where id = p_id for update;
    if not found then raise exception 'WITHDRAWAL_NOT_FOUND'; end if;
    if w.status <> 'approved' then raise exception 'INVALID_STATUS'; end if;

    if p_method = 'card' then
        select require_receipt_for_card into v_require_receipt from public.app_config where id;
        if coalesce(v_require_receipt, false) then
            select exists(select 1 from public.attachments
                           where withdrawal_id = w.id and role = 'receipt') into v_has_receipt;
            if not v_has_receipt then raise exception 'RECEIPT_REQUIRED'; end if;
        end if;
        update public.withdrawals
           set status = 'confirmed', method = 'card', paid_at = now(), confirmed_at = now(),
               comment = v_comment, decided_by = auth.uid()
         where id = w.id;
        -- Card: the money has left, so debit the balance now.
        perform public.ledger_post(w.child_id, -w.amount, 'withdrawal', 'withdrawal', w.id,
            'виплата на карту', 'withdrawal:' || w.id::text, now());
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (w.child_id, 'withdrawal_paid',
            jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount, 'method', 'card'));
    else
        update public.withdrawals
           set status = 'paid', method = 'cash', paid_at = now(),
               comment = v_comment, decided_by = auth.uid()
         where id = w.id;
        -- Cash: no debit yet — it is posted when the assignee confirms receipt.
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (w.child_id, 'withdrawal_cash_pending',
            jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount));
    end if;
end;
$$;
revoke all on function public.admin_withdrawal_pay(uuid, text, text) from public, anon;
grant execute on function public.admin_withdrawal_pay(uuid, text, text) to authenticated;

-- Translate the English notes already written by the previous revision.
update public.ledger_entries set note = 'готівку отримано'   where note = 'cash payout received';
update public.ledger_entries set note = 'виплата на карту'   where note = 'card payout';

-- ============================================================ journal follows its assignee

-- Rows of children deleted before this FK existed: detach, keep the record.
update public.events e
   set child_id = null
 where e.child_id is not null
   and not exists (select 1 from public.profiles p where p.id = e.child_id);

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'events_child_fk') then
        alter table public.events
            add constraint events_child_fk
            foreign key (child_id) references public.profiles (id) on delete cascade;
    end if;
end;
$$;

-- When an assignee is erased, ON DELETE CASCADE removes their tasks, bonuses
-- and payouts — and each of those deletions fires an audit trigger that logs an
-- event pointing at the profile that is being deleted in the same statement.
-- Guard the single choke point: if the referenced profile no longer exists,
-- log the event detached (the entity title still carries the context).
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
    v_child uuid := p_child;
begin
    if v_child is not null
       and not exists (select 1 from public.profiles where id = v_child) then
        v_child := null;
    end if;
    select * into a from public.event_actor();
    insert into public.events (actor_kind, actor_id, actor_name, action, entity,
                               entity_id, entity_title, child_id, details)
    values (a.kind, a.id, a.name, p_action, p_entity,
            p_entity_id, coalesce(p_title, ''), v_child, coalesce(p_details, '{}'::jsonb))
    returning id into v_id;
    -- cheap retention: keep the latest ~5000 rows
    if v_id % 200 = 0 then
        delete from public.events where id <= v_id - 5000;
    end if;
end;
$$;

-- Same cascade problem one layer deeper: erasing an assignee cascades their
-- bonuses, whose audit trigger posts a compensating ledger entry — for a child
-- that no longer exists. Money for an erased child is being erased with them,
-- so ledger_post simply skips posting when the profile is already gone.
create or replace function public.ledger_post(
    p_child       uuid,
    p_amount      numeric,
    p_kind        public.ledger_kind,
    p_source_type text default null,
    p_source_id   uuid default null,
    p_note        text default '',
    p_dedupe_key  text default null,
    p_created_at  timestamptz default null
)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    a record;
    v_id bigint;
begin
    if p_child is null then
        raise exception 'LEDGER_CHILD_NULL';
    end if;
    if not exists (select 1 from public.profiles where id = p_child) then
        return null;                              -- child mid-erasure: nothing to post to
    end if;
    if p_amount is null or p_amount = 0 then
        return null;                              -- nothing to post
    end if;
    select * into a from public.event_actor();
    insert into public.ledger_entries (
        child_id, amount, kind, source_type, source_id, note,
        created_at, actor_kind, actor_id, actor_name, dedupe_key)
    values (
        p_child, round(p_amount, 2), p_kind, p_source_type, p_source_id, coalesce(p_note, ''),
        coalesce(p_created_at, now()), a.kind, a.id, a.name, p_dedupe_key)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    return v_id;                                  -- null when deduped away
end;
$$;
revoke all on function public.ledger_post(uuid, numeric, public.ledger_kind, text, uuid, text, text, timestamptz)
    from public, anon, authenticated;

-- The "assignee deleted" journal entry must survive the deletion it records:
-- log it detached (child_id null, the name stays in the title), otherwise the
-- new FK rejects it mid-cascade.
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
        perform public.log_event('deleted', 'child', old.id, old.display_name, null);
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

-- ============================================================ maintenance RPCs (owner only)

create or replace function public.assert_owner()
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
    -- service_role (no JWT) passes; a signed-in caller must be an active owner.
    if auth.uid() is not null and not exists (
        select 1 from public.parents
         where id = auth.uid() and is_owner and not coalesce(disabled, false)
    ) then
        raise exception 'NOT_OWNER';
    end if;
end;
$$;
revoke all on function public.assert_owner() from public, anon;
grant execute on function public.assert_owner() to authenticated;

-- Clear the audit journal (all of it, or entries before p_before). Telegram
-- queue rows that were already delivered for those events go too; undelivered
-- ones are kept so pending owner notifications still go out.
create or replace function public.admin_clear_journal(p_before timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
    perform public.assert_owner();
    delete from public.tg_outbox q
     using public.events e
     where q.event_id = e.id and q.sent_at is not null
       and (p_before is null or e.created_at < p_before);
    delete from public.events
     where p_before is null or created_at < p_before;
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;
revoke all on function public.admin_clear_journal(timestamptz) from public, anon;
grant execute on function public.admin_clear_journal(timestamptz) to authenticated;

-- Clear the assignees' location history.
create or replace function public.admin_clear_locations(p_before timestamptz default null)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer;
begin
    perform public.assert_owner();
    delete from public.locations
     where p_before is null or created_at < p_before;
    get diagnostics v_count = row_count;
    return v_count;
end;
$$;
revoke all on function public.admin_clear_locations(timestamptz) from public, anon;
grant execute on function public.admin_clear_locations(timestamptz) to authenticated;

-- Drop already-delivered rows from both notification queues. Pending rows
-- (sent_at is null) are never touched.
create or replace function public.admin_clear_delivered_queue()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_count integer := 0; v_part integer;
begin
    perform public.assert_owner();
    delete from public.notifications_outbox where sent_at is not null;
    get diagnostics v_part = row_count;
    v_count := v_part;
    delete from public.tg_outbox where sent_at is not null;
    get diagnostics v_part = row_count;
    return v_count + v_part;
end;
$$;
revoke all on function public.admin_clear_delivered_queue() from public, anon;
grant execute on function public.admin_clear_delivered_queue() to authenticated;
