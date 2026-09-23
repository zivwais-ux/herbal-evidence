-- Extensions needed for UUIDs and the job queue.
create extension if not exists pgcrypto with schema extensions;

-- Generic "bump updated_at on row update" trigger function, used by every
-- table below that has an updated_at column.
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- App-level user role. 'user' submits claims, 'researcher' reviews and
-- approves them, 'admin' additionally assigns researchers. See D-005.
create type public.app_role as enum ('user', 'researcher', 'admin');

-- Lifecycle of a single herb/appetite claim ("request").
-- Allowed transitions are enforced by a trigger in 0003_requests.sql:
--   draft         -> submitted, withdrawn
--   submitted     -> ai_processing, withdrawn
--   ai_processing -> researcher_review, ai_failed
--   ai_failed     -> ai_processing (retry), researcher_review (manual fallback)
--   researcher_review -> approved, rejected
--   approved      -> published
--   (rejected, published, withdrawn are terminal)
create type public.request_status as enum (
  'draft',
  'submitted',
  'ai_processing',
  'ai_failed',
  'researcher_review',
  'approved',
  'rejected',
  'published',
  'withdrawn'
);

-- Durable job-queue status (D-010).
create type public.job_status as enum (
  'queued',
  'leased',
  'succeeded',
  'failed',
  'dead'
);
