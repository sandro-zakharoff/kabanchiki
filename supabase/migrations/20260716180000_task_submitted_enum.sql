-- Add the 'submitted' (awaiting parent review) state to task_status.
-- Kept in its own migration: a new enum value must be committed before other
-- migrations use it.
alter type public.task_status add value if not exists 'submitted';
