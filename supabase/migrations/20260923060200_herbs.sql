-- Canonical herb list used for identification/autocomplete when a user
-- submits a claim. Free-text is still captured on the request itself
-- (herb_name_raw) since the catalog will never be exhaustive.
create table public.herbs (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name_he text not null,
  name_en text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.herbs is
  'Reference catalog of herbs for claim submission autocomplete. Not exhaustive.';
