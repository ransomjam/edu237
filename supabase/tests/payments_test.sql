-- =============================================================================
-- Camiva — database tests for the commercial layer
-- =============================================================================
--
-- These cover the rules that CANNOT be tested from Dart, because they live in
-- the database: row-level security, function grants, webhook idempotency and
-- the ledger's transition rules.
--
-- Run against a database that has all migrations applied:
--
--     psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/payments_test.sql
--
-- Everything happens inside one transaction that is ROLLED BACK at the end, so
-- the script leaves no data behind. Any failed assertion aborts with an
-- exception naming the rule that broke.
--
-- NOTE: run this against a local or staging database. Do not point it at a
-- database holding real payments.
-- =============================================================================

begin;

-- Ensure a clean, known pricing configuration for the run.
update public.platform_fee_config
   set teacher_service_fee_amount = 1000,
       match_activation_fee_amount = 1000,
       match_activation_required = true,
       settlement_delay_hours = 0,
       currency = 'XAF'
 where id = 1;

-- ---------------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------------
do $$
declare
  v_parent   uuid := '11111111-1111-1111-1111-111111111111';
  v_parent2  uuid := '11111111-1111-1111-1111-111111111112';
  v_teacher  uuid := '22222222-2222-2222-2222-222222222221';
  v_teacher2 uuid := '22222222-2222-2222-2222-222222222222';
begin
  insert into auth.users (id, email, instance_id, aud, role)
  values
    (v_parent,   'parent1@test.local',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
    (v_parent2,  'parent2@test.local',  '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
    (v_teacher,  'teacher1@test.local', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
    (v_teacher2, 'teacher2@test.local', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
  on conflict (id) do nothing;

  insert into public.user_profiles (id, email, name, active_role, profile_complete, phone)
  values
    (v_parent,   'parent1@test.local',  'Marie Ngu',  'parent',  true, '670111111'),
    (v_parent2,  'parent2@test.local',  'Other Parent', 'parent', true, '670222222'),
    (v_teacher,  'teacher1@test.local', 'Jam Ransom', 'teacher', true, '670333333'),
    (v_teacher2, 'teacher2@test.local', 'Other Teacher', 'teacher', true, '670444444')
  on conflict (id) do nothing;

  insert into public.teacher_profiles (user_id, display_name, subjects, forms, hourly_rate)
  values (v_teacher, 'Jam Ransom', array['Mathematics'], array['Form 4'], 5000)
  on conflict (user_id) do nothing;

  insert into public.students (id, parent_id, name, school_level, subjects)
  values ('33333333-3333-3333-3333-333333333331', v_parent, 'Daniel', 'Form 4',
          array['Mathematics'])
  on conflict (id) do nothing;

  insert into public.parent_teacher_relationships
    (id, parent_id, student_id, teacher_id, subject, level, status)
  values ('44444444-4444-4444-4444-444444444441', v_parent,
          '33333333-3333-3333-3333-333333333331', v_teacher,
          'Mathematics', 'Form 4', 'accepted')
  on conflict (id) do nothing;
end $$;

-- Helper: act as a given user for the statements that follow.
create or replace function pg_temp.act_as(p_user uuid)
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

create or replace function pg_temp.act_as_service()
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', null, true);
  perform set_config('role', 'service_role', true);
end;
$$;

create or replace function pg_temp.check(p_condition boolean, p_rule text)
returns void language plpgsql as $$
begin
  if not p_condition then
    raise exception 'FAILED: %', p_rule;
  end if;
  raise notice 'ok: %', p_rule;
end;
$$;


-- ---------------------------------------------------------------------------
-- 1. A client cannot write financial state
-- ---------------------------------------------------------------------------
do $$
declare
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_denied boolean;
begin
  perform pg_temp.act_as(v_teacher);

  -- Direct insert into the ledger: no insert policy exists.
  v_denied := false;
  begin
    insert into public.payment_transactions (purpose, payer_id, amount)
    values ('tutoring_payment', v_teacher, 1000000);
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'client cannot insert a payment transaction directly');

  -- Recording a provider outcome: execute is revoked from authenticated.
  v_denied := false;
  begin
    perform public.apply_payment_provider_status('forged', 'SUCCESSFUL');
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'client cannot forge a successful payment');

  -- Marking a payout settled.
  v_denied := false;
  begin
    perform public.apply_payout_provider_status('forged', 'SUCCESSFUL');
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied, 'client cannot forge a successful payout');

  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 2. The amount comes from configuration, not the caller
-- ---------------------------------------------------------------------------
do $$
declare
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_parent  uuid := '11111111-1111-1111-1111-111111111111';
  v_rel     uuid := '44444444-4444-4444-4444-444444444441';
  v_row     public.payment_transactions;
  v_amount  integer;
  v_refused boolean;
begin
  perform pg_temp.act_as(v_teacher);
  select amount into v_amount
    from public.payment_quote('match_activation', v_rel, 1);
  perform pg_temp.check(v_amount = 1000,
    'activation is quoted at the configured fee');

  v_row := public.create_payment_intent('match_activation', v_rel, 1);
  perform pg_temp.check(v_row.amount = 1000 and v_row.status = 'pending',
    'activation intent is created pending at the configured fee');
  perform pg_temp.check(v_row.relationship_id = v_rel and v_row.payer_id = v_teacher,
    'activation intent carries the right relationship and payer');

  reset role;

  -- A parent cannot pay for tutoring while the relationship is not activated.
  perform pg_temp.act_as(v_parent);
  v_refused := false;
  begin
    perform amount from public.payment_quote('tutoring_payment', v_rel, 1);
  exception when others then
    v_refused := true;
  end;
  perform pg_temp.check(v_refused,
    'tutoring payment is refused while the relationship is not activated');
  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 3. Contact details are gated on activation
-- ---------------------------------------------------------------------------
do $$
declare
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_rel     uuid := '44444444-4444-4444-4444-444444444441';
  v_revealed boolean;
  v_phone   text;
begin
  perform pg_temp.act_as(v_teacher);

  perform pg_temp.check(
    public.relationship_activation_state(v_rel) = 'pending',
    'an in-flight activation payment leaves the relationship pending');

  select revealed, phone into v_revealed, v_phone
    from public.relationship_contact(v_rel);
  perform pg_temp.check(v_revealed = false and v_phone is null,
    'parent contact is not revealed before activation is confirmed');

  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 4. Webhook application: idempotent, and only the provider can move state
-- ---------------------------------------------------------------------------
do $$
declare
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_rel     uuid := '44444444-4444-4444-4444-444444444441';
  v_payment public.payment_transactions;
  v_reminders integer;
  v_events integer;
begin
  perform pg_temp.act_as_service();

  select * into v_payment from public.payment_transactions
   where relationship_id = v_rel and purpose = 'match_activation';

  perform public.attach_payment_provider_ref(v_payment.id, 'TRANS-ACT-1', null);

  -- A PENDING notification must not settle anything.
  v_payment := public.apply_payment_provider_status(
    'TRANS-ACT-1', 'PENDING', '{}'::jsonb, 'webhook');
  perform pg_temp.check(v_payment.status = 'pending',
    'a PENDING webhook leaves the payment pending');

  -- The successful webhook settles it once.
  v_payment := public.apply_payment_provider_status(
    'TRANS-ACT-1', 'SUCCESSFUL',
    '{"financialTransId":"FIN-1","medium":"mobile money"}'::jsonb, 'webhook');
  perform pg_temp.check(v_payment.status = 'successful'
                        and v_payment.paid_at is not null,
    'a SUCCESSFUL webhook settles the payment');
  perform pg_temp.check(
    v_payment.provider_financial_trans_id = 'FIN-1',
    'the provider financial reference is recorded');

  -- Redelivery changes nothing and creates no second effect.
  v_payment := public.apply_payment_provider_status(
    'TRANS-ACT-1', 'SUCCESSFUL', '{}'::jsonb, 'webhook');
  perform pg_temp.check(v_payment.status = 'successful',
    'a redelivered webhook is a no-op');

  select count(*) into v_events from public.payment_events
   where provider_trans_id = 'TRANS-ACT-1' and provider_status = 'SUCCESSFUL';
  perform pg_temp.check(v_events = 1,
    'a redelivered webhook does not duplicate the event');

  select count(*) into v_reminders from public.payment_reminders
   where payment_id = v_payment.id;
  perform pg_temp.check(v_reminders = 1,
    'a redelivered webhook does not duplicate the activation effect');

  -- A later FAILED notification cannot undo a settled payment.
  v_payment := public.apply_payment_provider_status(
    'TRANS-ACT-1', 'FAILED', '{}'::jsonb, 'webhook');
  perform pg_temp.check(v_payment.status = 'successful',
    'a settled payment cannot be moved back by a later webhook');

  -- An unknown provider status is rejected rather than guessed at.
  begin
    perform public.apply_payment_provider_status('TRANS-ACT-1', 'WHATEVER');
    perform pg_temp.check(false, 'an unknown provider status is rejected');
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    perform pg_temp.check(true, 'an unknown provider status is rejected');
  end;

  -- A webhook for a transaction we never created is rejected.
  begin
    perform public.apply_payment_provider_status('NOT-OURS', 'SUCCESSFUL');
    perform pg_temp.check(false, 'a webhook for an unknown transaction is rejected');
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    perform pg_temp.check(true, 'a webhook for an unknown transaction is rejected');
  end;

  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 5. Activation now reveals the contact, and the relationship is operational
-- ---------------------------------------------------------------------------
do $$
declare
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_rel     uuid := '44444444-4444-4444-4444-444444444441';
  v_revealed boolean;
  v_phone   text;
begin
  perform pg_temp.act_as(v_teacher);

  perform pg_temp.check(public.relationship_activation_state(v_rel) = 'active',
    'a confirmed activation payment activates the relationship');
  perform pg_temp.check(public.relationship_is_operational(v_rel),
    'an activated, accepted relationship is operational');

  select revealed, phone into v_revealed, v_phone
    from public.relationship_contact(v_rel);
  perform pg_temp.check(v_revealed and v_phone = '670111111',
    'parent contact is revealed only after confirmed activation');

  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 6. A second activation charge for the same relationship is impossible
-- ---------------------------------------------------------------------------
do $$
declare
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_rel     uuid := '44444444-4444-4444-4444-444444444441';
begin
  perform pg_temp.act_as(v_teacher);
  begin
    perform public.create_payment_intent('match_activation', v_rel, 1);
    perform pg_temp.check(false,
      'an already-activated relationship cannot be charged again');
  exception when others then
    if sqlerrm like 'FAILED:%' then raise; end if;
    perform pg_temp.check(true,
      'an already-activated relationship cannot be charged again');
  end;
  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 7. Tutoring payment, earnings and the isolation between users
-- ---------------------------------------------------------------------------
do $$
declare
  v_parent   uuid := '11111111-1111-1111-1111-111111111111';
  v_parent2  uuid := '11111111-1111-1111-1111-111111111112';
  v_teacher  uuid := '22222222-2222-2222-2222-222222222221';
  v_teacher2 uuid := '22222222-2222-2222-2222-222222222222';
  v_rel      uuid := '44444444-4444-4444-4444-444444444441';
  v_payment  public.payment_transactions;
  v_available integer;
  v_visible  integer;
begin
  -- The parent pays for one session at the teacher's rate.
  perform pg_temp.act_as(v_parent);
  v_payment := public.create_payment_intent('tutoring_payment', v_rel, 1);
  perform pg_temp.check(v_payment.amount = 5000,
    'a tutoring payment is priced from the teacher rate');
  reset role;

  -- Only a confirmed provider status turns it into earnings.
  perform pg_temp.act_as(v_teacher);
  select available into v_available from public.teacher_earnings_summary();
  perform pg_temp.check(coalesce(v_available, 0) = 0,
    'a pending payment is not yet earnings');
  reset role;

  perform pg_temp.act_as_service();
  perform public.attach_payment_provider_ref(v_payment.id, 'TRANS-TUT-1', null);
  perform public.apply_payment_provider_status(
    'TRANS-TUT-1', 'SUCCESSFUL', '{}'::jsonb, 'webhook');
  -- Redelivery must not double-count.
  perform public.apply_payment_provider_status(
    'TRANS-TUT-1', 'SUCCESSFUL', '{}'::jsonb, 'webhook');
  reset role;

  perform pg_temp.act_as(v_teacher);
  select available into v_available from public.teacher_earnings_summary();
  perform pg_temp.check(v_available = 5000,
    'a confirmed tutoring payment becomes earnings exactly once');
  reset role;

  -- Another teacher sees none of it.
  perform pg_temp.act_as(v_teacher2);
  select available into v_available from public.teacher_earnings_summary();
  perform pg_temp.check(coalesce(v_available, 0) = 0,
    'a teacher cannot see another teacher''s earnings');
  select count(*) into v_visible from public.payment_transactions;
  perform pg_temp.check(v_visible = 0,
    'a teacher cannot read another teacher''s transactions');
  reset role;

  -- Another parent sees none of it either.
  perform pg_temp.act_as(v_parent2);
  select count(*) into v_visible from public.payment_transactions;
  perform pg_temp.check(v_visible = 0,
    'a parent cannot see another parent''s payments');
  reset role;

  -- The paying parent sees their own.
  perform pg_temp.act_as(v_parent);
  select count(*) into v_visible from public.payment_transactions;
  perform pg_temp.check(v_visible = 2,
    'a parent sees the payments they are party to');
  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 8. A failed tutoring payment produces no earnings
-- ---------------------------------------------------------------------------
do $$
declare
  v_parent  uuid := '11111111-1111-1111-1111-111111111111';
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_rel     uuid := '44444444-4444-4444-4444-444444444441';
  v_payment public.payment_transactions;
  v_available integer;
begin
  perform pg_temp.act_as(v_parent);
  v_payment := public.create_payment_intent('tutoring_payment', v_rel, 1);
  reset role;

  perform pg_temp.act_as_service();
  perform public.attach_payment_provider_ref(v_payment.id, 'TRANS-TUT-2', null);
  perform public.apply_payment_provider_status(
    'TRANS-TUT-2', 'FAILED', '{"reason":"insufficient funds"}'::jsonb, 'webhook');
  reset role;

  perform pg_temp.act_as(v_teacher);
  select available into v_available from public.teacher_earnings_summary();
  perform pg_temp.check(v_available = 5000,
    'a failed payment adds nothing to earnings');
  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 9. Ledger immutability and legal transitions
-- ---------------------------------------------------------------------------
do $$
declare
  v_id uuid;
  v_denied boolean;
begin
  perform pg_temp.act_as_service();
  select id into v_id from public.payment_transactions
   where provider_trans_id = 'TRANS-TUT-1';

  v_denied := false;
  begin
    update public.payment_transactions set amount = 1 where id = v_id;
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied, 'the amount of a transaction is immutable');

  v_denied := false;
  begin
    update public.payment_transactions set payer_id = gen_random_uuid()
     where id = v_id;
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied, 'the payer of a transaction is immutable');

  v_denied := false;
  begin
    update public.payment_transactions set status = 'pending' where id = v_id;
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'a settled payment cannot be returned to pending');

  v_denied := false;
  begin
    update public.payment_transactions set provider_trans_id = 'REWRITTEN'
     where id = v_id;
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'a provider reference cannot be rewritten');

  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 10. Withdrawals
-- ---------------------------------------------------------------------------
do $$
declare
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_teacher2 uuid := '22222222-2222-2222-2222-222222222222';
  v_row     public.withdrawals;
  v_denied  boolean;
  v_available integer;
  v_visible integer;
begin
  perform pg_temp.act_as(v_teacher);

  -- No payout destination yet.
  v_denied := false;
  begin
    perform public.request_withdrawal(1000);
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'a withdrawal needs a payout destination first');

  insert into public.teacher_payout_accounts (teacher_id, medium, phone)
  values (v_teacher, 'mobile money', '670333333')
  on conflict (teacher_id) do update set phone = excluded.phone;

  -- More than the available amount is refused.
  v_denied := false;
  begin
    perform public.request_withdrawal(999999);
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'a teacher cannot withdraw more than their available earnings');

  v_row := public.request_withdrawal(5000);
  perform pg_temp.check(v_row.status = 'requested',
    'a withdrawal starts as requested, never successful');
  perform pg_temp.check(v_row.payout_phone = '670333333',
    'the payout goes to the stored destination');

  -- Reserved immediately, so it cannot be withdrawn twice.
  select available into v_available from public.teacher_earnings_summary();
  perform pg_temp.check(v_available = 0,
    'an in-flight withdrawal reserves the money');

  v_denied := false;
  begin
    perform public.request_withdrawal(1000);
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'a second in-flight withdrawal is refused');

  reset role;

  -- Another teacher cannot see it, nor point it at their own number.
  perform pg_temp.act_as(v_teacher2);
  select count(*) into v_visible from public.withdrawals;
  perform pg_temp.check(v_visible = 0,
    'a teacher cannot see another teacher''s withdrawals');

  v_denied := false;
  begin
    update public.teacher_payout_accounts set phone = '670999999'
     where teacher_id = v_teacher;
    if not found then v_denied := true; end if;
  exception when others then
    v_denied := true;
  end;
  perform pg_temp.check(v_denied,
    'a teacher cannot change another teacher''s payout destination');
  reset role;

  -- Only a confirmed payout settles it, and redelivery is a no-op.
  perform pg_temp.act_as_service();
  perform public.attach_withdrawal_provider_ref(v_row.id, 'TRANS-PAY-1');
  select * into v_row from public.withdrawals where id = v_row.id;
  perform pg_temp.check(v_row.status = 'processing',
    'attaching the provider reference moves a withdrawal to processing');

  v_row := public.apply_payout_provider_status(
    'TRANS-PAY-1', 'SUCCESSFUL', '{}'::jsonb, 'webhook');
  perform pg_temp.check(v_row.status = 'successful',
    'a confirmed payout settles the withdrawal');

  v_row := public.apply_payout_provider_status(
    'TRANS-PAY-1', 'SUCCESSFUL', '{}'::jsonb, 'webhook');
  perform pg_temp.check(v_row.status = 'successful',
    'a redelivered payout webhook is a no-op');

  select count(*) into v_visible from public.payment_events
   where provider_trans_id = 'TRANS-PAY-1';
  perform pg_temp.check(v_visible = 1,
    'a redelivered payout webhook does not duplicate the event');
  reset role;
end $$;


-- ---------------------------------------------------------------------------
-- 11. Activity summary reports transactions only
-- ---------------------------------------------------------------------------
do $$
declare
  v_parent  uuid := '11111111-1111-1111-1111-111111111111';
  v_teacher uuid := '22222222-2222-2222-2222-222222222221';
  v_payments integer;
  v_relationships integer;
begin
  perform pg_temp.act_as(v_parent);
  select completed_payments, active_relationships
    into v_payments, v_relationships
    from public.teacher_activity_summary(v_teacher);
  perform pg_temp.check(v_payments = 1 and v_relationships = 1,
    'the activity summary counts confirmed payments and active relationships');
  reset role;
end $$;

rollback;
