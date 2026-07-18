-- Kabanchiki: personal balances via an append-only ledger.
--
-- The ledger is the SINGLE source of truth for every balance change. Nothing
-- moves money except a row in public.ledger_entries. A balance is derived:
--   balance(child) = sum(ledger_entries.amount) + live uncredited job accrual
-- (the live tail is added in the jobs migration, once accrual helpers exist).
--
-- Money is numeric(12,2) throughout (exact decimal, never float). All money
-- arithmetic lives server-side; clients only format.

-- ============================================================ ledger

create type public.ledger_kind as enum (
    'task',        -- credited when a parent approves a task
    'job',         -- credited as an hourly job accrues (settlement)
    'bonus',       -- a positive manual grant
    'adjustment',  -- a manual correction, + or -
    'withdrawal',  -- a debit reserving/paying out a payout
    'reversal'     -- compensating entry (e.g. a rejected payout returns funds)
);

create table public.ledger_entries (
    id          bigint generated always as identity primary key,
    child_id    uuid not null references public.profiles (id) on delete cascade,
    amount      numeric(12, 2) not null,          -- signed: + credit, - debit
    kind        public.ledger_kind not null,
    source_type text,                             -- 'task'|'job'|'withdrawal'|'manual'
    source_id   uuid,                             -- the originating row, if any
    note        text not null default '',
    created_at  timestamptz not null default now(),  -- real operation time (migration keeps originals)
    actor_kind  text not null default 'system' check (actor_kind in ('parent', 'child', 'system')),
    actor_id    uuid,
    actor_name  text not null default '',
    -- Idempotency: a non-null key can appear at most once, so retries/failures
    -- never double-post. Repeatable postings (job accrual) leave it null;
    -- Postgres treats nulls as distinct so they never collide.
    dedupe_key  text unique
);
create index ledger_child_idx  on public.ledger_entries (child_id, created_at desc);
create index ledger_source_idx on public.ledger_entries (source_type, source_id);

alter table public.ledger_entries enable row level security;

create policy "own ledger" on public.ledger_entries
    for select to authenticated using (child_id = auth.uid());
create policy "parents read ledger" on public.ledger_entries
    for select to authenticated using (public.is_parent(auth.uid()));

alter table public.ledger_entries replica identity full;
alter publication supabase_realtime add table public.ledger_entries;

-- ============================================================ posting helper

-- The only way to append to the ledger. security definer; never granted to
-- clients. Idempotent when p_dedupe_key is provided (ON CONFLICT DO NOTHING).
-- Returns the new row id, or NULL if a row with that dedupe_key already existed.
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

-- Sum of the ledger (the "credited" part of the balance). The live job tail is
-- added on top by assignee_balance() in the jobs migration.
create or replace function public.ledger_balance(p_child uuid)
returns numeric
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select coalesce(sum(amount), 0)::numeric(12, 2)
      from public.ledger_entries where child_id = p_child;
$$;

grant execute on function public.ledger_balance(uuid) to authenticated;

-- ============================================================ balance settings

-- Global money settings live on the existing singleton app_config row.
-- Everyone authenticated may read (children need min_withdrawal / the enabled
-- flag); only owners update, via the existing "owners update config" policy.
alter table public.app_config
    add column if not exists min_withdrawal           numeric(12, 2) not null default 0  check (min_withdrawal >= 0),
    add column if not exists withdrawals_enabled       boolean        not null default true,
    add column if not exists auto_approve_below        numeric(12, 2) not null default 0  check (auto_approve_below >= 0),
    add column if not exists require_receipt_for_card  boolean        not null default false,
    add column if not exists currency                  text           not null default '₴';
