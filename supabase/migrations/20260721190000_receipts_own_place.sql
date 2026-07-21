-- Kabanchiki: payout receipts get their own place instead of living among the
-- task photos.
--
-- Receipts were being written into the task-photos bucket (and the Drive
-- "tasks" folder) purely because that was the upload path that already existed.
-- They are a different kind of document with a different audience — the owner
-- files them, the assignee checks them — and mixing them into the task gallery
-- makes both harder to look through.
--
-- Storage layout mirrors the other buckets exactly: "<child_id>/<file>", so RLS
-- is the same folder check, and the assignee can read their own receipts while
-- owners manage all of them.
--
-- Nothing has to be moved: on Supabase no receipt object was ever written (the
-- family's storage backend is Drive, where a file's id is independent of the
-- folder it sits in, so existing receipts keep resolving either way).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('receipts', 'receipts', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do update
    set allowed_mime_types = excluded.allowed_mime_types,
        file_size_limit    = excluded.file_size_limit;

create policy "parent manages receipts" on storage.objects
    for all to authenticated
    using (bucket_id = 'receipts' and public.is_parent(auth.uid()))
    with check (bucket_id = 'receipts' and public.is_parent(auth.uid()));

create policy "child reads own receipts" on storage.objects
    for select to authenticated
    using (bucket_id = 'receipts' and (storage.foldername(name))[1] = auth.uid()::text);

-- task-photos goes back to pictures only: PDFs were allowed there for exactly
-- one release, to carry receipts that now have their own bucket. Tightening the
-- list only gates future uploads; nothing already stored is affected.
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp']
 where id = 'task-photos';
