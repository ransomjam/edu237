-- =============================================================================
-- Camiva — lessons
-- =============================================================================
--
-- A lesson represents a piece of teaching content created by a teacher.
-- 
-- Security model:
--   Teacher  : create, read, update, delete their own lessons.
--   Parent   : read lessons if they have an accepted relationship with the 
--              teacher, AND the student's current school_level matches the 
--              lesson form, AND the lesson's subject is in the student's subjects.
-- =============================================================================

create table if not exists public.lessons (
  id          uuid        primary key default gen_random_uuid(),
  teacher_id  uuid        not null references auth.users (id) on delete cascade,
  title       text        not null,
  description text        not null,
  subject     text        not null,
  form        text        not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists lessons_teacher_idx on public.lessons (teacher_id);
create index if not exists lessons_form_idx on public.lessons (form);
create index if not exists lessons_subject_idx on public.lessons (subject);

drop trigger if exists lessons_set_updated_at on public.lessons;
create trigger lessons_set_updated_at
  before update on public.lessons
  for each row execute function public.set_updated_at();

alter table public.lessons enable row level security;

-- ---- TEACHER POLICIES -------------------------------------------------------

drop policy if exists "lessons: teacher can select own" on public.lessons;
create policy "lessons: teacher can select own"
  on public.lessons
  for select
  using (auth.uid() = teacher_id);

drop policy if exists "lessons: teacher can insert own" on public.lessons;
create policy "lessons: teacher can insert own"
  on public.lessons
  for insert
  with check (auth.uid() = teacher_id);

drop policy if exists "lessons: teacher can update own" on public.lessons;
create policy "lessons: teacher can update own"
  on public.lessons
  for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

drop policy if exists "lessons: teacher can delete own" on public.lessons;
create policy "lessons: teacher can delete own"
  on public.lessons
  for delete
  using (auth.uid() = teacher_id);

-- ---- PARENT POLICIES --------------------------------------------------------

-- Parent can read a lesson if their child has an accepted relationship with the
-- teacher, AND the child's form matches, AND the child takes the subject.
drop policy if exists "lessons: parent can read relevant child lessons" on public.lessons;
create policy "lessons: parent can read relevant child lessons"
  on public.lessons
  for select
  using (
    exists (
      select 1 from public.students s
      join public.parent_teacher_relationships r on r.student_id = s.id
      where s.parent_id = auth.uid()
        and r.teacher_id = lessons.teacher_id
        and r.status = 'accepted'
        and s.school_level = lessons.form
        and lessons.subject = any(s.subjects)
    )
  );
