-- =============================================================================
-- Camiva - the Platform Charge gate
-- =============================================================================
--
-- No teacher payment before parent confirmation.
--
-- relationship_activation_state() gains a 'blocked' answer, meaning "a charge
-- applies, but the parent has not confirmed the arrangement yet". While a
-- relationship is blocked, create_payment_intent() refuses to create the
-- charge at all - so the rule holds whether the request comes from the button
-- or straight from the API.
--
-- States:
--   'not_required'  no Platform Charge is configured
--   'blocked'       a charge applies, waiting on the parent's confirmation
--   'required'      the parent confirmed; the teacher can now pay
--   'pending'       a charge is in flight with the provider
--   'active'        the charge succeeded - the relationship is live
-- =============================================================================


create or replace function public.relationship_activation_state(p_relationship_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cfg      public.platform_fee_config;
  v_status text;
begin
  select * into cfg from public.platform_fee_config where id = 1;

  if cfg is null
     or not cfg.match_activation_required
     or coalesce(cfg.match_activation_fee_amount, 0) <= 0 then
    return 'not_required';
  end if;

  -- A successful charge is final, whatever happened to the agreement since.
  select status into v_status
  from public.payment_transactions
  where relationship_id = p_relationship_id
    and purpose = 'match_activation'
    and status = 'successful'
  limit 1;
  if found then
    return 'active';
  end if;

  select status into v_status
  from public.payment_transactions
  where relationship_id = p_relationship_id
    and purpose = 'match_activation'
    and status = 'pending'
  limit 1;
  if found then
    return 'pending';
  end if;

  -- The gate: nothing is owed until the parent has confirmed the terms.
  if not exists (
    select 1 from public.tutoring_agreements a
     where a.relationship_id = p_relationship_id
       and a.status in ('confirmed', 'active')
  ) then
    return 'blocked';
  end if;

  return 'required';
end;
$$;

grant execute on function public.relationship_activation_state(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- create_payment_intent(): refuse a Platform Charge that is not yet owed
-- -----------------------------------------------------------------------------

create or replace function public.create_payment_intent(
  p_purpose         text,
  p_relationship_id uuid default null,
  p_units           integer default 1,
  p_session_id      uuid default null,
  p_amount          integer default null
)
returns public.payment_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg       public.platform_fee_config;
  rel       public.parent_teacher_relationships;
  v_uid     uuid := auth.uid();
  v_rate    integer;
  v_amount  integer;
  v_row     public.payment_transactions;
  v_desc    text;
  v_balance integer;
  v_state   text;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if p_units is null or p_units < 1 or p_units > 100 then
    raise exception 'Invalid units';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;
  if cfg is null then
    raise exception 'Pricing is not configured';
  end if;

  if p_purpose = 'teacher_service_fee' then
    if coalesce(cfg.teacher_service_fee_amount, 0) <= 0 then
      raise exception 'No service fee is configured';
    end if;
    v_amount := cfg.teacher_service_fee_amount;
    v_desc   := 'Camiva service fee';

    insert into public.payment_transactions
      (purpose, payer_id, teacher_id, amount, currency, description)
    values
      ('teacher_service_fee', v_uid, v_uid, v_amount, cfg.currency, v_desc)
    returning * into v_row;
    return v_row;
  end if;

  if p_relationship_id is null then
    raise exception 'A relationship is required for this payment';
  end if;

  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;

  if p_purpose = 'match_activation' then
    if rel.teacher_id <> v_uid then
      raise exception 'Only the teacher can activate this relationship';
    end if;
    if rel.status <> 'accepted' then
      raise exception 'Relationship is not accepted';
    end if;
    if not public.is_teacher_verified(v_uid) then
      raise exception 'Complete your verification first';
    end if;

    v_state := public.relationship_activation_state(p_relationship_id);
    if v_state = 'blocked' then
      -- The rule this whole flow exists to protect.
      raise exception 'The parent has not confirmed the tutoring arrangement yet';
    end if;
    if v_state <> 'required' then
      raise exception 'Activation is not required for this relationship';
    end if;

    v_amount := cfg.match_activation_fee_amount;
    v_desc   := 'Camiva Platform Charge';

    insert into public.payment_transactions
      (purpose, payer_id, parent_id, teacher_id, student_id, relationship_id,
       amount, currency, description)
    values
      ('match_activation', v_uid, rel.parent_id, rel.teacher_id, rel.student_id,
       rel.id, v_amount, cfg.currency, v_desc)
    returning * into v_row;
    return v_row;

  elsif p_purpose = 'tutoring_payment' then
    if rel.parent_id <> v_uid then
      raise exception 'Only the parent can pay for this tutoring';
    end if;
    if not public.relationship_is_operational(p_relationship_id) then
      raise exception 'This relationship is not active yet';
    end if;

    select balance into v_balance
      from public.relationship_billing_summary(p_relationship_id);

    if v_balance is not null then
      if v_balance <= 0 then
        raise exception 'This month is already paid';
      end if;
      v_amount := coalesce(p_amount, v_balance);
      if v_amount < 100 then
        raise exception 'The smallest payment is 100';
      end if;
      if v_amount > v_balance then
        raise exception 'That is more than the balance for this month';
      end if;
      v_desc := 'Tutoring payment';
    else
      select hourly_rate into v_rate
        from public.teacher_profiles
        where user_id = rel.teacher_id;
      if v_rate is null or v_rate <= 0 then
        raise exception 'This teacher has not set a rate yet';
      end if;
      v_amount := v_rate * p_units;
      v_desc   := 'Tutoring payment';
    end if;

    if p_session_id is not null then
      if to_regclass('public.lesson_sessions') is null then
        raise exception 'Scheduling is not available on this project';
      end if;
      execute 'select 1 from public.lesson_sessions where id = $1 and relationship_id = $2'
        using p_session_id, p_relationship_id;
      if not found then
        raise exception 'Session does not belong to this relationship';
      end if;
    end if;

    insert into public.payment_transactions
      (purpose, payer_id, parent_id, teacher_id, student_id, relationship_id,
       session_id, amount, currency, description)
    values
      ('tutoring_payment', v_uid, rel.parent_id, rel.teacher_id, rel.student_id,
       rel.id, p_session_id, v_amount, cfg.currency, v_desc)
    returning * into v_row;
    return v_row;
  end if;

  raise exception 'Unknown payment purpose: %', p_purpose;
end;
$$;

revoke execute on function
  public.create_payment_intent(text, uuid, integer, uuid, integer) from public;
grant execute on function
  public.create_payment_intent(text, uuid, integer, uuid, integer) to authenticated;


-- -----------------------------------------------------------------------------
-- A confirmed Platform Charge makes the agreement active
-- -----------------------------------------------------------------------------
-- Applied inside the same idempotent function that records the payment, so a
-- redelivered webhook cannot activate twice, and an unconfirmed payment cannot
-- activate at all.
-- -----------------------------------------------------------------------------

create or replace function public.apply_payment_provider_status(
  p_trans_id text,
  p_status   text,
  p_payload  jsonb default '{}'::jsonb,
  p_source   text default 'webhook'
)
returns public.payment_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row      public.payment_transactions;
  v_internal text;
  v_first    boolean := false;
  v_child    text;
begin
  v_internal := public.fapshi_status_to_internal(p_status);
  if v_internal is null then
    raise exception 'Unknown provider status: %', p_status;
  end if;

  select * into v_row
    from public.payment_transactions
   where provider_trans_id = p_trans_id
   for update;

  if not found then
    raise exception 'No payment for provider transaction %', p_trans_id;
  end if;

  begin
    insert into public.payment_events
      (provider, provider_trans_id, provider_status, source, payload)
    values
      (v_row.provider, p_trans_id, upper(p_status), p_source,
       coalesce(p_payload, '{}'::jsonb));
    v_first := true;
  exception when unique_violation then
    v_first := false;
  end;

  if not v_first then
    return v_row;
  end if;
  if v_row.status <> 'pending' then
    return v_row;
  end if;
  if v_internal = 'pending' then
    return v_row;
  end if;

  update public.payment_transactions
     set status = v_internal,
         paid_at = case when v_internal = 'successful' then now() else paid_at end,
         provider_medium = coalesce(p_payload ->> 'medium', provider_medium),
         provider_financial_trans_id =
           coalesce(p_payload ->> 'financialTransId', provider_financial_trans_id),
         failure_reason = case
           when v_internal in ('failed', 'cancelled')
             then coalesce(p_payload ->> 'reason', failure_reason)
           else failure_reason end
   where id = v_row.id
  returning * into v_row;

  if v_row.status = 'successful' then
    select s.name into v_child from public.students s where s.id = v_row.student_id;

    if v_row.purpose = 'match_activation' then
      -- The relationship is now live. The agreement follows the money, never
      -- the other way round.
      update public.tutoring_agreements
         set status = 'active', teacher_activated_at = now()
       where relationship_id = v_row.relationship_id
         and status = 'confirmed';

      insert into public.payment_reminders
        (user_id, kind, title, body, payment_id, relationship_id)
      values
        (v_row.teacher_id, 'relationship_activated',
         'You''re connected',
         coalesce(v_child, 'Your new student') ||
           ' is now connected with you through Camiva.',
         v_row.id, v_row.relationship_id),
        (v_row.parent_id, 'relationship_activated',
         'You''re connected',
         coalesce(v_child, 'Your child') ||
           ' is now connected with your teacher through Camiva.',
         v_row.id, v_row.relationship_id);

    elsif v_row.purpose = 'tutoring_payment' then
      insert into public.payment_reminders
        (user_id, kind, title, body, payment_id, relationship_id)
      values
        (v_row.parent_id, 'payment_received',
         'Tutoring payment received',
         coalesce(v_child, 'Your child') || ' · ' ||
           to_char(v_row.amount, 'FM999G999G999') || ' ' || v_row.currency,
         v_row.id, v_row.relationship_id),
        (v_row.teacher_id, 'payment_received',
         'Tutoring payment received',
         coalesce(v_child, 'A student') || ' · ' ||
           to_char(v_row.amount, 'FM999G999G999') || ' ' || v_row.currency,
         v_row.id, v_row.relationship_id);

    elsif v_row.purpose = 'teacher_service_fee' then
      update public.service_fee_periods
         set status = 'paid', paid_at = now(), payment_id = v_row.id
       where teacher_id = v_row.teacher_id
         and status in ('due', 'reminded', 'overdue')
         and current_date between period_start and period_end;
    end if;

  elsif v_row.status in ('failed', 'cancelled') then
    -- A failed Platform Charge changes nothing: the agreement stays confirmed
    -- and the teacher can try again.
    insert into public.payment_reminders
      (user_id, kind, title, body, payment_id, relationship_id)
    values
      (v_row.payer_id, 'payment_failed',
       'Payment not completed',
       'Your payment was not completed. You can try again.',
       v_row.id, v_row.relationship_id);
  end if;

  return v_row;
end;
$$;

revoke execute on function
  public.apply_payment_provider_status(text, text, jsonb, text)
  from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- payment_quote(): quote the Platform Charge only when it is actually owed
-- -----------------------------------------------------------------------------

create or replace function public.payment_quote(
  p_purpose         text,
  p_relationship_id uuid default null,
  p_units           integer default 1
)
returns table (amount integer, currency text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cfg       public.platform_fee_config;
  rel       public.parent_teacher_relationships;
  v_uid     uuid := auth.uid();
  v_rate    integer;
  v_balance integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;

  if p_purpose = 'teacher_service_fee' then
    if coalesce(cfg.teacher_service_fee_amount, 0) <= 0 then
      raise exception 'No service fee is configured';
    end if;
    return query select cfg.teacher_service_fee_amount, cfg.currency;
    return;
  end if;

  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;
  if v_uid not in (rel.parent_id, rel.teacher_id) then
    raise exception 'Not authorised';
  end if;

  if p_purpose = 'match_activation' then
    if public.relationship_activation_state(p_relationship_id) = 'blocked' then
      raise exception 'The parent has not confirmed the tutoring arrangement yet';
    end if;
    return query select cfg.match_activation_fee_amount, cfg.currency;
    return;
  end if;

  if p_purpose = 'tutoring_payment' then
    select s.balance into v_balance
      from public.relationship_billing_summary(p_relationship_id) s;
    if v_balance is not null then
      return query select v_balance, cfg.currency;
      return;
    end if;

    select hourly_rate into v_rate from public.teacher_profiles
     where user_id = rel.teacher_id;
    if v_rate is null or v_rate <= 0 then
      raise exception 'This teacher has not set a rate yet';
    end if;
    return query select (v_rate * greatest(coalesce(p_units, 1), 1)), cfg.currency;
    return;
  end if;

  raise exception 'Unknown payment purpose: %', p_purpose;
end;
$$;

grant execute on function public.payment_quote(text, uuid, integer) to authenticated;
