-- =============================================================================
-- Camiva — Fix infinite recursion in RLS policies for learning activities
-- =============================================================================
--
-- Cross-table RLS recursion happens when learning_activities for select checks
-- learning_activity_recipients, while learning_activity_recipients for select
-- checks learning_activities.
--
-- Using security definer functions breaks the recursion by executing the
-- existence check with function owner privileges, bypassing user-level RLS.
-- =============================================================================

-- 1. Helper security definer functions to break cross-table RLS recursion

create or replace function public.is_teacher_of_activity(p_activity_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.learning_activities
    where id = p_activity_id
      and teacher_id = p_user_id
  );
$$;

create or replace function public.is_parent_of_activity(p_activity_id uuid, p_parent_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.learning_activity_recipients lar
    join public.students s on s.id = lar.student_id
    where lar.activity_id = p_activity_id
      and s.parent_id = p_parent_id
  );
$$;

create or replace function public.is_parent_of_student(p_student_id uuid, p_parent_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.students
    where id = p_student_id
      and parent_id = p_parent_id
  );
$$;

-- 2. Update policies on public.learning_activities
drop policy if exists "learning_activities: parent read child activities" on public.learning_activities;
create policy "learning_activities: parent read child activities"
  on public.learning_activities
  for select
  using (public.is_parent_of_activity(id, auth.uid()));

-- 3. Update policies on public.learning_activity_recipients
drop policy if exists "learning_activity_recipients: teacher select own" on public.learning_activity_recipients;
create policy "learning_activity_recipients: teacher select own"
  on public.learning_activity_recipients
  for select
  using (public.is_teacher_of_activity(activity_id, auth.uid()));

drop policy if exists "learning_activity_recipients: parent read child" on public.learning_activity_recipients;
create policy "learning_activity_recipients: parent read child"
  on public.learning_activity_recipients
  for select
  using (public.is_parent_of_student(student_id, auth.uid()));

drop policy if exists "learning_activity_recipients: teacher update own" on public.learning_activity_recipients;
create policy "learning_activity_recipients: teacher update own"
  on public.learning_activity_recipients
  for update
  using (public.is_teacher_of_activity(activity_id, auth.uid()));

drop policy if exists "learning_activity_recipients: teacher delete own" on public.learning_activity_recipients;
create policy "learning_activity_recipients: teacher delete own"
  on public.learning_activity_recipients
  for delete
  using (public.is_teacher_of_activity(activity_id, auth.uid()));
