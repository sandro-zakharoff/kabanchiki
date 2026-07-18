-- Kabanchiki: audit hardening.
-- Postgres grants EXECUTE on new functions to PUBLIC by default, which made
-- log_event callable by any authenticated user (or anon) via PostgREST —
-- letting a client forge journal entries. Only triggers may write events.

revoke execute on function public.log_event(text, text, uuid, text, uuid, jsonb)
    from public, anon, authenticated;
revoke execute on function public.event_actor()
    from public, anon, authenticated;
