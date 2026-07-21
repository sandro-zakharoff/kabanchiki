-- Kabanchiki: the currency becomes the acorn (жолудь), and an acorn is INDIVISIBLE.
--
-- Two things happen here, and the order matters:
--
--  1. Money stops being numeric(12,2) and becomes plain `integer`. Indivisibility
--     is a property of the TYPE, not of a validation rule someone can forget to
--     call — a fraction simply cannot be stored. Every client, the bot and the
--     cron all inherit that guarantee for free.
--
--  2. Hourly accrual is re-based on an EXACT INTEGER accumulator, so switching to
--     whole acorns cannot quietly evaporate earnings.
--
-- ---------------------------------------------------------------- why an accumulator
--
-- The old settlement priced the newly elapsed slice and rounded THE SLICE:
--     money := round((elapsed - settled_seconds) / 3600 * rate, 2)
-- Flooring that slice would drop the sub-acorn remainder on every settlement —
-- and settlement runs on a daily cron AND on every payout request, so a child
-- working short sessions could lose most of their earnings.
--
-- Flooring the cumulative total instead (floor(elapsed / 3600 * rate)) fixes the
-- leak but breaks the other invariant this schema deliberately maintains:
-- `settled_seconds` exists so that changing a job's hourly rate prices past time
-- at the OLD rate and only future time at the new one. A cumulative formula
-- re-prices all history at the newest rate.
--
-- So we bank the newly elapsed slice at the rate in force AT THAT MOMENT, in a
-- unit small enough to be exact — ACORN-SECONDS (seconds * rate, both integers):
--
--     accrued_acorn_seconds += (elapsed - settled_seconds) * rate   -- exact, integer
--     settled_seconds        = elapsed
--     total                  = accrued_acorn_seconds / 3600         -- integer div = floor
--     delta                  = total - credited_amount              -- what we post
--
-- No rounding happens anywhere, so there is nothing to lose: the remainder lives
-- on as whole acorn-seconds and matures into a whole acorn by itself. Past time
-- keeps its old price, because it was banked at that price. And the live tail
--     floor((accrued + (elapsed - settled) * rate) / 3600) - credited_amount
-- is by construction EXACTLY the delta the next settlement will post, so the
-- ticking balance in the three clients never jumps when the cron fires.

-- ============================================================ 0. exact-amount guard

-- Whole acorns or nothing. Used by the RPCs that accept an amount from a client:
-- storing into an integer column would silently round, and a silent round on
-- someone's money is exactly the kind of thing that should shout instead.
create or replace function public.acorns_exact(p_amount numeric)
returns integer
language plpgsql
immutable
as $$
begin
    if p_amount is null then return null; end if;
    if p_amount <> trunc(p_amount) then
        raise exception 'FRACTIONAL_AMOUNT';
    end if;
    return p_amount::integer;
end;
$$;
grant execute on function public.acorns_exact(numeric) to authenticated;

-- ============================================================ 1. crystallise before converting

-- Settle every member at the CURRENT fractional rates first, so no unsettled
-- tail is left to be mispriced by the rounded rates below.
select public.settle_all_jobs();

-- ============================================================ 2. audit + ledger conversion

-- Control values, captured before anything is touched. Kept permanently: this is
-- the record of what the money looked like on the day it became acorns.
create table if not exists public.acorn_migration_audit (
    child_id       uuid primary key references public.profiles (id) on delete cascade,
    ledger_before  numeric(12, 2) not null,   -- sum of the ledger, in hryvnia
    ledger_rounded numeric(12, 2) not null,   -- sum after rounding each entry
    target         integer        not null,   -- the balance we commit to, in acorns
    adjustment     integer        not null,   -- the correcting entry we posted
    entries        integer        not null,
    migrated_at    timestamptz    not null default now()
);

insert into public.acorn_migration_audit (child_id, ledger_before, ledger_rounded, target, adjustment, entries)
select l.child_id,
       sum(l.amount),
       sum(round(l.amount)),
       round(sum(l.amount))::integer,
       0,
       count(*)::integer
  from public.ledger_entries l
 group by l.child_id
on conflict (child_id) do nothing;

-- Round every historical entry. The amounts must change — an integer column
-- cannot hold 12.34 — but the BALANCE is not allowed to drift silently, so the
-- difference between the rounded sum and the committed target is posted as one
-- visible ledger entry per child instead of being absorbed into history.
update public.ledger_entries set amount = round(amount) where amount <> round(amount);

update public.acorn_migration_audit a
   set adjustment = a.target - a.ledger_rounded;

do $$
declare r record;
begin
    for r in select * from public.acorn_migration_audit where adjustment <> 0 loop
        perform public.ledger_post(
            r.child_id, r.adjustment, 'adjustment', 'manual', null,
            'округлення до жолудів', 'acorn-rounding:' || r.child_id::text, now());
    end loop;
end;
$$;

-- ============================================================ 3. money becomes integer

-- The one view over money columns has to step aside for the rewrite.
drop view if exists public.job_member_stats;

alter table public.ledger_entries alter column amount         type integer using round(amount)::integer;
alter table public.withdrawals    alter column amount         type integer using round(amount)::integer;
alter table public.bonuses        alter column amount         type integer using round(amount)::integer;
alter table public.tasks          alter column reward_amount  type integer using round(reward_amount)::integer;
alter table public.tasks          alter column earned_amount  type integer using round(earned_amount)::integer;
alter table public.jobs           alter column hourly_rate    type integer using round(hourly_rate)::integer;
alter table public.job_members    alter column credited_amount type integer using round(credited_amount)::integer;
alter table public.app_config     alter column min_withdrawal    type integer using round(min_withdrawal)::integer;
alter table public.app_config     alter column auto_approve_below type integer using round(auto_approve_below)::integer;

-- The currency label, now a word (an icon replaces the symbol in the UIs, but
-- push notifications, the bot and ledger notes need something pronounceable).
alter table public.app_config alter column currency set default 'жолудь';
update public.app_config set currency = 'жолудь' where currency = '₴' or currency is null;

-- ============================================================ 4. the accrual accumulator

alter table public.job_members
    add column if not exists accrued_acorn_seconds bigint not null default 0;

comment on column public.job_members.accrued_acorn_seconds is
    'Exact earnings banked as seconds*rate. Whole acorns = value / 3600; the '
    'remainder stays here and matures instead of being rounded away.';

-- Re-derive what was actually credited for each membership straight from the
-- (now integer) ledger, then seed the accumulator to match it exactly, so the
-- first settlement after this migration posts a delta of 0.
update public.job_members m
   set credited_amount = coalesce((
           select sum(l.amount) from public.ledger_entries l
            where l.child_id = m.child_id
              and l.kind = 'job'
              and l.source_type = 'job'
              and l.source_id = m.job_id), 0);

update public.job_members set accrued_acorn_seconds = credited_amount::bigint * 3600;

-- ============================================================ 5. accrual functions

-- These all return money, so they all change return type from numeric to
-- integer — which CREATE OR REPLACE cannot do. The view above is already gone,
-- and plpgsql bodies resolve their calls at runtime, so dropping is safe here.
drop function if exists public.job_member_unsettled_money(uuid, uuid);
drop function if exists public.settle_job_member(uuid, uuid);
drop function if exists public.ledger_balance(uuid);
drop function if exists public.assignee_balance(uuid);
drop function if exists public.reconcile_assignee(uuid);
drop function if exists public.withdrawal_open_total(uuid);

-- Whole acorns earned but not yet posted to the ledger. This is the live tail the
-- clients add to the credited balance while a job runs.
create or replace function public.job_member_unsettled_acorns(p_job_id uuid, p_child_id uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
    v_rate     integer;
    v_settled  bigint;
    v_accrued  bigint;
    v_credited integer;
    v_elapsed  bigint;
begin
    select j.hourly_rate, m.settled_seconds, m.accrued_acorn_seconds, m.credited_amount
      into v_rate, v_settled, v_accrued, v_credited
      from public.job_members m join public.jobs j on j.id = m.job_id
     where m.job_id = p_job_id and m.child_id = p_child_id;
    if not found then return 0; end if;
    v_elapsed := public.job_member_elapsed_seconds(p_job_id, p_child_id);
    -- integer division floors; every term is non-negative
    return greatest(0,
        ((v_accrued + greatest(0, v_elapsed - v_settled) * v_rate) / 3600)::integer - v_credited);
end;
$$;

-- Bank the newly elapsed seconds at the current rate and post whatever whole
-- acorns that made mature. Idempotent: calling it twice in a row posts 0.
create or replace function public.settle_job_member(p_job_id uuid, p_child_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    m         public.job_members;
    v_rate    integer;
    v_elapsed bigint;
    v_accrued bigint;
    v_total   integer;
    v_delta   integer;
begin
    select * into m from public.job_members
     where job_id = p_job_id and child_id = p_child_id for update;
    if not found then return 0; end if;
    select hourly_rate into v_rate from public.jobs where id = p_job_id;
    v_elapsed := public.job_member_elapsed_seconds(p_job_id, p_child_id);
    if v_elapsed <= m.settled_seconds then return 0; end if;

    -- price the new slice at today's rate, exactly, and add it to the bank
    v_accrued := m.accrued_acorn_seconds + (v_elapsed - m.settled_seconds) * v_rate;
    v_total   := (v_accrued / 3600)::integer;         -- whole acorns matured so far
    v_delta   := v_total - m.credited_amount;

    if v_delta <> 0 then
        perform public.ledger_post(p_child_id, v_delta, 'job', 'job', p_job_id, '', null, now());
    end if;
    -- settled_seconds always advances, even when delta is 0: the sub-acorn
    -- remainder is already safe inside accrued_acorn_seconds.
    update public.job_members
       set settled_seconds       = v_elapsed,
           accrued_acorn_seconds = v_accrued,
           credited_amount       = v_total
     where job_id = p_job_id and child_id = p_child_id;
    return v_delta;
end;
$$;
revoke all on function public.settle_job_member(uuid, uuid) from public, anon, authenticated;

-- Capture the final tail when a membership is removed.
create or replace function public.trg_job_member_final_settle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_delta integer;
begin
    v_delta := public.job_member_unsettled_acorns(old.job_id, old.child_id);
    if v_delta <> 0 then
        perform public.ledger_post(old.child_id, v_delta, 'job', 'job', old.job_id, '', null, now());
    end if;
    return old;
end;
$$;

-- ============================================================ 6. balances

create or replace function public.ledger_balance(p_child uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select coalesce(sum(amount), 0)::integer
      from public.ledger_entries where child_id = p_child;
$$;
grant execute on function public.ledger_balance(uuid) to authenticated;

create or replace function public.assignee_balance(p_child uuid)
returns integer
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_tail integer;
begin
    if auth.uid() is not null
       and not public.is_parent(auth.uid())
       and auth.uid() <> p_child then
        raise exception 'FORBIDDEN';
    end if;
    select coalesce(sum(public.job_member_unsettled_acorns(m.job_id, m.child_id)), 0)
      into v_tail
      from public.job_members m where m.child_id = p_child;
    return public.ledger_balance(p_child) + coalesce(v_tail, 0);
end;
$$;
grant execute on function public.assignee_balance(uuid) to authenticated;

create or replace function public.reconcile_assignee(p_child uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare r record;
begin
    for r in select job_id from public.job_members where child_id = p_child loop
        perform public.settle_job_member(r.job_id, p_child);
    end loop;
    return public.ledger_balance(p_child);
end;
$$;
revoke all on function public.reconcile_assignee(uuid) from public, anon, authenticated;

create or replace function public.withdrawal_open_total(p_child uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select coalesce(sum(amount), 0)::integer
      from public.withdrawals
     where child_id = p_child and status in ('requested', 'approved', 'paid');
$$;
revoke all on function public.withdrawal_open_total(uuid) from public, anon, authenticated;

-- ============================================================ 7. the view, rebuilt

-- `accrued_acorn_seconds` is the exact, un-rounded earning at snapshot time. It
-- is what lets the three clients tick a RUNNING job in whole acorns without ever
-- disagreeing with the server: they add (elapsed_since_snapshot * hourly_rate)
-- to it and floor by 3600 — the very arithmetic settle_job_member() performs.
-- Ticking a rounded number instead would drift and then visibly jump when the
-- settle cron lands.
create view public.job_member_stats
with (security_invoker = true) as
select
    m.job_id,
    m.child_id,
    j.title,
    j.description,
    j.hourly_rate,
    j.status,
    m.joined_at,
    m.credited_amount,
    (select coalesce(sum(extract(epoch from coalesce(s.ended_at, now()) - s.started_at)), 0)
       from public.job_sessions s where s.job_id = m.job_id)::bigint as total_seconds,
    live.elapsed as earned_seconds,
    live.acorn_seconds as accrued_acorn_seconds,
    (live.acorn_seconds / 3600)::integer as earned_total,
    (select s.started_at from public.job_sessions s
      where s.job_id = m.job_id and s.ended_at is null limit 1) as running_since,
    (select max(s.ended_at) from public.job_sessions s
      where s.job_id = m.job_id and s.ended_at is not null) as last_stopped_at,
    now() as snapshot_at
from public.job_members m
join public.jobs j on j.id = m.job_id
cross join lateral (
    select e.elapsed,
           (m.accrued_acorn_seconds
            + greatest(0, e.elapsed - m.settled_seconds) * j.hourly_rate)::bigint as acorn_seconds
      from (select public.job_member_elapsed_seconds(m.job_id, m.child_id) as elapsed) e
) live;
alter table public.job_member_stats owner to postgres;

-- ============================================================ 8. posting + client-facing RPCs

-- ledger_post now refuses fractions outright: every caller below hands it whole
-- acorns, so a fraction here means a bug, not a rounding decision.
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
        p_child, public.acorns_exact(p_amount), p_kind, p_source_type, p_source_id,
        coalesce(p_note, ''),
        coalesce(p_created_at, now()), a.kind, a.id, a.name, p_dedupe_key)
    on conflict (dedupe_key) do nothing
    returning id into v_id;
    return v_id;                                  -- null when deduped away
end;
$$;
revoke all on function public.ledger_post(uuid, numeric, public.ledger_kind, text, uuid, text, text, timestamptz)
    from public, anon, authenticated;

create or replace function public.request_withdrawal(p_amount numeric default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_child     uuid := auth.uid();
    v_min       integer;
    v_enabled   boolean;
    v_auto      integer;
    v_bal       integer;
    v_available integer;
    v_amount    integer;
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

    v_amount := coalesce(public.acorns_exact(p_amount), v_available);   -- null = all that is free
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

create or replace function public.admin_create_withdrawal(p_child uuid, p_amount numeric default null)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_bal       integer;
    v_available integer;
    v_amount    integer;
    v_id        uuid;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if not exists (select 1 from public.profiles where id = p_child) then raise exception 'CHILD_NOT_FOUND'; end if;

    perform 1 from public.profiles where id = p_child for update;   -- serialise with requests
    perform public.reconcile_assignee(p_child);                     -- settle live job tail
    v_bal       := public.ledger_balance(p_child);
    v_available := v_bal - public.withdrawal_open_total(p_child);

    v_amount := coalesce(public.acorns_exact(p_amount), v_available);  -- null = all that is free
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

create or replace function public.admin_adjust_balance(p_child uuid, p_amount numeric, p_note text)
returns bigint
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_note   text := nullif(trim(coalesce(p_note, '')), '');
    v_amount integer := public.acorns_exact(p_amount);
    v_id     bigint;
begin
    if auth.uid() is not null and not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    if v_amount is null or v_amount = 0 then raise exception 'INVALID_AMOUNT'; end if;
    if v_note is null then raise exception 'NOTE_REQUIRED'; end if;
    if not exists(select 1 from public.profiles where id = p_child) then raise exception 'CHILD_NOT_FOUND'; end if;
    v_id := public.ledger_post(p_child, v_amount, 'adjustment', 'manual', null, v_note, null, now());
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    values (p_child, 'balance_adjusted', jsonb_build_object('amount', v_amount, 'note', v_note));
    return v_id;
end;
$$;
revoke all on function public.admin_adjust_balance(uuid, numeric, text) from public, anon;
grant execute on function public.admin_adjust_balance(uuid, numeric, text) to authenticated;

-- ============================================================ 9. task rewards

-- Hourly-rewarded tasks are settled once, at completion, so there is no future
-- remainder to mature: round to the nearest acorn rather than flooring.
create or replace function public.task_complete(
    p_task_id uuid,
    p_proof_text text default null,
    p_proof_photo_path text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    v_seconds integer := 0;
    v_earned integer;
    v_has_proof_photos boolean;
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
    v_has_proof_photos := exists (
        select 1 from public.attachments
        where task_id = t.id and role = 'proof'
    );
    if t.proof_photo = 'required'
       and (p_proof_photo_path is null or length(trim(p_proof_photo_path)) = 0)
       and not v_has_proof_photos then
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
        v_earned := round(v_seconds / 3600.0 * t.reward_amount)::integer;
    end if;

    -- Legacy single proof photo also lands in attachments so every client
    -- sees one consistent gallery.
    if p_proof_photo_path is not null and length(trim(p_proof_photo_path)) > 0 then
        insert into public.attachments (task_id, role, storage, path, created_by)
        select t.id, 'proof', 'supabase', trim(p_proof_photo_path), auth.uid()
        where not exists (
            select 1 from public.attachments
            where task_id = t.id and role = 'proof' and path = trim(p_proof_photo_path)
        );
    end if;

    update public.tasks
       set status = 'submitted',
           completed_at = now(),
           decline_reason = null,
           total_seconds = v_seconds,
           earned_amount = v_earned,
           proof_text_content = nullif(trim(coalesce(p_proof_text, '')), ''),
           proof_photo_path = coalesce(nullif(trim(coalesce(p_proof_photo_path, '')), ''), t.proof_photo_path)
     where id = t.id;
end;
$$;
