-- Report the installed app version per device so the parent app can see
-- which build each child is running (and who needs to update).

alter table public.devices add column if not exists app_version text;
alter table public.devices add column if not exists app_version_code integer not null default 0;

-- Replace register_device with a version-aware signature. The old 2-arg
-- overload is dropped so PostgREST has no ambiguous candidate.
drop function if exists public.register_device(text, text);

create or replace function public.register_device(
    p_fcm_token text,
    p_platform text default 'android',
    p_app_version text default null,
    p_app_version_code integer default 0
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if auth.uid() is null then
        raise exception 'NOT_AUTHENTICATED';
    end if;
    insert into public.devices (profile_id, fcm_token, platform, app_version, app_version_code)
    values (auth.uid(), p_fcm_token, p_platform, p_app_version, p_app_version_code)
    on conflict (fcm_token)
    do update set
        profile_id = excluded.profile_id,
        platform = excluded.platform,
        app_version = excluded.app_version,
        app_version_code = excluded.app_version_code,
        updated_at = now();
end;
$$;

grant execute on function public.register_device(text, text, text, integer) to authenticated;
