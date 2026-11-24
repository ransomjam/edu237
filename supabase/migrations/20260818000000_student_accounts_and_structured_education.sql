-- =============================================================================
-- Camiva — student accounts + structured education model
-- =============================================================================
--
-- Two changes, both non-destructive:
--
--   1. STUDENT AS AN AUTHENTICATED ROLE
--      `students` stays the single canonical learner table. A student account
--      is a LINK to an existing row (`students.user_id`), never a second row.
--      A learner is therefore one of:
--        * parent-managed  — parent_id set, user_id null   (unchanged)
--        * self-managed    — user_id set, parent_id null
--        * linked          — both set (a parent linked an account, or a
--                            student's parent joined later)
--
--   2. STRUCTURED EDUCATION
--      The simplistic `school_level = 'Form 4'` free-text becomes a structured
--      academic profile: subsystem / school_stage / cycle / level_code /
--      series_code. `school_level` is KEPT as the denormalised human label of
--      the same level so historical rows, existing RLS policies (lessons,
--      teacher_requests snapshots) and older clients keep working.
--
-- MIGRATION SAFETY
-- -----------------------------------------------------------------------------
-- No column is dropped and no value is overwritten. The only data write is the
-- legacy backfill in section 4, which:
--   * only touches rows where level_code IS NULL, and
--   * only maps 'Form 1'…'Form 5' — the English subsystem is the sole possible
--     historical meaning of those labels, since that is all the product ever
--     offered.
-- Anything else (a typo, a hand-entered class, an unexpected value) is left
-- exactly as it is, with level_code NULL. The app treats those as "needs
-- review" and asks the user to confirm the class in Edit Child. A French level
-- is NEVER assigned to an existing record.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. user_profiles — allow the student role
-- -----------------------------------------------------------------------------
-- 'student' was explicitly rejected by the previous CHECK (the retired
-- Google-Classroom-style model). It is now a first-class authenticated role
-- with its own, deliberately small, experience.

alter table public.user_profiles
  drop constraint if exists user_profiles_active_role_check;
alter table public.user_profiles
  add constraint user_profiles_active_role_check
  check (active_role in ('parent', 'teacher', 'student'));


-- -----------------------------------------------------------------------------
-- 2. students — the account link
-- -----------------------------------------------------------------------------

alter table public.students
  add column if not exists user_id uuid references auth.users (id) on delete set null;

-- One account links to at most one learner record. This is the constraint that
-- makes "do not duplicate the same student" enforceable in the database rather
-- than only in the app.
create unique index if not exists students_user_id_key
  on public.students (user_id)
  where user_id is not null;

-- A self-managed student has no parent, so parent_id can no longer be NOT NULL.
alter table public.students
  alter column parent_id drop not null;

-- ...but a row must still belong to somebody. An orphan learner record is a
-- bug, not a state.
alter table public.students
  drop constraint if exists students_owner_present_check;
alter table public.students
  add constraint students_owner_present_check
  check (parent_id is not null or user_id is not null);


-- -----------------------------------------------------------------------------
-- 3. students — structured academic profile
-- -----------------------------------------------------------------------------
-- level_code is the canonical value (e.g. 'en.sec.ol.form4'); the other three
-- are denormalised from it so the database can filter and report on subsystem /
-- stage / cycle without parsing a string. school_level keeps the human label.

alter table public.students
  add column if not exists subsystem text
    constraint students_subsystem_check
    check (subsystem is null or subsystem in ('english', 'french'));

alter table public.students
  add column if not exists school_stage text
    constraint students_school_stage_check
    check (school_stage is null or school_stage in ('primary', 'secondary'));

alter table public.students
  add column if not exists cycle text;

alter table public.students
  add column if not exists level_code text;

alter table public.students
  add column if not exists series_code text;

create index if not exists students_level_code_idx
  on public.students (level_code);
create index if not exists students_subsystem_idx
  on public.students (subsystem);


-- -----------------------------------------------------------------------------
-- 4. Legacy backfill — 'Form 1'…'Form 5' only
-- -----------------------------------------------------------------------------
-- Those labels exist only because the product previously offered nothing but
-- the English GCE Ordinary Level. Interpreting them as English is therefore a
-- statement of historical fact, not a guess.
--
-- Rows whose school_level is anything else are intentionally left with
-- level_code NULL so the owner can confirm them. Run this to see them:
--
--   select id, name, school_level from public.students
--    where level_code is null and coalesce(school_level, '') <> '';

update public.students
   set subsystem    = 'english',
       school_stage = 'secondary',
       cycle        = 'en.sec.ol',
       level_code   = case trim(school_level)
                        when 'Form 1' then 'en.sec.ol.form1'
                        when 'Form 2' then 'en.sec.ol.form2'
                        when 'Form 3' then 'en.sec.ol.form3'
                        when 'Form 4' then 'en.sec.ol.form4'
                        when 'Form 5' then 'en.sec.ol.form5'
                      end
 where level_code is null
   and trim(coalesce(school_level, '')) in
       ('Form 1', 'Form 2', 'Form 3', 'Form 4', 'Form 5');


-- -----------------------------------------------------------------------------
-- 5. students — RLS for the student's own record
-- -----------------------------------------------------------------------------
-- The existing parent and teacher policies are untouched and still apply. A
-- parent-owned child keeps working exactly as before.

-- A student may read the one record their account is linked to.
drop policy if exists "students: student can select own" on public.students;
create policy "students: student can select own"
  on public.students
  for select
  using (auth.uid() = user_id);

-- A student may create their own record during signup, and only their own:
-- user_id must be themselves, and they may not attach a parent. The unique
-- index on user_id prevents a second record for the same account.
drop policy if exists "students: student can insert own" on public.students;
create policy "students: student can insert own"
  on public.students
  for insert
  with check (auth.uid() = user_id and parent_id is null);

-- A student may correct their own academic profile. They may NOT reassign the
-- record to another account or detach it, so `user_id` must still be them
-- after the update.
drop policy if exists "students: student can update own" on public.students;
create policy "students: student can update own"
  on public.students
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Deliberately no delete policy for students: removing a learner record can
-- destroy a parent's data and a teacher's history.


-- -----------------------------------------------------------------------------
-- 6. Read access for a signed-in student across their own learning
-- -----------------------------------------------------------------------------
-- We use SECURITY DEFINER helper functions to break cross-table RLS recursion
-- between students, parent_teacher_relationships, teacher_requests, and lesson_sessions.

create or replace function public.is_student_user_of(p_student_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.students s
    where s.id = p_student_id
      and s.user_id = p_user_id
  );
$$;

create or replace function public.is_teacher_in_accepted_relationship(p_student_id uuid, p_teacher_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.parent_teacher_relationships r
    where r.student_id = p_student_id
      and r.teacher_id = p_teacher_id
      and r.status = 'accepted'
  );
$$;

create or replace function public.is_teacher_in_pending_request(p_student_id uuid, p_teacher_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.teacher_requests tr
    where tr.student_id = p_student_id
      and tr.teacher_id = p_teacher_id
      and tr.status = 'pending'
  );
$$;

-- Fix teacher read policies on students to use security definer functions
drop policy if exists "students: teacher can read via pending request" on public.students;
create policy "students: teacher can read via pending request"
  on public.students
  for select
  using (public.is_teacher_in_pending_request(id, auth.uid()));

drop policy if exists "students: teacher can read via accepted relationship" on public.students;
create policy "students: teacher can read via accepted relationship"
  on public.students
  for select
  using (public.is_teacher_in_accepted_relationship(id, auth.uid()));

-- Their teaching arrangements (so Home can list "my teachers").
drop policy if exists "ptr: student can select own" on public.parent_teacher_relationships;
create policy "ptr: student can select own"
  on public.parent_teacher_relationships
  for select
  using (public.is_student_user_of(student_id, auth.uid()));

-- Their scheduled lessons.
drop policy if exists "ls: student can select own" on public.lesson_sessions;
create policy "ls: student can select own"
  on public.lesson_sessions
  for select
  using (public.is_student_user_of(student_id, auth.uid()));

-- The work set for them.
drop policy if exists "learning_activity_recipients: student read own"
  on public.learning_activity_recipients;
create policy "learning_activity_recipients: student read own"
  on public.learning_activity_recipients
  for select
  using (public.is_student_user_of(student_id, auth.uid()));

drop policy if exists "learning_activities: student read own"
  on public.learning_activities;
create policy "learning_activities: student read own"
  on public.learning_activities
  for select
  using (
    exists (
      select 1
        from public.learning_activity_recipients r
       where r.activity_id = learning_activities.id
         and public.is_student_user_of(r.student_id, auth.uid())
    )
  );

-- Note: teacher_profiles is already readable by any authenticated user
-- (discovery), so a student can resolve their teachers' names with no new
-- policy and no extra exposure.


-- -----------------------------------------------------------------------------
-- 7. teacher_profiles — structured teaching profile
-- -----------------------------------------------------------------------------
-- `forms` stays as the denormalised label mirror. `level_codes` is the
-- canonical field: it carries the subsystem, which is what makes matching
-- distinguish an English Form 4 teacher from a French 4ème teacher.

alter table public.teacher_profiles
  add column if not exists level_codes text[] not null default '{}';

alter table public.teacher_profiles
  add column if not exists series_codes text[] not null default '{}';

-- Backfill from the existing labels, same historical reasoning as section 4:
-- 'Form N' could only ever have meant the English subsystem.
update public.teacher_profiles
   set level_codes = (
         select coalesce(array_agg(mapped order by mapped), '{}')
           from (
             select case trim(f)
                      when 'Form 1' then 'en.sec.ol.form1'
                      when 'Form 2' then 'en.sec.ol.form2'
                      when 'Form 3' then 'en.sec.ol.form3'
                      when 'Form 4' then 'en.sec.ol.form4'
                      when 'Form 5' then 'en.sec.ol.form5'
                    end as mapped
               from unnest(teacher_profiles.forms) as f
           ) m
          where mapped is not null
       )
 where cardinality(level_codes) = 0
   and cardinality(forms) > 0;


-- -----------------------------------------------------------------------------
-- 8. Verification queries (run manually)
-- -----------------------------------------------------------------------------
-- Learner records still needing a confirmed class:
--   select id, name, school_level from public.students
--    where level_code is null and coalesce(school_level, '') <> '';
--
-- No learner record was orphaned:
--   select count(*) from public.students
--    where parent_id is null and user_id is null;   -- must be 0
--
-- No account is linked to two learner records:
--   select user_id, count(*) from public.students
--    where user_id is not null group by user_id having count(*) > 1;  -- empty
