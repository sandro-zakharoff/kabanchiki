-- Kabanchiki: ledger notes in Ukrainian (were English in a few RPCs) + fix
-- already-posted entries. The kind label already conveys the type, so reserve
-- and final-settle notes become empty; refunds/bonus edits get short Ukrainian.

create or replace function public.request_withdrawal(p_amount numeric default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_child   uuid := auth.uid();
    v_min     numeric(12, 2);
    v_enabled boolean;
    v_auto    numeric(12, 2);
    v_bal     numeric(12, 2);
    v_amount  numeric(12, 2);
    v_id      uuid;
begin
    if v_child is null then raise exception 'NOT_AUTHENTICATED'; end if;
    if public.is_blocked(v_child) then raise exception 'BLOCKED'; end if;
    perform 1 from public.profiles where id = v_child for update;
    select min_withdrawal, withdrawals_enabled, auto_approve_below
      into v_min, v_enabled, v_auto
      from public.app_config where id;
    if not coalesce(v_enabled, true) then raise exception 'WITHDRAWALS_DISABLED'; end if;
    perform public.reconcile_assignee(v_child);
    v_bal := public.ledger_balance(v_child);
    v_amount := round(coalesce(p_amount, v_bal), 2);
    if v_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
    if v_amount < coalesce(v_min, 0) then raise exception 'BELOW_MINIMUM'; end if;
    if v_amount > v_bal then raise exception 'ABOVE_BALANCE'; end if;
    insert into public.withdrawals (child_id, amount, status)
    values (v_child, v_amount, 'requested') returning id into v_id;
    perform public.ledger_post(v_child, -v_amount, 'withdrawal', 'withdrawal', v_id,
        '', 'withdrawal:' || v_id::text, now());
    if coalesce(v_auto, 0) > 0 and v_amount <= v_auto then
        update public.withdrawals set status = 'approved', approved_at = now() where id = v_id;
    end if;
    return v_id;
end;
$$;
grant execute on function public.request_withdrawal(numeric) to authenticated;

create or replace function public.cancel_withdrawal(p_id uuid)
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
    if w.status not in ('requested', 'approved') then raise exception 'INVALID_STATUS'; end if;
    update public.withdrawals
       set status = 'rejected', reject_reason = 'cancelled', decided_at = now()
     where id = w.id;
    perform public.withdrawal_refund(w.id, w.child_id, w.amount, 'вивід скасовано');
end;
$$;
grant execute on function public.cancel_withdrawal(uuid) to authenticated;

create or replace function public.admin_withdrawal_reject(p_id uuid, p_reason text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    w public.withdrawals;
    v_reason text := nullif(trim(coalesce(p_reason, '')), '');
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into w from public.withdrawals where id = p_id for update;
    if not found then raise exception 'WITHDRAWAL_NOT_FOUND'; end if;
    if w.status not in ('requested', 'approved') then raise exception 'INVALID_STATUS'; end if;
    update public.withdrawals
       set status = 'rejected', reject_reason = v_reason, decided_at = now(), decided_by = auth.uid()
     where id = w.id;
    perform public.withdrawal_refund(w.id, w.child_id, w.amount, 'вивід відхилено');
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (w.child_id, 'withdrawal_rejected',
        jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount, 'reason', v_reason));
end;
$$;
grant execute on function public.admin_withdrawal_reject(uuid, text) to authenticated;

create or replace function public.trg_job_member_final_settle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_money numeric(12, 2);
begin
    v_money := public.job_member_unsettled_money(old.job_id, old.child_id);
    if v_money <> 0 then
        perform public.ledger_post(old.child_id, v_money, 'job', 'job', old.job_id, '', null, now());
    end if;
    return old;
end;
$$;

create or replace function public.trg_bonus_ledger()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        perform public.ledger_post(new.child_id, new.amount, 'bonus', 'bonus', new.id,
            coalesce(new.note, ''), 'bonus:' || new.id::text, new.created_at);
        return new;
    elsif tg_op = 'UPDATE' then
        if new.amount is distinct from old.amount then
            perform public.ledger_post(new.child_id, new.amount - old.amount, 'adjustment', 'bonus',
                new.id, 'бонус змінено', null, now());
        end if;
        return new;
    elsif tg_op = 'DELETE' then
        perform public.ledger_post(old.child_id, -old.amount, 'reversal', 'bonus', old.id,
            'бонус видалено', null, now());
        return old;
    end if;
    return null;
end;
$$;

-- Fix already-posted English notes.
update public.ledger_entries set note = ''               where note = 'withdrawal request';
update public.ledger_entries set note = 'вивід скасовано' where note = 'withdrawal cancelled';
update public.ledger_entries set note = 'вивід відхилено' where note = 'withdrawal rejected';
update public.ledger_entries set note = ''               where note = 'final';
update public.ledger_entries set note = 'бонус змінено'   where note = 'bonus edited';
update public.ledger_entries set note = 'бонус видалено'  where note = 'bonus removed';
