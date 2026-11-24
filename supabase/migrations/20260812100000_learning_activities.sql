-- =============================================================================
-- Camiva — learning activities
-- =============================================================================
--
-- A lightweight learning activity system designed for minimal teacher input.
-- Teachers create activities by selecting subject, type, topic, students.
--
-- Security model:
--   Teacher  : full CRUD on own activities. Manage recipient status.
--   Parent   : read-only access to activities targeting their children.
-- =============================================================================

-- ---- LEARNING ACTIVITIES TABLE -----------------------------------------------

create table if not exists public.learning_activities (
  id            uuid        primary key default gen_random_uuid(),
  teacher_id    uuid        not null references auth.users (id) on delete cascade,
  subject       text        not null,
  form          text        not null,
  topic         text        not null,
  activity_type text        not null check (activity_type in ('lesson', 'practice', 'homework', 'revision')),
  note          text,
  due_date      date,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists learning_activities_teacher_idx
  on public.learning_activities (teacher_id);
create index if not exists learning_activities_form_subject_idx
  on public.learning_activities (form, subject);

drop trigger if exists learning_activities_set_updated_at on public.learning_activities;
create trigger learning_activities_set_updated_at
  before update on public.learning_activities
  for each row execute function public.set_updated_at();

alter table public.learning_activities enable row level security;

-- ---- LEARNING ACTIVITY RECIPIENTS TABLE -------------------------------------

create table if not exists public.learning_activity_recipients (
  id            uuid        primary key default gen_random_uuid(),
  activity_id   uuid        not null references public.learning_activities (id) on delete cascade,
  student_id    uuid        not null references public.students (id) on delete cascade,
  status        text        not null default 'upcoming'
                            check (status in ('upcoming', 'in_progress', 'completed', 'needs_attention')),
  teacher_note  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create unique index if not exists learning_activity_recipients_unique_idx
  on public.learning_activity_recipients (activity_id, student_id);
create index if not exists learning_activity_recipients_student_idx
  on public.learning_activity_recipients (student_id);
create index if not exists learning_activity_recipients_activity_idx
  on public.learning_activity_recipients (activity_id);

drop trigger if exists learning_activity_recipients_set_updated_at on public.learning_activity_recipients;
create trigger learning_activity_recipients_set_updated_at
  before update on public.learning_activity_recipients
  for each row execute function public.set_updated_at();

alter table public.learning_activity_recipients enable row level security;

-- =============================================================================
-- RLS POLICIES — LEARNING ACTIVITIES
-- =============================================================================

-- Teacher can read own activities
drop policy if exists "learning_activities: teacher select own" on public.learning_activities;
create policy "learning_activities: teacher select own"
  on public.learning_activities for select
  using (auth.uid() = teacher_id);

-- Teacher can insert own activities
drop policy if exists "learning_activities: teacher insert own" on public.learning_activities;
create policy "learning_activities: teacher insert own"
  on public.learning_activities for insert
  with check (auth.uid() = teacher_id);

-- Teacher can update own activities
drop policy if exists "learning_activities: teacher update own" on public.learning_activities;
create policy "learning_activities: teacher update own"
  on public.learning_activities for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

-- Teacher can delete own activities
drop policy if exists "learning_activities: teacher delete own" on public.learning_activities;
create policy "learning_activities: teacher delete own"
  on public.learning_activities for delete
  using (auth.uid() = teacher_id);

-- Parent can read activities where their child is a recipient
drop policy if exists "learning_activities: parent read child activities" on public.learning_activities;
create policy "learning_activities: parent read child activities"
  on public.learning_activities for select
  using (
    exists (
      select 1
      from public.learning_activity_recipients lar
      join public.students s on s.id = lar.student_id
      where lar.activity_id = learning_activities.id
        and s.parent_id = auth.uid()
    )
  );

-- =============================================================================
-- RLS POLICIES — LEARNING ACTIVITY RECIPIENTS
-- =============================================================================

-- Teacher can read recipients for their own activities
drop policy if exists "learning_activity_recipients: teacher select own" on public.learning_activity_recipients;
create policy "learning_activity_recipients: teacher select own"
  on public.learning_activity_recipients for select
  using (
    exists (
      select 1 from public.learning_activities la
      where la.id = learning_activity_recipients.activity_id
        and la.teacher_id = auth.uid()
    )
  );

-- Teacher can insert recipients only for own activities AND connected students
drop policy if exists "learning_activity_recipients: teacher insert connected" on public.learning_activity_recipients;
create policy "learning_activity_recipients: teacher insert connected"
  on public.learning_activity_recipients for insert
  with check (
    exists (
      select 1 from public.learning_activities la
      where la.id = learning_activity_recipients.activity_id
        and la.teacher_id = auth.uid()
    )
    and exists (
      select 1 from public.parent_teacher_relationships ptr
      where ptr.student_id = learning_activity_recipients.student_id
        and ptr.teacher_id = auth.uid()
        and ptr.status = 'accepted'
    )
  );

-- Teacher can update recipient status for own activities
drop policy if exists "learning_activity_recipients: teacher update own" on public.learning_activity_recipients;
create policy "learning_activity_recipients: teacher update own"
  on public.learning_activity_recipients for update
  using (
    exists (
      select 1 from public.learning_activities la
      where la.id = learning_activity_recipients.activity_id
        and la.teacher_id = auth.uid()
    )
  );

-- Teacher can delete recipients for own activities
drop policy if exists "learning_activity_recipients: teacher delete own" on public.learning_activity_recipients;
create policy "learning_activity_recipients: teacher delete own"
  on public.learning_activity_recipients for delete
  using (
    exists (
      select 1 from public.learning_activities la
      where la.id = learning_activity_recipients.activity_id
        and la.teacher_id = auth.uid()
    )
  );

-- Parent can read recipient rows for own children
drop policy if exists "learning_activity_recipients: parent read child" on public.learning_activity_recipients;
create policy "learning_activity_recipients: parent read child"
  on public.learning_activity_recipients for select
  using (
    exists (
      select 1 from public.students s
      where s.id = learning_activity_recipients.student_id
        and s.parent_id = auth.uid()
    )
  );
