-- =============================================================================
-- Camiva - monthly tutoring billing + installments
-- =============================================================================
--
-- Until now a tutoring payment was a one-off: rate x units. Real arrangements in
-- Cameroon are monthly, and parents often pay in instalments across the month.
-- This adds the monthly cycle, derived rather than stored, and lets a parent pay
-- part of it at a time.
--
-- WHO SETS THE PRICE
-- -----------------------------------------------------------------------------
-- The teacher does. monthly_amount is the teacher's own fee for that
-- relationship, not an Camiva price - the platform's own fees stay in
-- platform_fee_config and are untouched here.
--
-- HOW THE CYCLE WORKS (all derived, nothing scheduled)
-- -----------------------------------------------------------------------------
--   period_start  the most recent due_day on or before today
--   period_end    the day before the next due_day
--   paid          successful tutoring payments with paid_at inside that window
--   balance       monthly_amount - paid, floored at zero
--   next_due_on   period_end + 1 day
--
-- Because every figure is computed from the ledger at read time, a balance can
-- never drift from the payments behind it, and there is no job to run.
--
-- INSTALMENTS AND THE "CLIENT NEVER SENDS AN AMOUNT" RULE
-- -----------------------------------------------------------------------------
-- That rule now reads: the client may PROPOSE an instalment, and the server
-- BOUNDS it. create_payment_intent() accepts an amount only for a tutoring
-- payment, and refuses anything above the outstanding balance for the current
-- period. A parent still cannot invent a price, pay a different teacher's fee,
-- or overpay a month.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. relationship_billing - the teacher's monthly arrangement
-- -----------------------------------------------------------------------------

create table if not exists public.relationship_billing (
  relationship_id uuid        primary key
                    references public.parent_teacher_relationships (id) on delete cascade,
  teacher_id      uuid        not null references auth.users (id) on delete cascade,
  parent_id       uuid        not null references auth.users (id) on delete cascade,

  -- The teacher's own monthly fee for this child.
  monthly_amount  integer     not null
                    constraint relationship_billing_amount_check
                    check (monthly_amount >= 100),
  currency        text        not null default 'XAF',

  -- When tutoring started, shown on the parent's card.
  started_on      date        not null default current_date,

  -- Day of the month the next month's fee falls due. Capped at 28 so every
  -- month has that day.
  due_day         smallint    not null default 1
                    constraint relationship_billing_due_day_check
                    check (due_day between 1 and 28),

  active          boolean     not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists relationship_billing_parent_idx
  on public.relationship_billing (parent_id);
create index if not exists relationship_billing_teacher_idx
  on public.relationship_billing (teacher_id);

drop trigger if exists relationship_billing_set_updated_at on public.relationship_billing;
create trigger relationship_billing_set_updated_at
  before update on public.relationship_billing
  for each row execute function public.set_updated_at();

alter table public.relationship_billing enable row level security;

-- Both parties may read it: the parent has to see what they owe.
drop policy if exists "billing: parties can select" on public.relationship_billing;
create policy "billing: parties can select"
  on public.relationship_billing
  for select
  to authenticated
  using (auth.uid() = parent_id or auth.uid() = teacher_id
         or public.is_platform_admin());

-- Only the teacher sets or changes their own fee, and only on a relationship
-- that is actually theirs.
drop policy if exists "billing: teacher can insert own" on public.relationship_billing;
create policy "billing: teacher can insert own"
  on public.relationship_billing
  for insert
  to authenticated
  with check (
    auth.uid() = teacher_id
    and exists (
      select 1 from public.parent_teacher_relationships r
      where r.id = relationship_id
        and r.teacher_id = auth.uid()
        and r.parent_id = relationship_billing.parent_id
    )
  );

drop policy if exists "billing: teacher can update own" on public.relationship_billing;
create policy "billing: teacher can update own"
  on public.relationship_billing
  for update
  to authenticated
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

grant select on public.relationship_billing to authenticated;
grant insert, update on public.relationship_billing to authenticated;


-- The teacher sets their monthly fee through this, so parent_id and teacher_id
-- are filled from the relationship itself and can never be spoofed.
create or replace function public.set_relationship_billing(
  p_relationship_id uuid,
  p_monthly_amount  integer,
  p_due_day         smallint default null,
  p_started_on      date default null
)
returns public.relationship_billing
language plpgsql
security definer
set search_path = public
as $$
declare
  rel public.parent_teacher_relationships;
  v_row public.relationship_billing;
begin
  select * into rel from public.parent_teacher_relationships
   where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;
  if rel.teacher_id <> auth.uid() then
    raise exception 'Only the teacher can set the monthly fee';
  end if;
  if p_monthly_amount is null or p_monthly_amount < 100 then
    raise exception 'Enter a monthly fee of at least 100';
  end if;

  insert into public.relationship_billing
    (relationship_id, teacher_id, parent_id, monthly_amount, due_day, started_on)
  values
    (rel.id, rel.teacher_id, rel.parent_id, p_monthly_amount,
     coalesce(p_due_day, 1), coalesce(p_started_on, current_date))
  on conflict (relationship_id) do update
    set monthly_amount = excluded.monthly_amount,
        due_day        = coalesce(p_due_day, relationship_billing.due_day),
        started_on     = coalesce(p_started_on, relationship_billing.started_on),
        active         = true
  returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function
  public.set_relationship_billing(uuid, integer, smallint, date) from public, anon;
grant execute on function
  public.set_relationship_billing(uuid, integer, smallint, date) to authenticated;


-- -----------------------------------------------------------------------------
-- 2. The derived monthly picture
-- -----------------------------------------------------------------------------
-- Returns no row when the teacher has not set a monthly fee, so the app shows
-- nothing rather than inventing a figure.
-- -----------------------------------------------------------------------------

create or replace function public.relationship_billing_summary(p_relationship_id uuid)
returns table (
  monthly_amount   integer,
  currency         text,
  started_on       date,
  period_start     date,
  period_end       date,
  next_due_on      date,
  paid_this_period integer,
  balance          integer,
  last_paid_at     timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  b            public.relationship_billing;
  rel          public.parent_teacher_relationships;
  v_start      date;
  v_end        date;
  v_paid       integer;
  v_last       timestamptz;
begin
  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    return;
  end if;
  -- Only the two parties (or an admin) may see the money on a relationship.
  if auth.uid() not in (rel.parent_id, rel.teacher_id)
     and not public.is_platform_admin() then
    return;
  end if;

  select * into b from public.relationship_billing
   where relationship_id = p_relationship_id and active;
  if not found then
    return;
  end if;

  -- The most recent due_day on or before today starts the current period.
  v_start := make_date(
    extract(year from current_date)::int,
    extract(month from current_date)::int,
    b.due_day
  );
  if v_start > current_date then
    v_start := (v_start - interval '1 month')::date;
  end if;
  v_end := (v_start + interval '1 month' - interval '1 day')::date;

  select coalesce(sum(t.amount), 0), max(t.paid_at)
    into v_paid, v_last
    from public.payment_transactions t
   where t.relationship_id = p_relationship_id
     and t.purpose = 'tutoring_payment'
     and t.status = 'successful'
     and t.paid_at >= v_start::timestamptz
     and t.paid_at < (v_end + 1)::timestamptz;

  return query select
    b.monthly_amount,
    b.currency,
    b.started_on,
    v_start,
    v_end,
    (v_end + 1)::date,
    v_paid,
    greatest(b.monthly_amount - v_paid, 0),
    v_last;
end;
$$;

grant execute on function public.relationship_billing_summary(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. create_payment_intent(): instalments, bounded server-side
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
  cfg      public.platform_fee_config;
  rel      public.parent_teacher_relationships;
  v_uid    uuid := auth.uid();
  v_rate   integer;
  v_amount integer;
  v_row    public.payment_transactions;
  v_desc   text;
  v_balance integer;
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
    if public.relationship_activation_state(p_relationship_id) <> 'required' then
      raise exception 'Activation is not required for this relationship';
    end if;

    v_amount := cfg.match_activation_fee_amount;
    v_desc   := 'Camiva relationship activation';

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

    -- Monthly arrangement: the parent may pay all of it or part of it, but
    -- never more than is outstanding for the current period.
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
      -- No monthly fee set: fall back to the teacher's rate per session.
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

-- The old 4-argument signature is replaced by the one above.
drop function if exists public.create_payment_intent(text, uuid, integer, uuid);


-- payment_quote() must quote the same figure the intent will charge.
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
  cfg      public.platform_fee_config;
  rel      public.parent_teacher_relationships;
  v_uid    uuid := auth.uid();
  v_rate   integer;
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
