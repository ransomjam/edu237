-- =============================================================================
-- Camiva — linking a student account to an existing parent-managed child
-- =============================================================================
--
-- The problem this solves: a parent adds "Grace / Form 4", and later Grace
-- registers her own account. Without a link step Grace would exist twice —
-- once as her parent's child, once as her own learner record — and her
-- teachers, lessons and history would be split between them.
--
-- The mechanism is deliberately the simplest thing that is safe:
--
--   1. The parent asks for a one-time code on their child's record.
--   2. The child enters that code when signing up.
--   3. The code is consumed and the child's account attaches to the EXISTING
--      row. No second record is ever created.
--
-- A student cannot see a row they do not own, so step 3 cannot be an ordinary
-- UPDATE under RLS. It runs in a SECURITY DEFINER function that re-checks
-- everything itself and touches exactly one row.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. The code column
-- -----------------------------------------------------------------------------

alter table public.students
  add column if not exists link_code text;

-- Codes must be unique while outstanding; they are set to NULL once used, and
-- a partial index keeps those NULLs out of the constraint.
create unique index if not exists students_link_code_key
  on public.students (link_code)
  where link_code is not null;


-- -----------------------------------------------------------------------------
-- 2. Claiming a code
-- -----------------------------------------------------------------------------
-- SECURITY DEFINER because the caller has no read access to the target row
-- yet. Every rule is therefore enforced inside the function:
--
--   * the caller must be authenticated;
--   * the caller must not already be linked to a learner record
--     (one account, one learner — the same rule as students_user_id_key);
--   * the code must exist and belong to a row with no account yet;
--   * the code is cleared in the same statement, so it cannot be replayed.
--
-- `search_path` is pinned so the function cannot be redirected at call time.

create or replace function public.link_student_account(p_code text)
returns public.students
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row public.students;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated.';
  end if;

  if exists (select 1 from public.students s where s.user_id = v_uid) then
    raise exception 'This account is already linked to a student.';
  end if;

  update public.students s
     set user_id   = v_uid,
         link_code = null
   where s.link_code = upper(trim(p_code))
     and s.user_id is null
  returning * into v_row;

  if v_row.id is null then
    raise exception 'Invalid or already used code.';
  end if;

  return v_row;
end;
$$;

revoke all on function public.link_student_account(text) from public;
grant execute on function public.link_student_account(text) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Notes on issuing a code
-- -----------------------------------------------------------------------------
-- Issuing is an ordinary UPDATE by the parent and needs no new privilege: the
-- existing "students: parent can update own" policy already covers it, and the
-- app only offers it for a child with no account yet.
--
-- The student-side update policy added in the previous migration requires
-- `user_id = auth.uid()` both before and after, so a student can never issue,
-- clear or steal a code on someone else's record.
--
-- Verification:
--   select id, name, link_code, user_id from public.students
--    where link_code is not null;      -- outstanding invitations
--   select user_id, count(*) from public.students
--    where user_id is not null group by user_id having count(*) > 1;  -- empty
