-- Kabanchiki: full owner-account management.
-- Parents gain profile fields (phone, note) and an activity status. A disabled
-- parent loses every RLS grant at once because is_parent() now excludes them;
-- the admin Edge Function additionally bans the auth user so they cannot even
-- sign in.

alter table public.parents
    add column if not exists phone text not null default '',
    add column if not exists note text not null default '',
    add column if not exists disabled boolean not null default false;

create or replace function public.is_parent(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists(select 1 from public.parents where id = p_uid and not disabled);
$$;
