-- Kabanchiki: the full story of a single entity.
--
-- The journal is a flat feed of everything; to follow one task or one payout
-- you had to scan it. Every event already carries (entity, entity_id), so the
-- story exists — it just needs to be served per entity.
--
-- A client-side filter would not do: the apps only load the last few hundred
-- events, so anything older would silently show a truncated history. This RPC
-- always returns the complete, ordered story straight from the table.

create index if not exists events_entity_idx on public.events (entity, entity_id, id);

create or replace function public.entity_timeline(p_entity text, p_entity_id uuid)
returns table (
    id           bigint,
    created_at   timestamptz,
    action       text,
    actor_kind   text,
    actor_name   text,
    entity_title text,
    details      jsonb
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
    -- Mirrors the "parents read events" policy this function bypasses.
    if auth.uid() is not null and not public.is_parent(auth.uid()) then
        raise exception 'NOT_PARENT';
    end if;
    return query
        select e.id, e.created_at, e.action, e.actor_kind, e.actor_name,
               e.entity_title, e.details
          from public.events e
         where e.entity = p_entity
           and e.entity_id = p_entity_id
         order by e.id;
end;
$$;

revoke all on function public.entity_timeline(text, uuid) from public, anon;
grant execute on function public.entity_timeline(text, uuid) to authenticated;
