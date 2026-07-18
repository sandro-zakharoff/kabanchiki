-- Kabanchiki: assignee geolocation.
-- The Android app (with the child's explicit consent on the device) reports a
-- point every ~15 minutes through location_report(). Parents see the latest
-- point and a short history; children write only their own row through the
-- SECURITY DEFINER RPC — the table has no insert policy.

create table public.locations (
    id bigint generated always as identity primary key,
    child_id uuid not null references public.profiles (id) on delete cascade,
    lat double precision not null check (lat between -90 and 90),
    lng double precision not null check (lng between -180 and 180),
    accuracy real,
    locality text not null default '',
    created_at timestamptz not null default now()
);

create index locations_child_idx on public.locations (child_id, id desc);

alter table public.locations enable row level security;
create policy "parents read locations" on public.locations
    for select to authenticated using (public.is_parent(auth.uid()));

alter table public.locations replica identity full;
alter publication supabase_realtime add table public.locations;

create or replace function public.location_report(
    p_lat double precision,
    p_lng double precision,
    p_accuracy real default null,
    p_locality text default ''
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_uid uuid := auth.uid();
begin
    if v_uid is null then
        raise exception 'NOT_AUTHENTICATED';
    end if;
    if not exists (select 1 from public.profiles where id = v_uid) then
        raise exception 'NOT_CHILD';
    end if;
    if public.is_blocked(v_uid) then
        raise exception 'BLOCKED';
    end if;
    insert into public.locations (child_id, lat, lng, accuracy, locality)
    values (v_uid, p_lat, p_lng, p_accuracy, coalesce(trim(p_locality), ''));
    -- keep only the newest 50 points per child
    delete from public.locations
     where child_id = v_uid
       and id <= (select max(id) - 50 from public.locations where child_id = v_uid);
end;
$$;

revoke execute on function public.location_report(double precision, double precision, real, text)
    from public, anon;
grant execute on function public.location_report(double precision, double precision, real, text)
    to authenticated;
