-- Private bucket for staff-facing artifacts (e.g. AI-provider raw
-- responses, researcher-uploaded files). Not public; not listed anywhere
-- for anon/authenticated (D-011) — the storage.objects RLS policies below
-- are deliberately omitted, so only the service role can read/write it.
insert into storage.buckets (id, name, public)
values ('staff-artifacts', 'staff-artifacts', false)
on conflict (id) do nothing;
