-- LOCAL/DEV MOCK DATA ONLY.
-- Run automatically by `supabase db reset` / `supabase start` against the
-- local Docker stack. Never run this against herbal-evidence-dev or
-- herbal-evidence-prod (it creates auth.users rows with a fixed password).

-- ---------------------------------------------------------------------
-- Herbs catalog
-- ---------------------------------------------------------------------
insert into public.herbs (slug, name_he, name_en) values
  ('ginger', 'ג׳ינג׳ר', 'Ginger'),
  ('chamomile', 'קמומיל', 'Chamomile'),
  ('fenugreek', 'חילבה', 'Fenugreek'),
  ('peppermint', 'נענע פלפלת', 'Peppermint'),
  ('milk-thistle', 'כברה מצויה', 'Milk thistle'),
  ('turmeric', 'כורכום', 'Turmeric')
on conflict (slug) do nothing;

-- ---------------------------------------------------------------------
-- Mock auth users. Password for all: "password123" (local dev only).
-- The handle_new_user() trigger creates a matching public.profiles row
-- with role='user' for each; we then elevate the researcher/admin roles.
-- ---------------------------------------------------------------------
do $$
declare
  v_patient_id uuid := '00000000-0000-0000-0000-000000000001';
  v_caregiver_id uuid := '00000000-0000-0000-0000-000000000002';
  v_researcher_id uuid := '00000000-0000-0000-0000-000000000003';
  v_admin_id uuid := '00000000-0000-0000-0000-000000000004';
  v_ginger_id uuid;
  v_chamomile_id uuid;
  v_request_published uuid;
  v_request_in_review uuid;
  v_request_draft uuid;
  v_review_id uuid;
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  ) values
    ('00000000-0000-0000-0000-000000000000', v_patient_id, 'authenticated', 'authenticated',
     'patient@example.com', crypt('password123', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}', '{"display_name":"מטופל לדוגמה"}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_caregiver_id, 'authenticated', 'authenticated',
     'caregiver@example.com', crypt('password123', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}', '{"display_name":"מטפל/ת לדוגמה"}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_researcher_id, 'authenticated', 'authenticated',
     'researcher@example.com', crypt('password123', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}', '{"display_name":"חוקר/ת לדוגמה"}', now(), now()),
    ('00000000-0000-0000-0000-000000000000', v_admin_id, 'authenticated', 'authenticated',
     'admin@example.com', crypt('password123', gen_salt('bf')), now(),
     '{"provider":"email","providers":["email"]}', '{"display_name":"מנהל/ת לדוגמה"}', now(), now())
  on conflict (id) do nothing;

  update public.profiles set role = 'researcher' where id = v_researcher_id;
  update public.profiles set role = 'admin' where id = v_admin_id;

  select id into v_ginger_id from public.herbs where slug = 'ginger';
  select id into v_chamomile_id from public.herbs where slug = 'chamomile';

  -- A fully published request (patient can read published_results for it).
  insert into public.requests (id, user_id, herb_id, herb_name_raw, claim_text, is_caregiver, status, assigned_researcher_id)
  values (gen_random_uuid(), v_patient_id, v_ginger_id, 'ג׳ינג׳ר', 'שתיית תה ג׳ינג׳ר לפני הארוחות שיפרה לי את התיאבון.', false, 'draft', v_researcher_id)
  returning id into v_request_published;

  update public.requests set status = 'submitted' where id = v_request_published;
  update public.requests set status = 'ai_processing' where id = v_request_published;
  update public.requests set status = 'researcher_review' where id = v_request_published;
  update public.requests set status = 'approved' where id = v_request_published;
  update public.requests set status = 'published' where id = v_request_published;

  insert into public.ai_drafts (request_id, provider, model, content, citations)
  values (v_request_published, 'openai', 'mock', '{"summary": "מוקאפ: תקציר AI ראשוני"}'::jsonb, '[]'::jsonb);

  insert into public.researcher_reviews (request_id, researcher_id, decision, final_content, researcher_notes)
  values (v_request_published, v_researcher_id, 'approved',
          '{"summary": "קיימות מספר עדויות מוקדמות התומכות בטענה, ברמת ודאות נמוכה."}'::jsonb,
          'מוקאפ: נבדק מול 2 מקורות PubMed, אין התוויית נגד ידועה.')
  returning id into v_review_id;

  insert into public.published_results (request_id, researcher_review_id, body, published_by)
  values (v_request_published, v_review_id,
          '{"summary": "קיימות מספר עדויות מוקדמות התומכות בטענה, ברמת ודאות נמוכה.", "citations": []}'::jsonb,
          v_researcher_id);

  -- A request sitting in researcher_review (visible to researcher/admin, not to the patient's result).
  insert into public.requests (id, user_id, herb_id, herb_name_raw, claim_text, is_caregiver, status, assigned_researcher_id)
  values (gen_random_uuid(), v_caregiver_id, v_chamomile_id, 'קמומיל', 'המטופל שלי שתה תה קמומיל וזה עזר לתיאבון.', true, 'draft', v_researcher_id)
  returning id into v_request_in_review;

  update public.requests set status = 'submitted' where id = v_request_in_review;
  update public.requests set status = 'ai_processing' where id = v_request_in_review;
  update public.requests set status = 'researcher_review' where id = v_request_in_review;

  insert into public.ai_drafts (request_id, provider, model, content, citations)
  values (v_request_in_review, 'openai', 'mock', '{"summary": "מוקאפ: תקציר AI ראשוני לקמומיל"}'::jsonb, '[]'::jsonb);

  -- A plain draft (not yet submitted), owned by the patient.
  insert into public.requests (id, user_id, herb_name_raw, claim_text, is_caregiver, status)
  values (gen_random_uuid(), v_patient_id, 'חילבה', 'טיוטה - עדיין לא נשלחה.', false, 'draft')
  returning id into v_request_draft;
end $$;
