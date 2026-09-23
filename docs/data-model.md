# data-model

Schema lives as SQL migrations in `supabase/migrations/`, applied in filename order.
This doc explains the *why*; the migrations are the source of truth for the *what*.

## Entities

| Table | Purpose |
|---|---|
| `profiles` | One row per `auth.users` row: app role (`user` / `researcher` / `admin`) + display name. Created automatically by the `handle_new_user()` trigger on signup. |
| `herbs` | Reference catalog for claim-submission autocomplete/identification. Not exhaustive — `requests.herb_name_raw` always keeps the free text as typed. |
| `requests` | The core entity: one claim that a single herb improved appetite. Owned by the submitting user (patient or caregiver, `is_caregiver`). Carries the lifecycle `status`. |
| `request_status_history` | Append-only audit log of every `requests.status` change (who, when, from/to). Written automatically by triggers, never by clients. |
| `ai_drafts` | AI-generated evidence-review draft(s) for a request. Staff-only. |
| `literature_sources` | Raw PubMed / Europe PMC records fetched while building a draft. Staff-only. |
| `researcher_reviews` | A researcher's decision (`approved`/`rejected`) + edited final content. Staff-only. |
| `published_results` | The one final, human-approved artifact the *owning user* is allowed to read, once their request reaches `published`. |
| `research_jobs` | Durable job queue backing the AI/research workflow (D-010). Staff-only. |

## Request lifecycle

```
draft -> submitted -> ai_processing -> researcher_review -> approved -> published
                 \-> withdrawn            \-> ai_failed -> ai_processing (retry)
                                                        \-> researcher_review (manual fallback)
                            researcher_review -> rejected
```

Enforced server-side by the `enforce_request_status_transition()` trigger on
`public.requests` — any other transition raises an error. Every transition
(and the initial `draft` insert) is copied into `request_status_history` by
`log_request_status_change()` / `log_request_created()`.

Clients never update `requests.status` directly: there is no client UPDATE
policy on `requests` (see RLS below). Only the backend, using the Supabase
service role (which bypasses RLS), drives the state machine — matching the
Phase 2 "state machine" work and D-004 (backend validates JWTs itself, does
its own authorization on top of what RLS allows).

## Row Level Security

RLS is **on** for every table in `public`. Summary (full policies in
`supabase/migrations/20260923060700_rls.sql`):

| Table | anon | authenticated (owner) | authenticated (researcher/admin) | service role |
|---|---|---|---|---|
| `herbs` | read (active) | read (active) | read all | all |
| `profiles` | — | read/update own row | read all | all |
| `requests` | — | read own; insert own (status=`draft` only) | read all | all |
| `request_status_history` | — | read own (via request) | read all | all |
| `published_results` | — | read own, once `published` | read all | all |
| `ai_drafts`, `literature_sources`, `researcher_reviews`, `research_jobs` | — | — | — | all |

The last row is D-011: drafts and staff-internal artifacts (and the job
queue) have **no** RLS policies for `anon`/`authenticated` at all — not even
for researchers/admins. They're reachable only through the backend, which
holds the service-role key and does its own role check
(`profiles.role in ('researcher','admin')`) before returning anything. This
is deliberate defense in depth: a leaked user JWT, even a researcher's,
can't read AI drafts or job internals straight from PostgREST/Supabase.

The private Storage bucket `staff-artifacts` follows the same pattern: no
`storage.objects` policies are defined for it, so only the service role can
read/write.

## Job queue (`research_jobs`)

Postgres-only durable queue per D-010 — no Redis. The backend's consumer
calls:

- `claim_job(worker, lease_seconds)` — atomically claims the oldest
  `queued` job, or a `leased` job whose lease expired (a crashed worker),
  using `FOR UPDATE SKIP LOCKED` so multiple consumer processes never
  double-claim the same row.
- `heartbeat_job(job_id, worker, lease_seconds)` — extends the lease while
  work is still in progress.
- `complete_job(job_id, worker, result)` — marks it `succeeded`.
- `fail_job(job_id, worker, error)` — retries (back to `queued`) while
  `attempts < max_attempts`, else marks it permanently `dead`.

`idempotency_key` is unique, so re-enqueuing the same logical job
(e.g. a retry triggered by the API) is a safe no-op via `ON CONFLICT`.

## Local development

```sh
supabase start          # local Docker stack
supabase db reset       # (re)apply all migrations + supabase/seed.sql
supabase test db        # run supabase/tests/database/*.test.sql (pgTAP)
```

`supabase/seed.sql` is **local/dev-only** mock data: 4 auth users
(patient, caregiver, researcher, admin — password `password123` for all)
and 3 requests covering `draft`, `researcher_review`, and `published`. It
must never be run against `herbal-evidence-dev` or `herbal-evidence-prod`.

See `docs/deployment.md` for linking the CLI to the remote dev project and
`docs/decisions.md` for the numbered engineering decisions referenced above.
