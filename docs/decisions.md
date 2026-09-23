# Engineering Decisions (changeable implementation choices)

These entries are **implementation defaults**, not previously approved product decisions. Product-level binding decisions live in the specification (sections 1–2) and are not restated here.

| # | Date | Decision | Rationale | Status |
|---|------|----------|-----------|--------|
| D-001 | 2026-09-16 | Working name **Herbal Evidence** (Hebrew UI: ראיות צמחים). Hebrew RTL first, structured for future localization (string tables, `dir` attributes, bidi isolation). | Spec §3 | default |
| D-002 | 2026-09-16 | Backend: Python 3.13, FastAPI, Uvicorn, `uv` for dependency management. | Spec §3; uv installed locally | default |
| D-003 | 2026-09-16 | Frontend: plain HTML/CSS/JS, no framework. Served by a static server (Caddy) in its own Railway service. | Spec §3 | default |
| D-004 | 2026-09-16 | Auth: Supabase Auth, email/password, email verification, password reset. Backend validates Supabase JWTs (iss/aud/exp). | Spec §3 | default |
| D-005 | 2026-09-16 | Admin manually assigns requests to researchers. Simple `assigned_researcher_id` column; replaceable. | Spec §3, open business decision | default |
| D-006 | 2026-09-16 | No request-update emails in v1. | Spec §3 | default |
| D-007 | 2026-09-16 | Separate Supabase projects `herbal-evidence-dev` and `herbal-evidence-prod`, in a **new Supabase organization** created for this product. | Spec §3, §12; user choice during planning | default |
| D-008 | 2026-09-16 | AI provider interface is replaceable; first concrete adapter targets **OpenAI**. Model and key via `AI_PROVIDER`, `AI_MODEL`, `AI_API_KEY`. Without a key the provider raises a structured "not configured" job failure — never mock content. | Spec §3; user choice during planning | default |
| D-009 | 2026-09-16 | Literature adapters: PubMed E-utilities (esearch/efetch) + Europe PMC REST. Optional `NCBI_API_KEY` for higher rate limits. | Spec §6 | default |
| D-010 | 2026-09-16 | Durable job queue in Postgres (`research_jobs`), claimed with `FOR UPDATE SKIP LOCKED`, lease + heartbeat, bounded retries, idempotency key; consumer runs inside the backend process lifespan. No Redis, no third service. | Spec §8 | default |
| D-011 | 2026-09-16 | Drafts and staff artifacts have **no** RLS policies for `anon`/`authenticated`; they are reachable only through the backend using the service-role key with explicit server-side authorization. | Spec §9–10 | default |
| D-012 | 2026-09-16 | Design created in Google Stitch (project `12444680124780591192`, design system asset `602809031577218080`). Screen IDs in `docs/design/stitch.md`. | Spec §11 | default |
| D-013 | 2026-09-16 | Work is executed in phases (0–6) with a review stop after each; progress logged in Obsidian `HERBAL_EVIDENCE_PROJECT/`. | User instruction | default |
| D-014 | 2026-09-23 | Dev Supabase project `herbal-evidence-dev` (ref `prfamfzsepxespdncjfk`, `eu-central-1`) created in the existing org `zivwais-ux's Org` (free plan) rather than a new org; organizations can't be created from the tooling used. Can be moved to a dedicated org later via the Supabase dashboard (project transfer). Supersedes the org part of D-007. | Frankfurt is the closest available region to Israel-based users | default |
