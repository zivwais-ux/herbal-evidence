-- Durable job queue (D-010). No Redis: the backend's consumer claims rows
-- with FOR UPDATE SKIP LOCKED, holds a lease it must heartbeat, and retries
-- up to max_attempts before the job is marked 'dead'.
create table public.research_jobs (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  job_type text not null default 'ai_research',
  status public.job_status not null default 'queued',
  idempotency_key text not null unique,
  payload jsonb not null default '{}'::jsonb,
  result jsonb,
  last_error text,
  attempts int not null default 0,
  max_attempts int not null default 5,
  leased_by text,
  leased_at timestamptz,
  lease_expires_at timestamptz,
  heartbeat_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.research_jobs is
  'Durable job queue for the AI/research workflow. Staff/backend-only (D-011): no RLS policies for anon/authenticated.';

create trigger set_research_jobs_updated_at
  before update on public.research_jobs
  for each row execute function public.set_updated_at();

create index research_jobs_status_idx on public.research_jobs (status);
create index research_jobs_request_id_idx on public.research_jobs (request_id);

-- Atomically claim the oldest available job: either freshly queued, or
-- 'leased' with an expired lease (a crashed/stalled worker). Runs as the
-- service role from the backend process.
create function public.claim_job(p_worker text, p_lease_seconds int default 60)
returns public.research_jobs
language plpgsql
as $$
declare
  claimed public.research_jobs;
begin
  update public.research_jobs
  set status = 'leased',
      leased_by = p_worker,
      leased_at = now(),
      lease_expires_at = now() + make_interval(secs => p_lease_seconds),
      heartbeat_at = now(),
      attempts = attempts + 1
  where id = (
    select id
    from public.research_jobs
    where status = 'queued'
       or (status = 'leased' and lease_expires_at < now())
    order by created_at
    for update skip locked
    limit 1
  )
  returning * into claimed;

  -- A no-match UPDATE ... RETURNING INTO leaves every field of `claimed`
  -- NULL, but the row value itself is NOT SQL NULL (it's a tuple of
  -- nulls) — returning it as-is would serialize as {"id": null, ...} over
  -- RPC instead of a plain null. Return true NULL explicitly.
  if claimed.id is null then
    return null;
  end if;

  return claimed;
end;
$$;

comment on function public.claim_job is
  'Claims the next available research job with SKIP LOCKED, or returns null if none is available.';

-- Called periodically by the worker while it still owns the job, so a
-- healthy-but-slow job is not reclaimed by another worker.
create function public.heartbeat_job(p_job_id uuid, p_worker text, p_lease_seconds int default 60)
returns public.research_jobs
language plpgsql
as $$
declare
  updated public.research_jobs;
begin
  update public.research_jobs
  set heartbeat_at = now(),
      lease_expires_at = now() + make_interval(secs => p_lease_seconds)
  where id = p_job_id
    and leased_by = p_worker
    and status = 'leased'
  returning * into updated;

  -- See claim_job() above for why this explicit check is needed.
  if updated.id is null then
    return null;
  end if;

  return updated; -- null if the lease was lost (already reclaimed elsewhere)
end;
$$;

create function public.complete_job(p_job_id uuid, p_worker text, p_result jsonb default null)
returns public.research_jobs
language plpgsql
as $$
declare
  updated public.research_jobs;
begin
  update public.research_jobs
  set status = 'succeeded',
      result = coalesce(p_result, result),
      leased_by = null,
      lease_expires_at = null
  where id = p_job_id
    and leased_by = p_worker
    and status = 'leased'
  returning * into updated;

  -- See claim_job() above for why this explicit check is needed.
  if updated.id is null then
    return null;
  end if;

  return updated;
end;
$$;

-- Fails a job: retries (back to 'queued') while under max_attempts, else
-- marks it permanently 'dead'.
create function public.fail_job(p_job_id uuid, p_worker text, p_error text)
returns public.research_jobs
language plpgsql
as $$
declare
  updated public.research_jobs;
begin
  update public.research_jobs
  set status = case when attempts >= max_attempts then 'dead' else 'queued' end,
      last_error = p_error,
      leased_by = null,
      lease_expires_at = null
  where id = p_job_id
    and leased_by = p_worker
    and status = 'leased'
  returning * into updated;

  -- See claim_job() above for why this explicit check is needed.
  if updated.id is null then
    return null;
  end if;

  return updated;
end;
$$;
