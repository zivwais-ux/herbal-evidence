-- One row per AI-generated draft attempt for a request (there can be
-- retries). Never shown to the end user directly (D-011) — only a
-- researcher-approved published_results row is.
create table public.ai_drafts (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  provider text not null,
  model text,
  content jsonb not null,
  citations jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.ai_drafts is
  'AI-generated evidence-review drafts. Staff-only (D-011): no RLS policies for anon/authenticated.';

-- Raw literature fetched from PubMed / Europe PMC while building a draft
-- (D-009), kept for traceability and reuse across retries.
create table public.literature_sources (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  source text not null check (source in ('pubmed', 'europe_pmc')),
  external_id text not null,
  title text,
  url text,
  fetched_at timestamptz not null default now(),
  raw jsonb,
  unique (request_id, source, external_id)
);

comment on table public.literature_sources is
  'Literature fetched from PubMed/Europe PMC for a request. Staff-only (D-011).';

-- The researcher's edit/decision on a request. final_content is what gets
-- copied into published_results once decision = 'approved'.
create table public.researcher_reviews (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.requests (id) on delete cascade,
  researcher_id uuid not null references public.profiles (id),
  ai_draft_id uuid references public.ai_drafts (id),
  decision text not null check (decision in ('approved', 'rejected')),
  final_content jsonb,
  researcher_notes text,
  created_at timestamptz not null default now()
);

comment on table public.researcher_reviews is
  'Researcher edit/decision on a request, staff-only (D-011).';

create index ai_drafts_request_id_idx on public.ai_drafts (request_id);
create index literature_sources_request_id_idx on public.literature_sources (request_id);
create index researcher_reviews_request_id_idx on public.researcher_reviews (request_id);

-- The final, human-approved content shown to the requesting user. This is
-- the one staff-produced artifact that IS visible to its owner (not
-- covered by D-011, which is about drafts/staff-internal artifacts).
create table public.published_results (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.requests (id) on delete cascade,
  researcher_review_id uuid not null references public.researcher_reviews (id),
  body jsonb not null,
  published_at timestamptz not null default now(),
  published_by uuid not null references public.profiles (id)
);

comment on table public.published_results is
  'Final researcher-approved content, one per request, readable by the owning user once requests.status = published.';
