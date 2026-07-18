-- Single source of truth for the Kabanchiki/{tasks,proofs,avatars} folder ids.
--
-- Two upload paths were each caching folder ids independently — the desktop in
-- the Windows keyring, the `drive` Edge Function in app_secrets.gdrive_folders
-- — so neither reused the other's folder and Drive ended up with two
-- "Kabanchiki" folders. gdrive_status() now also returns the shared folder map,
-- and an owner-only setter lets the desktop publish the ids it created; the
-- Edge Function already reads/writes the same column. Whoever creates the
-- folders first wins; everyone else reuses them.

create or replace function public.gdrive_status()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    s public.app_secrets;
begin
    if not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into s from public.app_secrets where id = true;
    return jsonb_build_object(
        'has_credentials', coalesce(s.gdrive_client_id, '') <> '' and coalesce(s.gdrive_client_secret, '') <> '',
        'connected', coalesce(s.gdrive_refresh_token, '') <> '',
        'email', coalesce(s.gdrive_email, ''),
        'client_id', coalesce(s.gdrive_client_id, ''),
        'folders', coalesce(s.gdrive_folders, '{}'::jsonb)
    );
end;
$$;

create or replace function public.set_gdrive_folders(p_folders jsonb)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not exists (select 1 from public.parents where id = auth.uid() and is_owner) then
        raise exception 'NOT_OWNER';
    end if;
    update public.app_secrets set gdrive_folders = p_folders, updated_at = now()
     where id = true;
end;
$$;

revoke all on function public.set_gdrive_folders(jsonb) from public;
grant execute on function public.set_gdrive_folders(jsonb) to authenticated;
