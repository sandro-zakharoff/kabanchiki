-- Kabanchiki: multi-photo attachments, assignee avatars, Google Drive storage.
--
-- 1. attachments — one-to-many photos for tasks (role 'task' = set by a parent,
--    role 'proof' = uploaded by the child). Each row records WHERE the file
--    lives: storage 'supabase' (path = bucket object path) or 'drive'
--    (path = Drive file id). Existing single photos are backfilled losslessly;
--    the legacy tasks.photo_path / proof_photo_path columns stay so that old
--    Android builds keep working.
-- 2. profiles.avatar_* — an optional avatar image for assignees, changeable by
--    parents (RLS) and by the assignee themselves (RPC with a blocked-guard).
-- 3. app_secrets.gdrive_* — the owner's Google OAuth credentials, written
--    through owner-only RPCs and readable only by service_role (the `drive`
--    Edge Function), same pattern as telegram_bot_token.

-- ============================================================ attachments

create table public.attachments (
    id uuid primary key default gen_random_uuid(),
    task_id uuid not null references public.tasks (id) on delete cascade,
    role text not null check (role in ('task', 'proof')),
    storage text not null default 'supabase' check (storage in ('supabase', 'drive')),
    path text not null,
    thumb_path text,
    mime text not null default 'image/jpeg',
    size_bytes integer not null default 0,
    created_by uuid,
    created_at timestamptz not null default now()
);
create index attachments_task_idx on public.attachments (task_id, role, created_at);

alter table public.attachments enable row level security;

create policy "parent all attachments" on public.attachments
    for all to authenticated
    using (public.is_parent(auth.uid())) with check (public.is_parent(auth.uid()));

-- The child sees every photo of their own tasks (both roles).
create policy "child reads own task attachments" on public.attachments
    for select to authenticated
    using (exists (
        select 1 from public.tasks t
        where t.id = task_id and t.child_id = auth.uid()
    ));

alter publication supabase_realtime add table public.attachments;

-- Children add/remove proof photos strictly through guarded RPCs.
create or replace function public.task_attach_proof(
    p_task_id uuid,
    p_storage text,
    p_path text,
    p_thumb_path text default null,
    p_mime text default 'image/jpeg',
    p_size_bytes integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    v_id uuid;
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then raise exception 'TASK_NOT_FOUND'; end if;
    if t.status not in ('new', 'in_progress', 'paused') then
        raise exception 'INVALID_STATUS';
    end if;
    if p_storage not in ('supabase', 'drive') then raise exception 'BAD_STORAGE'; end if;
    if coalesce(trim(p_path), '') = '' then raise exception 'BAD_PATH'; end if;
    if (select count(*) from public.attachments
         where task_id = t.id and role = 'proof') >= 10 then
        raise exception 'TOO_MANY_PHOTOS';
    end if;

    insert into public.attachments (task_id, role, storage, path, thumb_path, mime, size_bytes, created_by)
    values (t.id, 'proof', p_storage, p_path, p_thumb_path, coalesce(p_mime, 'image/jpeg'),
            coalesce(p_size_bytes, 0), auth.uid())
    returning id into v_id;
    return v_id;
end;
$$;

create or replace function public.task_remove_proof(p_attachment_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    a public.attachments;
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select att.* into a from public.attachments att
      join public.tasks t on t.id = att.task_id
     where att.id = p_attachment_id and att.role = 'proof'
       and t.child_id = auth.uid() and t.status in ('new', 'in_progress', 'paused')
     for update of att;
    if not found then raise exception 'ATTACHMENT_NOT_FOUND'; end if;
    delete from public.attachments where id = a.id;
end;
$$;

revoke all on function public.task_attach_proof(uuid, text, text, text, text, integer) from public;
revoke all on function public.task_remove_proof(uuid) from public;
grant execute on function public.task_attach_proof(uuid, text, text, text, text, integer) to authenticated;
grant execute on function public.task_remove_proof(uuid) to authenticated;

-- task_complete: a required photo proof is satisfied either by the legacy
-- single path (old clients) or by at least one proof attachment (new clients).
create or replace function public.task_complete(
    p_task_id uuid,
    p_proof_text text default null,
    p_proof_photo_path text default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
    v_seconds integer := 0;
    v_earned numeric(12, 2);
    v_has_proof_photos boolean;
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;

    if t.completion_mode = 'simple' then
        if t.status <> 'new' then
            raise exception 'INVALID_STATUS';
        end if;
    else
        if t.status not in ('in_progress', 'paused') then
            raise exception 'INVALID_STATUS';
        end if;
    end if;

    if t.proof_text = 'required' and (p_proof_text is null or length(trim(p_proof_text)) = 0) then
        raise exception 'PROOF_TEXT_REQUIRED';
    end if;
    v_has_proof_photos := exists (
        select 1 from public.attachments
        where task_id = t.id and role = 'proof'
    );
    if t.proof_photo = 'required'
       and (p_proof_photo_path is null or length(trim(p_proof_photo_path)) = 0)
       and not v_has_proof_photos then
        raise exception 'PROOF_PHOTO_REQUIRED';
    end if;

    if t.completion_mode = 'timer' then
        update public.task_intervals set ended_at = now()
         where task_id = t.id and ended_at is null;
        select coalesce(sum(extract(epoch from i.ended_at - i.started_at)), 0)::int
          into v_seconds
          from public.task_intervals i
         where i.task_id = t.id and i.ended_at is not null;
    end if;

    if t.reward_type = 'fixed' then
        v_earned := t.reward_amount;
    else
        v_earned := round(v_seconds / 3600.0 * t.reward_amount, 2);
    end if;

    -- Legacy single proof photo also lands in attachments so every client
    -- sees one consistent gallery.
    if p_proof_photo_path is not null and length(trim(p_proof_photo_path)) > 0 then
        insert into public.attachments (task_id, role, storage, path, created_by)
        select t.id, 'proof', 'supabase', trim(p_proof_photo_path), auth.uid()
        where not exists (
            select 1 from public.attachments
            where task_id = t.id and role = 'proof' and path = trim(p_proof_photo_path)
        );
    end if;

    update public.tasks
       set status = 'submitted',
           completed_at = now(),
           decline_reason = null,
           total_seconds = v_seconds,
           earned_amount = v_earned,
           proof_text_content = nullif(trim(coalesce(p_proof_text, '')), ''),
           proof_photo_path = coalesce(nullif(trim(coalesce(p_proof_photo_path, '')), ''), t.proof_photo_path)
     where id = t.id;
end;
$$;

-- Backfill: every existing single photo becomes an attachment row (idempotent).
insert into public.attachments (task_id, role, storage, path, created_at)
select t.id, 'task', 'supabase', t.photo_path, t.created_at
  from public.tasks t
 where t.photo_path is not null and length(trim(t.photo_path)) > 0
   and not exists (
        select 1 from public.attachments a
        where a.task_id = t.id and a.role = 'task' and a.path = t.photo_path);

insert into public.attachments (task_id, role, storage, path, created_at)
select t.id, 'proof', 'supabase', t.proof_photo_path, coalesce(t.completed_at, t.created_at)
  from public.tasks t
 where t.proof_photo_path is not null and length(trim(t.proof_photo_path)) > 0
   and not exists (
        select 1 from public.attachments a
        where a.task_id = t.id and a.role = 'proof' and a.path = t.proof_photo_path);

-- ============================================================ avatars

alter table public.profiles
    add column if not exists avatar_storage text check (avatar_storage in ('supabase', 'drive')),
    add column if not exists avatar_path text,
    add column if not exists avatar_updated_at timestamptz;

-- Public bucket: avatars show everywhere all the time, so cache-friendly
-- public URLs beat expiring signed ones. Paths are unguessable uuids.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "parent manages avatars" on storage.objects
    for all to authenticated
    using (bucket_id = 'avatars' and public.is_parent(auth.uid()))
    with check (bucket_id = 'avatars' and public.is_parent(auth.uid()));

create policy "child uploads own avatar" on storage.objects
    for insert to authenticated
    with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- The assignee updates their own avatar pointer (parents use RLS directly).
create or replace function public.profile_set_avatar(
    p_storage text,
    p_path text
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    if not exists (select 1 from public.profiles where id = auth.uid()) then
        raise exception 'NOT_A_CHILD';
    end if;
    if p_path is not null and p_storage not in ('supabase', 'drive') then
        raise exception 'BAD_STORAGE';
    end if;
    update public.profiles
       set avatar_storage = case when p_path is null then null else p_storage end,
           avatar_path = nullif(trim(coalesce(p_path, '')), ''),
           avatar_updated_at = now()
     where id = auth.uid();
end;
$$;

revoke all on function public.profile_set_avatar(text, text) from public;
grant execute on function public.profile_set_avatar(text, text) to authenticated;

-- ============================================================ google drive

alter table public.app_config
    add column if not exists storage_backend text not null default 'supabase'
        check (storage_backend in ('supabase', 'drive'));

alter table public.app_secrets
    add column if not exists gdrive_client_id text,
    add column if not exists gdrive_client_secret text,
    add column if not exists gdrive_refresh_token text,
    add column if not exists gdrive_email text,
    add column if not exists gdrive_folders jsonb;

-- Owner-only writers; values never travel back to clients.
create or replace function public.set_gdrive_credentials(p_client_id text, p_client_secret text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not exists (select 1 from public.parents where id = auth.uid() and is_owner) then
        raise exception 'NOT_OWNER';
    end if;
    update public.app_secrets
       set gdrive_client_id = nullif(trim(p_client_id), ''),
           gdrive_client_secret = nullif(trim(p_client_secret), ''),
           -- new credentials invalidate old tokens
           gdrive_refresh_token = null,
           gdrive_email = null,
           gdrive_folders = null,
           updated_at = now()
     where id = true;
end;
$$;

create or replace function public.set_gdrive_tokens(p_refresh_token text, p_email text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not exists (select 1 from public.parents where id = auth.uid() and is_owner) then
        raise exception 'NOT_OWNER';
    end if;
    update public.app_secrets
       set gdrive_refresh_token = nullif(trim(p_refresh_token), ''),
           gdrive_email = nullif(trim(p_email), ''),
           updated_at = now()
     where id = true;
end;
$$;

create or replace function public.gdrive_disconnect()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if not exists (select 1 from public.parents where id = auth.uid() and is_owner) then
        raise exception 'NOT_OWNER';
    end if;
    update public.app_secrets
       set gdrive_refresh_token = null,
           gdrive_email = null,
           gdrive_folders = null,
           updated_at = now()
     where id = true;
    update public.app_config set storage_backend = 'supabase' where id = true;
end;
$$;

-- Parents see connection state (booleans + account email only).
create or replace function public.gdrive_status()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    s public.app_secrets;
begin
    if not public.is_parent(auth.uid()) then raise exception 'NOT_PARENT'; end if;
    select * into s from public.app_secrets where id = true;
    return jsonb_build_object(
        'has_credentials', coalesce(s.gdrive_client_id, '') <> '' and coalesce(s.gdrive_client_secret, '') <> '',
        'connected', coalesce(s.gdrive_refresh_token, '') <> '',
        'email', coalesce(s.gdrive_email, ''),
        'client_id', coalesce(s.gdrive_client_id, '')
    );
end;
$$;

revoke all on function public.set_gdrive_credentials(text, text) from public;
revoke all on function public.set_gdrive_tokens(text, text) from public;
revoke all on function public.gdrive_disconnect() from public;
revoke all on function public.gdrive_status() from public;
grant execute on function public.set_gdrive_credentials(text, text) to authenticated;
grant execute on function public.set_gdrive_tokens(text, text) to authenticated;
grant execute on function public.gdrive_disconnect() to authenticated;
grant execute on function public.gdrive_status() to authenticated;
