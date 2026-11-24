-- =============================================================================
-- Camiva — lesson_sessions (actual scheduled lessons)
-- =============================================================================
--
-- Once a teacher has ACCEPTED a parent's request, an active
-- parent_teacher_relationship exists. A lesson_session is ONE real, scheduled
-- lesson built on top of that relationship:
--
--     relationship (who teaches whom)  →  lesson_session (a specific lesson)
--
-- The relationship is the source of truth for the parties. We deliberately do
-- NOT re-store the parent/student/teacher identities as editable fields — the
-- teacher_id / student_id / parent_id on the session are DERIVED from the
-- relationship by a BEFORE INSERT trigger, so a session can never point at a
-- student the teacher is not actually connected to.
--
-- MVP scope (intentionally small):
--   * Teacher creates the session; the parent views/confirms it.
--   * One teacher → one student per session (no group lessons).
--   * Status is a flat set, not a state machine: scheduled | completed |
--     cancelled | missed.
--   * A single 30-minute reminder is expressed as reminder_minutes_before; the
--     reminder itself is computed from scheduled_at (see the app-side planner).
--
-- Denormalised, read-only display snapshots (student_name, teacher_name) are
-- filled by the trigger so both sides can render a card without extra joins or
-- widened RLS — mirroring the teacher_requests snapshot pattern.
-- =============================================================================

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
  -- Read-only display snapshots (see trigger below).
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

-- ---------------------------------------------------------------------------
-- Prevent double-booking: a teacher cannot have two SCHEDULED sessions
-- whose time ranges overlap. Completed/cancelled/missed sessions are ignored so
-- history never blocks new scheduling. Implemented via trigger.
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- Derive parties + snapshots from the relationship. Runs as owner so it can
-- read the relationship / student / teacher rows regardless of the caller's
-- RLS, but it VALIDATES that the relationship is accepted before allowing the
-- insert. The RLS WITH CHECK (evaluated after this BEFORE trigger) then
-- confirms the caller is the derived teacher.
-- ---------------------------------------------------------------------------
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

  -- Parties always come from the relationship — never trusted from the client.
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

-- ---- SELECT ---------------------------------------------------------------
-- Teacher sees sessions they teach; parent sees sessions for their children.
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

-- ---- INSERT ---------------------------------------------------------------
-- Only the teacher of an ACCEPTED relationship may create a session. The
-- trigger has already set teacher_id from the relationship, so requiring
-- auth.uid() = teacher_id here means a caller can only insert for a
-- relationship where THEY are the teacher. The relationship existence/ownership
-- is re-checked so a parent (or another teacher) can never insert.
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

-- ---- UPDATE ---------------------------------------------------------------
-- The teacher owns the lifecycle: reschedule, mark completed/missed/cancelled,
-- add a note. They can never move a session to another teacher.
drop policy if exists "ls: teacher can update own" on public.lesson_sessions;
create policy "ls: teacher can update own"
  on public.lesson_sessions
  for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

-- Parents are intentionally read-only in the MVP (teacher-created scheduling).
-- No parent INSERT/UPDATE/DELETE policy is granted.

-- ---- DELETE ---------------------------------------------------------------
-- The teacher may delete a session they own (e.g. created by mistake).
drop policy if exists "ls: teacher can delete own" on public.lesson_sessions;
create policy "ls: teacher can delete own"
  on public.lesson_sessions
  for delete
  using (auth.uid() = teacher_id);
