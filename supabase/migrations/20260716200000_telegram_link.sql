-- Kabanchiki: Telegram integration foundation.
--
-- Two pieces:
--   1. public.app_config — a single shared settings row (Telegram bot username,
--      Mini App URL). Owners edit it from the desktop; every client reads it.
--      The bot *token* is a server-only secret (Edge Function env), never stored
--      here, because this row is readable by all parents.
--   2. Telegram account linking — a short-lived link code stored on the parent's
--      row. The desktop generates it (parent_start_link); the Mini App presents
--      it back through the tg-auth Edge Function, which binds the Telegram user
--      id to that parent. After that, the Mini App logs the parent in silently.

-- ============================================================ app_config

create table public.app_config (
    id boolean primary key default true check (id),
    telegram_bot_username text not null default '',
    telegram_miniapp_url text not null default '',
    updated_at timestamptz not null default now()
);

-- Singleton row.
insert into public.app_config (id) values (true) on conflict (id) do nothing;

alter table public.app_config enable row level security;

create policy "parents read config" on public.app_config
    for select to authenticated using (public.is_parent(auth.uid()));

create policy "owners update config" on public.app_config
    for update to authenticated
    using (exists (select 1 from public.parents where id = auth.uid() and is_owner))
    with check (exists (select 1 from public.parents where id = auth.uid() and is_owner));

alter table public.app_config replica identity full;
alter publication supabase_realtime add table public.app_config;

-- ============================================================ Telegram linking

alter table public.parents
    add column link_code text,
    add column link_code_expires timestamptz;

-- Generate a fresh single-use link code for the calling parent (valid 15 min).
create or replace function public.parent_start_link()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_code text;
begin
    if not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    -- gen_random_uuid() is core Postgres (secure RNG); avoids the pgcrypto
    -- extension schema, which isn't on this function's search_path.
    v_code := replace(gen_random_uuid()::text, '-', '');
    update public.parents
       set link_code = v_code,
           link_code_expires = now() + interval '15 minutes'
     where id = auth.uid();
    return v_code;
end;
$$;

-- Detach the caller's Telegram account.
create or replace function public.parent_unlink_telegram()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    update public.parents
       set telegram_id = null, link_code = null, link_code_expires = null
     where id = auth.uid();
end;
$$;

grant execute on function public.parent_start_link() to authenticated;
grant execute on function public.parent_unlink_telegram() to authenticated;
