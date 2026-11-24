-- =============================================================================
-- Camiva: Quick Fix for RLS Recursion and lesson_sessions Table
-- =============================================================================

-- 1. Helper functions to break cross-table RLS infinite recursion
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

-- 2. Fix policies on public.students to use security definer functions
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

-- 3. Fix policies on public.parent_teacher_relationships to use security definer function
drop policy if exists "ptr: student can select own" on public.parent_teacher_relationships;
create policy "ptr: student can select own"
  on public.parent_teacher_relationships
  for select
  using (public.is_student_user_of(student_id, auth.uid()));

-- 4. Create public.lesson_sessions table if missing
create table if not exists public.lesson_sessions (
  id                     uuid        primary key default gen_random_uuid(),
  relationship_id        uuid        not null
                           references public.parent_teacher_relationships (id) on delete cascade,
  teacher_id             uuid        not null references auth.users (id) on delete cascade,
  student_id             uuid        not null references public.students (id) on delete cascade,
  parent_id              uuid        not null references auth.users (id) on delete cascade,
  subject                text        not null,
  scheduled_at           timestamptz not null,
  duration_minutes       integer     not null default 60
                           constraint lesson_sessions_duration_check
                           check (duration_minutes between 15 and 480),
  teaching_mode          text        not null default 'in_person'
                           constraint lesson_sessions_mode_check
                           check (teaching_mode in ('online', 'in_person', 'both')),
  location_area          text,
  location_city          text,
  status                 text        not null default 'scheduled'
                           constraint lesson_sessions_status_check
                           check (status in ('scheduled', 'completed', 'cancelled', 'missed')),
  note                   text,
  reminder_minutes_before integer    not null default 30
                           constraint lesson_sessions_reminder_check
                           check (reminder_minutes_before between 0 and 240),
  student_name           text,
  teacher_name           text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists lesson_sessions_teacher_idx
  on public.lesson_sessions (teacher_id);
create index if not exists lesson_sessions_student_idx
  on public.lesson_sessions (student_id);
create index if not exists lesson_sessions_parent_idx
  on public.lesson_sessions (parent_id);
create index if not exists lesson_sessions_relationship_idx
  on public.lesson_sessions (relationship_id);
create index if not exists lesson_sessions_scheduled_at_idx
  on public.lesson_sessions (scheduled_at);
create index if not exists lesson_sessions_status_idx
  on public.lesson_sessions (status);

drop trigger if exists lesson_sessions_set_updated_at on public.lesson_sessions;
create trigger lesson_sessions_set_updated_at
  before update on public.lesson_sessions
  for each row execute function public.set_updated_at();

create or replace function public.lesson_sessions_check_overlap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'scheduled' and exists (
    select 1 from public.lesson_sessions
    where teacher_id = new.teacher_id
      and status = 'scheduled'
      and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and scheduled_at < (new.scheduled_at + (new.duration_minutes * interval '1 minute'))
      and (scheduled_at + (duration_minutes * interval '1 minute')) > new.scheduled_at
  ) then
    raise exception 'That time clashes with another lesson.';
  end if;
  return new;
end;
$$;

drop trigger if exists lesson_sessions_check_overlap on public.lesson_sessions;
create trigger lesson_sessions_check_overlap
  before insert or update on public.lesson_sessions
  for each row execute function public.lesson_sessions_check_overlap();

create or replace function public.lesson_sessions_fill_from_relationship()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rel public.parent_teacher_relationships;
  stu public.students;
  v_teacher_name text;
begin
  select * into rel
    from public.parent_teacher_relationships
    where id = new.relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;
  if rel.status <> 'accepted' then
    raise exception 'Cannot schedule on a relationship that is not active';
  end if;

  new.teacher_id := rel.teacher_id;
  new.student_id := rel.student_id;
  new.parent_id  := rel.parent_id;

  select * into stu from public.students where id = rel.student_id;
  if found then
    new.student_name := stu.name;
  end if;

  select display_name into v_teacher_name
    from public.teacher_profiles where user_id = rel.teacher_id;
  if v_teacher_name is null then
    select name into v_teacher_name
      from public.user_profiles where id = rel.teacher_id;
  end if;
  new.teacher_name := v_teacher_name;

  return new;
end;
$$;

drop trigger if exists lesson_sessions_fill_from_relationship on public.lesson_sessions;
create trigger lesson_sessions_fill_from_relationship
  before insert on public.lesson_sessions
  for each row execute function public.lesson_sessions_fill_from_relationship();

alter table public.lesson_sessions enable row level security;

drop policy if exists "ls: teacher can select own" on public.lesson_sessions;
create policy "ls: teacher can select own"
  on public.lesson_sessions
  for select
  using (auth.uid() = teacher_id);

drop policy if exists "ls: parent can select own" on public.lesson_sessions;
create policy "ls: parent can select own"
  on public.lesson_sessions
  for select
  using (auth.uid() = parent_id);

drop policy if exists "ls: student can select own" on public.lesson_sessions;
create policy "ls: student can select own"
  on public.lesson_sessions
  for select
  using (public.is_student_user_of(student_id, auth.uid()));

drop policy if exists "ls: teacher can insert for active relationship" on public.lesson_sessions;
create policy "ls: teacher can insert for active relationship"
  on public.lesson_sessions
  for insert
  with check (
    auth.uid() = teacher_id
    and status = 'scheduled'
    and exists (
      select 1 from public.parent_teacher_relationships r
      where r.id = relationship_id
        and r.teacher_id = auth.uid()
        and r.student_id = lesson_sessions.student_id
        and r.parent_id  = lesson_sessions.parent_id
        and r.status = 'accepted'
    )
  );

drop policy if exists "ls: teacher can update own" on public.lesson_sessions;
create policy "ls: teacher can update own"
  on public.lesson_sessions
  for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

drop policy if exists "ls: teacher can delete own" on public.lesson_sessions;
create policy "ls: teacher can delete own"
  on public.lesson_sessions
  for delete
  using (auth.uid() = teacher_id);
