-- Children need app_config.storage_backend to route photo uploads
-- (Supabase Storage vs the Drive Edge Function). The table holds no secrets
-- (bot username, Mini App URL, storage backend), so let every family member
-- read it; writes remain owner-only.
create policy "authenticated read config" on public.app_config
    for select to authenticated using (true);
