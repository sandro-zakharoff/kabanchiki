-- Kabanchiki: settlement safeguards for job accrual.
--
-- The live balance already includes un-settled accrual, so no frequent cron is
-- needed for correctness. We only crystallise at natural boundaries:
--   * job stop / archive / member removal (earlier migration),
--   * a withdrawal request (settle-first),
--   * an hourly-rate change (here) — so a rate edit prices prior time at the
--     OLD rate and only future time at the new rate,
--   * a daily roll-up (here) — books running jobs into history once a day.

-- Settle members at the OLD rate before an hourly-rate change takes effect.
create or replace function public.trg_job_rate_settle()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
    if new.hourly_rate is distinct from old.hourly_rate then
        perform public.settle_job(old.id);   -- reads the still-current (old) rate
    end if;
    return new;
end;
$$;
create trigger job_rate_settle before update on public.jobs
for each row execute function public.trg_job_rate_settle();

-- Daily roll-up (00:05) so a long-running job posts earnings into the ledger
-- history without cluttering it with frequent micro-entries.
create extension if not exists pg_cron;
select cron.schedule('settle-jobs-daily', '5 0 * * *',
                     $$select public.settle_all_jobs()$$);
