-- =============================================================================
-- Camiva — assignments, recipients, and submissions
-- =============================================================================

-- =============================================================================
-- ASSIGNMENTS
-- =============================================================================
create table if not exists public.assignments (
  id           uuid        primary key default gen_random_uuid(),
  lesson_id    uuid        not null references public.lessons (id) on delete cascade,
  teacher_id   uuid        not null references auth.users (id) on delete cascade,
  title        text        not null,
  instructions text        not null,
  due_at       timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

create index if not exists assignments_teacher_idx on public.assignments (teacher_id);
create index if not exists assignments_lesson_idx on public.assignments (lesson_id);

drop trigger if exists assignments_set_updated_at on public.assignments;
create trigger assignments_set_updated_at
  before update on public.assignments
  for each row execute function public.set_updated_at();

alter table public.assignments enable row level security;

-- =============================================================================
-- ASSIGNMENT RECIPIENTS
-- =============================================================================
create table if not exists public.assignment_recipients (
  assignment_id uuid        not null references public.assignments (id) on delete cascade,
  student_id    uuid        not null references public.students (id) on delete cascade,
  assigned_at   timestamptz not null default now(),
  primary key (assignment_id, student_id)
);

create index if not exists assignment_recipients_student_idx on public.assignment_recipients (student_id);

alter table public.assignment_recipients enable row level security;


-- =============================================================================
-- SUBMISSIONS
-- =============================================================================
create table if not exists public.submissions (
  id            uuid        primary key default gen_random_uuid(),
  assignment_id uuid        not null references public.assignments (id) on delete cascade,
  student_id    uuid        not null references public.students (id) on delete cascade,
  content       text        not null,
  submitted_at  timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- One submission per assignment per student
create unique index if not exists submissions_assignment_student_idx 
  on public.submissions (assignment_id, student_id);

drop trigger if exists submissions_set_updated_at on public.submissions;
create trigger submissions_set_updated_at
  before update on public.submissions
  for each row execute function public.set_updated_at();

alter table public.submissions enable row level security;


-- =============================================================================
-- POLICIES
-- =============================================================================

-- ---- ASSIGNMENTS ----

-- TEACHER POLICIES (assignments)
drop policy if exists "assignments: teacher can select own" on public.assignments;
create policy "assignments: teacher can select own"
  on public.assignments for select using (auth.uid() = teacher_id);

drop policy if exists "assignments: teacher can insert own" on public.assignments;
create policy "assignments: teacher can insert own"
  on public.assignments for insert with check (auth.uid() = teacher_id);

drop policy if exists "assignments: teacher can update own" on public.assignments;
create policy "assignments: teacher can update own"
  on public.assignments for update using (auth.uid() = teacher_id) with check (auth.uid() = teacher_id);

drop policy if exists "assignments: teacher can delete own" on public.assignments;
create policy "assignments: teacher can delete own"
  on public.assignments for delete using (auth.uid() = teacher_id);

-- PARENT POLICIES (assignments)
-- Parent can select an assignment if their child is a recipient
drop policy if exists "assignments: parent can select if child is recipient" on public.assignments;
create policy "assignments: parent can select if child is recipient"
  on public.assignments for select
  using (
    exists (
      select 1 from public.assignment_recipients ar
      join public.students s on s.id = ar.student_id
      where ar.assignment_id = assignments.id
        and s.parent_id = auth.uid()
    )
  );

-- ---- ASSIGNMENT RECIPIENTS ----

-- TEACHER POLICIES (recipients)
drop policy if exists "recipients: teacher can select for own assignments" on public.assignment_recipients;
create policy "recipients: teacher can select for own assignments"
  on public.assignment_recipients for select
  using (
    exists (
      select 1 from public.assignments a
      where a.id = assignment_id and a.teacher_id = auth.uid()
    )
  );

-- Teacher can insert a recipient ONLY IF the student has an 'accepted' relationship with the teacher.
drop policy if exists "recipients: teacher can insert for connected students" on public.assignment_recipients;
create policy "recipients: teacher can insert for connected students"
  on public.assignment_recipients for insert
  with check (
    exists (
      select 1 from public.assignments a
      where a.id = assignment_id and a.teacher_id = auth.uid()
    )
    and exists (
      select 1 from public.parent_teacher_relationships r
      where r.student_id = student_id
        and r.teacher_id = auth.uid()
        and r.status = 'accepted'
    )
  );

drop policy if exists "recipients: teacher can delete from own assignments" on public.assignment_recipients;
create policy "recipients: teacher can delete from own assignments"
  on public.assignment_recipients for delete
  using (
    exists (
      select 1 from public.assignments a
      where a.id = assignment_id and a.teacher_id = auth.uid()
    )
  );

-- PARENT POLICIES (recipients)
drop policy if exists "recipients: parent can select own child" on public.assignment_recipients;
create policy "recipients: parent can select own child"
  on public.assignment_recipients for select
  using (
    exists (
      select 1 from public.students s
      where s.id = student_id and s.parent_id = auth.uid()
    )
  );

-- ---- SUBMISSIONS ----

-- TEACHER POLICIES (submissions)
drop policy if exists "submissions: teacher can select for own assignments" on public.submissions;
create policy "submissions: teacher can select for own assignments"
  on public.submissions for select
  using (
    exists (
      select 1 from public.assignments a
      where a.id = assignment_id and a.teacher_id = auth.uid()
    )
  );
-- Teachers cannot insert/update/delete submissions

-- PARENT POLICIES (submissions)
drop policy if exists "submissions: parent can select own child" on public.submissions;
create policy "submissions: parent can select own child"
  on public.submissions for select
  using (
    exists (
      select 1 from public.students s
      where s.id = student_id and s.parent_id = auth.uid()
    )
  );

-- Parent can insert/update submission if their child is an assignment recipient
drop policy if exists "submissions: parent can insert for child recipient" on public.submissions;
create policy "submissions: parent can insert for child recipient"
  on public.submissions for insert
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_id and s.parent_id = auth.uid()
    )
    and exists (
      select 1 from public.assignment_recipients ar
      where ar.assignment_id = assignment_id and ar.student_id = student_id
    )
  );

drop policy if exists "submissions: parent can update for child recipient" on public.submissions;
create policy "submissions: parent can update for child recipient"
  on public.submissions for update
  using (
    exists (
      select 1 from public.students s
      where s.id = student_id and s.parent_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.students s
      where s.id = student_id and s.parent_id = auth.uid()
    )
  );
