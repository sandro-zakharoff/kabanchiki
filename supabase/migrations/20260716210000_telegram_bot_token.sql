-- Kabanchiki: Telegram bot token, configurable from the desktop settings.
--
-- The token is a powerful secret, so it is NOT kept in app_config (which every
-- parent can read). It lives in app_secrets, a table with row-level security and
-- no policies at all — meaning no authenticated client can read or write it
-- directly. Only service_role (the tg-auth Edge Function) reads it, and the
-- owner writes it through a SECURITY DEFINER function that never returns the
-- value back. This lets the owner manage the token from the settings page while
-- keeping it out of reach of the clients.

create table public.app_secrets (
    id boolean primary key default true check (id),
    telegram_bot_token text,
    updated_at timestamptz not null default now()
);

insert into public.app_secrets (id) values (true) on conflict (id) do nothing;

alter table public.app_secrets enable row level security;
-- Intentionally no policies: authenticated clients cannot select/insert/update.

-- Owner-only writer. Empty string clears the token.
create or replace function public.set_telegram_bot_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not exists (select 1 from public.parents where id = auth.uid() and is_owner) then
        raise exception 'NOT_OWNER';
    end if;
    update public.app_secrets
       set telegram_bot_token = nullif(trim(p_token), ''),
           updated_at = now()
     where id = true;
end;
$$;

-- Parents may check whether a token is configured (boolean only, never the value).
create or replace function public.telegram_bot_configured()
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not public.is_parent(auth.uid()) then return false; end if;
    return exists (
        select 1 from public.app_secrets
        where id = true and coalesce(telegram_bot_token, '') <> ''
    );
end;
$$;

grant execute on function public.set_telegram_bot_token(text) to authenticated;
grant execute on function public.telegram_bot_configured() to authenticated;
