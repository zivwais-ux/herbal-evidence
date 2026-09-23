-- Linter hardening (see mcp Supabase security advisors):
--  1. Pin search_path on every function so it can't be hijacked by a
--     session-local search_path change.
--  2. Trigger-only functions (handle_new_user, log_request_created,
--     log_request_status_change) are never meant to be called directly as
--     RPCs; revoke that default PUBLIC execute grant. Trigger firing does
--     not require the firing role to hold EXECUTE on the function.
--  3. current_app_role() is used inside RLS policies evaluated as
--     `authenticated`, so it must stay executable by that role, but anon
--     never needs it (anon-facing policies don't call it).

alter function public.set_updated_at() set search_path = public, pg_temp;
alter function public.enforce_request_status_transition() set search_path = public, pg_temp;
alter function public.claim_job(text, int) set search_path = public, pg_temp;
alter function public.heartbeat_job(uuid, text, int) set search_path = public, pg_temp;
alter function public.complete_job(uuid, text, jsonb) set search_path = public, pg_temp;
alter function public.fail_job(uuid, text, text) set search_path = public, pg_temp;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.log_request_created() from public, anon, authenticated;
revoke execute on function public.log_request_status_change() from public, anon, authenticated;
-- Function-level grants default to PUBLIC (which anon/authenticated both
-- inherit), so revoking from anon alone isn't enough: revoke from PUBLIC
-- and grant back explicitly only to the role that needs it.
revoke execute on function public.current_app_role() from public;
grant execute on function public.current_app_role() to authenticated;
