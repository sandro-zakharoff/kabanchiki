-- Kabanchiki: real parent accounts.
--
-- Parents are Supabase auth users listed in public.parents. They get full RLS
-- access to all family data, so the desktop (and later the Telegram app) can
-- work while authenticated as a parent instead of holding the service_role key.
-- Auth-admin operations (creating child/parent accounts, passwords, bans) still
-- need service_role and go through the 'admin' Edge Function.

create table public.parents (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text not null,
    email text,
    telegram_id bigint unique,
    is_owner boolean not null default false,
    created_at timestamptz not null default now()
);

alter table public.parents enable row level security;

create or replace function public.is_parent(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists(select 1 from public.parents where id = p_uid);
$$;

grant execute on function public.is_parent(uuid) to authenticated;

-- Parents can see each other (to list owners in the UI).
create policy "parents read" on public.parents
    for select to authenticated using (public.is_parent(auth.uid()));

-- ============================================================ RLS: parent full access
-- Additive to the existing child "own row" policies (policies are OR'd).

create policy "parent all tasks" on public.tasks
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

create policy "parent all task_intervals" on public.task_intervals
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

create policy "parent all jobs" on public.jobs
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

create policy "parent all job_members" on public.job_members
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

create policy "parent all job_sessions" on public.job_sessions
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

create policy "parent all withdrawals" on public.withdrawals
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

create policy "parent all bonuses" on public.bonuses
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

create policy "parent all devices" on public.devices
    for select to authenticated using (public.is_parent(auth.uid()));

create policy "parent all app_releases" on public.app_releases
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

-- Profiles: parents read all and edit (name/color/blocked). Create/delete of
-- child profiles happens in the admin Edge Function together with the auth user.
create policy "parent read profiles" on public.profiles
    for select to authenticated using (public.is_parent(auth.uid()));

create policy "parent update profiles" on public.profiles
    for update to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

-- ============================================================ storage: parent access

create policy "parent uploads task photos" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'task-photos' and public.is_parent(auth.uid()));

create policy "parent reads task photos" on storage.objects
    for select to authenticated
    using (bucket_id = 'task-photos' and public.is_parent(auth.uid()));

create policy "parent reads proof photos" on storage.objects
    for select to authenticated
    using (bucket_id = 'proof-photos' and public.is_parent(auth.uid()));

create policy "parent manages releases" on storage.objects
    for all to authenticated
    using (bucket_id = 'app-releases' and public.is_parent(auth.uid()))
    with check (bucket_id = 'app-releases' and public.is_parent(auth.uid()));

-- ============================================================ realtime for parents

alter table public.parents replica identity full;
alter publication supabase_realtime add table public.parents;

-- ============================================================ RPC guards
-- Allow parents (and service_role, whose auth.uid() is null) to call the
-- privileged RPCs; a signed-in child is rejected. Then grant to authenticated.

create or replace function public.admin_decide_withdrawal(p_withdrawal_id uuid, p_approve boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    w public.withdrawals;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into w from public.withdrawals where id = p_withdrawal_id for update;
    if not found then raise exception 'WITHDRAWAL_NOT_FOUND'; end if;
    if w.status <> 'pending' then raise exception 'ALREADY_DECIDED'; end if;

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

create or replace function public.admin_job_start(p_job_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare j public.jobs;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into j from public.jobs where id = p_job_id for update;
    if not found then raise exception 'JOB_NOT_FOUND'; end if;
    if j.status <> 'idle' then raise exception 'INVALID_STATUS'; end if;
    update public.jobs set status = 'running' where id = j.id;
    insert into public.job_sessions (job_id) values (j.id);
end; $$;

create or replace function public.admin_job_stop(p_job_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare j public.jobs;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into j from public.jobs where id = p_job_id for update;
    if not found then raise exception 'JOB_NOT_FOUND'; end if;
    if j.status <> 'running' then raise exception 'INVALID_STATUS'; end if;
    update public.job_sessions set ended_at = now() where job_id = j.id and ended_at is null;
    update public.jobs set status = 'idle' where id = j.id;
end; $$;

create or replace function public.admin_job_archive(p_job_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    update public.job_sessions set ended_at = now() where job_id = p_job_id and ended_at is null;
    update public.jobs set status = 'archived' where id = p_job_id;
end; $$;

-- task_review / payments: add the same guard.
create or replace function public.task_review(p_task_id uuid, p_action text, p_note text default null)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare t public.tasks; v_note text := nullif(trim(coalesce(p_note, '')), '');
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into t from public.tasks where id = p_task_id for update;
    if not found then raise exception 'TASK_NOT_FOUND'; end if;
    if t.status <> 'submitted' then raise exception 'INVALID_STATUS'; end if;
    if p_action = 'approve' then
        update public.tasks set status = 'done', completed_at = now(), decline_reason = null where id = t.id;
    elsif p_action = 'reject' then
        update public.tasks set status = 'declined', decline_reason = v_note, earned_amount = null, completed_at = now() where id = t.id;
    elsif p_action = 'rework' then
        update public.tasks set status = 'new', decline_reason = v_note, completed_at = null where id = t.id;
    else raise exception 'INVALID_ACTION';
    end if;
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (t.child_id, 'task_reviewed', jsonb_build_object(
        'task_id', t.id, 'title', t.title, 'action', p_action, 'note', v_note, 'amount', t.earned_amount));
end; $$;

create or replace function public.task_set_payment(p_task_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare t public.tasks;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if p_status not in ('unpaid', 'awaiting', 'paid') then raise exception 'INVALID_STATUS'; end if;
    select * into t from public.tasks where id = p_task_id for update;
    if not found then raise exception 'TASK_NOT_FOUND'; end if;
    if t.status <> 'done' then raise exception 'INVALID_STATUS'; end if;
    update public.tasks set payment_status = p_status::public.payment_status,
           paid_at = case when p_status = 'paid' then now() else null end where id = t.id;
    if p_status = 'paid' then
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (t.child_id, 'task_paid', jsonb_build_object('task_id', t.id, 'title', t.title, 'amount', t.earned_amount));
    end if;
end; $$;

create or replace function public.withdrawal_set_payment(p_withdrawal_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare w public.withdrawals;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if p_status not in ('unpaid', 'awaiting', 'paid') then raise exception 'INVALID_STATUS'; end if;
    select * into w from public.withdrawals where id = p_withdrawal_id for update;
    if not found then raise exception 'WITHDRAWAL_NOT_FOUND'; end if;
    if w.status <> 'approved' then raise exception 'INVALID_STATUS'; end if;
    update public.withdrawals set payment_status = p_status::public.payment_status,
           paid_at = case when p_status = 'paid' then now() else null end where id = w.id;
    if p_status = 'paid' then
        insert into public.notifications_outbox (recipient_id, event_type, payload)
        values (w.child_id, 'withdrawal_paid', jsonb_build_object('withdrawal_id', w.id, 'amount', w.amount));
    end if;
end; $$;

grant execute on function
    public.admin_decide_withdrawal(uuid, boolean),
    public.admin_job_start(uuid),
    public.admin_job_stop(uuid),
    public.admin_job_archive(uuid),
    public.task_review(uuid, text, text),
    public.task_set_payment(uuid, text),
    public.withdrawal_set_payment(uuid, text)
to authenticated;
