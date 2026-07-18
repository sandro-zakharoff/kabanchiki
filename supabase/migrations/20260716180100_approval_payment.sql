-- Kabanchiki: parent review of finished tasks + payment tracking.
--
-- New task lifecycle: child completes -> 'submitted' (awaiting review). Parent
-- reviews: approve -> 'done', reject -> 'declined', rework -> back to 'new'.
-- Payment is a separate axis (unpaid / awaiting / paid) on tasks and withdrawals.

create type public.payment_status as enum ('unpaid', 'awaiting', 'paid');

alter table public.tasks
    add column payment_status public.payment_status not null default 'unpaid',
    add column paid_at timestamptz;

alter table public.withdrawals
    add column payment_status public.payment_status not null default 'unpaid',
    add column paid_at timestamptz;

-- ---------------------------------------------------------------- task_complete
-- Now finishes into 'submitted' instead of 'done'. Keeps the simple/timer branch
-- and the block guard from earlier migrations.
create or replace function public.task_complete(
    p_task_id uuid,
    p_proof_text text default null,
    p_proof_photo_path text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    v_seconds integer := 0;
    v_earned numeric(12, 2);
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;

    if t.completion_mode = 'simple' then
        if t.status <> 'new' then
            raise exception 'INVALID_STATUS';
        end if;
    else
        if t.status not in ('in_progress', 'paused') then
            raise exception 'INVALID_STATUS';
        end if;
    end if;

    if t.proof_text = 'required' and (p_proof_text is null or length(trim(p_proof_text)) = 0) then
        raise exception 'PROOF_TEXT_REQUIRED';
    end if;
    if t.proof_photo = 'required' and (p_proof_photo_path is null or length(trim(p_proof_photo_path)) = 0) then
        raise exception 'PROOF_PHOTO_REQUIRED';
    end if;

    if t.completion_mode = 'timer' then
        update public.task_intervals set ended_at = now()
         where task_id = t.id and ended_at is null;
        select coalesce(sum(extract(epoch from i.ended_at - i.started_at)), 0)::int
          into v_seconds
          from public.task_intervals i
         where i.task_id = t.id and i.ended_at is not null;
    end if;

    if t.reward_type = 'fixed' then
        v_earned := t.reward_amount;
    else
        v_earned := round(v_seconds / 3600.0 * t.reward_amount, 2);
    end if;

    update public.tasks
       set status = 'submitted',
           completed_at = now(),
           decline_reason = null,
           total_seconds = v_seconds,
           earned_amount = v_earned,
           proof_text_content = nullif(trim(coalesce(p_proof_text, '')), ''),
           proof_photo_path = nullif(trim(coalesce(p_proof_photo_path, '')), '')
     where id = t.id;
end;
$$;

-- ---------------------------------------------------------------- task_review (parent)
create or replace function public.task_review(
    p_task_id uuid,
    p_action text,           -- 'approve' | 'reject' | 'rework'
    p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
    select * into t from public.tasks where id = p_task_id for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.status <> 'submitted' then
        raise exception 'INVALID_STATUS';
    end if;

    if p_action = 'approve' then
        update public.tasks set status = 'done', completed_at = now(), decline_reason = null
         where id = t.id;
    elsif p_action = 'reject' then
        update public.tasks
           set status = 'declined', decline_reason = v_note, earned_amount = null, completed_at = now()
         where id = t.id;
    elsif p_action = 'rework' then
        -- Back to the assignee to redo. Accumulated time is kept.
        update public.tasks set status = 'new', decline_reason = v_note, completed_at = null
         where id = t.id;
    else
        raise exception 'INVALID_ACTION';
    end if;

    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (t.child_id, 'task_reviewed', jsonb_build_object(
        'task_id', t.id, 'title', t.title, 'action', p_action,
        'note', v_note, 'amount', t.earned_amount
    ));
end;
$$;

-- ---------------------------------------------------------------- payments (parent)
create or replace function public.task_set_payment(p_task_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
begin
    if p_status not in ('unpaid', 'awaiting', 'paid') then
        raise exception 'INVALID_STATUS';
    end if;
    select * into t from public.tasks where id = p_task_id for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.status <> 'done' then
        raise exception 'INVALID_STATUS';
    end if;
    update public.tasks
       set payment_status = p_status::public.payment_status,
           paid_at = case when p_status = 'paid' then now() else null end
     where id = t.id;
    if p_status = 'paid' then
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (t.child_id, 'task_paid', jsonb_build_object(
            'task_id', t.id, 'title', t.title, 'amount', t.earned_amount
        ));
    end if;
end;
$$;

create or replace function public.withdrawal_set_payment(p_withdrawal_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    w public.withdrawals;
begin
    if p_status not in ('unpaid', 'awaiting', 'paid') then
        raise exception 'INVALID_STATUS';
    end if;
    select * into w from public.withdrawals where id = p_withdrawal_id for update;
    if not found then
        raise exception 'WITHDRAWAL_NOT_FOUND';
    end if;
    if w.status <> 'approved' then
        raise exception 'INVALID_STATUS';
    end if;
    update public.withdrawals
       set payment_status = p_status::public.payment_status,
           paid_at = case when p_status = 'paid' then now() else null end
     where id = w.id;
    if p_status = 'paid' then
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (w.child_id, 'withdrawal_paid', jsonb_build_object(
            'withdrawal_id', w.id, 'amount', w.amount
        ));
    end if;
end;
$$;

-- Approving a withdrawal now marks it as awaiting payment.
create or replace function public.admin_decide_withdrawal(p_withdrawal_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    w public.withdrawals;
begin
    select * into w from public.withdrawals where id = p_withdrawal_id for update;
    if not found then
        raise exception 'WITHDRAWAL_NOT_FOUND';
    end if;
    if w.status <> 'pending' then
        raise exception 'ALREADY_DECIDED';
    end if;

    update public.withdrawals
       set status = case when p_approve then 'approved'::public.withdrawal_status
                         else 'declined'::public.withdrawal_status end,
           payment_status = case when p_approve then 'awaiting'::public.payment_status
                                 else 'unpaid'::public.payment_status end,
           decided_at = now()
     where id = w.id;

    if p_approve then
        update public.job_members
           set earnings_reset_at = w.period_to,
               total_withdrawn = total_withdrawn + w.amount
         where job_id = w.job_id and child_id = w.child_id;
    end if;
end;
$$;

-- Parent-only RPCs (desktop/service_role for now; parent-guarded in phase 3).
revoke execute on function
    public.task_review(uuid, text, text),
    public.task_set_payment(uuid, text),
    public.withdrawal_set_payment(uuid, text)
from public, anon, authenticated;
