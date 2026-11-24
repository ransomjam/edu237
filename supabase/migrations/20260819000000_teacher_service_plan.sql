-- =============================================================================
-- Camiva - the Teacher Service Plan model
-- =============================================================================
--
-- THE MODEL, IN ONE PARAGRAPH
-- -----------------------------------------------------------------------------
-- A teacher gets the tutoring relationship first, at no charge. The parent pays
-- tutoring through Camiva. The teacher earns 100% of that tutoring money. After
-- the teacher's FIRST MONTH of tutoring earnings, a flat Camiva Teacher Service
-- Plan of 3,000 FCFA/month keeps their account active.
--
-- WHAT THIS MIGRATION RETIRES
-- -----------------------------------------------------------------------------
-- The one-time relationship charge is gone. No match fee, no activation fee, no
-- contact fee: match_activation is switched off in config AND refused by
-- create_payment_intent(), so it cannot come back by a config edit alone.
--
-- WHAT IT IS NOT
-- -----------------------------------------------------------------------------
-- Not a commission. teacher_earning_bps stays at 10000 — the teacher keeps
-- every franc of tutoring money. The service plan is a separate, flat charge.
--
-- The first month is NOT free tutoring: the parent pays in full and the teacher
-- earns in full. Camiva simply does not charge the service plan yet.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Configuration
-- -----------------------------------------------------------------------------
alter table public.platform_fee_config
  add column if not exists service_plan_grace_days smallint not null default 7,
  -- How long the first month of tutoring runs before the plan falls due.
  add column if not exists first_month_days smallint not null default 30;

alter table public.platform_fee_config
  drop constraint if exists platform_fee_config_grace_check;
alter table public.platform_fee_config
  add constraint platform_fee_config_grace_check
  check (service_plan_grace_days between 0 and 60);

-- The model being tested: 3,000 FCFA/month, and no relationship charge at all.
-- Both stay configurable; these are the current values, not hard-coded rules.
update public.platform_fee_config
   set teacher_service_fee_amount        = 3000,
       teacher_service_fee_interval_days = 30,
       match_activation_required         = false,
       match_activation_fee_amount       = null,
       -- 100% of tutoring money is the teacher's. This is not a commission
       -- model and this value is what says so.
       teacher_earning_bps               = 10000
 where id = 1;


-- -----------------------------------------------------------------------------
-- 2. The teacher's agreement to the Camiva terms
-- -----------------------------------------------------------------------------
-- Recorded at the moment the teacher accepts a request, with the exact terms
-- text they saw. Storing the text (not just a version number) means a later
-- wording change cannot rewrite what someone actually agreed to.
-- -----------------------------------------------------------------------------

create table if not exists public.teacher_terms_acceptances (
  id           uuid        primary key default gen_random_uuid(),
  teacher_id   uuid        not null references auth.users (id) on delete cascade,
  request_id   uuid        references public.teacher_requests (id) on delete set null,
  terms_version text       not null,
  terms_text   text        not null,
  -- The plan price quoted at the time, so a price change never retroactively
  -- alters what was agreed.
  quoted_amount integer,
  currency     text        not null default 'XAF',
  accepted_at  timestamptz not null default now()
);

create index if not exists teacher_terms_acceptances_teacher_idx
  on public.teacher_terms_acceptances (teacher_id, accepted_at desc);

alter table public.teacher_terms_acceptances enable row level security;

drop policy if exists "terms: teacher can select own" on public.teacher_terms_acceptances;
create policy "terms: teacher can select own"
  on public.teacher_terms_acceptances
  for select
  to authenticated
  using (auth.uid() = teacher_id or public.is_platform_admin());

grant select on public.teacher_terms_acceptances to authenticated;


create or replace function public.accept_teacher_terms(
  p_terms_version text,
  p_terms_text    text,
  p_request_id    uuid default null
)
returns public.teacher_terms_acceptances
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg   public.platform_fee_config;
  v_uid uuid := auth.uid();
  v_row public.teacher_terms_acceptances;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce(btrim(p_terms_text), '') = '' then
    raise exception 'Terms text is required';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;

  insert into public.teacher_terms_acceptances
    (teacher_id, request_id, terms_version, terms_text, quoted_amount, currency)
  values
    (v_uid, p_request_id, p_terms_version, p_terms_text,
     cfg.teacher_service_fee_amount, coalesce(cfg.currency, 'XAF'))
  returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function
  public.accept_teacher_terms(text, text, uuid) from public, anon;
grant execute on function
  public.accept_teacher_terms(text, text, uuid) to authenticated;


create or replace function public.has_accepted_teacher_terms()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.teacher_terms_acceptances t
     where t.teacher_id = auth.uid()
  );
$$;

grant execute on function public.has_accepted_teacher_terms() to authenticated;


-- -----------------------------------------------------------------------------
-- 3. The service plan state
-- -----------------------------------------------------------------------------
-- Everything is derived from the ledger at read time. The anchor is the
-- teacher's FIRST successful tutoring payment — the plan cannot fall due for
-- someone who has never earned.
--
-- States:
--   'not_started'   no tutoring earnings yet; nothing is owed
--   'first_month'   inside the first month of earnings; nothing is owed
--   'due'           the first month is complete; the plan is payable
--   'pending'       a plan payment is in flight with the provider
--   'active'        paid, and the current period is covered
--   'overdue'       past due, still inside the grace period
--   'suspended'     past due beyond grace
--
-- 'overdue' and 'suspended' are deliberately separate: a teacher with a failed
-- payment is not cut off the same day. Existing child relationships are never
-- ended by this function — it reports state, it does not sever teaching.
-- -----------------------------------------------------------------------------

create or replace function public.teacher_service_status(p_teacher_id uuid default null)
returns table (
  state           text,
  amount          integer,
  currency        text,
  first_earned_at timestamptz,
  due_on          date,
  grace_ends_on   date,
  paid_until      date
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cfg        public.platform_fee_config;
  v_teacher  uuid := coalesce(p_teacher_id, auth.uid());
  v_first    timestamptz;
  v_due      date;
  v_grace    date;
  v_paid_to  date;
  v_state    text;
  v_pending  boolean;
begin
  if v_teacher is null then
    raise exception 'Not authenticated';
  end if;
  -- A teacher sees only their own; admins see anyone's.
  if v_teacher <> auth.uid() and not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;

  -- The anchor: the first tutoring money this teacher actually received.
  select min(t.paid_at) into v_first
    from public.payment_transactions t
   where t.teacher_id = v_teacher
     and t.purpose = 'tutoring_payment'
     and t.status = 'successful';

  -- How far the teacher has already paid the plan.
  select max(p.period_end) into v_paid_to
    from public.service_fee_periods p
   where p.teacher_id = v_teacher and p.status = 'paid';

  select exists (
    select 1 from public.payment_transactions t
     where t.teacher_id = v_teacher
       and t.purpose = 'teacher_service_fee'
       and t.status = 'pending'
  ) into v_pending;

  if v_first is null then
    -- Never earned: nothing is owed, and nothing is implied.
    return query select 'not_started'::text,
      cfg.teacher_service_fee_amount, coalesce(cfg.currency, 'XAF'),
      null::timestamptz, null::date, null::date, v_paid_to;
    return;
  end if;

  v_due := (v_first + make_interval(days => coalesce(cfg.first_month_days, 30)))::date;
  -- Once a period has been paid, the next one falls due when it ends.
  if v_paid_to is not null and v_paid_to >= v_due then
    v_due := (v_paid_to + 1);
  end if;
  v_grace := v_due + coalesce(cfg.service_plan_grace_days, 7);

  if current_date < v_due then
    v_state := case when v_paid_to is null then 'first_month' else 'active' end;
  elsif v_pending then
    v_state := 'pending';
  elsif current_date <= v_grace then
    v_state := case when current_date = v_due then 'due' else 'overdue' end;
  else
    v_state := 'suspended';
  end if;

  return query select v_state,
    cfg.teacher_service_fee_amount, coalesce(cfg.currency, 'XAF'),
    v_first, v_due, v_grace, v_paid_to;
end;
$$;

grant execute on function public.teacher_service_status(uuid) to authenticated;


-- Whether the teacher may take on NEW Camiva relationships. An unpaid plan
-- stops new work; it never touches teaching already underway.
create or replace function public.teacher_can_accept_new_work(p_teacher_id uuid default null)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_state text;
begin
  select state into v_state
    from public.teacher_service_status(coalesce(p_teacher_id, auth.uid()));
  return v_state is distinct from 'suspended';
end;
$$;

grant execute on function public.teacher_can_accept_new_work(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Service fee periods follow the plan
-- -----------------------------------------------------------------------------
-- Opens the period the teacher is being asked to pay for, but only when the
-- plan is actually due. Nothing is created for a teacher who has not finished
-- their first month.
-- -----------------------------------------------------------------------------

create or replace function public.ensure_service_fee_period()
returns public.service_fee_periods
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg     public.platform_fee_config;
  v_uid   uuid := auth.uid();
  v_row   public.service_fee_periods;
  v_state text;
  v_due   date;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;
  if cfg is null or coalesce(cfg.teacher_service_fee_amount, 0) <= 0 then
    return null;
  end if;

  select state, due_on into v_state, v_due
    from public.teacher_service_status(v_uid);

  -- Not due yet: no period, no reminder, nothing owed.
  if v_state in ('not_started', 'first_month', 'active') or v_due is null then
    return null;
  end if;

  select * into v_row from public.service_fee_periods
   where teacher_id = v_uid and period_start = v_due
   limit 1;
  if found then
    if v_row.status in ('due', 'reminded') and current_date > v_row.period_end then
      update public.service_fee_periods set status = 'overdue'
       where id = v_row.id returning * into v_row;
    end if;
    return v_row;
  end if;

  insert into public.service_fee_periods
    (teacher_id, period_start, period_end, amount, currency)
  values
    (v_uid, v_due,
     v_due + (coalesce(cfg.teacher_service_fee_interval_days, 30) - 1),
     cfg.teacher_service_fee_amount, cfg.currency)
  on conflict (teacher_id, period_start) do nothing
  returning * into v_row;

  if v_row is null then
    select * into v_row from public.service_fee_periods
     where teacher_id = v_uid and period_start = v_due;
  end if;
  return v_row;
end;
$$;

revoke execute on function public.ensure_service_fee_period() from public;
grant execute on function public.ensure_service_fee_period() to authenticated;


-- -----------------------------------------------------------------------------
-- 5. Payments: the plan is payable only when due; no relationship charge
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

  -- The Camiva Teacher Service Plan.
  if p_purpose = 'teacher_service_fee' then
    if coalesce(cfg.teacher_service_fee_amount, 0) <= 0 then
      raise exception 'No service plan is configured';
    end if;

    select state into v_state from public.teacher_service_status(v_uid);
    if v_state in ('not_started', 'first_month') then
      -- The teacher earns first. Nothing is owed during the first month.
      raise exception 'Your service plan starts after your first month';
    end if;
    if v_state = 'active' then
      raise exception 'Your service plan is already paid for this period';
    end if;

    v_amount := cfg.teacher_service_fee_amount;
    v_desc   := 'Camiva Teacher Service Plan';

    insert into public.payment_transactions
      (purpose, payer_id, teacher_id, amount, currency, description)
    values
      ('teacher_service_fee', v_uid, v_uid, v_amount, cfg.currency, v_desc)
    returning * into v_row;
    return v_row;
  end if;

  -- The relationship charge is not part of this model, in any configuration.
  if p_purpose = 'match_activation' then
    raise exception 'Camiva does not charge to start a tutoring relationship';
  end if;

  if p_purpose <> 'tutoring_payment' then
    raise exception 'Unknown payment purpose: %', p_purpose;
  end if;

  if p_relationship_id is null then
    raise exception 'A relationship is required for this payment';
  end if;

  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;
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
  else
    select hourly_rate into v_rate
      from public.teacher_profiles where user_id = rel.teacher_id;
    if v_rate is null or v_rate <= 0 then
      raise exception 'This teacher has not set a rate yet';
    end if;
    v_amount := v_rate * p_units;
  end if;
  v_desc := 'Tutoring payment';

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
end;
$$;

revoke execute on function
  public.create_payment_intent(text, uuid, integer, uuid, integer) from public;
grant execute on function
  public.create_payment_intent(text, uuid, integer, uuid, integer) to authenticated;


-- Quotes follow the same rules, so a screen never shows a price that cannot be
-- charged.
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
      raise exception 'No service plan is configured';
    end if;
    return query select cfg.teacher_service_fee_amount, cfg.currency;
    return;
  end if;

  if p_purpose = 'match_activation' then
    raise exception 'Camiva does not charge to start a tutoring relationship';
  end if;

  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;
  if v_uid not in (rel.parent_id, rel.teacher_id) then
    raise exception 'Not authorised';
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


-- -----------------------------------------------------------------------------
-- 6. No relationship charge means no activation gate
-- -----------------------------------------------------------------------------
-- A relationship is operational once the parent has confirmed the arrangement.
-- Money is no longer part of that condition, because there is no charge to pay.
-- -----------------------------------------------------------------------------

create or replace function public.relationship_activation_state(p_relationship_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select 'not_required'::text;
$$;

grant execute on function public.relationship_activation_state(uuid) to authenticated;


create or replace function public.relationship_is_operational(p_relationship_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.parent_teacher_relationships r
     where r.id = p_relationship_id
       and r.status = 'accepted'
  )
  -- Where an arrangement exists, the parent must have confirmed it. Older
  -- relationships that predate arrangements stay operational.
  and not exists (
    select 1 from public.tutoring_agreements a
     where a.relationship_id = p_relationship_id
       and a.status = 'proposed'
  );
$$;

grant execute on function public.relationship_is_operational(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 7. Camiva-managed payment is the arrangement
-- -----------------------------------------------------------------------------
-- Direct-to-teacher is not offered for a relationship obtained through Camiva,
-- so the column keeps its shape but only one value is accepted.
-- -----------------------------------------------------------------------------

update public.tutoring_agreements
   set payment_method = 'edu237'
 where payment_method <> 'edu237'
   and status in ('proposed', 'confirmed', 'active');

create or replace function public.propose_tutoring_agreement(
  p_relationship_id   uuid,
  p_subject           text,
  p_start_date        date,
  p_frequency         text,
  p_lessons_per_week  smallint,
  p_lesson_minutes    smallint,
  p_price             integer,
  p_price_unit        text,
  p_teaching_mode     text,
  p_location_area     text default null,
  p_payment_method    text default 'edu237',
  p_payment_frequency text default 'per_month'
)
returns public.tutoring_agreements
language plpgsql
security definer
set search_path = public
as $$
declare
  rel   public.parent_teacher_relationships;
  v_uid uuid := auth.uid();
  v_row public.tutoring_agreements;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into rel from public.parent_teacher_relationships
   where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;
  if rel.teacher_id <> v_uid then
    raise exception 'Only the teacher can propose tutoring';
  end if;
  if rel.status <> 'accepted' then
    raise exception 'Accept the request first';
  end if;
  if not public.is_teacher_verified(v_uid) then
    raise exception 'Complete your verification first';
  end if;

  if exists (
    select 1 from public.tutoring_agreements a
     where a.relationship_id = p_relationship_id
       and a.status in ('proposed', 'confirmed', 'active')
  ) then
    raise exception 'There is already a tutoring arrangement for this student';
  end if;

  insert into public.tutoring_agreements
    (relationship_id, parent_id, teacher_id, student_id, subject, start_date,
     frequency, lessons_per_week, lesson_minutes, price, price_unit,
     teaching_mode, location_area, payment_method, payment_frequency)
  values
    (rel.id, rel.parent_id, rel.teacher_id, rel.student_id,
     coalesce(nullif(btrim(coalesce(p_subject, '')), ''), rel.subject),
     p_start_date, p_frequency, p_lessons_per_week, p_lesson_minutes,
     p_price, p_price_unit, p_teaching_mode,
     nullif(btrim(coalesce(p_location_area, '')), ''),
     -- Tutoring obtained through Camiva is managed through Camiva.
     'edu237',
     coalesce(p_payment_frequency, 'per_month'))
  returning * into v_row;

  insert into public.payment_reminders
    (user_id, kind, title, body, relationship_id)
  values
    (rel.parent_id, 'agreement_update', 'Tutoring arrangement to review',
     'Your teacher has sent the tutoring details. Review and confirm to continue.',
     rel.id);

  return v_row;
end;
$$;

revoke execute on function public.propose_tutoring_agreement(
  uuid, text, date, text, smallint, smallint, integer, text, text, text, text, text)
  from public, anon;
grant execute on function public.propose_tutoring_agreement(
  uuid, text, date, text, smallint, smallint, integer, text, text, text, text, text)
  to authenticated;
