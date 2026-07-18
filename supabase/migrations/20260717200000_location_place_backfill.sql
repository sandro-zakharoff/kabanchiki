-- Shared reverse-geocode cache for location points.
--
-- The assignee's phone fills locality via its on-device geocoder; on rural
-- points or offline maintenance-window wakes it can come back empty and every
-- client then shows raw coordinates. Instead of each client reverse-geocoding
-- on its own (repeated lookups, nothing shared), a parent resolves an empty
-- point once and writes the name back here — so all three clients read the
-- resolved name from the DB and the lookup happens once per point, system-wide.
--
-- Fills empties only; the phone's own value is never overwritten.

create or replace function public.set_location_place(p_location_id bigint, p_locality text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    -- locality is NOT NULL: only write a non-empty resolved name, and only
    -- into a point the phone left blank.
    if coalesce(trim(coalesce(p_locality, '')), '') = '' then return; end if;
    update public.locations
       set locality = trim(p_locality)
     where id = p_location_id
       and coalesce(locality, '') = '';
end;
$$;

revoke all on function public.set_location_place(bigint, text) from public;
grant execute on function public.set_location_place(bigint, text) to authenticated;
