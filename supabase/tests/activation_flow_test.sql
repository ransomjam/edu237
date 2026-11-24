-- =============================================================================
-- Camiva - activation flow rules, at the database level
-- =============================================================================
--
--   psql "$DATABASE_URL" -f supabase/tests/activation_flow_test.sql
--
-- Everything runs inside a transaction that is rolled back, so it leaves no
-- data behind. Each check raises on failure, so the script either completes
-- silently or stops at the first broken rule.
--
-- These cover what widget tests cannot: the server-side gates that hold even
-- when the request bypasses the app entirely.
-- =============================================================================

begin;

-- ---- fixtures ---------------------------------------------------------------
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'parent@test.local'),
  ('22222222-2222-2222-2222-222222222222', 'teacher@test.local'),
  ('33333333-3333-3333-3333-333333333333', 'other@test.local')
on conflict (id) do nothing;

insert into public.user_profiles (id, email, name, active_role, profile_complete)
values
  ('11111111-1111-1111-1111-111111111111', 'parent@test.local', 'Parent', 'parent', true),
  ('22222222-2222-2222-2222-222222222222', 'teacher@test.local', 'Teacher', 'teacher', true),
  ('33333333-3333-3333-3333-333333333333', 'other@test.local', 'Other', 'teacher', true)
on conflict (id) do nothing;

insert into public.students (id, parent_id, name, school_level)
values ('44444444-4444-4444-4444-444444444444',
        '11111111-1111-1111-1111-111111111111', 'Daniel', 'Form 4')
on conflict (id) do nothing;

insert into public.parent_teacher_relationships
  (id, parent_id, student_id, teacher_id, subject, level, status)
values ('55555555-5555-5555-5555-555555555555',
        '11111111-1111-1111-1111-111111111111',
        '44444444-4444-4444-4444-444444444444',
        '22222222-2222-2222-2222-222222222222',
        'Mathematics', 'Form 4', 'accepted')
on conflict (id) do nothing;

-- A Platform Charge applies, so the gate is live.
update public.platform_fee_config
   set match_activation_fee_amount = 1000,
       match_activation_required = true
 where id = 1;

-- Act as the teacher.
set local role authenticated;
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';


-- ---- 1. an unverified teacher cannot propose -------------------------------
do $$
begin
  begin
    perform public.propose_tutoring_agreement(
      '55555555-5555-5555-5555-555555555555', 'Mathematics',
      current_date + 1, 'twice_weekly', 2::smallint, 60::smallint,
      5000, 'per_lesson', 'in_person', 'Bastos', 'edu237', 'per_month');
    raise exception 'FAIL: an unverified teacher was allowed to propose';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;


-- ---- 2. a teacher cannot make themselves verified ---------------------------
do $$
declare v_status text;
begin
  perform public.submit_teacher_verification('p/id.jpg', 'national_id', 'p/c.jpg', null);
  select status into v_status from public.teacher_verifications
   where teacher_id = '22222222-2222-2222-2222-222222222222';
  if v_status <> 'pending' then
    raise exception 'FAIL: submitting produced % instead of pending', v_status;
  end if;

  begin
    perform public.admin_review_verification(
      '22222222-2222-2222-2222-222222222222', true, null);
    raise exception 'FAIL: a non-admin approved a verification';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

-- Approve as the service role, standing in for an Camiva admin.
reset role;
update public.teacher_verifications
   set status = 'verified', reviewed_at = now()
 where teacher_id = '22222222-2222-2222-2222-222222222222';

set local role authenticated;
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';


-- ---- 3. the Platform Charge is blocked before the parent confirms -----------
do $$
declare v_agreement uuid; v_state text;
begin
  select (public.propose_tutoring_agreement(
      '55555555-5555-5555-5555-555555555555', 'Mathematics',
      current_date + 1, 'twice_weekly', 2::smallint, 60::smallint,
      5000, 'per_lesson', 'in_person', 'Bastos', 'edu237', 'per_month')).id
    into v_agreement;

  v_state := public.relationship_activation_state('55555555-5555-5555-5555-555555555555');
  if v_state <> 'blocked' then
    raise exception 'FAIL: state is % before confirmation, expected blocked', v_state;
  end if;

  -- The rule the whole flow exists to protect.
  begin
    perform public.create_payment_intent(
      'match_activation', '55555555-5555-5555-5555-555555555555', 1, null, null);
    raise exception 'FAIL: a Platform Charge was created before parent confirmation';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;

  if exists (select 1 from public.payment_transactions
              where relationship_id = '55555555-5555-5555-5555-555555555555'
                and purpose = 'match_activation') then
    raise exception 'FAIL: a charge row exists before parent confirmation';
  end if;
end $$;


-- ---- 4. an unrelated teacher cannot touch the agreement ---------------------
set local request.jwt.claims =
  '{"sub":"33333333-3333-3333-3333-333333333333","role":"authenticated"}';

do $$
declare v_count integer;
begin
  select count(*) into v_count from public.tutoring_agreements;
  if v_count <> 0 then
    raise exception 'FAIL: an unrelated teacher can read % agreements', v_count;
  end if;
end $$;


-- ---- 5. only the parent can confirm ----------------------------------------
do $$
declare v_agreement uuid;
begin
  reset role;
  select id into v_agreement from public.tutoring_agreements limit 1;
  set local role authenticated;

  begin
    perform public.confirm_tutoring_agreement(v_agreement);
    raise exception 'FAIL: a stranger confirmed the arrangement';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;


-- ---- 6. after confirmation the charge becomes payable ----------------------
set local request.jwt.claims =
  '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

do $$
declare v_agreement uuid; v_state text;
begin
  reset role;
  select id into v_agreement from public.tutoring_agreements limit 1;
  set local role authenticated;

  perform public.confirm_tutoring_agreement(v_agreement);

  v_state := public.relationship_activation_state('55555555-5555-5555-5555-555555555555');
  if v_state <> 'required' then
    raise exception 'FAIL: state is % after confirmation, expected required', v_state;
  end if;
end $$;


-- ---- 7. contact stays hidden until the charge succeeds ----------------------
set local request.jwt.claims =
  '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

do $$
declare v_revealed boolean; v_payment uuid; v_trans text := 'TEST-TRANS-1';
begin
  select revealed into v_revealed
    from public.relationship_contact('55555555-5555-5555-5555-555555555555');
  if v_revealed then
    raise exception 'FAIL: contact revealed before the Platform Charge succeeded';
  end if;

  -- Create and pay the charge the way the app does.
  select (public.create_payment_intent(
      'match_activation', '55555555-5555-5555-5555-555555555555',
      1, null, null)).id into v_payment;

  reset role;
  perform public.attach_payment_provider_ref(v_payment, v_trans, null);

  -- A failed charge changes nothing.
  perform public.apply_payment_provider_status(v_trans, 'FAILED', '{}'::jsonb, 'webhook');
  if public.relationship_activation_state('55555555-5555-5555-5555-555555555555')
     = 'active' then
    raise exception 'FAIL: a failed charge activated the relationship';
  end if;
end $$;


-- ---- 8. a successful charge activates, and only once ------------------------
do $$
declare v_payment uuid; v_trans text := 'TEST-TRANS-2'; v_count integer;
declare v_revealed boolean;
begin
  set local role authenticated;
  set local request.jwt.claims =
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  select (public.create_payment_intent(
      'match_activation', '55555555-5555-5555-5555-555555555555',
      1, null, null)).id into v_payment;

  reset role;
  perform public.attach_payment_provider_ref(v_payment, v_trans, null);
  perform public.apply_payment_provider_status(v_trans, 'SUCCESSFUL', '{}'::jsonb, 'webhook');

  if public.relationship_activation_state('55555555-5555-5555-5555-555555555555')
     <> 'active' then
    raise exception 'FAIL: a successful charge did not activate the relationship';
  end if;

  -- The same webhook again must change nothing.
  perform public.apply_payment_provider_status(v_trans, 'SUCCESSFUL', '{}'::jsonb, 'webhook');

  select count(*) into v_count from public.tutoring_agreements
   where relationship_id = '55555555-5555-5555-5555-555555555555'
     and status = 'active';
  if v_count <> 1 then
    raise exception 'FAIL: duplicate webhook produced % active agreements', v_count;
  end if;

  select count(*) into v_count from public.payment_transactions
   where relationship_id = '55555555-5555-5555-5555-555555555555'
     and purpose = 'match_activation' and status = 'successful';
  if v_count <> 1 then
    raise exception 'FAIL: duplicate webhook produced % successful charges', v_count;
  end if;

  -- Contact is available now, and only now.
  set local role authenticated;
  set local request.jwt.claims =
    '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
  select revealed into v_revealed
    from public.relationship_contact('55555555-5555-5555-5555-555555555555');
  if not v_revealed then
    raise exception 'FAIL: contact still hidden after a successful charge';
  end if;
end $$;


-- ---- 9. the agreed terms cannot be edited -----------------------------------
do $$
begin
  reset role;
  begin
    update public.tutoring_agreements set price = 1 where true;
    raise exception 'FAIL: the agreed price was changed';
  exception when others then
    if sqlerrm like 'FAIL:%' then raise; end if;
  end;
end $$;

rollback;
