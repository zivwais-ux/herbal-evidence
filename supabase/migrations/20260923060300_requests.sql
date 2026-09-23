-- A single claim: "this herb improved my/my patient's appetite". One herb
-- per request (spec: "single herb and appetite improvement").
create table public.requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  herb_id uuid references public.herbs (id),
  herb_name_raw text not null,
  claim_text text not null,
  is_caregiver boolean not null default false,
  status public.request_status not null default 'draft',
  assigned_researcher_id uuid references public.profiles (id),
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.requests is
  'One herb/appetite claim submitted by a patient or caregiver, tracked through AI draft + human researcher review.';
comment on column public.requests.herb_name_raw is
  'Free text as typed by the user; herb_id is set once matched against the herbs catalog (D-005/spec herb identification).';
comment on column public.requests.assigned_researcher_id is
  'Manually assigned by an admin (D-005). Null until picked up.';

create trigger set_requests_updated_at
  before update on public.requests
  for each row execute function public.set_updated_at();

-- Append-only audit trail of every status change, per docs/privacy-and-retention.md.
create table public.request_status_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  from_status public.request_status,
  to_status public.request_status not null,
  changed_by uuid references public.profiles (id),
  note text,
  created_at timestamptz not null default now()
);

comment on table public.request_status_history is
  'Append-only audit trail of requests.status changes.';

-- Enforce the state machine described in 0000_extensions_and_enums.sql and
-- record every transition. Direct client writes to `status` never bypass
-- this: the table has no client UPDATE policy (see 0006_rls.sql), so in
-- practice only the backend, using the service role, reaches this trigger.
create function public.enforce_request_status_transition()
returns trigger
language plpgsql
as $$
declare
  allowed boolean;
begin
  if new.status = old.status then
    return new;
  end if;

  allowed := case old.status
    when 'draft' then new.status in ('submitted', 'withdrawn')
    when 'submitted' then new.status in ('ai_processing', 'withdrawn')
    when 'ai_processing' then new.status in ('researcher_review', 'ai_failed')
    when 'ai_failed' then new.status in ('ai_processing', 'researcher_review')
    when 'researcher_review' then new.status in ('approved', 'rejected')
    when 'approved' then new.status in ('published')
    else false
  end;

  if not allowed then
    raise exception 'invalid request status transition: % -> %', old.status, new.status;
  end if;

  if new.status = 'submitted' and new.submitted_at is null then
    new.submitted_at := now();
  end if;

  return new;
end;
$$;

create trigger enforce_requests_status_transition
  before update of status on public.requests
  for each row execute function public.enforce_request_status_transition();

create function public.log_request_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.request_status_history (request_id, from_status, to_status, changed_by)
  values (new.id, old.status, new.status, auth.uid());
  return new;
end;
$$;

create trigger requests_log_status_change
  after update of status on public.requests
  for each row
  when (old.status is distinct from new.status)
  execute function public.log_request_status_change();

-- Also log the initial insert (from_status null -> 'draft').
create function public.log_request_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.request_status_history (request_id, from_status, to_status, changed_by)
  values (new.id, null, new.status, auth.uid());
  return new;
end;
$$;

create trigger requests_log_created
  after insert on public.requests
  for each row execute function public.log_request_created();

create index requests_user_id_idx on public.requests (user_id);
create index requests_status_idx on public.requests (status);
create index requests_assigned_researcher_id_idx on public.requests (assigned_researcher_id);
