-- Kabanchiki: storage buckets
-- task-photos:  photos the parent attaches to tasks (uploaded with service_role).
-- proof-photos: completion proofs uploaded by children.
-- Object paths are always "<child_id>/<file>", so RLS is a folder check.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
    ('task-photos', 'task-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp']),
    ('proof-photos', 'proof-photos', false, 10485760, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "child reads own task photos" on storage.objects
    for select to authenticated
    using (bucket_id = 'task-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "child reads own proof photos" on storage.objects
    for select to authenticated
    using (bucket_id = 'proof-photos' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "child uploads own proof photos" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'proof-photos' and (storage.foldername(name))[1] = auth.uid()::text);
