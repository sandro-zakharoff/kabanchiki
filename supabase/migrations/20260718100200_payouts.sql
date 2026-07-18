-- Kabanchiki: payouts from the personal balance (new withdrawal lifecycle).
--
-- Withdrawals are no longer per-job. An assignee requests an amount from their
-- whole balance; the amount is reserved immediately by a ledger debit (so it is
-- impossible to request more than available, even concurrently). Lifecycle:
--   requested -> approved -> paid -> confirmed        (+ rejected, with reason)
-- Payment method is fixed at payout: card (attach a receipt) or cash (the
-- assignee must confirm receipt — two-way confirmation).

-- ============================================================ tear down the old model

drop trigger  if exists withdrawal_decided_outbox on public.withdrawals;
drop function if exists public.trg_withdrawal_decided();

drop function if exists public.request_withdrawal(uuid, numeric);
drop function if exists public.admin_decide_withdrawal(uuid, boolean);
drop function if exists public.withdrawal_set_payment(uuid, text);

drop index if exists public.withdrawals_pending_uniq;   -- was partial on job_id

-- ============================================================ new enums

create type public.payout_status as enum ('requested', 'approved', 'paid', 'confirmed', 'rejected');
create type public.payout_method as enum ('card', 'cash');

-- ============================================================ reshape withdrawals

alter table public.withdrawals alter column status drop default;
alter table public.withdrawals
    alter column status type public.payout_status using (
        case status::text
            when 'pending'  then 'requested'
            when 'approved' then 'approved'
            when 'declined' then 'rejected'
            else 'requested'
        end::public.payout_status);
alter table public.withdrawals alter column status set default 'requested';

alter table public.withdrawals
    drop column if exists job_id,
    drop column if exists period_from,
    drop column if exists period_to,
    drop column if exists payment_status,
    add  column if not exists method       public.payout_method,
    add  column if not exists reject_reason text,
    add  column if not exists comment      text,
    add  column if not exists approved_at   timestamptz,
    add  column if not exists confirmed_at  timestamptz,
    add  column if not exists decided_by    uuid;

drop type if exists public.withdrawal_status;

-- job_members no longer track per-job withdrawal state
alter table public.job_members
    drop column if exists earnings_reset_at,
    drop column if exists total_withdrawn,
    drop column if exists withdrawn_since_reset;

-- ============================================================ receipts (attachments)

alter table public.attachments alter column task_id drop not null;
alter table public.attachments
    add column if not exists withdrawal_id uuid references public.withdrawals (id) on delete cascade;
alter table public.attachments drop constraint attachments_role_check;
alter table public.attachments
    add constraint attachments_role_check check (role in ('task', 'proof', 'receipt'));
alter table public.attachments
    add constraint attachments_parent_chk
    check ((task_id is not null)::int + (withdrawal_id is not null)::int = 1);
create index if not exists attachments_withdrawal_idx on public.attachments (withdrawal_id);

create policy "child reads own receipt attachments" on public.attachments
    for select to authenticated using (
        withdrawal_id is not null and exists (
            select 1 from public.withdrawals w
             where w.id = attachments.withdrawal_id and w.child_id = auth.uid()));

-- ============================================================ audit trigger (rebuilt, no job)

create or replace function public.trg_events_withdrawals()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if tg_op = 'INSERT' then
        perform public.log_event('requested', 'withdrawal', new.id, '', new.child_id,
            jsonb_build_object('amount', new.amount));
        return new;
    elsif tg_op = 'DELETE' then
        perform public.log_event('deleted', 'withdrawal', old.id, '', old.child_id,
            jsonb_build_object('amount', old.amount));
        return old;
    end if;

    if new.status is distinct from old.status then
        perform public.log_event(new.status::text, 'withdrawal', new.id, '', new.child_id,
            jsonb_strip_nulls(jsonb_build_object(
                'amount', new.amount,
                'method', new.method,
                'reason', new.reject_reason)));
    end if;
    return new;
end;
$$;

-- ============================================================ assignee: request / cancel / confirm

-- Request an amount (null = whole balance) from the personal balance.
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

    -- serialise concurrent requests for this assignee (prevents over-reserve)
    perform 1 from public.profiles where id = v_child for update;

    select min_withdrawal, withdrawals_enabled, auto_approve_below
      into v_min, v_enabled, v_auto
      from public.app_config where id;
    if not coalesce(v_enabled, true) then raise exception 'WITHDRAWALS_DISABLED'; end if;

    -- crystallise the live job tail so it becomes withdrawable and reservable
    perform public.reconcile_assignee(v_child);
    v_bal := public.ledger_balance(v_child);

    v_amount := round(coalesce(p_amount, v_bal), 2);
    if v_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
    if v_amount < coalesce(v_min, 0) then raise exception 'BELOW_MINIMUM'; end if;
    if v_amount > v_bal then raise exception 'ABOVE_BALANCE'; end if;

    insert into public.withdrawals (child_id, amount, status)
    values (v_child, v_amount, 'requested') returning id into v_id;

    -- reserve: debit the balance now, idempotent on the withdrawal id
    perform public.ledger_post(v_child, -v_amount, 'withdrawal', 'withdrawal', v_id,
        'withdrawal request', 'withdrawal:' || v_id::text, now());

    -- optional auto-approval of small amounts
    if coalesce(v_auto, 0) > 0 and v_amount <= v_auto then
        update public.withdrawals set status = 'approved', approved_at = now() where id = v_id;
    end if;
    return v_id;
end;
$$;
grant execute on function public.request_withdrawal(numeric) to authenticated;

-- Return the reserved funds to the balance, exactly once (reject or cancel).
create or replace function public.withdrawal_refund(p_id uuid, p_child uuid, p_amount numeric, p_note text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    perform public.ledger_post(p_child, p_amount, 'reversal', 'withdrawal', p_id,
        p_note, 'withdrawal-refund:' || p_id::text, now());
end;
$$;
revoke all on function public.withdrawal_refund(uuid, uuid, numeric, text) from public, anon, authenticated;

-- Assignee cancels their own not-yet-paid request.
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
    perform public.withdrawal_refund(w.id, w.child_id, w.amount, 'withdrawal cancelled');
end;
$$;
grant execute on function public.cancel_withdrawal(uuid) to authenticated;

-- Assignee confirms cash receipt (closes a cash payout).
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
end;
$$;
grant execute on function public.confirm_withdrawal(uuid) to authenticated;

-- ============================================================ admin: approve / reject / pay

create or replace function public.admin_withdrawal_approve(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare w public.withdrawals;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into w from public.withdrawals where id = p_id for update;
    if not found then raise exception 'WITHDRAWAL_NOT_FOUND'; end if;
    if w.status <> 'requested' then raise exception 'INVALID_STATUS'; end if;
    update public.withdrawals
       set status = 'approved', approved_at = now(), decided_at = now(), decided_by = auth.uid()
     where id = w.id;
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (w.child_id, 'withdrawal_approved', jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount));
end;
$$;

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
    perform public.withdrawal_refund(w.id, w.child_id, w.amount, 'withdrawal rejected');
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (w.child_id, 'withdrawal_rejected',
        jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount, 'reason', v_reason));
end;
$$;

-- Mark the payout done. Card -> closed immediately (receipt is the record);
-- cash -> 'paid', awaiting the assignee's confirmation.
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
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (w.child_id, 'withdrawal_paid',
            jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount, 'method', 'card'));
    else
        update public.withdrawals
           set status = 'paid', method = 'cash', paid_at = now(),
               comment = v_comment, decided_by = auth.uid()
         where id = w.id;
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (w.child_id, 'withdrawal_cash_pending',
            jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount));
    end if;
end;
$$;

revoke all on function public.admin_withdrawal_approve(uuid) from public, anon;
revoke all on function public.admin_withdrawal_reject(uuid, text) from public, anon;
revoke all on function public.admin_withdrawal_pay(uuid, text, text) from public, anon;
grant execute on function public.admin_withdrawal_approve(uuid) to authenticated;
grant execute on function public.admin_withdrawal_reject(uuid, text) to authenticated;
grant execute on function public.admin_withdrawal_pay(uuid, text, text) to authenticated;

-- ============================================================ manual adjustments + ledger-backed bonuses

-- Parent bonus / penalty / correction. Sign carries meaning; note is mandatory.
create or replace function public.admin_adjust_balance(p_child uuid, p_amount numeric, p_note text)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_note text := nullif(trim(coalesce(p_note, '')), ''); v_id bigint;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if p_amount is null or p_amount = 0 then raise exception 'INVALID_AMOUNT'; end if;
    if v_note is null then raise exception 'NOTE_REQUIRED'; end if;
    if not exists(select 1 from public.profiles where id = p_child) then raise exception 'CHILD_NOT_FOUND'; end if;
    v_id := public.ledger_post(p_child, round(p_amount, 2), 'adjustment', 'manual', null, v_note, null, now());
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (p_child, 'balance_adjusted', jsonb_build_object('amount', round(p_amount, 2), 'note', v_note));
    return v_id;
end;
$$;
revoke all on function public.admin_adjust_balance(uuid, numeric, text) from public, anon;
grant execute on function public.admin_adjust_balance(uuid, numeric, text) to authenticated;

-- Bonuses stay as an input surface but are now ledger-backed (single source of
-- truth is the ledger). Insert -> credit; edit -> delta; delete -> reversal.
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
                new.id, 'bonus edited', null, now());
        end if;
        return new;
    elsif tg_op = 'DELETE' then
        perform public.ledger_post(old.child_id, -old.amount, 'reversal', 'bonus', old.id,
            'bonus removed', null, now());
        return old;
    end if;
    return null;
end;
$$;
create trigger bonus_ledger after insert or update or delete on public.bonuses
for each row execute function public.trg_bonus_ledger();
