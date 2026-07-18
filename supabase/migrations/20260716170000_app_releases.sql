-- Kabanchiki: self-hosted app updates (no Play Store).
-- The parent publishes a release (APK in Storage + a row here); children's
-- apps compare their versionCode to the latest and offer to update.

create table public.app_releases (
    id uuid primary key default gen_random_uuid(),
    platform text not null default 'android',
    version_name text not null,
    version_code integer not null,
    apk_path text not null,               -- object path in the app-releases bucket
    notes text not null default '',
    mandatory boolean not null default false,
    created_at timestamptz not null default now()
);
create index app_releases_platform_idx on public.app_releases (platform, version_code desc);

alter table public.app_releases enable row level security;

-- Every signed-in child may read releases to learn about updates.
create policy "read releases" on public.app_releases
    for select to authenticated using (true);

alter table public.app_releases replica identity full;
alter publication supabase_realtime add table public.app_releases;

-- Public bucket so the APK can be downloaded directly by the updater.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('app-releases', 'app-releases', true, 209715200,
        array['application/vnd.android.package-archive', 'application/octet-stream'])
on conflict (id) do nothing;

-- Notify every child about a new release (reuses send-push via the outbox).
create or replace function public.trg_app_release()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    insert into public.notifications_outbox (recipient_id, event_type, payload)
    select p.id, 'app_update', jsonb_build_object(
        'version_name', new.version_name,
        'version_code', new.version_code,
        'mandatory', new.mandatory,
        'notes', new.notes
    )
    from public.profiles p;
    return new;
end;
$$;

create trigger app_release_outbox after insert on public.app_releases
for each row execute function public.trg_app_release();

-- Helper the clients call to get the latest release for their platform.
create or replace function public.latest_release(p_platform text default 'android')
returns public.app_releases
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select * from public.app_releases
     where platform = p_platform
     order by version_code desc
     limit 1;
$$;

grant execute on function public.latest_release(text) to authenticated;
