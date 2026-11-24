-- =============================================================================
-- Camiva - tutoring agreements + the Platform Charge gate
-- =============================================================================
--
-- THE RULE THIS MIGRATION EXISTS TO ENFORCE
-- -----------------------------------------------------------------------------
-- A teacher must not pay the Camiva Platform Charge before the parent has
-- confirmed the tutoring arrangement. Paying to activate a request that never
-- becomes real tutoring is exactly what this prevents.
--
-- It is enforced in the database, not in the UI: relationship_activation_state()
-- reports 'blocked' until a confirmed agreement exists, and
-- create_payment_intent() refuses a match_activation payment in that state. A
-- teacher calling the API directly hits the same wall as the button.
--
-- THE ORDER
-- -----------------------------------------------------------------------------
--   request -> accept -> verify -> propose -> parent confirms
--     -> Platform Charge -> payment confirmed by Fapshi -> ACTIVE -> contact
--
-- The agreement is the source of truth for the tutoring terms: structured
-- fields, not free text, so both sides see the same thing and the expected
-- payment can be computed from it.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. tutoring_agreements
-- -----------------------------------------------------------------------------

create table if not exists public.tutoring_agreements (
  id              uuid        primary key default gen_random_uuid(),
  relationship_id uuid        not null
                    references public.parent_teacher_relationships (id) on delete cascade,
  parent_id       uuid        not null references auth.users (id) on delete cascade,
  teacher_id      uuid        not null references auth.users (id) on delete cascade,
  student_id      uuid        not null references public.students (id) on delete cascade,

  subject         text        not null,
  start_date      date        not null,

  frequency       text        not null
                    constraint tutoring_agreements_frequency_check
                    check (frequency in ('once_weekly', 'twice_weekly',
                                         'thrice_weekly', 'custom')),
  -- Lessons per week. Carried explicitly so 'custom' is a real number rather
  -- than a label, and the expected payment can be computed from it.
  lessons_per_week   smallint  not null default 1
                       constraint tutoring_agreements_lpw_check
                       check (lessons_per_week between 1 and 14),
  lesson_minutes     smallint  not null
                       constraint tutoring_agreements_duration_check
                       check (lesson_minutes in (30, 45, 60, 90, 120)),

  price           integer     not null
                    constraint tutoring_agreements_price_check check (price >= 100),
  price_unit      text        not null
                    constraint tutoring_agreements_price_unit_check
                    check (price_unit in ('per_lesson', 'per_week', 'per_month')),
  currency        text        not null default 'XAF',

  teaching_mode   text        not null
                    constraint tutoring_agreements_mode_check
                    check (teaching_mode in ('in_person', 'online')),
  -- An AREA only (e.g. "Bastos"). Never a street address: Camiva does not ask
  -- for or store exact private residences.
  location_area   text,

  -- 'edu237' keeps the payment inside Camiva (receipts, history, reminders,
  -- earnings, support). 'direct' is retained as a controlled option and is
  -- deliberately not the default.
  payment_method  text        not null default 'edu237'
                    constraint tutoring_agreements_payment_method_check
                    check (payment_method in ('edu237', 'direct')),
  payment_frequency text      not null default 'per_month'
                    constraint tutoring_agreements_payment_frequency_check
                    check (payment_frequency in ('per_lesson', 'per_week', 'per_month')),

  status          text        not null default 'proposed'
                    constraint tutoring_agreements_status_check
                    check (status in ('proposed', 'confirmed', 'declined',
                                      'active', 'cancelled')),

  proposed_at         timestamptz not null default now(),
  parent_confirmed_at timestamptz,
  parent_declined_at  timestamptz,
  decline_reason      text,
  teacher_activated_at timestamptz,

  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists tutoring_agreements_relationship_idx
  on public.tutoring_agreements (relationship_id);
create index if not exists tutoring_agreements_parent_idx
  on public.tutoring_agreements (parent_id, status);
create index if not exists tutoring_agreements_teacher_idx
  on public.tutoring_agreements (teacher_id, status);

-- One live agreement per relationship: a teacher cannot have two proposals in
-- flight, and a confirmed arrangement cannot be quietly replaced.
create unique index if not exists tutoring_agreements_live_unique
  on public.tutoring_agreements (relationship_id)
  where status in ('proposed', 'confirmed', 'active');

drop trigger if exists tutoring_agreements_set_updated_at on public.tutoring_agreements;
create trigger tutoring_agreements_set_updated_at
  before update on public.tutoring_agreements
  for each row execute function public.set_updated_at();


-- The commercial terms are the teacher's, and they are frozen once proposed.
-- A parent confirms or declines what they were shown - they can never edit the
-- price, the frequency or anything else, and neither can the teacher after the
-- parent has confirmed.
create or replace function public.tutoring_agreements_guard()
returns trigger
language plpgsql
as $$
begin
  if new.id              is distinct from old.id
     or new.relationship_id is distinct from old.relationship_id
     or new.parent_id    is distinct from old.parent_id
     or new.teacher_id   is distinct from old.teacher_id
     or new.student_id   is distinct from old.student_id
     or new.subject      is distinct from old.subject
     or new.start_date   is distinct from old.start_date
     or new.frequency    is distinct from old.frequency
     or new.lessons_per_week is distinct from old.lessons_per_week
     or new.lesson_minutes   is distinct from old.lesson_minutes
     or new.price        is distinct from old.price
     or new.price_unit   is distinct from old.price_unit
     or new.currency     is distinct from old.currency
     or new.teaching_mode is distinct from old.teaching_mode
     or new.location_area is distinct from old.location_area
     or new.payment_method is distinct from old.payment_method
     or new.payment_frequency is distinct from old.payment_frequency
     or new.proposed_at  is distinct from old.proposed_at
     or new.created_at   is distinct from old.created_at
  then
    raise exception 'tutoring_agreements: the agreed terms cannot be changed';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'proposed'  and new.status in ('confirmed', 'declined', 'cancelled'))
      or (old.status = 'confirmed' and new.status in ('active', 'cancelled'))
      or (old.status = 'active'    and new.status = 'cancelled')
    ) then
      raise exception 'tutoring_agreements: illegal status transition % -> %',
        old.status, new.status;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists tutoring_agreements_guard on public.tutoring_agreements;
create trigger tutoring_agreements_guard
  before update on public.tutoring_agreements
  for each row execute function public.tutoring_agreements_guard();

alter table public.tutoring_agreements enable row level security;

-- Only the two parties to the arrangement (and an admin) can read it.
drop policy if exists "agreements: parties can select" on public.tutoring_agreements;
create policy "agreements: parties can select"
  on public.tutoring_agreements
  for select
  to authenticated
  using (
    auth.uid() = parent_id
    or auth.uid() = teacher_id
    or public.is_platform_admin()
  );

-- No write policies at all: proposing, confirming and declining are functions.
grant select on public.tutoring_agreements to authenticated;


-- -----------------------------------------------------------------------------
-- 2. Proposing
-- -----------------------------------------------------------------------------
-- Refuses unless the caller is the teacher on an ACCEPTED relationship AND is
-- verified. The student is taken from the relationship, not from the caller, so
-- a teacher can never slip an unrelated child into a proposal.
-- -----------------------------------------------------------------------------

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

  -- Verification is a trust gate and it comes first.
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
     coalesce(p_payment_method, 'edu237'),
     coalesce(p_payment_frequency, 'per_month'))
  returning * into v_row;

  -- Tell the parent there is something to review.
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


-- -----------------------------------------------------------------------------
-- 3. Parent confirms or declines
-- -----------------------------------------------------------------------------

create or replace function public.confirm_tutoring_agreement(p_agreement_id uuid)
returns public.tutoring_agreements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row  public.tutoring_agreements;
  v_child text;
begin
  select * into v_row from public.tutoring_agreements
   where id = p_agreement_id for update;
  if not found then
    raise exception 'Tutoring arrangement not found';
  end if;
  if v_row.parent_id <> auth.uid() then
    raise exception 'Only the parent can confirm this arrangement';
  end if;
  -- Confirming twice is a no-op rather than an error.
  if v_row.status = 'confirmed' or v_row.status = 'active' then
    return v_row;
  end if;
  if v_row.status <> 'proposed' then
    raise exception 'This arrangement can no longer be confirmed';
  end if;

  update public.tutoring_agreements
     set status = 'confirmed', parent_confirmed_at = now()
   where id = v_row.id
  returning * into v_row;

  -- Set up the monthly billing the parent just agreed to, but ONLY for
  -- Camiva-managed payment. A direct arrangement is not tracked as Camiva
  -- money, so it gets no billing record and no reminders.
  if v_row.payment_method = 'edu237' then
    insert into public.relationship_billing
      (relationship_id, teacher_id, parent_id, monthly_amount, currency,
       started_on, due_day)
    values
      (v_row.relationship_id, v_row.teacher_id, v_row.parent_id,
       public.agreement_monthly_amount(v_row), v_row.currency,
       v_row.start_date,
       least(greatest(extract(day from v_row.start_date)::smallint, 1), 28))
    on conflict (relationship_id) do update
      set monthly_amount = excluded.monthly_amount,
          started_on     = excluded.started_on,
          active         = true;
  end if;

  select s.name into v_child from public.students s where s.id = v_row.student_id;

  -- The teacher is told the parent confirmed - this is the moment the Platform
  -- Charge becomes due, and not a moment earlier.
  insert into public.payment_reminders
    (user_id, kind, title, body, relationship_id)
  values
    (v_row.teacher_id, 'agreement_update', 'Tutoring arrangement confirmed',
     coalesce(v_child, 'The parent') ||
       ' - the parent confirmed. Activate the relationship to continue.',
     v_row.relationship_id);

  return v_row;
end;
$$;

revoke execute on function public.confirm_tutoring_agreement(uuid) from public, anon;
grant execute on function public.confirm_tutoring_agreement(uuid) to authenticated;


create or replace function public.decline_tutoring_agreement(
  p_agreement_id uuid,
  p_reason       text default null
)
returns public.tutoring_agreements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.tutoring_agreements;
begin
  select * into v_row from public.tutoring_agreements
   where id = p_agreement_id for update;
  if not found then
    raise exception 'Tutoring arrangement not found';
  end if;
  if v_row.parent_id <> auth.uid() then
    raise exception 'Only the parent can decline this arrangement';
  end if;
  if v_row.status <> 'proposed' then
    return v_row;
  end if;

  update public.tutoring_agreements
     set status = 'declined',
         parent_declined_at = now(),
         decline_reason = nullif(btrim(coalesce(p_reason, '')), '')
   where id = v_row.id
  returning * into v_row;

  insert into public.payment_reminders
    (user_id, kind, title, body, relationship_id)
  values
    (v_row.teacher_id, 'agreement_update', 'Tutoring arrangement declined',
     coalesce(v_row.decline_reason,
              'The parent declined this arrangement. You can propose new terms.'),
     v_row.relationship_id);

  return v_row;
end;
$$;

revoke execute on function
  public.decline_tutoring_agreement(uuid, text) from public, anon;
grant execute on function
  public.decline_tutoring_agreement(uuid, text) to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Expected payment, derived from the agreed terms
-- -----------------------------------------------------------------------------
-- The monthly figure the parent agreed to, normalised from whatever unit the
-- teacher priced in. 4.33 weeks per month is the usual convention and keeps a
-- weekly price honest across a month.
--
-- This is the EXPECTED amount. It is never a payment: only a Fapshi-confirmed
-- transaction marks anything paid.
-- -----------------------------------------------------------------------------

create or replace function public.agreement_monthly_amount(
  a public.tutoring_agreements
)
returns integer
language sql
immutable
as $$
  select case a.price_unit
    when 'per_month'  then a.price
    when 'per_week'   then round(a.price * 4.33)::integer
    when 'per_lesson' then round(a.price * a.lessons_per_week * 4.33)::integer
  end;
$$;

grant execute on function
  public.agreement_monthly_amount(public.tutoring_agreements) to authenticated;


-- What the parent is expected to pay, and when, in the terms they agreed.
create or replace function public.agreement_expected_payment(p_agreement_id uuid)
returns table (
  amount    integer,
  currency  text,
  due_on    date,
  frequency text,
  is_edu237 boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  a public.tutoring_agreements;
begin
  select * into a from public.tutoring_agreements where id = p_agreement_id;
  if not found then
    return;
  end if;
  if auth.uid() not in (a.parent_id, a.teacher_id)
     and not public.is_platform_admin() then
    return;
  end if;

  return query select
    case a.payment_frequency
      when 'per_lesson' then
        case a.price_unit
          when 'per_lesson' then a.price
          when 'per_week'   then round(a.price / greatest(a.lessons_per_week, 1))::integer
          when 'per_month'  then round(a.price / greatest(a.lessons_per_week * 4.33, 1))::integer
        end
      when 'per_week' then
        case a.price_unit
          when 'per_lesson' then a.price * a.lessons_per_week
          when 'per_week'   then a.price
          when 'per_month'  then round(a.price / 4.33)::integer
        end
      else public.agreement_monthly_amount(a)
    end,
    a.currency,
    a.start_date,
    a.payment_frequency,
    (a.payment_method = 'edu237');
end;
$$;

grant execute on function public.agreement_expected_payment(uuid) to authenticated;


-- The live agreement for a relationship, for whichever side is asking.
create or replace function public.relationship_agreement(p_relationship_id uuid)
returns public.tutoring_agreements
language sql
stable
security definer
set search_path = public
as $$
  select a.* from public.tutoring_agreements a
   where a.relationship_id = p_relationship_id
     and a.status in ('proposed', 'confirmed', 'active')
     and (auth.uid() in (a.parent_id, a.teacher_id) or public.is_platform_admin())
   limit 1;
$$;

grant execute on function public.relationship_agreement(uuid) to authenticated;
