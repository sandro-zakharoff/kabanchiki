-- Broadcast profile changes (last_seen_at, blocked) over Realtime so the
-- parent app reflects presence in real time. RLS still applies: a child only
-- receives their own profile row; the parent (service_role) receives all.

alter table public.profiles replica identity full;
alter publication supabase_realtime add table public.profiles;
