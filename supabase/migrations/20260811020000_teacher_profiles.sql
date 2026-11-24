-- =============================================================================
-- Camiva — teacher_profiles
-- =============================================================================
--
-- A teacher's public teaching profile, used for parent-side discovery. Holds
-- only discovery-relevant fields (name, subjects, forms, bio) — no address,
-- phone, or date of birth. One profile per teacher (user_id is unique).
--
-- RLS:
--   * A teacher may create / read / update ONLY their own profile.
--   * Any authenticated user (parents included) may READ all teacher profiles
--     for discovery. No one may modify a profile they do not own.
-- =============================================================================

create table if not exists public.teacher_profiles (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null unique references auth.users (id) on delete cascade,
  display_name  text        not null,
  subjects      text[]      not null default '{}',
  forms         text[]      not null default '{}',
  bio           text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists teacher_profiles_user_id_idx
  on public.teacher_profiles (user_id);

drop trigger if exists teacher_profiles_set_updated_at on public.teacher_profiles;
create trigger teacher_profiles_set_updated_at
  before update on public.teacher_profiles
  for each row execute function public.set_updated_at();

alter table public.teacher_profiles enable row level security;

-- Any authenticated user may read teacher profiles (discovery). This exposes
-- only teaching info, never private account data.
drop policy if exists "teacher_profiles: authenticated can read" on public.teacher_profiles;
create policy "teacher_profiles: authenticated can read"
  on public.teacher_profiles
  for select
  using (auth.uid() is not null);

-- A teacher may create only their own profile.
drop policy if exists "teacher_profiles: owner can insert" on public.teacher_profiles;
create policy "teacher_profiles: owner can insert"
  on public.teacher_profiles
  for insert
  with check (auth.uid() = user_id);

-- A teacher may update only their own profile. Parents (non-owners) are denied.
drop policy if exists "teacher_profiles: owner can update" on public.teacher_profiles;
create policy "teacher_profiles: owner can update"
  on public.teacher_profiles
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- No delete policy. Profiles are retained.
