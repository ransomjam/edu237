-- =============================================================================
-- Camiva — teacher_requests child identity snapshot (additive)
-- =============================================================================
--
-- A teacher can always read requests addressed to them, but the parent's
-- identity and (for non-active requests) the child's live row are not readable
-- under RLS. To give the teacher enough SAFE context to identify the child for
-- ANY request — without weakening RLS — we snapshot the child's name, Form and
-- subjects onto the request row at insert time.
--
-- The snapshot is populated SERVER-SIDE by a trigger from the referenced
-- students row, so a client cannot forge it. The parent's INSERT policy already
-- guarantees they own that student, so the snapshot is always the parent's own
-- child. This is request context, NOT relationship data — the relationship
-- table is unchanged, and post-acceptance screens still read the live student.
--
-- Additive & non-destructive: existing rows are backfilled.
-- =============================================================================

alter table public.teacher_requests
  add column if not exists student_name text;
alter table public.teacher_requests
  add column if not exists student_form text;
alter table public.teacher_requests
  add column if not exists student_subjects text[] not null default '{}';

-- Populate the snapshot from the referenced student on insert. SECURITY DEFINER
-- so it can read the student regardless of the caller's RLS (the caller's
-- INSERT policy already restricts them to their own student).
create or replace function public.set_teacher_request_student_snapshot()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  s public.students;
begin
  select * into s from public.students where id = new.student_id;
  if found then
    new.student_name := s.name;
    new.student_form := s.school_level;
    new.student_subjects := coalesce(s.subjects, '{}');
  end if;
  return new;
end;
$$;

drop trigger if exists teacher_requests_student_snapshot on public.teacher_requests;
create trigger teacher_requests_student_snapshot
  before insert on public.teacher_requests
  for each row execute function public.set_teacher_request_student_snapshot();

-- Backfill existing requests.
update public.teacher_requests tr
set student_name = s.name,
    student_form = s.school_level,
    student_subjects = coalesce(s.subjects, '{}')
from public.students s
where s.id = tr.student_id
  and (tr.student_name is null or tr.student_name = '');
