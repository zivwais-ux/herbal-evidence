-- RLS policy summary
-- ------------------
-- profiles              : owner select/update own row; researcher/admin select all.
-- herbs                 : public read (anon + authenticated); no client writes.
-- requests               : owner select own; owner insert own (draft only);
--                           researcher/admin select assigned/all; NO client
--                           update/delete — all status transitions go
--                           through the backend with the service role.
-- request_status_history : owner select own (via request); researcher/admin select all.
-- published_results      : owner select own, once published; researcher/admin select all.
-- ai_drafts, literature_sources, researcher_reviews, research_jobs
--                        : RLS enabled, NO policies for anon/authenticated (D-011).
--                          The service role bypasses RLS entirely, which is
--                          how the backend reaches these tables.

alter table public.profiles enable row level security;
alter table public.herbs enable row level security;
alter table public.requests enable row level security;
alter table public.request_status_history enable row level security;
alter table public.published_results enable row level security;
alter table public.ai_drafts enable row level security;
alter table public.literature_sources enable row level security;
alter table public.researcher_reviews enable row level security;
alter table public.research_jobs enable row level security;

-- profiles
create policy profiles_select_own on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.current_app_role() in ('researcher', 'admin'));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- herbs: public reference data, readable by anyone (incl. before signup).
create policy herbs_select_all on public.herbs
  for select to anon, authenticated
  using (is_active);

create policy herbs_select_all_staff on public.herbs
  for select to authenticated
  using (public.current_app_role() in ('researcher', 'admin'));

-- requests
create policy requests_select_own_or_staff on public.requests
  for select to authenticated
  using (
    user_id = auth.uid()
    or public.current_app_role() in ('researcher', 'admin')
  );

create policy requests_insert_own on public.requests
  for insert to authenticated
  with check (user_id = auth.uid() and status = 'draft');

-- request_status_history
create policy request_status_history_select_own_or_staff on public.request_status_history
  for select to authenticated
  using (
    exists (
      select 1 from public.requests r
      where r.id = request_status_history.request_id
        and (r.user_id = auth.uid() or public.current_app_role() in ('researcher', 'admin'))
    )
  );

-- published_results
create policy published_results_select_own_or_staff on public.published_results
  for select to authenticated
  using (
    public.current_app_role() in ('researcher', 'admin')
    or exists (
      select 1 from public.requests r
      where r.id = published_results.request_id
        and r.user_id = auth.uid()
        and r.status = 'published'
    )
  );
