-- Kabanchiki: task/job authorship.
-- Who created the record. The display name is denormalized so assignees can
-- show "Task from: …" without RLS access to the parents table, and the name
-- survives a deleted parent. Existing rows stay NULL (author unknown).

alter table public.tasks
    add column if not exists created_by uuid references public.parents (id) on delete set null,
    add column if not exists created_by_name text not null default '';

alter table public.jobs
    add column if not exists created_by uuid references public.parents (id) on delete set null,
    add column if not exists created_by_name text not null default '';

create or replace function public.trg_set_created_by()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if new.created_by is null and auth.uid() is not null then
        select p.id, coalesce(nullif(p.display_name, ''), p.email, '')
          into new.created_by, new.created_by_name
          from public.parents p
         where p.id = auth.uid();
    end if;
    return new;
end;
$$;

create trigger set_created_by before insert on public.tasks
for each row execute function public.trg_set_created_by();

create trigger set_created_by before insert on public.jobs
for each row execute function public.trg_set_created_by();
