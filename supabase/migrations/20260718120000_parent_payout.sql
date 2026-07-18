-- Kabanchiki: parent-initiated payouts.
--
-- Until now only an assignee could start a withdrawal (request_withdrawal).
-- admin_create_withdrawal lets an owner pay an assignee directly: it creates an
-- already-approved payout from the assignee's balance and reserves the amount.
-- The owner then settles it with the existing admin_withdrawal_pay (card /
-- cash + confirmation), so the whole payment/receipt/confirmation flow is
-- reused unchanged. Money can never exceed the current balance.

create or replace function public.admin_create_withdrawal(p_child uuid, p_amount numeric default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_bal    numeric(12, 2);
    v_amount numeric(12, 2);
    v_id     uuid;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if not exists (select 1 from public.profiles where id = p_child) then raise exception 'CHILD_NOT_FOUND'; end if;

    perform 1 from public.profiles where id = p_child for update;   -- serialise with requests
    perform public.reconcile_assignee(p_child);                     -- settle live job tail
    v_bal := public.ledger_balance(p_child);

    v_amount := round(coalesce(p_amount, v_bal), 2);                 -- null = whole balance
    if v_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
    if v_amount > v_bal then raise exception 'ABOVE_BALANCE'; end if;

    insert into public.withdrawals (child_id, amount, status, approved_at, decided_at, decided_by)
    values (p_child, v_amount, 'approved', now(), now(), auth.uid())
    returning id into v_id;

    perform public.ledger_post(p_child, -v_amount, 'withdrawal', 'withdrawal', v_id,
        '', 'withdrawal:' || v_id::text, now());
    return v_id;
end;
$$;

revoke all on function public.admin_create_withdrawal(uuid, numeric) from public, anon;
grant execute on function public.admin_create_withdrawal(uuid, numeric) to authenticated;
