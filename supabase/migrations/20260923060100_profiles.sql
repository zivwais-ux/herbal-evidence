-- One row per auth user, holding the app-level role and display data that
-- Supabase Auth itself doesn't store.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  role public.app_role not null default 'user',
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is
  'App-level profile + role for each auth.users row. Created automatically on signup by handle_new_user().';

create trigger set_profiles_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- New Supabase Auth users automatically get a 'user' profile.
-- Researcher/admin roles are elevated later by an admin (out of scope for
-- this trigger; see docs/decisions.md).
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Small helper used throughout RLS policies to read the caller's role
-- without recursive RLS checks on profiles itself.
create function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;
