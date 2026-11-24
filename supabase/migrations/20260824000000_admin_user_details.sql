-- =============================================================================
-- Camiva - Admin visibility over platform users
-- =============================================================================
--
-- Exposes platform users (Parents, Teachers, Students) and all their associated
-- details to platform administrators.
-- =============================================================================

-- 1. Allow admins to select all profiles
drop policy if exists "user_profiles: admin can select all" on public.user_profiles;
create policy "user_profiles: admin can select all"
  on public.user_profiles
  for select
  to authenticated
  using (public.is_platform_admin());

-- 2. Function: admin_users_list
create or replace function public.admin_users_list(
  p_query text default null,
  p_role  text default null
)
returns table (
  id                  uuid,
  email               text,
  name                text,
  phone               text,
  active_role         text,
  profile_complete    boolean,
  created_at          timestamptz,
  updated_at          timestamptz,
  verification_status text,
  children_count      integer,
  students_count      integer,
  subjects            text[],
  town                text,
  balance             integer,
  total_earnings      integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;

  return query
    select
      p.id,
      p.email,
      p.name,
      p.phone,
      p.active_role,
      p.profile_complete,
      p.created_at,
      p.updated_at,
      coalesce(tv.status, 'unverified') as verification_status,
      (
        case when p.active_role = 'parent' then
          (select count(*)::integer from public.students s where s.parent_id = p.id)
        else null end
      ) as children_count,
      (
        case when p.active_role = 'teacher' then
          (select count(distinct ptr.student_id)::integer
             from public.parent_teacher_relationships ptr
            where ptr.teacher_id = p.id)
        else null end
      ) as students_count,
      coalesce(tp.subjects, '{}') as subjects,
      coalesce(tp.town, null) as town,
      0 as balance,
      0 as total_earnings
    from public.user_profiles p
    left join public.teacher_profiles tp on tp.user_id = p.id
    left join public.teacher_verifications tv on tv.teacher_id = p.id
    where (p_role is null or p_role = '' or p.active_role = p_role)
      and (
        p_query is null or p_query = '' or
        p.name ilike '%' || p_query || '%' or
        p.email ilike '%' || p_query || '%' or
        coalesce(p.phone, '') ilike '%' || p_query || '%'
      )
    order by p.created_at desc;
end;
$$;

revoke execute on function public.admin_users_list(text, text) from public, anon;
grant execute on function public.admin_users_list(text, text) to authenticated;

-- 3. Function: admin_user_detail
create or replace function public.admin_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user record;
  v_teacher record;
  v_result jsonb;
  v_children jsonb := '[]'::jsonb;
  v_students jsonb := '[]'::jsonb;
  v_teacher_payout record;
  v_student record;
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;

  select * into v_user from public.user_profiles where id = p_user_id;
  if not found then
    return null;
  end if;

  v_result := jsonb_build_object(
    'id', v_user.id,
    'email', v_user.email,
    'name', v_user.name,
    'phone', v_user.phone,
    'active_role', v_user.active_role,
    'profile_complete', v_user.profile_complete,
    'created_at', v_user.created_at,
    'updated_at', v_user.updated_at
  );

  -- Teacher details
  if v_user.active_role = 'teacher' then
    select tp.*, tv.status as ver_status, tv.identity_doc_path, tv.qualification_doc_path, tv.qualification_title
      into v_teacher
      from public.teacher_profiles tp
      left join public.teacher_verifications tv on tv.teacher_id = tp.user_id
     where tp.user_id = p_user_id;

    select * into v_teacher_payout
      from public.teacher_payout_accounts
     where teacher_id = p_user_id;

    select jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'name', s.name,
               'level', s.level_code,
               'subsystem', s.education_subsystem,
               'subjects', coalesce(s.subjects, '{}')
             )
           ) into v_students
      from public.parent_teacher_relationships ptr
      join public.students s on s.id = ptr.student_id
     where ptr.teacher_id = p_user_id;

    v_result := v_result || jsonb_build_object(
      'teacher_profile', jsonb_build_object(
        'display_name', coalesce(v_teacher.display_name, v_user.name),
        'bio', v_teacher.bio,
        'subjects', coalesce(v_teacher.subjects, '{}'),
        'forms', coalesce(v_teacher.forms, '{}'),
        'hourly_rate', coalesce(v_teacher.hourly_rate, 0),
        'teaching_mode', v_teacher.teaching_mode,
        'town', v_teacher.town,
        'neighbourhood', v_teacher.neighbourhood,
        'verification_status', coalesce(v_teacher.ver_status, 'unverified'),
        'identity_doc_path', v_teacher.identity_doc_path,
        'qualification_doc_path', v_teacher.qualification_doc_path,
        'qualification_title', v_teacher.qualification_title,
        'payout_phone', v_teacher_payout.phone_number,
        'payout_medium', v_teacher_payout.provider,
        'total_earnings', 0,
        'available_balance', 0,
        'active_agreements_count', coalesce(jsonb_array_length(v_students), 0),
        'students', coalesce(v_students, '[]'::jsonb)
      )
    );
  end if;

  -- Parent details
  if v_user.active_role = 'parent' then
    select jsonb_agg(
             jsonb_build_object(
               'id', s.id,
               'name', s.name,
               'level', s.level_code,
               'subsystem', s.education_subsystem,
               'subjects', coalesce(s.subjects, '{}')
             )
           ) into v_children
      from public.students s
     where s.parent_id = p_user_id;

    v_result := v_result || jsonb_build_object(
      'parent_profile', jsonb_build_object(
        'children', coalesce(v_children, '[]'::jsonb),
        'active_teachers', '[]'::jsonb,
        'active_agreements_count', 0,
        'total_paid', 0,
        'outstanding_balance', 0
      )
    );
  end if;

  -- Student details
  if v_user.active_role = 'student' then
    select s.*, p.name as parent_name, p.phone as parent_phone
      into v_student
      from public.students s
      left join public.user_profiles p on p.id = s.parent_id
     where s.user_id = p_user_id;

    if found then
      v_result := v_result || jsonb_build_object(
        'student_profile', jsonb_build_object(
          'student_id', v_student.id,
          'parent_id', v_student.parent_id,
          'parent_name', v_student.parent_name,
          'parent_phone', v_student.parent_phone,
          'is_self_managed', (v_student.parent_id is null),
          'subsystem', v_student.education_subsystem,
          'level', v_student.level_code,
          'series', v_student.series_code,
          'subjects', coalesce(v_student.subjects, '{}'),
          'assigned_teachers', '[]'::jsonb,
          'total_sessions', 0
        )
      );
    end if;
  end if;

  return v_result;
end;
$$;

revoke execute on function public.admin_user_detail(uuid) from public, anon;
grant execute on function public.admin_user_detail(uuid) to authenticated;
