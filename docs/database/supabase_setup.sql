-- =============================================================================
-- Camiva - Supabase database setup
-- =============================================================================
--
-- Run this SQL in the Supabase SQL editor for your project.
-- It is safe to run multiple times (uses IF NOT EXISTS / OR REPLACE).
--
-- Prerequisites:
--   - A Supabase project with Auth enabled.
--   - Email confirmation can be ON or OFF. When it is ON, onboarding starts
--     only after the user confirms email and signs in.
--
-- Tables created:
--   - user_profiles
--   - students
--   - parent_teacher_relationships
--
-- Do not run destructive SQL against an unknown project.
--
-- =============================================================================
--
-- DOMAIN MODEL (corrected 2026-08-11)
-- -----------------------------------------------------------------------------
-- Camiva is a parent–teacher tutoring platform, NOT a student classroom app.
--   * Parent and Teacher are the only authenticated roles.
--   * A Student is a managed learner record owned by a Parent. Students never
--     authenticate, never log in, and never enter join codes.
--   * The core teaching arrangement is the parent_teacher_relationship, scoped
--     to a single student. There is no Class entity in the MVP.
--
-- MIGRATION NOTE — replacing the retired Google-Classroom-style model
-- -----------------------------------------------------------------------------
-- Two changes below are potentially destructive on an existing project:
--   1. user_profiles.active_role CHECK now allows only ('parent','teacher').
--      Any existing row with active_role = 'student' will violate the new
--      constraint. Because this is a development project, inspect first:
--
--        select id, email, active_role from public.user_profiles
--          where active_role not in ('parent','teacher');
--
--      Decide per project how to handle any such rows, e.g. convert legacy
--      student accounts to parents (they were the account holder):
--
--        update public.user_profiles set active_role = 'parent'
--          where active_role = 'student';
--
--      Only then apply the new CHECK constraint (see section 1). Do NOT run a
--      blind data-losing migration against production.
--   2. The `classes` table (join-code self-enrolment) is retired. It is NOT
--      dropped automatically by this script — see section 5 for the guarded,
--      opt-in drop so history is preserved until you consciously remove it.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. user_profiles
-- -----------------------------------------------------------------------------
-- One row per authenticated user.
-- The primary key is the Supabase Auth user UUID so foreign-key integrity is
-- maintained automatically.
--
-- active_role stores the authenticated role the user operates under.
-- Allowed values: 'parent' | 'teacher'  (there is no authenticated student)
-- The CHECK constraint prevents arbitrary strings being stored.
--
-- The app does not write a fake or provisional profile during signup.
-- Onboarding creates or updates this row after Supabase has established an
-- authenticated session. profile_complete is set to TRUE once name and
-- active_role have been confirmed by the user.
-- -----------------------------------------------------------------------------

create table if not exists public.user_profiles (
  id               uuid        primary key references auth.users (id) on delete cascade,
  email            text        not null,
  name             text        not null,
  active_role      text        not null
                     constraint user_profiles_active_role_check
                     check (active_role in ('parent', 'teacher')),
  profile_complete boolean     not null default false,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

-- Migration for an existing user_profiles table that still carries the old
-- ('student','teacher') CHECK. Run the data-cleanup query in the header first;
-- this replaces the constraint idempotently. Safe to run when the table is new.
alter table public.user_profiles
  drop constraint if exists user_profiles_active_role_check;
alter table public.user_profiles
  add constraint user_profiles_active_role_check
  check (active_role in ('parent', 'teacher'));

-- Keep updated_at current automatically.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_profiles_set_updated_at on public.user_profiles;
create trigger user_profiles_set_updated_at
  before update on public.user_profiles
  for each row execute function public.set_updated_at();


-- -----------------------------------------------------------------------------
-- 2. Row Level Security
-- -----------------------------------------------------------------------------
-- RLS is ENABLED. Users can only read and write their own profile row.
-- No policy allows reading another user's profile.
-- Service-role key (used only server-side) bypasses RLS; never expose it
-- to the client app.
-- -----------------------------------------------------------------------------

alter table public.user_profiles enable row level security;

-- A user may read their own profile.
drop policy if exists "user_profiles: owner can select" on public.user_profiles;
create policy "user_profiles: owner can select"
  on public.user_profiles
  for select
  using (auth.uid() = id);

-- A user may insert their own profile row during onboarding.
drop policy if exists "user_profiles: owner can insert" on public.user_profiles;
create policy "user_profiles: owner can insert"
  on public.user_profiles
  for insert
  with check (auth.uid() = id);

-- A user may update their own profile row.
drop policy if exists "user_profiles: owner can update" on public.user_profiles;
create policy "user_profiles: owner can update"
  on public.user_profiles
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- No delete policy. Profiles are retained when a user logs out.
-- Account deletion is out of scope for the MVP.


-- -----------------------------------------------------------------------------
-- 3. Verification queries (run manually to confirm setup)
-- -----------------------------------------------------------------------------
-- select * from public.user_profiles; -- should be empty initially
-- select * from pg_policies where tablename = 'user_profiles'; -- 3 policies

-- -----------------------------------------------------------------------------
-- 4. students
-- -----------------------------------------------------------------------------
-- A managed learner record owned by a parent. NOT an authenticated user:
-- no email, password, phone, or auth linkage. parent_id references the owning
-- parent's auth.users id. A parent may own many students.
-- -----------------------------------------------------------------------------

create table if not exists public.students (
  id             uuid        primary key default gen_random_uuid(),
  parent_id      uuid        not null references auth.users (id) on delete cascade,
  name           text        not null,
  date_of_birth  date,
  school_level   text,
  notes          text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

create index if not exists students_parent_id_idx
  on public.students (parent_id);

drop trigger if exists students_set_updated_at on public.students;
create trigger students_set_updated_at
  before update on public.students
  for each row execute function public.set_updated_at();

alter table public.students enable row level security;

-- A parent may only see, create, update, and delete students they own.
-- No policy grants access to another parent's students.
drop policy if exists "students: parent can select own" on public.students;
create policy "students: parent can select own"
  on public.students
  for select
  using (auth.uid() = parent_id);

drop policy if exists "students: parent can insert own" on public.students;
create policy "students: parent can insert own"
  on public.students
  for insert
  with check (auth.uid() = parent_id);

drop policy if exists "students: parent can update own" on public.students;
create policy "students: parent can update own"
  on public.students
  for update
  using (auth.uid() = parent_id)
  with check (auth.uid() = parent_id);

drop policy if exists "students: parent can delete own" on public.students;
create policy "students: parent can delete own"
  on public.students
  for delete
  using (auth.uid() = parent_id);


-- -----------------------------------------------------------------------------
-- 5. parent_teacher_relationships
-- -----------------------------------------------------------------------------
-- The core teaching arrangement, scoped to a single student. The same teacher
-- can teach multiple students (including several children of one parent) via
-- distinct relationship rows. There is no Class entity in the MVP.
--
-- parent_id must always match the owning parent of student_id; this is enforced
-- by RLS (the insert check confirms the caller owns the student).
-- -----------------------------------------------------------------------------

create table if not exists public.parent_teacher_relationships (
  id          uuid        primary key default gen_random_uuid(),
  parent_id   uuid        not null references auth.users (id) on delete cascade,
  student_id  uuid        not null references public.students (id) on delete cascade,
  teacher_id  uuid        not null references auth.users (id) on delete cascade,
  subject     text        not null,
  level       text        not null,
  status      text        not null default 'requested'
                constraint parent_teacher_relationships_status_check
                check (status in
                  ('requested', 'accepted', 'rejected', 'cancelled', 'suspended')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists ptr_parent_id_idx
  on public.parent_teacher_relationships (parent_id);
create index if not exists ptr_teacher_id_idx
  on public.parent_teacher_relationships (teacher_id);
create index if not exists ptr_student_id_idx
  on public.parent_teacher_relationships (student_id);

drop trigger if exists ptr_set_updated_at on public.parent_teacher_relationships;
create trigger ptr_set_updated_at
  before update on public.parent_teacher_relationships
  for each row execute function public.set_updated_at();

alter table public.parent_teacher_relationships enable row level security;

-- A parent may read relationships for their own students. A teacher may read
-- relationships where they are the named teacher. No broad authenticated read.
drop policy if exists "ptr: parent can select own" on public.parent_teacher_relationships;
create policy "ptr: parent can select own"
  on public.parent_teacher_relationships
  for select
  using (auth.uid() = parent_id);

drop policy if exists "ptr: teacher can select assigned" on public.parent_teacher_relationships;
create policy "ptr: teacher can select assigned"
  on public.parent_teacher_relationships
  for select
  using (auth.uid() = teacher_id);

-- A parent may create a request only for a student they own, and only with
-- themselves as parent_id. The subquery prevents requesting on another
-- parent's student.
drop policy if exists "ptr: parent can insert for own student" on public.parent_teacher_relationships;
create policy "ptr: parent can insert for own student"
  on public.parent_teacher_relationships
  for insert
  with check (
    auth.uid() = parent_id
    and exists (
      select 1 from public.students s
      where s.id = student_id and s.parent_id = auth.uid()
    )
  );

-- A parent may update their own relationship rows (e.g. cancel).
drop policy if exists "ptr: parent can update own" on public.parent_teacher_relationships;
create policy "ptr: parent can update own"
  on public.parent_teacher_relationships
  for update
  using (auth.uid() = parent_id)
  with check (auth.uid() = parent_id);

-- A teacher may update relationship rows assigned to them (e.g. accept/reject/
-- suspend). A teacher cannot reassign a relationship to another teacher.
drop policy if exists "ptr: teacher can update assigned" on public.parent_teacher_relationships;
create policy "ptr: teacher can update assigned"
  on public.parent_teacher_relationships
  for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);


-- -----------------------------------------------------------------------------
-- 6. RETIRED: classes (Google-Classroom-style join-code self-enrolment)
-- -----------------------------------------------------------------------------
-- The `classes` table and its join-code flow are retired. They assumed students
-- log in and enter a join code, which is no longer the product model.
--
-- This script does NOT drop `classes` automatically, so history is preserved.
-- When you have confirmed no data must be retained, drop it explicitly:
--
--   drop table if exists public.classes cascade;
--
-- (Its RLS policies and trigger are removed together with the table.)
