-- Kabanchiki: one-time journal backfill.
-- The events table was born on 2026-07-16; history before that (finished/paid
-- tasks, withdrawals, bonuses) is synthesized here with the ORIGINAL dates and
-- the 'system' actor (who exactly clicked the buttons was never recorded).
-- Guarded per record: rows that already have any event are skipped, so the
-- migration is idempotent and never duplicates live entries.

-- ---------------------------------------------------------------- tasks
insert into public.events (created_at, actor_kind, actor_name, action, entity,
                           entity_id, entity_title, child_id, details)
select t.created_at, 'system', '', 'created', 'task', t.id, t.title, t.child_id,
       jsonb_build_object('reward', t.reward_amount, 'reward_type', t.reward_type,
                          'backfilled', true)
from public.tasks t
where not exists (select 1 from public.events e
                   where e.entity = 'task' and e.entity_id = t.id);

insert into public.events (created_at, actor_kind, actor_name, action, entity,
                           entity_id, entity_title, child_id, details)
select t.completed_at, 'system', '',
       case when t.status = 'done' then 'approved' else 'declined' end,
       'task', t.id, t.title, t.child_id,
       jsonb_strip_nulls(jsonb_build_object('earned', t.earned_amount,
                                            'note', nullif(t.decline_reason, ''),
                                            'backfilled', true))
from public.tasks t
where t.status in ('done', 'declined')
  and t.completed_at is not null
  and not exists (select 1 from public.events e
                   where e.entity = 'task' and e.entity_id = t.id
                     and e.action in ('approved', 'completed', 'declined', 'rejected'));

insert into public.events (created_at, actor_kind, actor_name, action, entity,
                           entity_id, entity_title, child_id, details)
select t.paid_at, 'system', '', 'payment_changed', 'task', t.id, t.title, t.child_id,
       jsonb_build_object('to', t.payment_status, 'amount', t.earned_amount,
                          'backfilled', true)
from public.tasks t
where t.paid_at is not null
  and not exists (select 1 from public.events e
                   where e.entity = 'task' and e.entity_id = t.id
                     and e.action = 'payment_changed');

-- ---------------------------------------------------------------- withdrawals
insert into public.events (created_at, actor_kind, actor_name, action, entity,
                           entity_id, entity_title, child_id, details)
select w.requested_at, 'system', '', 'requested', 'withdrawal', w.id,
       coalesce(j.title, ''), w.child_id,
       jsonb_build_object('amount', w.amount, 'backfilled', true)
from public.withdrawals w
left join public.jobs j on j.id = w.job_id
where not exists (select 1 from public.events e
                   where e.entity = 'withdrawal' and e.entity_id = w.id);

insert into public.events (created_at, actor_kind, actor_name, action, entity,
                           entity_id, entity_title, child_id, details)
select w.decided_at, 'system', '',
       case when w.status = 'approved' then 'approved' else 'declined' end,
       'withdrawal', w.id, coalesce(j.title, ''), w.child_id,
       jsonb_build_object('amount', w.amount, 'backfilled', true)
from public.withdrawals w
left join public.jobs j on j.id = w.job_id
where w.status in ('approved', 'declined')
  and w.decided_at is not null
  and not exists (select 1 from public.events e
                   where e.entity = 'withdrawal' and e.entity_id = w.id
                     and e.action in ('approved', 'declined'));

insert into public.events (created_at, actor_kind, actor_name, action, entity,
                           entity_id, entity_title, child_id, details)
select w.paid_at, 'system', '', 'payment_changed', 'withdrawal', w.id,
       coalesce(j.title, ''), w.child_id,
       jsonb_build_object('to', w.payment_status, 'amount', w.amount,
                          'backfilled', true)
from public.withdrawals w
left join public.jobs j on j.id = w.job_id
where w.paid_at is not null
  and not exists (select 1 from public.events e
                   where e.entity = 'withdrawal' and e.entity_id = w.id
                     and e.action = 'payment_changed');

-- ---------------------------------------------------------------- bonuses
insert into public.events (created_at, actor_kind, actor_name, action, entity,
                           entity_id, entity_title, child_id, details)
select b.created_at, 'system', '', 'granted', 'bonus', b.id,
       coalesce(b.note, ''), b.child_id,
       jsonb_build_object('amount', b.amount, 'backfilled', true)
from public.bonuses b
where not exists (select 1 from public.events e
                   where e.entity = 'bonus' and e.entity_id = b.id);
