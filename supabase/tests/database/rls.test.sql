-- Run with: supabase test db
-- (requires `supabase db reset` to have applied migrations + seed.sql first,
-- which supabase test db does automatically against a fresh local stack).
--
-- These simulate PostgREST's per-request session by setting `role` and
-- `request.jwt.claims` the same way PostgREST does, so auth.uid() and our
-- RLS policies behave exactly as they would over the API.

begin;
select plan(14);

-- Fixed ids from supabase/seed.sql:
--   00000000-0000-0000-0000-000000000001 = patient@example.com
--   00000000-0000-0000-0000-000000000002 = caregiver@example.com
--   00000000-0000-0000-0000-000000000003 = researcher@example.com
--   00000000-0000-0000-0000-000000000004 = admin@example.com

-- ---------------------------------------------------------------------
-- herbs: public read
-- ---------------------------------------------------------------------
set local role anon;
select is(
  (select count(*)::int from public.herbs),
  6,
  'anon can read the active herbs catalog'
);
reset role;

-- ---------------------------------------------------------------------
-- requests: anon has no access at all
-- ---------------------------------------------------------------------
set local role anon;
select is(
  (select count(*)::int from public.requests),
  0,
  'anon cannot read any requests'
);
reset role;

-- ---------------------------------------------------------------------
-- requests: a patient sees only their own requests
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.requests),
  2,
  'patient sees exactly their own 2 requests (published + draft), not the caregiver''s'
);

select is(
  (select bool_and(user_id = '00000000-0000-0000-0000-000000000001') from public.requests),
  true,
  'every request row a patient can see belongs to them'
);

-- direct client UPDATE must never succeed, even on your own row
select throws_ok(
  $$ update public.requests set claim_text = 'tampered' where user_id = '00000000-0000-0000-0000-000000000001' and status = 'draft' $$,
  null,
  null,
  'patient cannot UPDATE their own request directly (no UPDATE policy; backend/service role only)'
);

-- staff-only tables: patient gets zero rows, not an error (RLS enabled, no policy = empty set)
select is(
  (select count(*)::int from public.ai_drafts),
  0,
  'patient cannot read ai_drafts (staff-only per D-011)'
);

select is(
  (select count(*)::int from public.researcher_reviews),
  0,
  'patient cannot read researcher_reviews (staff-only per D-011)'
);

select is(
  (select count(*)::int from public.research_jobs),
  0,
  'patient cannot read research_jobs (staff-only per D-011)'
);

-- published_results: only visible once the owning request is published
select is(
  (select count(*)::int from public.published_results),
  1,
  'patient sees the one published_results row for their published request'
);

reset role;

-- ---------------------------------------------------------------------
-- requests: the caregiver only sees their own request, not the patient's
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select is(
  (select count(*)::int from public.requests),
  1,
  'caregiver sees only their own 1 request'
);

select is(
  (select count(*)::int from public.published_results),
  0,
  'caregiver has no published_results (their request is only in researcher_review)'
);

reset role;

-- ---------------------------------------------------------------------
-- requests: a researcher sees everything
-- ---------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "00000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is(
  (select count(*)::int from public.requests),
  3,
  'researcher sees all 3 requests across all users'
);

select is(
  (select count(*)::int from public.ai_drafts),
  0,
  'researcher still cannot read ai_drafts directly (D-011: service role only, not just any staff JWT)'
);

select is(
  (select count(*)::int from public.published_results),
  1,
  'researcher sees the one published_results row'
);

-- profiles: researcher can see all profiles, not just their own
select is(
  (select count(*)::int from public.profiles),
  4,
  'researcher can read all 4 profiles'
);

reset role;

select * from finish();
rollback;
