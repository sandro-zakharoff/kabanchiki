-- Kabanchiki: offline location queue support (B1).
-- Points captured offline are flushed later in a batch; each carries its real
-- capture time. Drop the old signature first so PostgREST never sees two
-- overloads (the register_device lesson).

drop function if exists public.location_report(double precision, double precision, real, text);

create function public.location_report(
    p_lat double precision,
    p_lng double precision,
    p_accuracy real default null,
    p_locality text default '',
    p_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    v_uid uuid := auth.uid();
    v_at timestamptz := coalesce(p_at, now());
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
    -- clamp nonsense timestamps from clients
    if v_at > now() + interval '5 minutes' or v_at < now() - interval '2 days' then
        v_at := now();
    end if;
    insert into public.locations (child_id, lat, lng, accuracy, locality, created_at)
    values (v_uid, p_lat, p_lng, p_accuracy, coalesce(trim(p_locality), ''), v_at);
    -- keep only the newest 50 points per child
    delete from public.locations
     where child_id = v_uid
       and id <= (select max(id) - 50 from public.locations where child_id = v_uid);
end;
$$;

revoke execute on function
    public.location_report(double precision, double precision, real, text, timestamptz)
    from public, anon;
grant execute on function
    public.location_report(double precision, double precision, real, text, timestamptz)
    to authenticated;
