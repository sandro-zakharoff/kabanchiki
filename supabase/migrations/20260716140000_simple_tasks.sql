-- Kabanchiki: task completion mode.
-- 'timer'  — existing behaviour: child taps Start, a timer runs, then Done.
-- 'simple' — no timer: the child taps Done directly from the list.
-- Hourly reward is meaningless without a timer, so it is only valid for 'timer'.

create type public.task_completion_mode as enum ('timer', 'simple');

alter table public.tasks
    add column completion_mode public.task_completion_mode not null default 'timer';

alter table public.tasks
    add constraint tasks_simple_is_fixed
    check (not (completion_mode = 'simple' and reward_type = 'hourly'));

-- Recreate task_start: keep the block guard, and reject starting a simple task.
create or replace function public.task_start(p_task_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
    t public.tasks;
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;
    if t.completion_mode = 'simple' then
        raise exception 'INVALID_STATUS';
    end if;
    if t.status not in ('new', 'paused') then
        raise exception 'INVALID_STATUS';
    end if;
    insert into public.task_intervals (task_id) values (t.id);
    update public.tasks
       set status = 'in_progress', started_at = coalesce(started_at, now())
     where id = t.id;
end;
$$;

-- Recreate task_complete: block guard + simple/timer branch.
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
begin
    if public.is_blocked(auth.uid()) then raise exception 'BLOCKED'; end if;
    select * into t from public.tasks
     where id = p_task_id and child_id = auth.uid() for update;
    if not found then
        raise exception 'TASK_NOT_FOUND';
    end if;

    -- Allowed source states depend on the mode.
    if t.completion_mode = 'simple' then
        if t.status <> 'new' then
            raise exception 'INVALID_STATUS';
        end if;
    else
        if t.status not in ('in_progress', 'paused') then
            raise exception 'INVALID_STATUS';
        end if;
    end if;

    -- Proof requirements apply to both modes.
    if t.proof_text = 'required' and (p_proof_text is null or length(trim(p_proof_text)) = 0) then
        raise exception 'PROOF_TEXT_REQUIRED';
    end if;
    if t.proof_photo = 'required' and (p_proof_photo_path is null or length(trim(p_proof_photo_path)) = 0) then
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

    update public.tasks
       set status = 'done',
           completed_at = now(),
           total_seconds = v_seconds,
           earned_amount = v_earned,
           proof_text_content = nullif(trim(coalesce(p_proof_text, '')), ''),
           proof_photo_path = nullif(trim(coalesce(p_proof_photo_path, '')), '')
     where id = t.id;
end;
$$;
