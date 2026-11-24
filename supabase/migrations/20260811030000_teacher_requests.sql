-- =============================================================================
-- Camiva — teacher_requests + acceptance → relationship
-- =============================================================================
--
-- A teacher request is a parent asking a teacher to teach one of their
-- children:  parent → student → teacher.  It is separate from
-- parent_teacher_relationships: the RELATIONSHIP is created only when the
-- teacher ACCEPTS a request (via the accept_teacher_request function below).
--
-- Statuses: pending | accepted | declined | cancelled
--
-- Security model:
--   Parent   : create own (pending), read own, cancel own pending.
--   Parent   : may NOT set accepted/declined, nor touch another parent's row.
--   Teacher  : read incoming, decline own pending. Accept is done through the
--              SECURITY DEFINER function (which also creates the relationship).
--   Teacher  : may NOT touch another teacher's row, nor set accepted directly.
--
-- A partial unique index prevents more than one ACTIVE (pending/accepted)
-- request for the same (parent, student, teacher); a declined/cancelled request
-- does not block a future request.
-- =============================================================================

create table if not exists public.teacher_requests (
  id          uuid        primary key default gen_random_uuid(),
  parent_id   uuid        not null references auth.users (id) on delete cascade,
  student_id  uuid        not null references public.students (id) on delete cascade,
  teacher_id  uuid        not null references auth.users (id) on delete cascade,
  status      text        not null default 'pending'
                constraint teacher_requests_status_check
                check (status in ('pending', 'accepted', 'declined', 'cancelled')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- At most one active request per (parent, student, teacher).
create unique index if not exists teacher_requests_active_unique
  on public.teacher_requests (parent_id, student_id, teacher_id)
  where status in ('pending', 'accepted');

create index if not exists teacher_requests_parent_idx
  on public.teacher_requests (parent_id);
create index if not exists teacher_requests_teacher_idx
  on public.teacher_requests (teacher_id);
create index if not exists teacher_requests_student_idx
  on public.teacher_requests (student_id);

drop trigger if exists teacher_requests_set_updated_at on public.teacher_requests;
create trigger teacher_requests_set_updated_at
  before update on public.teacher_requests
  for each row execute function public.set_updated_at();

alter table public.teacher_requests enable row level security;

-- ---- SELECT --------------------------------------------------------------
drop policy if exists "tr: parent can select own" on public.teacher_requests;
create policy "tr: parent can select own"
  on public.teacher_requests
  for select
  using (auth.uid() = parent_id);

drop policy if exists "tr: teacher can select incoming" on public.teacher_requests;
create policy "tr: teacher can select incoming"
  on public.teacher_requests
  for select
  using (auth.uid() = teacher_id);

-- ---- INSERT --------------------------------------------------------------
-- A parent may create a pending request only for a student they own.
drop policy if exists "tr: parent can insert for own student" on public.teacher_requests;
create policy "tr: parent can insert for own student"
  on public.teacher_requests
  for insert
  with check (
    auth.uid() = parent_id
    and status = 'pending'
    and exists (
      select 1 from public.students s
      where s.id = student_id and s.parent_id = auth.uid()
    )
  );

-- ---- UPDATE --------------------------------------------------------------
-- Parent may ONLY cancel their own pending request (pending -> cancelled).
drop policy if exists "tr: parent can cancel own pending" on public.teacher_requests;
create policy "tr: parent can cancel own pending"
  on public.teacher_requests
  for update
  using (auth.uid() = parent_id and status = 'pending')
  with check (auth.uid() = parent_id and status = 'cancelled');

-- Teacher may ONLY decline their own pending request (pending -> declined).
-- Acceptance is handled by accept_teacher_request(), never by a direct update.
drop policy if exists "tr: teacher can decline incoming pending" on public.teacher_requests;
create policy "tr: teacher can decline incoming pending"
  on public.teacher_requests
  for update
  using (auth.uid() = teacher_id and status = 'pending')
  with check (auth.uid() = teacher_id and status = 'declined');


-- -----------------------------------------------------------------------------
-- Teacher-side visibility of connected / requesting students
-- -----------------------------------------------------------------------------
-- These are ADDITIVE (permissive OR) policies — they do not weaken the existing
-- parent-only student policies. A teacher may read a student only when there is
-- a pending request to them or an accepted relationship with them.
drop policy if exists "students: teacher can read via pending request" on public.students;
create policy "students: teacher can read via pending request"
  on public.students
  for select
  using (
    exists (
      select 1 from public.teacher_requests tr
      where tr.student_id = students.id
        and tr.teacher_id = auth.uid()
        and tr.status = 'pending'
    )
  );

drop policy if exists "students: teacher can read via accepted relationship" on public.students;
create policy "students: teacher can read via accepted relationship"
  on public.students
  for select
  using (
    exists (
      select 1 from public.parent_teacher_relationships r
      where r.student_id = students.id
        and r.teacher_id = auth.uid()
        and r.status = 'accepted'
    )
  );


-- -----------------------------------------------------------------------------
-- Prevent duplicate accepted relationships for the same triple.
-- -----------------------------------------------------------------------------
create unique index if not exists ptr_accepted_unique
  on public.parent_teacher_relationships (parent_id, student_id, teacher_id)
  where status = 'accepted';


-- -----------------------------------------------------------------------------
-- accept_teacher_request(): atomic, validated acceptance.
-- -----------------------------------------------------------------------------
-- Runs as owner (SECURITY DEFINER) so it can create the relationship, but
-- validates internally that the caller is the request's teacher, the request is
-- pending, and the student belongs to the requesting parent. Idempotent on the
-- relationship (won't create a duplicate).
create or replace function public.accept_teacher_request(p_request_id uuid)
returns public.parent_teacher_relationships
language plpgsql
security definer
set search_path = public
as $$
declare
  req public.teacher_requests;
  stu public.students;
  rel public.parent_teacher_relationships;
  v_subject text;
  v_level text;
begin
  select * into req from public.teacher_requests where id = p_request_id;
  if not found then
    raise exception 'Request not found';
  end if;
  if req.teacher_id <> auth.uid() then
    raise exception 'Not authorised to accept this request';
  end if;
  if req.status <> 'pending' then
    raise exception 'Request is not pending';
  end if;

  select * into stu from public.students where id = req.student_id;
  if not found then
    raise exception 'Student not found';
  end if;
  if stu.parent_id <> req.parent_id then
    raise exception 'Student does not belong to the requesting parent';
  end if;

  v_level := coalesce(nullif(stu.school_level, ''), 'Not set');
  v_subject := coalesce(nullif(array_to_string(stu.subjects, ', '), ''), 'General');

  -- Reuse an existing accepted relationship if present; otherwise create one.
  select * into rel from public.parent_teacher_relationships
    where parent_id = req.parent_id
      and student_id = req.student_id
      and teacher_id = req.teacher_id
      and status = 'accepted'
    limit 1;

  if not found then
    insert into public.parent_teacher_relationships
      (parent_id, student_id, teacher_id, subject, level, status)
    values
      (req.parent_id, req.student_id, req.teacher_id, v_subject, v_level, 'accepted')
    returning * into rel;
  end if;

  update public.teacher_requests set status = 'accepted' where id = p_request_id;

  return rel;
end;
$$;

grant execute on function public.accept_teacher_request(uuid) to authenticated;
