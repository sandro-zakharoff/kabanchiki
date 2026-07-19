-- Kabanchiki: debit the balance only when the money actually leaves.
--
-- Before, a withdrawal reserved (debited) the balance the moment it was
-- requested or created, and refunded it on reject/cancel. That surprised
-- users: a cash payout showed as "withdrawn" and lowered the balance before
-- the assignee had confirmed receiving the cash.
--
-- New rule — the ledger debit is posted exactly once, at the moment money
-- truly changes hands:
--   * card  -> at admin_withdrawal_pay (the owner sent it, the receipt is proof)
--   * cash  -> at confirm_withdrawal   (the assignee confirms they received it)
-- Until then the balance is untouched. An assignee can also say they did NOT
-- receive the cash (decline_withdrawal): no debit, the money stays.
--
-- Over-withdrawal is prevented by checking the available balance
-- (balance minus the amounts already tied up in open payouts) at creation time,
-- instead of by an eager reservation.
--
-- The debit keeps the dedupe key 'withdrawal:<id>', the same one the old
-- reservation used, so any withdrawal that was already reserved under the old
-- model can never be debited twice (ON CONFLICT DO NOTHING).

-- ============================================================ helper: tied-up funds

-- Sum of amounts in open payouts (not yet paid out or still awaiting cash
-- confirmation). Used to compute how much is still free to withdraw.
create or replace function public.withdrawal_open_total(p_child uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select coalesce(sum(amount), 0)::numeric(12, 2)
      from public.withdrawals
     where child_id = p_child and status in ('requested', 'approved', 'paid');
$$;
revoke all on function public.withdrawal_open_total(uuid) from public, anon, authenticated;

-- ============================================================ assignee: request

create or replace function public.request_withdrawal(p_amount numeric default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_child     uuid := auth.uid();
    v_min       numeric(12, 2);
    v_enabled   boolean;
    v_auto      numeric(12, 2);
    v_bal       numeric(12, 2);
    v_available numeric(12, 2);
    v_amount    numeric(12, 2);
    v_id        uuid;
begin
    if v_child is null then raise exception 'NOT_AUTHENTICATED'; end if;
    if public.is_blocked(v_child) then raise exception 'BLOCKED'; end if;

    -- serialise concurrent requests for this assignee (prevents over-commit)
    perform 1 from public.profiles where id = v_child for update;

    select min_withdrawal, withdrawals_enabled, auto_approve_below
      into v_min, v_enabled, v_auto
      from public.app_config where id;
    if not coalesce(v_enabled, true) then raise exception 'WITHDRAWALS_DISABLED'; end if;

    -- crystallise the live job tail so it counts as withdrawable
    perform public.reconcile_assignee(v_child);
    v_bal       := public.ledger_balance(v_child);
    v_available := v_bal - public.withdrawal_open_total(v_child);

    v_amount := round(coalesce(p_amount, v_available), 2);   -- null = all that is free
    if v_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
    if v_amount < coalesce(v_min, 0) then raise exception 'BELOW_MINIMUM'; end if;
    if v_amount > v_available then raise exception 'ABOVE_BALANCE'; end if;

    insert into public.withdrawals (child_id, amount, status)
    values (v_child, v_amount, 'requested') returning id into v_id;
    -- No ledger debit here: the balance is untouched until the payout completes.

    if coalesce(v_auto, 0) > 0 and v_amount <= v_auto then
        update public.withdrawals set status = 'approved', approved_at = now() where id = v_id;
    end if;
    return v_id;
end;
$$;
grant execute on function public.request_withdrawal(numeric) to authenticated;

-- ============================================================ owner: create directly

create or replace function public.admin_create_withdrawal(p_child uuid, p_amount numeric default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_bal       numeric(12, 2);
    v_available numeric(12, 2);
    v_amount    numeric(12, 2);
    v_id        uuid;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if not exists (select 1 from public.profiles where id = p_child) then raise exception 'CHILD_NOT_FOUND'; end if;

    perform 1 from public.profiles where id = p_child for update;   -- serialise with requests
    perform public.reconcile_assignee(p_child);                     -- settle live job tail
    v_bal       := public.ledger_balance(p_child);
    v_available := v_bal - public.withdrawal_open_total(p_child);

    v_amount := round(coalesce(p_amount, v_available), 2);           -- null = all that is free
    if v_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
    if v_amount > v_available then raise exception 'ABOVE_BALANCE'; end if;

    insert into public.withdrawals (child_id, amount, status, approved_at, decided_at, decided_by)
    values (p_child, v_amount, 'approved', now(), now(), auth.uid())
    returning id into v_id;
    -- No ledger debit here either: it is posted when the payout completes.
    return v_id;
end;
$$;
revoke all on function public.admin_create_withdrawal(uuid, numeric) from public, anon;
grant execute on function public.admin_create_withdrawal(uuid, numeric) to authenticated;

-- ============================================================ owner: pay

-- Card -> debit now (money sent) and close. Cash -> mark 'paid' and wait for the
-- assignee to confirm; nothing is debited until they do.
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
            'card payout', 'withdrawal:' || w.id::text, now());
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

-- ============================================================ assignee: confirm / decline cash

-- The assignee confirms they received the cash -> debit the balance now.
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
        'cash payout received', 'withdrawal:' || w.id::text, now());
end;
$$;
grant execute on function public.confirm_withdrawal(uuid) to authenticated;

-- The assignee says they did NOT receive the cash -> no debit, the money stays.
-- Returns to the owner's attention as a rejected payout marked 'not_received'.
create or replace function public.decline_withdrawal(p_id uuid)
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
    update public.withdrawals
       set status = 'rejected', reject_reason = 'not_received', decided_at = now()
     where id = w.id;
    -- No ledger change: nothing was debited, the balance is intact. The status
    -- change is logged as an event, so owners are notified over Telegram
    -- through the existing events -> tg_outbox path.
end;
$$;
grant execute on function public.decline_withdrawal(uuid) to authenticated;

-- ============================================================ reject / cancel: no refund needed

-- Nothing was debited before payout, so rejecting or cancelling an open payout
-- just closes it — no compensating ledger entry.
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
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (w.child_id, 'withdrawal_rejected',
        jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount, 'reason', v_reason));
end;
$$;
revoke all on function public.admin_withdrawal_reject(uuid, text) from public, anon;
grant execute on function public.admin_withdrawal_reject(uuid, text) to authenticated;

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
end;
$$;
grant execute on function public.cancel_withdrawal(uuid) to authenticated;

-- The eager-reservation refund helper is no longer used by any flow.
drop function if exists public.withdrawal_refund(uuid, uuid, numeric, text);
