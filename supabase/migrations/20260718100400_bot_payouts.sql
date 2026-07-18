-- Kabanchiki: point the bot's payout quick-actions at the new RPCs, and let
-- owners hear when an assignee confirms a cash payout.

-- bot_act: wd_approve/wd_decline now use the personal-balance payout RPCs
-- (admin_decide_withdrawal was removed). A bot decline carries no typed reason.
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
        when 'wd_approve'   then perform public.admin_withdrawal_approve(p_target);
        when 'wd_decline'   then perform public.admin_withdrawal_reject(p_target, p_note);
        else raise exception 'UNKNOWN_ACTION';
    end case;
end;
$$;

revoke execute on function public.bot_act(uuid, text, uuid, text)
    from public, anon, authenticated;

-- Notify owners on withdrawal request AND on cash-receipt confirmation.
create or replace function public.trg_events_tg_outbox()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if (new.actor_kind = 'child'
        and ((new.entity = 'task' and new.action in ('started', 'submitted', 'declined', 'completed'))
             or (new.entity = 'withdrawal' and new.action in ('requested', 'confirmed'))))
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
