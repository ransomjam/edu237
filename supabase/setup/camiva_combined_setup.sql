-- =============================================================================
-- Camiva - combined setup script
-- =============================================================================
--
-- Every migration from 14 August onward, concatenated in dependency order so
-- the whole schema can be applied in ONE run of the Supabase SQL editor.
--
-- HOW TO RUN
--   SQL Editor -> New query -> paste this whole file -> Run.
--
-- SAFE TO RE-RUN. Every statement uses create-if-not-exists / create-or-replace
-- / drop-if-exists, so applying it to a database that already has some of these
-- objects simply brings the rest into line.
--
-- ALL OR NOTHING. The editor runs this in a single transaction: if any
-- statement fails, nothing is applied and the error names the exact line. That
-- is deliberate - a half-applied schema is worse than none.
--
-- GENERATED FILE. Built from supabase/migrations/ by concatenating the files
-- listed below. Do not edit this copy; edit the migration and regenerate, or
-- the two will disagree.
--
-- Later files rewrite functions defined by earlier ones (the service plan
-- supersedes the earlier relationship-charge rules, for example). Running them
-- in this order is what produces the current model.
--
-- Contains:
--   20260814000000_teacher_availability.sql
--   20260814010000_lesson_sessions.sql
--   20260814020000_profile_photos_storage.sql
--   20260814030000_teacher_title.sql
--   20260814040000_teacher_fee.sql
--   20260815000000_payments.sql
--   20260815010000_payments_grants.sql
--   20260816000000_manual_payouts.sql
--   20260816010000_admin_payments.sql
--   20260817000000_monthly_billing.sql
--   20260817010000_reminders_and_push.sql
--   20260818000000_teacher_verification.sql
--   20260818010000_tutoring_agreements.sql
--   20260818020000_platform_charge_gate.sql
--   20260819000000_teacher_service_plan.sql
--   20260820000000_push_token_register.sql
-- =============================================================================


-- ===========================================================================
-- BEGIN 20260814000000_teacher_availability.sql
-- ===========================================================================

-- =============================================================================
-- Camiva — teacher_availability (recurring weekly availability)
-- =============================================================================
--
-- A teacher declares when they are normally available to teach, as a simple
-- recurring weekly schedule: at most ONE window per weekday (e.g. "Monday
-- 4:00 PM – 8:00 PM"). A weekday with no row means "Unavailable".
--
-- Deliberately NOT a calendar: no dates, no recurrence engine, no exceptions.
-- Just the weekly shape that makes availability-aware scheduling possible.
--
-- Representation
--   * weekday       : 1..7 following Dart's DateTime.weekday (Mon=1 … Sun=7),
--                     so the client never has to remap.
--   * start_minute  : minutes from midnight, 0..1439 (e.g. 16:00 → 960).
--   * end_minute    : minutes from midnight, 1..1440 (end may be 24:00 = 1440).
--   * end_minute must be strictly greater than start_minute.
--   * At most one window per (teacher, weekday) — enforced by a unique index.
--
-- RLS
--   * Any authenticated user may READ availability (it is part of the public
--     teacher profile a parent uses to decide before requesting).
--   * Only the owning teacher may INSERT / UPDATE / DELETE their own rows.
--
-- Additive only: no existing table or data is modified.
-- =============================================================================

create table if not exists public.teacher_availability (
  id           uuid        primary key default gen_random_uuid(),
  teacher_id   uuid        not null references auth.users (id) on delete cascade,
  weekday      smallint    not null
                 constraint teacher_availability_weekday_check
                 check (weekday between 1 and 7),
  start_minute integer     not null
                 constraint teacher_availability_start_check
                 check (start_minute between 0 and 1439),
  end_minute   integer     not null
                 constraint teacher_availability_end_check
                 check (end_minute between 1 and 1440),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  constraint teacher_availability_order_check
    check (end_minute > start_minute)
);

-- At most one window per teacher per weekday (MVP: a single daily window).
create unique index if not exists teacher_availability_teacher_weekday_unique
  on public.teacher_availability (teacher_id, weekday);

create index if not exists teacher_availability_teacher_idx
  on public.teacher_availability (teacher_id);

drop trigger if exists teacher_availability_set_updated_at on public.teacher_availability;
create trigger teacher_availability_set_updated_at
  before update on public.teacher_availability
  for each row execute function public.set_updated_at();

alter table public.teacher_availability enable row level security;

-- ---- SELECT: any authenticated user (discovery) ---------------------------
drop policy if exists "ta: authenticated can read" on public.teacher_availability;
create policy "ta: authenticated can read"
  on public.teacher_availability
  for select
  using (auth.uid() is not null);

-- ---- INSERT: owner only ----------------------------------------------------
drop policy if exists "ta: owner can insert" on public.teacher_availability;
create policy "ta: owner can insert"
  on public.teacher_availability
  for insert
  with check (auth.uid() = teacher_id);

-- ---- UPDATE: owner only ----------------------------------------------------
drop policy if exists "ta: owner can update" on public.teacher_availability;
create policy "ta: owner can update"
  on public.teacher_availability
  for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

-- ---- DELETE: owner only ----------------------------------------------------
drop policy if exists "ta: owner can delete" on public.teacher_availability;
create policy "ta: owner can delete"
  on public.teacher_availability
  for delete
  using (auth.uid() = teacher_id);

-- END 20260814000000_teacher_availability.sql


-- ===========================================================================
-- BEGIN 20260814010000_lesson_sessions.sql
-- ===========================================================================

-- =============================================================================
-- Camiva — lesson_sessions (actual scheduled lessons)
-- =============================================================================
--
-- Once a teacher has ACCEPTED a parent's request, an active
-- parent_teacher_relationship exists. A lesson_session is ONE real, scheduled
-- lesson built on top of that relationship:
--
--     relationship (who teaches whom)  →  lesson_session (a specific lesson)
--
-- The relationship is the source of truth for the parties. We deliberately do
-- NOT re-store the parent/student/teacher identities as editable fields — the
-- teacher_id / student_id / parent_id on the session are DERIVED from the
-- relationship by a BEFORE INSERT trigger, so a session can never point at a
-- student the teacher is not actually connected to.
--
-- MVP scope (intentionally small):
--   * Teacher creates the session; the parent views/confirms it.
--   * One teacher → one student per session (no group lessons).
--   * Status is a flat set, not a state machine: scheduled | completed |
--     cancelled | missed.
--   * A single 30-minute reminder is expressed as reminder_minutes_before; the
--     reminder itself is computed from scheduled_at (see the app-side planner).
--
-- Denormalised, read-only display snapshots (student_name, teacher_name) are
-- filled by the trigger so both sides can render a card without extra joins or
-- widened RLS — mirroring the teacher_requests snapshot pattern.
-- =============================================================================

create table if not exists public.lesson_sessions (
  id                     uuid        primary key default gen_random_uuid(),
  relationship_id        uuid        not null
                           references public.parent_teacher_relationships (id) on delete cascade,
  teacher_id             uuid        not null references auth.users (id) on delete cascade,
  student_id             uuid        not null references public.students (id) on delete cascade,
  parent_id              uuid        not null references auth.users (id) on delete cascade,
  subject                text        not null,
  scheduled_at           timestamptz not null,
  duration_minutes       integer     not null default 60
                           constraint lesson_sessions_duration_check
                           check (duration_minutes between 15 and 480),
  teaching_mode          text        not null default 'in_person'
                           constraint lesson_sessions_mode_check
                           check (teaching_mode in ('online', 'in_person', 'both')),
  location_area          text,
  location_city          text,
  status                 text        not null default 'scheduled'
                           constraint lesson_sessions_status_check
                           check (status in ('scheduled', 'completed', 'cancelled', 'missed')),
  note                   text,
  reminder_minutes_before integer    not null default 30
                           constraint lesson_sessions_reminder_check
                           check (reminder_minutes_before between 0 and 240),
  -- Read-only display snapshots (see trigger below).
  student_name           text,
  teacher_name           text,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

create index if not exists lesson_sessions_teacher_idx
  on public.lesson_sessions (teacher_id);
create index if not exists lesson_sessions_student_idx
  on public.lesson_sessions (student_id);
create index if not exists lesson_sessions_parent_idx
  on public.lesson_sessions (parent_id);
create index if not exists lesson_sessions_relationship_idx
  on public.lesson_sessions (relationship_id);
create index if not exists lesson_sessions_scheduled_at_idx
  on public.lesson_sessions (scheduled_at);
create index if not exists lesson_sessions_status_idx
  on public.lesson_sessions (status);

drop trigger if exists lesson_sessions_set_updated_at on public.lesson_sessions;
create trigger lesson_sessions_set_updated_at
  before update on public.lesson_sessions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Prevent double-booking: a teacher cannot have two SCHEDULED sessions
-- whose time ranges overlap. Completed/cancelled/missed sessions are ignored so
-- history never blocks new scheduling. Implemented via trigger.
-- ---------------------------------------------------------------------------
create or replace function public.lesson_sessions_check_overlap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'scheduled' and exists (
    select 1 from public.lesson_sessions
    where teacher_id = new.teacher_id
      and status = 'scheduled'
      and id <> coalesce(new.id, '00000000-0000-0000-0000-000000000000'::uuid)
      and scheduled_at < (new.scheduled_at + (new.duration_minutes * interval '1 minute'))
      and (scheduled_at + (duration_minutes * interval '1 minute')) > new.scheduled_at
  ) then
    raise exception 'That time clashes with another lesson.';
  end if;
  return new;
end;
$$;

drop trigger if exists lesson_sessions_check_overlap on public.lesson_sessions;
create trigger lesson_sessions_check_overlap
  before insert or update on public.lesson_sessions
  for each row execute function public.lesson_sessions_check_overlap();

-- ---------------------------------------------------------------------------
-- Derive parties + snapshots from the relationship. Runs as owner so it can
-- read the relationship / student / teacher rows regardless of the caller's
-- RLS, but it VALIDATES that the relationship is accepted before allowing the
-- insert. The RLS WITH CHECK (evaluated after this BEFORE trigger) then
-- confirms the caller is the derived teacher.
-- ---------------------------------------------------------------------------
create or replace function public.lesson_sessions_fill_from_relationship()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  rel public.parent_teacher_relationships;
  stu public.students;
  v_teacher_name text;
begin
  select * into rel
    from public.parent_teacher_relationships
    where id = new.relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;
  if rel.status <> 'accepted' then
    raise exception 'Cannot schedule on a relationship that is not active';
  end if;

  -- Parties always come from the relationship — never trusted from the client.
  new.teacher_id := rel.teacher_id;
  new.student_id := rel.student_id;
  new.parent_id  := rel.parent_id;

  select * into stu from public.students where id = rel.student_id;
  if found then
    new.student_name := stu.name;
  end if;

  select display_name into v_teacher_name
    from public.teacher_profiles where user_id = rel.teacher_id;
  if v_teacher_name is null then
    select name into v_teacher_name
      from public.user_profiles where id = rel.teacher_id;
  end if;
  new.teacher_name := v_teacher_name;

  return new;
end;
$$;

drop trigger if exists lesson_sessions_fill_from_relationship on public.lesson_sessions;
create trigger lesson_sessions_fill_from_relationship
  before insert on public.lesson_sessions
  for each row execute function public.lesson_sessions_fill_from_relationship();

alter table public.lesson_sessions enable row level security;

-- ---- SELECT ---------------------------------------------------------------
-- Teacher sees sessions they teach; parent sees sessions for their children.
drop policy if exists "ls: teacher can select own" on public.lesson_sessions;
create policy "ls: teacher can select own"
  on public.lesson_sessions
  for select
  using (auth.uid() = teacher_id);

drop policy if exists "ls: parent can select own" on public.lesson_sessions;
create policy "ls: parent can select own"
  on public.lesson_sessions
  for select
  using (auth.uid() = parent_id);

-- ---- INSERT ---------------------------------------------------------------
-- Only the teacher of an ACCEPTED relationship may create a session. The
-- trigger has already set teacher_id from the relationship, so requiring
-- auth.uid() = teacher_id here means a caller can only insert for a
-- relationship where THEY are the teacher. The relationship existence/ownership
-- is re-checked so a parent (or another teacher) can never insert.
drop policy if exists "ls: teacher can insert for active relationship" on public.lesson_sessions;
create policy "ls: teacher can insert for active relationship"
  on public.lesson_sessions
  for insert
  with check (
    auth.uid() = teacher_id
    and status = 'scheduled'
    and exists (
      select 1 from public.parent_teacher_relationships r
      where r.id = relationship_id
        and r.teacher_id = auth.uid()
        and r.student_id = lesson_sessions.student_id
        and r.parent_id  = lesson_sessions.parent_id
        and r.status = 'accepted'
    )
  );

-- ---- UPDATE ---------------------------------------------------------------
-- The teacher owns the lifecycle: reschedule, mark completed/missed/cancelled,
-- add a note. They can never move a session to another teacher.
drop policy if exists "ls: teacher can update own" on public.lesson_sessions;
create policy "ls: teacher can update own"
  on public.lesson_sessions
  for update
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);

-- Parents are intentionally read-only in the MVP (teacher-created scheduling).
-- No parent INSERT/UPDATE/DELETE policy is granted.

-- ---- DELETE ---------------------------------------------------------------
-- The teacher may delete a session they own (e.g. created by mistake).
drop policy if exists "ls: teacher can delete own" on public.lesson_sessions;
create policy "ls: teacher can delete own"
  on public.lesson_sessions
  for delete
  using (auth.uid() = teacher_id);

-- END 20260814010000_lesson_sessions.sql


-- ===========================================================================
-- BEGIN 20260814020000_profile_photos_storage.sql
-- ===========================================================================

-- =============================================================================
-- Camiva — profile-photos Supabase Storage bucket + RLS
-- =============================================================================
--
-- Creates a dedicated storage bucket for teacher (and future parent) profile
-- photos. The bucket is PUBLIC so that profile photos can be displayed on
-- public teacher profiles without signed URLs.
--
-- RLS policies:
--   * Anyone (including anonymous) may READ objects — profile photos are
--     intentionally public content.
--   * Only an authenticated user may INSERT / UPDATE / DELETE files under
--     their own path prefix ({user_id}/…). This prevents one user from
--     modifying another's photo.
--
-- The client stores the resulting public URL (or storage path) in the
-- teacher_profiles.photo_url column (already present from an earlier
-- migration).
--
-- Additive only: no existing tables or data are modified.
-- =============================================================================

-- 1. Create the bucket (idempotent — Supabase ignores if it already exists)
insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', true)
on conflict (id) do nothing;

-- 2. RLS policies on storage.objects for this bucket

-- Allow anyone to read profile photos (they are public content).
drop policy if exists "profile-photos: public read" on storage.objects;
create policy "profile-photos: public read"
  on storage.objects
  for select
  using (bucket_id = 'profile-photos');

-- Allow authenticated users to upload their own photo (path must start with
-- their auth.uid()).
drop policy if exists "profile-photos: owner can insert" on storage.objects;
create policy "profile-photos: owner can insert"
  on storage.objects
  for insert
  with check (
    bucket_id = 'profile-photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow authenticated users to update (replace) their own photo.
drop policy if exists "profile-photos: owner can update" on storage.objects;
create policy "profile-photos: owner can update"
  on storage.objects
  for update
  using (
    bucket_id = 'profile-photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Allow authenticated users to delete their own photo.
drop policy if exists "profile-photos: owner can delete" on storage.objects;
create policy "profile-photos: owner can delete"
  on storage.objects
  for delete
  using (
    bucket_id = 'profile-photos'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- END 20260814020000_profile_photos_storage.sql


-- ===========================================================================
-- BEGIN 20260814030000_teacher_title.sql
-- ===========================================================================

-- =============================================================================
-- Camiva — teacher_profiles title field (additive)
-- =============================================================================
--
-- Adds honorific title (e.g. 'Mr', 'Mrs', 'Ms', 'Dr', 'Prof', 'Engr') to
-- teacher profiles. Nullable, optional, and defaults to null.
-- =============================================================================

alter table public.teacher_profiles
  add column if not exists title text;

-- END 20260814030000_teacher_title.sql


-- ===========================================================================
-- BEGIN 20260814040000_teacher_fee.sql
-- ===========================================================================

-- =============================================================================
-- Camiva — teacher_profiles hourly_rate field (additive)
-- =============================================================================
alter table public.teacher_profiles
  add column if not exists hourly_rate integer not null default 5000;

-- END 20260814040000_teacher_fee.sql


-- ===========================================================================
-- BEGIN 20260815000000_payments.sql
-- ===========================================================================

-- =============================================================================
-- Camiva — commercial layer: payments, activations, earnings, withdrawals
-- =============================================================================
--
-- This migration is ADDITIVE. It creates new tables and functions and adds one
-- nullable column to user_profiles. No existing table is dropped or narrowed.
--
-- DESIGN RULES ENCODED HERE
-- -----------------------------------------------------------------------------
--  1. The ledger is the source of truth. There is no mutable "balance" column
--     anywhere: earnings and available funds are DERIVED from
--     payment_transactions and withdrawals (see teacher_earnings_summary()).
--
--  2. The client can never write financial state. payment_transactions,
--     withdrawals and payment_events have NO insert/update/delete policies for
--     authenticated users. Every write happens through a SECURITY DEFINER
--     function; the ones that record provider outcomes are executable only by
--     the service role (used from the Edge Functions), never from the app.
--
--  3. The client never sends an amount. Amounts are computed server-side from
--     platform_fee_config (fees) or teacher_profiles.hourly_rate (tutoring).
--
--  4. Prices are CONFIGURATION, not schema. platform_fee_config ships with NULL
--     amounts and match activation switched off, so nothing is charged until an
--     operator sets real values. No price is hard-coded as a business rule.
--
--  5. Relationship activation is DERIVED from the ledger
--     (relationship_activation_state), so a relationship can never drift out of
--     sync with whether its activation payment actually succeeded.
--
--  6. Transactions are effectively immutable: a trigger rejects any change to
--     the money-defining columns and allows only legal status transitions.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. platform_fee_config — the single, operator-managed pricing row
-- -----------------------------------------------------------------------------
-- Every commercial amount in Camiva is read from here. Final pricing is NOT
-- decided in code: the row ships empty (NULL amounts, activation not required)
-- and an operator sets values with a normal UPDATE, e.g.
--
--   update public.platform_fee_config set
--     teacher_service_fee_amount = 1000,   -- current target range 500–1000 XAF
--     match_activation_fee_amount = 1000,
--     match_activation_required = true
--   where id = 1;
--
-- Reading it is allowed for any signed-in user (the app must be able to show
-- the exact fee before charging). Writing is service-role only — there is no
-- update policy for authenticated users.
-- -----------------------------------------------------------------------------

create table if not exists public.platform_fee_config (
  id                                smallint    primary key default 1
                                      constraint platform_fee_config_singleton
                                      check (id = 1),
  currency                          text        not null default 'XAF',

  -- Recurring Camiva service fee charged to a teacher. NULL = not configured,
  -- and therefore not charged.
  teacher_service_fee_amount        integer
                                      constraint pfc_service_fee_positive
                                      check (teacher_service_fee_amount is null
                                             or teacher_service_fee_amount > 0),
  teacher_service_fee_interval_days integer     not null default 30
                                      constraint pfc_service_fee_interval_check
                                      check (teacher_service_fee_interval_days between 1 and 366),

  -- One-time charge applied when a new parent–teacher relationship is
  -- activated. Only applied when match_activation_required is true AND an
  -- amount is set.
  match_activation_fee_amount       integer
                                      constraint pfc_match_fee_positive
                                      check (match_activation_fee_amount is null
                                             or match_activation_fee_amount > 0),
  match_activation_required         boolean     not null default false,

  -- Share of a successful tutoring payment that becomes teacher earnings, in
  -- basis points. Ships at 10000 = 100%: Camiva takes NO percentage of a lesson
  -- by default. This exists so settlement rules stay configurable, not to
  -- introduce a commission.
  teacher_earning_bps               integer     not null default 10000
                                      constraint pfc_teacher_earning_bps_check
                                      check (teacher_earning_bps between 0 and 10000),

  -- How long after a successful tutoring payment the money becomes withdrawable
  -- ("Pending" until then).
  settlement_delay_hours            integer     not null default 24
                                      constraint pfc_settlement_delay_check
                                      check (settlement_delay_hours between 0 and 720),

  -- Fapshi rejects amounts below 100 XAF, so this is a provider floor, not a
  -- pricing decision.
  min_withdrawal_amount             integer     not null default 100
                                      constraint pfc_min_withdrawal_check
                                      check (min_withdrawal_amount >= 100),

  updated_at                        timestamptz not null default now()
);

insert into public.platform_fee_config (id) values (1)
  on conflict (id) do nothing;

drop trigger if exists platform_fee_config_set_updated_at on public.platform_fee_config;
create trigger platform_fee_config_set_updated_at
  before update on public.platform_fee_config
  for each row execute function public.set_updated_at();

alter table public.platform_fee_config enable row level security;

drop policy if exists "fee_config: signed-in can read" on public.platform_fee_config;
create policy "fee_config: signed-in can read"
  on public.platform_fee_config
  for select
  to authenticated
  using (true);
-- No insert/update/delete policy: pricing is changed by the service role only.


-- -----------------------------------------------------------------------------
-- 2. payment_transactions — the internal ledger
-- -----------------------------------------------------------------------------
-- One row per money movement Camiva attempts to collect. The row is created
-- BEFORE the provider is called (status 'pending') so nothing can be collected
-- without a matching internal record.
--
-- purpose:
--   teacher_service_fee — recurring Camiva service fee, paid by a teacher
--   match_activation    — one-time relationship activation, paid by a teacher
--   tutoring_payment    — parent paying for tutoring
-- -----------------------------------------------------------------------------

create table if not exists public.payment_transactions (
  id                          uuid        primary key default gen_random_uuid(),

  purpose                     text        not null
                                constraint payment_transactions_purpose_check
                                check (purpose in ('teacher_service_fee',
                                                   'match_activation',
                                                   'tutoring_payment')),

  -- Who is paying. Always an authenticated user.
  payer_id                    uuid        not null references auth.users (id) on delete cascade,

  -- Context. Which of these are set depends on the purpose; all are optional at
  -- the schema level and enforced per-purpose by create_payment_intent().
  parent_id                   uuid        references auth.users (id) on delete set null,
  teacher_id                  uuid        references auth.users (id) on delete set null,
  student_id                  uuid        references public.students (id) on delete set null,
  relationship_id             uuid        references public.parent_teacher_relationships (id) on delete set null,
  -- Optional link to one scheduled lesson. Declared without a foreign key here
  -- and wired up below only if lesson_sessions exists, so the commercial layer
  -- can be applied to a project that does not have scheduling yet.
  session_id                  uuid,

  amount                      integer     not null
                                constraint payment_transactions_amount_check
                                check (amount >= 100),
  currency                    text        not null default 'XAF',

  status                      text        not null default 'pending'
                                constraint payment_transactions_status_check
                                check (status in ('pending', 'successful', 'failed',
                                                  'cancelled', 'refunded')),

  provider                    text        not null default 'fapshi',
  -- Fapshi transId. Unique so a provider transaction can never be recorded
  -- against two internal rows.
  provider_trans_id           text        unique,
  provider_medium             text,
  provider_financial_trans_id text,
  -- Fapshi-hosted checkout link (Initiate Pay). Never shown for payouts.
  checkout_url                text,

  description                 text,
  failure_reason              text,

  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  paid_at                     timestamptz
);

-- Add the scheduled-lesson foreign key only when that table is present.
do $$
begin
  if to_regclass('public.lesson_sessions') is not null
     and not exists (
       select 1 from pg_constraint
        where conname = 'payment_transactions_session_id_fkey'
     ) then
    alter table public.payment_transactions
      add constraint payment_transactions_session_id_fkey
      foreign key (session_id) references public.lesson_sessions (id)
      on delete set null;
  end if;
end $$;

-- The tutoring price comes from the teacher's rate, so make sure the column is
-- there. This mirrors the teacher_fee migration and is a no-op when it ran.
alter table public.teacher_profiles
  add column if not exists hourly_rate integer not null default 5000;

create index if not exists payment_transactions_payer_idx
  on public.payment_transactions (payer_id, created_at desc);
create index if not exists payment_transactions_teacher_idx
  on public.payment_transactions (teacher_id, created_at desc);
create index if not exists payment_transactions_parent_idx
  on public.payment_transactions (parent_id, created_at desc);
create index if not exists payment_transactions_relationship_idx
  on public.payment_transactions (relationship_id);
create index if not exists payment_transactions_status_idx
  on public.payment_transactions (status);

-- At most ONE in-flight or successful activation payment per relationship, so a
-- duplicated tap or a replayed webhook can never charge twice for one match.
create unique index if not exists payment_transactions_activation_unique
  on public.payment_transactions (relationship_id)
  where purpose = 'match_activation' and status in ('pending', 'successful');

drop trigger if exists payment_transactions_set_updated_at on public.payment_transactions;
create trigger payment_transactions_set_updated_at
  before update on public.payment_transactions
  for each row execute function public.set_updated_at();

-- ---- immutability + legal status transitions --------------------------------
create or replace function public.payment_transactions_guard()
returns trigger
language plpgsql
as $$
begin
  -- Money-defining columns are immutable once written.
  if new.id              is distinct from old.id
     or new.purpose      is distinct from old.purpose
     or new.payer_id     is distinct from old.payer_id
     or new.parent_id    is distinct from old.parent_id
     or new.teacher_id   is distinct from old.teacher_id
     or new.student_id   is distinct from old.student_id
     or new.relationship_id is distinct from old.relationship_id
     or new.session_id   is distinct from old.session_id
     or new.amount       is distinct from old.amount
     or new.currency     is distinct from old.currency
     or new.provider     is distinct from old.provider
     or new.created_at   is distinct from old.created_at
  then
    raise exception 'payment_transactions: immutable column changed';
  end if;

  -- The provider reference may be written once, never rewritten.
  if old.provider_trans_id is not null
     and new.provider_trans_id is distinct from old.provider_trans_id then
    raise exception 'payment_transactions: provider_trans_id is already set';
  end if;

  -- Legal transitions only. Re-applying the same status is a no-op (this is
  -- what makes repeated webhook delivery safe).
  if new.status is distinct from old.status then
    if not (
      (old.status = 'pending'    and new.status in ('successful', 'failed', 'cancelled'))
      or (old.status = 'successful' and new.status = 'refunded')
    ) then
      raise exception 'payment_transactions: illegal status transition % -> %',
        old.status, new.status;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists payment_transactions_guard on public.payment_transactions;
create trigger payment_transactions_guard
  before update on public.payment_transactions
  for each row execute function public.payment_transactions_guard();

alter table public.payment_transactions enable row level security;

-- A user may read a transaction they are financially party to: the payer, the
-- parent it was made for, or the teacher it relates to. Nothing else.
drop policy if exists "payments: party can select" on public.payment_transactions;
create policy "payments: party can select"
  on public.payment_transactions
  for select
  to authenticated
  using (
    auth.uid() = payer_id
    or auth.uid() = parent_id
    or auth.uid() = teacher_id
  );
-- Deliberately NO insert/update/delete policies. All writes go through the
-- SECURITY DEFINER functions below.


-- ---- display view -----------------------------------------------------------
-- A receipt has to say WHO and WHICH CHILD, not just an amount. This view adds
-- the child's name and the teacher's display name to each row.
--
-- security_invoker = on means the view runs with the CALLER's permissions, so
-- the RLS policies above still decide which rows are visible — the view widens
-- nothing. The joined names come from tables the caller can already read
-- (their own children; teacher profiles, which are readable for discovery).
create or replace view public.payment_history
with (security_invoker = on) as
  select
    t.*,
    s.name as student_name,
    tp.display_name as teacher_name
  from public.payment_transactions t
  left join public.students s on s.id = t.student_id
  left join public.teacher_profiles tp on tp.user_id = t.teacher_id;

grant select on public.payment_history to authenticated;


-- -----------------------------------------------------------------------------
-- 3. payment_events — provider callback audit log + idempotency key
-- -----------------------------------------------------------------------------
-- Every accepted webhook / verification result is recorded here first. The
-- unique key (provider_trans_id, provider_status) means a redelivered webhook
-- collides instead of being applied twice.
-- -----------------------------------------------------------------------------

create table if not exists public.payment_events (
  id                uuid        primary key default gen_random_uuid(),
  provider          text        not null default 'fapshi',
  provider_trans_id text        not null,
  provider_status   text        not null,
  -- 'webhook' | 'verify' — how we learned about this state.
  source            text        not null default 'webhook',
  payload           jsonb       not null default '{}'::jsonb,
  received_at       timestamptz not null default now()
);

create unique index if not exists payment_events_idempotency
  on public.payment_events (provider, provider_trans_id, provider_status);

create index if not exists payment_events_trans_idx
  on public.payment_events (provider_trans_id);

alter table public.payment_events enable row level security;
-- No policies at all: this table is service-role only.


-- -----------------------------------------------------------------------------
-- 4. teacher_payout_accounts — where a teacher's withdrawals are sent
-- -----------------------------------------------------------------------------
-- One row per teacher, owned by that teacher. RLS makes it impossible for a
-- user to read or change another teacher's payout destination.
-- -----------------------------------------------------------------------------

create table if not exists public.teacher_payout_accounts (
  teacher_id   uuid        primary key references auth.users (id) on delete cascade,
  -- Fapshi payout mediums.
  medium       text        not null default 'mobile money'
                 constraint payout_medium_check
                 check (medium in ('mobile money', 'orange money')),
  -- Cameroon mobile number in the local 9-digit form Fapshi expects (6XXXXXXXX).
  phone        text        not null
                 constraint payout_phone_check
                 check (phone ~ '^6[0-9]{8}$'),
  account_name text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

drop trigger if exists teacher_payout_accounts_set_updated_at on public.teacher_payout_accounts;
create trigger teacher_payout_accounts_set_updated_at
  before update on public.teacher_payout_accounts
  for each row execute function public.set_updated_at();

alter table public.teacher_payout_accounts enable row level security;

drop policy if exists "payout accounts: owner can select" on public.teacher_payout_accounts;
create policy "payout accounts: owner can select"
  on public.teacher_payout_accounts
  for select
  to authenticated
  using (auth.uid() = teacher_id);

drop policy if exists "payout accounts: owner can insert" on public.teacher_payout_accounts;
create policy "payout accounts: owner can insert"
  on public.teacher_payout_accounts
  for insert
  to authenticated
  with check (auth.uid() = teacher_id);

drop policy if exists "payout accounts: owner can update" on public.teacher_payout_accounts;
create policy "payout accounts: owner can update"
  on public.teacher_payout_accounts
  for update
  to authenticated
  using (auth.uid() = teacher_id)
  with check (auth.uid() = teacher_id);


-- -----------------------------------------------------------------------------
-- 5. withdrawals — teacher payout requests
-- -----------------------------------------------------------------------------
-- A withdrawal is never marked successful because the app said so: only a
-- confirmed provider payout status moves it there.
-- -----------------------------------------------------------------------------

create table if not exists public.withdrawals (
  id                uuid        primary key default gen_random_uuid(),
  teacher_id        uuid        not null references auth.users (id) on delete cascade,
  amount            integer     not null
                      constraint withdrawals_amount_check check (amount >= 100),
  currency          text        not null default 'XAF',
  status            text        not null default 'requested'
                      constraint withdrawals_status_check
                      check (status in ('requested', 'processing', 'successful',
                                        'failed', 'cancelled')),
  -- Snapshot of the destination at request time, so history stays truthful even
  -- if the teacher later changes their payout account.
  payout_medium     text        not null,
  payout_phone      text        not null,
  provider          text        not null default 'fapshi',
  provider_trans_id text        unique,
  failure_reason    text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  completed_at      timestamptz
);

create index if not exists withdrawals_teacher_idx
  on public.withdrawals (teacher_id, created_at desc);

-- At most one in-flight withdrawal per teacher.
create unique index if not exists withdrawals_in_flight_unique
  on public.withdrawals (teacher_id)
  where status in ('requested', 'processing');

drop trigger if exists withdrawals_set_updated_at on public.withdrawals;
create trigger withdrawals_set_updated_at
  before update on public.withdrawals
  for each row execute function public.set_updated_at();

create or replace function public.withdrawals_guard()
returns trigger
language plpgsql
as $$
begin
  if new.id            is distinct from old.id
     or new.teacher_id is distinct from old.teacher_id
     or new.amount     is distinct from old.amount
     or new.currency   is distinct from old.currency
     or new.created_at is distinct from old.created_at
  then
    raise exception 'withdrawals: immutable column changed';
  end if;

  if old.provider_trans_id is not null
     and new.provider_trans_id is distinct from old.provider_trans_id then
    raise exception 'withdrawals: provider_trans_id is already set';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'requested'  and new.status in ('processing', 'successful',
                                                    'failed', 'cancelled'))
      or (old.status = 'processing' and new.status in ('successful', 'failed'))
    ) then
      raise exception 'withdrawals: illegal status transition % -> %',
        old.status, new.status;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists withdrawals_guard on public.withdrawals;
create trigger withdrawals_guard
  before update on public.withdrawals
  for each row execute function public.withdrawals_guard();

alter table public.withdrawals enable row level security;

drop policy if exists "withdrawals: teacher can select own" on public.withdrawals;
create policy "withdrawals: teacher can select own"
  on public.withdrawals
  for select
  to authenticated
  using (auth.uid() = teacher_id);
-- No write policies: withdrawals are created by request_withdrawal() and only
-- ever advanced by confirmed provider status.


-- -----------------------------------------------------------------------------
-- 6. service_fee_periods — foundation for the recurring service fee
-- -----------------------------------------------------------------------------
-- Deliberately NOT a billing engine. One row per teacher per billing window,
-- carrying just enough state to show "due / reminded / paid / overdue".
-- -----------------------------------------------------------------------------

create table if not exists public.service_fee_periods (
  id              uuid        primary key default gen_random_uuid(),
  teacher_id      uuid        not null references auth.users (id) on delete cascade,
  period_start    date        not null,
  period_end      date        not null,
  amount          integer     not null
                    constraint service_fee_amount_check check (amount > 0),
  currency        text        not null default 'XAF',
  status          text        not null default 'due'
                    constraint service_fee_status_check
                    check (status in ('due', 'reminded', 'paid', 'overdue')),
  payment_id      uuid        references public.payment_transactions (id) on delete set null,
  reminder_sent_at timestamptz,
  paid_at         timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint service_fee_periods_unique unique (teacher_id, period_start)
);

create index if not exists service_fee_periods_teacher_idx
  on public.service_fee_periods (teacher_id, period_start desc);

drop trigger if exists service_fee_periods_set_updated_at on public.service_fee_periods;
create trigger service_fee_periods_set_updated_at
  before update on public.service_fee_periods
  for each row execute function public.set_updated_at();

alter table public.service_fee_periods enable row level security;

drop policy if exists "service fee: teacher can select own" on public.service_fee_periods;
create policy "service fee: teacher can select own"
  on public.service_fee_periods
  for select
  to authenticated
  using (auth.uid() = teacher_id);


-- -----------------------------------------------------------------------------
-- 7. payment_reminders — in-app reminder inbox
-- -----------------------------------------------------------------------------
-- These rows ARE the reminder: creating one makes it appear in the recipient's
-- in-app reminders list. There is no push infrastructure in the app yet, so
-- nothing here claims a push notification was delivered — delivered_channel is
-- 'in_app' and stays that way until a push transport actually exists.
-- -----------------------------------------------------------------------------

create table if not exists public.payment_reminders (
  id                uuid        primary key default gen_random_uuid(),
  user_id           uuid        not null references auth.users (id) on delete cascade,
  kind              text        not null
                      constraint payment_reminders_kind_check
                      -- The full set, including kinds added by later
                      -- migrations: a narrower list here would fail on re-run
                      -- once rows of those kinds exist.
                      check (kind in ('payment_received',
                                      'payment_failed',
                                      'payment_due',
                                      'service_fee_due',
                                      'service_fee_overdue',
                                      'relationship_activated',
                                      'verification_update',
                                      'agreement_update',
                                      'withdrawal_update')),
  title             text        not null,
  body              text        not null,
  payment_id        uuid        references public.payment_transactions (id) on delete set null,
  relationship_id   uuid        references public.parent_teacher_relationships (id) on delete set null,
  withdrawal_id     uuid        references public.withdrawals (id) on delete set null,
  delivered_channel text        not null default 'in_app'
                      constraint payment_reminders_channel_check
                      check (delivered_channel in ('in_app')),
  created_at        timestamptz not null default now(),
  read_at           timestamptz
);

create index if not exists payment_reminders_user_idx
  on public.payment_reminders (user_id, created_at desc);

alter table public.payment_reminders enable row level security;

drop policy if exists "reminders: owner can select" on public.payment_reminders;
create policy "reminders: owner can select"
  on public.payment_reminders
  for select
  to authenticated
  using (auth.uid() = user_id);

-- The owner may mark their own reminder read; nothing else is writable. The
-- policy grants UPDATE, and the guard below narrows it to read_at only, so a
-- user cannot rewrite the text of a reminder they received.
drop policy if exists "reminders: owner can mark read" on public.payment_reminders;
create policy "reminders: owner can mark read"
  on public.payment_reminders
  for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create or replace function public.payment_reminders_guard()
returns trigger
language plpgsql
as $$
begin
  if new.id                is distinct from old.id
     or new.user_id        is distinct from old.user_id
     or new.kind           is distinct from old.kind
     or new.title          is distinct from old.title
     or new.body           is distinct from old.body
     or new.payment_id     is distinct from old.payment_id
     or new.relationship_id is distinct from old.relationship_id
     or new.withdrawal_id  is distinct from old.withdrawal_id
     or new.delivered_channel is distinct from old.delivered_channel
     or new.created_at     is distinct from old.created_at
  then
    raise exception 'payment_reminders: only read_at may be updated';
  end if;
  return new;
end;
$$;

drop trigger if exists payment_reminders_guard on public.payment_reminders;
create trigger payment_reminders_guard
  before update on public.payment_reminders
  for each row execute function public.payment_reminders_guard();


-- -----------------------------------------------------------------------------
-- 8. support_requests — "Need help?" from a payment or relationship
-- -----------------------------------------------------------------------------
-- Not a dispute system. It captures the message plus the exact transaction /
-- relationship reference so the Camiva team can investigate. It promises
-- nothing about refunds or outcomes.
-- -----------------------------------------------------------------------------

create table if not exists public.support_requests (
  id              uuid        primary key default gen_random_uuid(),
  user_id         uuid        not null references auth.users (id) on delete cascade,
  payment_id      uuid        references public.payment_transactions (id) on delete set null,
  relationship_id uuid        references public.parent_teacher_relationships (id) on delete set null,
  withdrawal_id   uuid        references public.withdrawals (id) on delete set null,
  message         text        not null
                    constraint support_requests_message_check
                    check (char_length(btrim(message)) between 1 and 2000),
  status          text        not null default 'open'
                    constraint support_requests_status_check
                    check (status in ('open', 'in_review', 'closed')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index if not exists support_requests_user_idx
  on public.support_requests (user_id, created_at desc);

drop trigger if exists support_requests_set_updated_at on public.support_requests;
create trigger support_requests_set_updated_at
  before update on public.support_requests
  for each row execute function public.set_updated_at();

alter table public.support_requests enable row level security;

drop policy if exists "support: owner can select" on public.support_requests;
create policy "support: owner can select"
  on public.support_requests
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "support: owner can insert" on public.support_requests;
create policy "support: owner can insert"
  on public.support_requests
  for insert
  to authenticated
  with check (auth.uid() = user_id and status = 'open');


-- -----------------------------------------------------------------------------
-- 9. Contact details + gated reveal
-- -----------------------------------------------------------------------------
-- The app had no contact field at all. A nullable phone is added to
-- user_profiles; it is readable ONLY through relationship_contact() below,
-- because the existing user_profiles policies restrict every user to their own
-- row and are left untouched.
-- -----------------------------------------------------------------------------

alter table public.user_profiles
  add column if not exists phone text;

alter table public.user_profiles
  drop constraint if exists user_profiles_phone_check;
alter table public.user_profiles
  add constraint user_profiles_phone_check
  check (phone is null or phone ~ '^6[0-9]{8}$');


-- -----------------------------------------------------------------------------
-- 10. Derived state: is this relationship activated?
-- -----------------------------------------------------------------------------
-- Returns one of:
--   'not_required' — activation is switched off, or no fee is configured
--   'required'     — a fee applies and no activation payment has succeeded
--   'pending'      — an activation payment exists and is still in flight
--   'active'       — an activation payment succeeded
--
-- Because this reads the ledger rather than a stored flag, a relationship can
-- never appear activated without a successful payment behind it.
-- -----------------------------------------------------------------------------

create or replace function public.relationship_activation_state(p_relationship_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cfg public.platform_fee_config;
  v_status text;
begin
  select * into cfg from public.platform_fee_config where id = 1;

  if cfg is null
     or not cfg.match_activation_required
     or coalesce(cfg.match_activation_fee_amount, 0) <= 0 then
    return 'not_required';
  end if;

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

  return 'required';
end;
$$;

grant execute on function public.relationship_activation_state(uuid) to authenticated;


-- A relationship is operational when it is accepted AND activation is satisfied.
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
  and public.relationship_activation_state(p_relationship_id)
      in ('not_required', 'active');
$$;

grant execute on function public.relationship_is_operational(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 11. relationship_contact() — the ONLY way private contact details are read
-- -----------------------------------------------------------------------------
-- A teacher gets the parent's name and phone only once the relationship is
-- accepted AND its activation condition is satisfied. A parent gets the
-- teacher's contact once the relationship is accepted. Anyone else gets
-- nothing. Failing the condition returns a row with revealed = false rather
-- than raising, so the UI can render the locked state without leaking anything.
-- -----------------------------------------------------------------------------

create or replace function public.relationship_contact(p_relationship_id uuid)
returns table (revealed boolean, name text, phone text)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  rel public.parent_teacher_relationships;
  v_counterpart uuid;
begin
  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    return query select false, null::text, null::text;
    return;
  end if;

  if auth.uid() = rel.teacher_id then
    -- Teacher asking for the parent's details: gated on activation.
    if not public.relationship_is_operational(p_relationship_id) then
      return query select false, null::text, null::text;
      return;
    end if;
    v_counterpart := rel.parent_id;
  elsif auth.uid() = rel.parent_id then
    -- Parent asking for the teacher's details: gated on acceptance.
    if rel.status <> 'accepted' then
      return query select false, null::text, null::text;
      return;
    end if;
    v_counterpart := rel.teacher_id;
  else
    return query select false, null::text, null::text;
    return;
  end if;

  return query
    select true, p.name, p.phone
    from public.user_profiles p
    where p.id = v_counterpart;
end;
$$;

grant execute on function public.relationship_contact(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 12. payment_quote() — what this payment costs, decided server-side
-- -----------------------------------------------------------------------------
-- The single place a price is worked out. Both the screen (to show the exact
-- amount BEFORE charging) and create_payment_intent (to write it) call this, so
-- the figure a user approves is by construction the figure that gets charged.
--
-- It also carries every entitlement check, and raises rather than returning a
-- price the caller is not allowed to pay.
--
-- p_units is only meaningful for a tutoring payment: amount = hourly_rate ×
-- units, so a parent may pay for more than one session but never sets the price.
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
  cfg    public.platform_fee_config;
  rel    public.parent_teacher_relationships;
  v_uid  uuid := auth.uid();
  v_rate integer;
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
    return query select cfg.teacher_service_fee_amount, cfg.currency;
    return;
  end if;

  -- The remaining purposes are relationship-scoped.
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
    return query select cfg.match_activation_fee_amount, cfg.currency;
    return;

  elsif p_purpose = 'tutoring_payment' then
    if rel.parent_id <> v_uid then
      raise exception 'Only the parent can pay for this tutoring';
    end if;
    if not public.relationship_is_operational(p_relationship_id) then
      raise exception 'This relationship is not active yet';
    end if;

    select hourly_rate into v_rate
      from public.teacher_profiles
      where user_id = rel.teacher_id;
    if v_rate is null or v_rate <= 0 then
      raise exception 'This teacher has not set a rate yet';
    end if;

    return query select (v_rate * p_units)::integer, cfg.currency;
    return;
  end if;

  raise exception 'Unknown payment purpose: %', p_purpose;
end;
$$;

revoke execute on function public.payment_quote(text, uuid, integer) from public;
grant execute on function public.payment_quote(text, uuid, integer) to authenticated;


-- -----------------------------------------------------------------------------
-- 13. create_payment_intent() — the only way a transaction is born
-- -----------------------------------------------------------------------------
-- Runs as the CALLER's identity (auth.uid()), so it is safe to expose to the
-- app through an Edge Function that forwards the user's JWT. It takes the price
-- and the entitlement decision from payment_quote(), writes a 'pending' row and
-- returns it. The client never sends an amount.
-- -----------------------------------------------------------------------------

create or replace function public.create_payment_intent(
  p_purpose         text,
  p_relationship_id uuid default null,
  p_units           integer default 1,
  p_session_id      uuid default null
)
returns public.payment_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  rel      public.parent_teacher_relationships;
  v_uid    uuid := auth.uid();
  v_amount integer;
  v_currency text;
  v_row    public.payment_transactions;
begin
  -- Validates entitlement and prices the payment; raises if either fails.
  select q.amount, q.currency into v_amount, v_currency
    from public.payment_quote(p_purpose, p_relationship_id, p_units) q;

  if p_purpose = 'teacher_service_fee' then
    insert into public.payment_transactions
      (purpose, payer_id, teacher_id, amount, currency, description)
    values
      ('teacher_service_fee', v_uid, v_uid, v_amount, v_currency,
       'Camiva service fee')
    returning * into v_row;
    return v_row;
  end if;

  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;

  if p_purpose = 'match_activation' then
    insert into public.payment_transactions
      (purpose, payer_id, parent_id, teacher_id, student_id, relationship_id,
       amount, currency, description)
    values
      ('match_activation', v_uid, rel.parent_id, rel.teacher_id, rel.student_id,
       rel.id, v_amount, v_currency, 'Camiva relationship activation')
    returning * into v_row;
    return v_row;
  end if;

  -- tutoring_payment
  -- A session may be named only where scheduling exists, and only when it
  -- belongs to this relationship.
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
     rel.id, p_session_id, v_amount, v_currency, 'Tutoring payment')
  returning * into v_row;
  return v_row;
end;
$$;

revoke execute on function
  public.create_payment_intent(text, uuid, integer, uuid) from public;
grant execute on function
  public.create_payment_intent(text, uuid, integer, uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 13. Provider-facing functions — SERVICE ROLE ONLY
-- -----------------------------------------------------------------------------
-- These are what the Edge Functions call after talking to Fapshi. Execute is
-- revoked from anon/authenticated, so no app client can invoke them: this is
-- what makes it impossible for a client to forge a successful payment.
-- -----------------------------------------------------------------------------

-- Attach the provider reference right after the payment is created upstream.
create or replace function public.attach_payment_provider_ref(
  p_payment_id   uuid,
  p_trans_id     text,
  p_checkout_url text default null
)
returns public.payment_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payment_transactions;
begin
  update public.payment_transactions
     set provider_trans_id = p_trans_id,
         checkout_url = coalesce(p_checkout_url, checkout_url)
   where id = p_payment_id
     and provider_trans_id is null
  returning * into v_row;

  if not found then
    -- Either the row is gone or a reference is already attached; return the
    -- current row so the caller can decide, rather than corrupting state.
    select * into v_row from public.payment_transactions where id = p_payment_id;
  end if;

  return v_row;
end;
$$;

revoke execute on function
  public.attach_payment_provider_ref(uuid, text, text) from public, anon, authenticated;


-- Cancel a payment whose provider call never got off the ground (network error,
-- provider rejected the request). Only ever applied to a row with no provider
-- reference, so a real in-flight transaction can never be cancelled locally.
create or replace function public.fail_payment_intent(
  p_payment_id uuid,
  p_reason     text
)
returns public.payment_transactions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.payment_transactions;
begin
  update public.payment_transactions
     set status = 'cancelled', failure_reason = p_reason
   where id = p_payment_id
     and status = 'pending'
     and provider_trans_id is null
  returning * into v_row;

  if not found then
    select * into v_row from public.payment_transactions where id = p_payment_id;
  end if;
  return v_row;
end;
$$;

revoke execute on function
  public.fail_payment_intent(uuid, text) from public, anon, authenticated;


-- Map a Fapshi status onto the internal ledger status.
--   CREATED / PENDING → pending    (still in flight)
--   SUCCESSFUL        → successful
--   FAILED            → failed
--   EXPIRED           → cancelled  (the payment link lapsed unpaid)
create or replace function public.fapshi_status_to_internal(p_status text)
returns text
language sql
immutable
as $$
  select case upper(coalesce(p_status, ''))
    when 'SUCCESSFUL' then 'successful'
    when 'FAILED'     then 'failed'
    when 'EXPIRED'    then 'cancelled'
    when 'PENDING'    then 'pending'
    when 'CREATED'    then 'pending'
    else null
  end;
$$;

grant execute on function public.fapshi_status_to_internal(text) to authenticated;


-- Apply a provider-confirmed COLLECTION status. Idempotent by construction:
--   * the (trans_id, status) event insert collides on redelivery,
--   * the ledger transition rejects illegal moves and no-ops on repeats,
--   * downstream effects are only produced on the first successful application.
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

  -- Audit + idempotency. A redelivered webhook for the same (trans, status)
  -- stops here and simply returns the current row.
  begin
    insert into public.payment_events
      (provider, provider_trans_id, provider_status, source, payload)
    values
      (v_row.provider, p_trans_id, upper(p_status), p_source, coalesce(p_payload, '{}'::jsonb));
    v_first := true;
  exception when unique_violation then
    v_first := false;
  end;

  if not v_first then
    return v_row;
  end if;

  -- Already terminal: record the event, change nothing.
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

  -- ---- downstream effects, first application only --------------------------
  if v_row.status = 'successful' then
    select s.name into v_child from public.students s where s.id = v_row.student_id;

    if v_row.purpose = 'match_activation' then
      insert into public.payment_reminders
        (user_id, kind, title, body, payment_id, relationship_id)
      values
        (v_row.teacher_id, 'relationship_activated',
         'Relationship activated',
         coalesce(v_child, 'Your new student') || ' · you''re connected to this family',
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
  public.apply_payment_provider_status(text, text, jsonb, text) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 14. Earnings — derived from the ledger, never stored
-- -----------------------------------------------------------------------------
-- available : settled tutoring earnings minus everything already withdrawn or
--             reserved by an in-flight withdrawal
-- pending   : successful tutoring payments still inside the settlement window
-- Both are computed from payment_transactions + withdrawals every time.
-- -----------------------------------------------------------------------------

create or replace function public.teacher_earnings_summary()
returns table (
  available integer,
  pending   integer,
  lifetime  integer,
  withdrawn integer,
  currency  text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cfg       public.platform_fee_config;
  v_uid     uuid := auth.uid();
  v_settled bigint := 0;
  v_pending bigint := 0;
  v_reserved bigint := 0;
  v_paidout bigint := 0;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;

  select
    coalesce(sum(case when t.paid_at <= now() - make_interval(hours => cfg.settlement_delay_hours)
                      then (t.amount::bigint * cfg.teacher_earning_bps) / 10000 else 0 end), 0),
    coalesce(sum(case when t.paid_at >  now() - make_interval(hours => cfg.settlement_delay_hours)
                      then (t.amount::bigint * cfg.teacher_earning_bps) / 10000 else 0 end), 0)
  into v_settled, v_pending
  from public.payment_transactions t
  where t.teacher_id = v_uid
    and t.purpose = 'tutoring_payment'
    and t.status = 'successful';

  select
    coalesce(sum(case when w.status in ('requested', 'processing', 'successful')
                      then w.amount else 0 end), 0),
    coalesce(sum(case when w.status = 'successful' then w.amount else 0 end), 0)
  into v_reserved, v_paidout
  from public.withdrawals w
  where w.teacher_id = v_uid;

  return query select
    greatest(v_settled - v_reserved, 0)::integer,
    v_pending::integer,
    (v_settled + v_pending)::integer,
    v_paidout::integer,
    coalesce(cfg.currency, 'XAF');
end;
$$;

grant execute on function public.teacher_earnings_summary() to authenticated;


-- A teacher's Camiva activity summary, for the profile indicator. It states
-- transaction history only — it says nothing about teaching quality.
create or replace function public.teacher_activity_summary(p_teacher_id uuid)
returns table (completed_payments integer, active_relationships integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    (select count(*)::integer
       from public.payment_transactions t
      where t.teacher_id = p_teacher_id
        and t.purpose = 'tutoring_payment'
        and t.status = 'successful'),
    (select count(*)::integer
       from public.parent_teacher_relationships r
      where r.teacher_id = p_teacher_id
        and r.status = 'accepted'
        and public.relationship_is_operational(r.id));
$$;

grant execute on function public.teacher_activity_summary(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 15. Withdrawals — request (caller) and provider outcome (service role)
-- -----------------------------------------------------------------------------

create or replace function public.request_withdrawal(p_amount integer)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg       public.platform_fee_config;
  v_uid     uuid := auth.uid();
  acct      public.teacher_payout_accounts;
  v_avail   integer;
  v_row     public.withdrawals;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Serialise concurrent requests from the same teacher so two taps can never
  -- both pass the balance check.
  perform pg_advisory_xact_lock(hashtext('withdrawal:' || v_uid::text));

  select * into cfg from public.platform_fee_config where id = 1;
  if p_amount is null or p_amount < cfg.min_withdrawal_amount then
    raise exception 'Minimum withdrawal is % %', cfg.min_withdrawal_amount, cfg.currency;
  end if;

  select * into acct from public.teacher_payout_accounts where teacher_id = v_uid;
  if not found then
    raise exception 'Add your payout number first';
  end if;

  if exists (select 1 from public.withdrawals
              where teacher_id = v_uid and status in ('requested', 'processing')) then
    raise exception 'You already have a withdrawal in progress';
  end if;

  select available into v_avail from public.teacher_earnings_summary();
  if p_amount > v_avail then
    raise exception 'Amount is more than your available earnings';
  end if;

  insert into public.withdrawals
    (teacher_id, amount, currency, payout_medium, payout_phone)
  values
    (v_uid, p_amount, cfg.currency, acct.medium, acct.phone)
  returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function public.request_withdrawal(integer) from public;
grant execute on function public.request_withdrawal(integer) to authenticated;


create or replace function public.attach_withdrawal_provider_ref(
  p_withdrawal_id uuid,
  p_trans_id      text
)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.withdrawals;
begin
  update public.withdrawals
     set provider_trans_id = p_trans_id,
         status = case when status = 'requested' then 'processing' else status end
   where id = p_withdrawal_id
     and provider_trans_id is null
  returning * into v_row;

  if not found then
    select * into v_row from public.withdrawals where id = p_withdrawal_id;
  end if;
  return v_row;
end;
$$;

revoke execute on function
  public.attach_withdrawal_provider_ref(uuid, text) from public, anon, authenticated;


-- Mark a withdrawal failed when the provider call itself never got off the
-- ground (network error, provider rejection at request time).
create or replace function public.fail_withdrawal(p_withdrawal_id uuid, p_reason text)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.withdrawals;
begin
  update public.withdrawals
     set status = 'failed', failure_reason = p_reason, completed_at = now()
   where id = p_withdrawal_id
     and status in ('requested', 'processing')
  returning * into v_row;

  if not found then
    select * into v_row from public.withdrawals where id = p_withdrawal_id;
  end if;
  return v_row;
end;
$$;

revoke execute on function public.fail_withdrawal(uuid, text) from public, anon, authenticated;


-- Apply a provider-confirmed PAYOUT status. Same idempotency construction as
-- the collection path.
create or replace function public.apply_payout_provider_status(
  p_trans_id text,
  p_status   text,
  p_payload  jsonb default '{}'::jsonb,
  p_source   text default 'webhook'
)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row      public.withdrawals;
  v_internal text;
  v_first    boolean := false;
begin
  v_internal := public.fapshi_status_to_internal(p_status);
  if v_internal is null then
    raise exception 'Unknown provider status: %', p_status;
  end if;

  select * into v_row from public.withdrawals
   where provider_trans_id = p_trans_id
   for update;
  if not found then
    raise exception 'No withdrawal for provider transaction %', p_trans_id;
  end if;

  begin
    insert into public.payment_events
      (provider, provider_trans_id, provider_status, source, payload)
    values
      (v_row.provider, p_trans_id, upper(p_status), p_source, coalesce(p_payload, '{}'::jsonb));
    v_first := true;
  exception when unique_violation then
    v_first := false;
  end;

  if not v_first then
    return v_row;
  end if;
  if v_row.status not in ('requested', 'processing') then
    return v_row;
  end if;
  if v_internal = 'pending' then
    return v_row;
  end if;

  update public.withdrawals
     set status = case when v_internal = 'successful' then 'successful' else 'failed' end,
         failure_reason = case when v_internal <> 'successful'
                               then coalesce(p_payload ->> 'reason', failure_reason)
                               else failure_reason end,
         completed_at = now()
   where id = v_row.id
  returning * into v_row;

  insert into public.payment_reminders
    (user_id, kind, title, body, withdrawal_id)
  values
    (v_row.teacher_id, 'withdrawal_update',
     case when v_row.status = 'successful' then 'Withdrawal sent' else 'Withdrawal failed' end,
     to_char(v_row.amount, 'FM999G999G999') || ' ' || v_row.currency ||
       case when v_row.status = 'successful' then ' is on its way to your number.'
            else ' could not be sent. Your earnings are unchanged.' end,
     v_row.id);

  return v_row;
end;
$$;

revoke execute on function
  public.apply_payout_provider_status(text, text, jsonb, text) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 16. Service fee period bookkeeping
-- -----------------------------------------------------------------------------
-- Creates the current period for the signed-in teacher when a service fee is
-- configured, and returns it. Called by the app when the teacher opens their
-- fee/earnings surface. Marks a lapsed period overdue. This is the foundation
-- only — there is no scheduler and nothing here claims one exists.
-- -----------------------------------------------------------------------------

create or replace function public.ensure_service_fee_period()
returns public.service_fee_periods
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg   public.platform_fee_config;
  v_uid uuid := auth.uid();
  v_row public.service_fee_periods;
  v_start date;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;
  if cfg is null or coalesce(cfg.teacher_service_fee_amount, 0) <= 0 then
    return null;
  end if;

  -- Mark any earlier unpaid period overdue before opening the current one.
  update public.service_fee_periods
     set status = 'overdue'
   where teacher_id = v_uid
     and status in ('due', 'reminded')
     and period_end < current_date;

  select * into v_row
    from public.service_fee_periods
   where teacher_id = v_uid
     and current_date between period_start and period_end
   limit 1;
  if found then
    return v_row;
  end if;

  v_start := current_date;
  insert into public.service_fee_periods
    (teacher_id, period_start, period_end, amount, currency)
  values
    (v_uid, v_start,
     v_start + (cfg.teacher_service_fee_interval_days - 1),
     cfg.teacher_service_fee_amount, cfg.currency)
  on conflict (teacher_id, period_start) do nothing
  returning * into v_row;

  if v_row is null then
    select * into v_row from public.service_fee_periods
      where teacher_id = v_uid and period_start = v_start;
  end if;

  return v_row;
end;
$$;

revoke execute on function public.ensure_service_fee_period() from public;
grant execute on function public.ensure_service_fee_period() to authenticated;


-- Record that a service-fee reminder was actually shown to the teacher. Called
-- by the app at the moment the in-app reminder is displayed, so the timestamp
-- reflects a reminder that genuinely happened.
create or replace function public.mark_service_fee_reminded(p_period_id uuid)
returns public.service_fee_periods
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.service_fee_periods;
begin
  update public.service_fee_periods
     set status = case when status = 'due' then 'reminded' else status end,
         reminder_sent_at = coalesce(reminder_sent_at, now())
   where id = p_period_id
     and teacher_id = auth.uid()
  returning * into v_row;
  return v_row;
end;
$$;

revoke execute on function public.mark_service_fee_reminded(uuid) from public;
grant execute on function public.mark_service_fee_reminded(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 17. Reminder read receipts
-- -----------------------------------------------------------------------------
create or replace function public.mark_reminder_read(p_reminder_id uuid)
returns void
language sql
security invoker
set search_path = public
as $$
  update public.payment_reminders
     set read_at = coalesce(read_at, now())
   where id = p_reminder_id and user_id = auth.uid();
$$;

grant execute on function public.mark_reminder_read(uuid) to authenticated;

-- END 20260815000000_payments.sql


-- ===========================================================================
-- BEGIN 20260815010000_payments_grants.sql
-- ===========================================================================

-- =============================================================================
-- Camiva — Data API grants for the commercial layer
-- =============================================================================
--
-- Row-level security decides WHICH ROWS a user may see. It does not grant
-- access to the table in the first place: a role still needs table privileges,
-- and a Supabase project configured with `auto_expose_new_tables` off (the
-- current cloud default) gives new tables no privileges at all. Without these
-- grants every payments query fails with a permission error, which is what the
-- app surfaces as "Could not load payments".
--
-- The grants below are deliberately narrow, and RLS still applies on top of
-- them:
--   * read-only everywhere the app only reads,
--   * insert/update only where a policy already allows it (a teacher's own
--     payout account, their own reminder read receipts, their own support
--     requests),
--   * NOTHING on payment_transactions, withdrawals or payment_events beyond
--     select — the ledger is still written only by the SECURITY DEFINER
--     functions, so this cannot be used to forge a payment.
-- =============================================================================

grant usage on schema public to authenticated;

-- ---- read-only ------------------------------------------------------------
grant select on public.platform_fee_config    to authenticated;
grant select on public.payment_transactions   to authenticated;
grant select on public.payment_history        to authenticated;
grant select on public.withdrawals            to authenticated;
grant select on public.service_fee_periods    to authenticated;

-- ---- read + the writes an existing policy already permits ------------------
-- A teacher's own payout destination.
grant select, insert, update on public.teacher_payout_accounts to authenticated;
-- Marking one's own reminder read (a trigger restricts the update to read_at).
grant select, update          on public.payment_reminders      to authenticated;
-- Raising one's own support request.
grant select, insert          on public.support_requests       to authenticated;

-- payment_events is intentionally omitted: it is service-role only.

-- ---- server-side --------------------------------------------------------
-- The Edge Functions use the service role, which bypasses RLS but still needs
-- table privileges.
grant select, insert, update on all tables in schema public to service_role;

-- END 20260815010000_payments_grants.sql


-- ===========================================================================
-- BEGIN 20260816000000_manual_payouts.sql
-- ===========================================================================

-- =============================================================================
-- Camiva - manual payout settlement + platform admins
-- =============================================================================
--
-- Fapshi disburses only through a separate, provider-activated payout service.
-- Until Camiva has one, withdrawals are settled by hand: a teacher requests,
-- an Camiva admin sends the money themselves, then records that they did.
--
-- This is built as a first-class MODE rather than a workaround, so switching to
-- automatic payouts later is one config change and no rewrite:
--
--   platform_fee_config.payout_mode = 'manual'    (default today)
--     request -> sits at 'requested' -> admin settles it
--
--   platform_fee_config.payout_mode = 'provider'
--     request -> Fapshi /payout -> 'processing' -> webhook settles it
--
-- Honesty rules encoded here:
--   * A manually settled withdrawal is never dressed up as a provider payout.
--     settlement_mode records which route it took, settled_by records WHO
--     attested to sending it, and manual_reference carries their reference.
--   * An admin can settle or reject a withdrawal. An admin can NOT change where
--     the money goes: the payout destination stays teacher-owned, so no admin
--     can redirect another person's earnings. A wrong number is rejected, the
--     teacher corrects it, and requests again.
--   * Rejecting returns the amount to the teacher's available balance, because
--     availability is derived from withdrawals rather than stored.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Payout mode
-- -----------------------------------------------------------------------------
alter table public.platform_fee_config
  add column if not exists payout_mode text not null default 'manual';

alter table public.platform_fee_config
  drop constraint if exists platform_fee_config_payout_mode_check;
alter table public.platform_fee_config
  add constraint platform_fee_config_payout_mode_check
  check (payout_mode in ('manual', 'provider'));


-- -----------------------------------------------------------------------------
-- 2. Platform admins
-- -----------------------------------------------------------------------------
-- Deliberately a separate table rather than a new user_profiles.active_role
-- value: the existing role CHECK is ('parent','teacher') and the whole app
-- branches on it, so widening it would ripple everywhere. Admin is an extra
-- capability a normal account holds, not a third kind of user.
--
-- Add yourself with:
--   insert into public.platform_admins (user_id, note)
--   select id, 'founder' from auth.users where email = 'you@example.com';
-- -----------------------------------------------------------------------------

create table if not exists public.platform_admins (
  user_id    uuid        primary key references auth.users (id) on delete cascade,
  note       text,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;

-- An admin may confirm their own admin status (the app uses this to decide
-- whether to show the admin surface). Nobody can enumerate other admins, and
-- there is no policy granting writes: admins are added by the service role.
drop policy if exists "admins: can see own row" on public.platform_admins;
create policy "admins: can see own row"
  on public.platform_admins
  for select
  to authenticated
  using (auth.uid() = user_id);

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins a where a.user_id = auth.uid()
  );
$$;

grant execute on function public.is_platform_admin() to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Withdrawal settlement columns
-- -----------------------------------------------------------------------------
alter table public.withdrawals
  add column if not exists settlement_mode  text,
  add column if not exists settled_by       uuid references auth.users (id) on delete set null,
  add column if not exists manual_reference text,
  add column if not exists reviewed_at      timestamptz;

alter table public.withdrawals
  drop constraint if exists withdrawals_settlement_mode_check;
alter table public.withdrawals
  add constraint withdrawals_settlement_mode_check
  check (settlement_mode is null or settlement_mode in ('manual', 'provider'));

-- The immutability guard must keep protecting the money-defining columns while
-- allowing the settlement fields to be written once, by the admin functions.
create or replace function public.withdrawals_guard()
returns trigger
language plpgsql
as $$
begin
  if new.id            is distinct from old.id
     or new.teacher_id is distinct from old.teacher_id
     or new.amount     is distinct from old.amount
     or new.currency   is distinct from old.currency
     or new.created_at is distinct from old.created_at
     or new.payout_medium is distinct from old.payout_medium
     or new.payout_phone  is distinct from old.payout_phone
  then
    raise exception 'withdrawals: immutable column changed';
  end if;

  if old.provider_trans_id is not null
     and new.provider_trans_id is distinct from old.provider_trans_id then
    raise exception 'withdrawals: provider_trans_id is already set';
  end if;

  -- Who settled it and how cannot be rewritten afterwards.
  if old.settled_by is not null
     and new.settled_by is distinct from old.settled_by then
    raise exception 'withdrawals: settled_by is already set';
  end if;
  if old.settlement_mode is not null
     and new.settlement_mode is distinct from old.settlement_mode then
    raise exception 'withdrawals: settlement_mode is already set';
  end if;

  if new.status is distinct from old.status then
    if not (
      (old.status = 'requested'  and new.status in ('processing', 'successful',
                                                    'failed', 'cancelled'))
      or (old.status = 'processing' and new.status in ('successful', 'failed'))
    ) then
      raise exception 'withdrawals: illegal status transition % -> %',
        old.status, new.status;
    end if;
  end if;

  return new;
end;
$$;

-- An admin may read every withdrawal, because settling one means seeing who is
-- owed what and which number to send it to. Teachers keep seeing only their own
-- (the existing policy is untouched; this one is additive).
drop policy if exists "withdrawals: admin can select all" on public.withdrawals;
create policy "withdrawals: admin can select all"
  on public.withdrawals
  for select
  to authenticated
  using (public.is_platform_admin());


-- -----------------------------------------------------------------------------
-- 4. Admin settlement actions
-- -----------------------------------------------------------------------------
-- Both check is_platform_admin() internally, so a non-admin calling them
-- directly is refused regardless of what the app shows. Both are idempotent on
-- an already-settled withdrawal, so a double tap cannot pay twice.
-- -----------------------------------------------------------------------------

create or replace function public.admin_mark_withdrawal_sent(
  p_withdrawal_id uuid,
  p_reference     text
)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.withdrawals;
  v_ref text := nullif(btrim(coalesce(p_reference, '')), '');
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;
  if v_ref is null then
    raise exception 'A payment reference is required';
  end if;

  select * into v_row from public.withdrawals
   where id = p_withdrawal_id for update;
  if not found then
    raise exception 'Withdrawal not found';
  end if;

  -- Already settled: report the existing row rather than settling twice.
  if v_row.status <> 'requested' then
    return v_row;
  end if;

  update public.withdrawals
     set status           = 'successful',
         settlement_mode  = 'manual',
         settled_by       = auth.uid(),
         manual_reference = v_ref,
         reviewed_at      = now(),
         completed_at     = now()
   where id = v_row.id
  returning * into v_row;

  insert into public.payment_reminders
    (user_id, kind, title, body, withdrawal_id)
  values
    (v_row.teacher_id, 'withdrawal_update',
     'Withdrawal sent',
     to_char(v_row.amount, 'FM999G999G999') || ' ' || v_row.currency ||
       ' has been sent to your number. Reference: ' || v_ref,
     v_row.id);

  return v_row;
end;
$$;

revoke execute on function
  public.admin_mark_withdrawal_sent(uuid, text) from public, anon;
grant execute on function
  public.admin_mark_withdrawal_sent(uuid, text) to authenticated;


create or replace function public.admin_reject_withdrawal(
  p_withdrawal_id uuid,
  p_reason        text
)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    public.withdrawals;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;
  if v_reason is null then
    raise exception 'A reason is required';
  end if;

  select * into v_row from public.withdrawals
   where id = p_withdrawal_id for update;
  if not found then
    raise exception 'Withdrawal not found';
  end if;
  if v_row.status <> 'requested' then
    return v_row;
  end if;

  -- 'cancelled' releases the reserved amount: teacher_earnings_summary() counts
  -- only requested/processing/successful against the balance, so rejecting
  -- returns the money to available without any balance being edited.
  update public.withdrawals
     set status          = 'cancelled',
         settlement_mode = 'manual',
         settled_by      = auth.uid(),
         failure_reason  = v_reason,
         reviewed_at     = now(),
         completed_at    = now()
   where id = v_row.id
  returning * into v_row;

  insert into public.payment_reminders
    (user_id, kind, title, body, withdrawal_id)
  values
    (v_row.teacher_id, 'withdrawal_update',
     'Withdrawal not sent',
     v_reason || ' Your earnings are unchanged, so you can request again.',
     v_row.id);

  return v_row;
end;
$$;

revoke execute on function
  public.admin_reject_withdrawal(uuid, text) from public, anon;
grant execute on function
  public.admin_reject_withdrawal(uuid, text) to authenticated;


-- -----------------------------------------------------------------------------
-- 5. The admin queue
-- -----------------------------------------------------------------------------
-- Everything an admin needs to actually send the money: who, how much, and
-- which number. Refuses to return anything to a non-admin.
-- -----------------------------------------------------------------------------

create or replace function public.admin_pending_withdrawals()
returns table (
  id            uuid,
  teacher_id    uuid,
  teacher_name  text,
  amount        integer,
  currency      text,
  payout_medium text,
  payout_phone  text,
  status        text,
  created_at    timestamptz
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
    select w.id, w.teacher_id, p.name, w.amount, w.currency,
           w.payout_medium, w.payout_phone, w.status, w.created_at
      from public.withdrawals w
      left join public.user_profiles p on p.id = w.teacher_id
     where w.status = 'requested'
     order by w.created_at asc;
end;
$$;

revoke execute on function public.admin_pending_withdrawals() from public, anon;
grant execute on function public.admin_pending_withdrawals() to authenticated;


-- Recently settled withdrawals, so an admin can see what they already sent.
create or replace function public.admin_recent_withdrawals(p_limit integer default 20)
returns table (
  id               uuid,
  teacher_name     text,
  amount           integer,
  currency         text,
  status           text,
  settlement_mode  text,
  manual_reference text,
  completed_at     timestamptz
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
    select w.id, p.name, w.amount, w.currency, w.status,
           w.settlement_mode, w.manual_reference, w.completed_at
      from public.withdrawals w
      left join public.user_profiles p on p.id = w.teacher_id
     where w.status <> 'requested'
     order by coalesce(w.completed_at, w.updated_at) desc
     limit greatest(1, least(coalesce(p_limit, 20), 100));
end;
$$;

revoke execute on function public.admin_recent_withdrawals(integer) from public, anon;
grant execute on function public.admin_recent_withdrawals(integer) to authenticated;


-- -----------------------------------------------------------------------------
-- 6. request_withdrawal(): stamp the mode it will settle through
-- -----------------------------------------------------------------------------
create or replace function public.request_withdrawal(p_amount integer)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg     public.platform_fee_config;
  v_uid   uuid := auth.uid();
  acct    public.teacher_payout_accounts;
  v_avail integer;
  v_row   public.withdrawals;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  -- Serialise concurrent requests from the same teacher so two taps can never
  -- both pass the balance check.
  perform pg_advisory_xact_lock(hashtext('withdrawal:' || v_uid::text));

  select * into cfg from public.platform_fee_config where id = 1;
  if p_amount is null or p_amount < cfg.min_withdrawal_amount then
    raise exception 'Minimum withdrawal is % %', cfg.min_withdrawal_amount, cfg.currency;
  end if;

  select * into acct from public.teacher_payout_accounts where teacher_id = v_uid;
  if not found then
    raise exception 'Add your payout number first';
  end if;

  if exists (select 1 from public.withdrawals
              where teacher_id = v_uid and status in ('requested', 'processing')) then
    raise exception 'You already have a withdrawal in progress';
  end if;

  select available into v_avail from public.teacher_earnings_summary();
  if p_amount > v_avail then
    raise exception 'Amount is more than your available earnings';
  end if;

  insert into public.withdrawals
    (teacher_id, amount, currency, payout_medium, payout_phone, settlement_mode)
  values
    (v_uid, p_amount, cfg.currency, acct.medium, acct.phone,
     case when cfg.payout_mode = 'provider' then null else 'manual' end)
  returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function public.request_withdrawal(integer) from public;
grant execute on function public.request_withdrawal(integer) to authenticated;


-- -----------------------------------------------------------------------------
-- 7. The provider path stamps its mode too
-- -----------------------------------------------------------------------------
-- So every settled withdrawal says plainly which route it took, and a manual
-- settlement can never be mistaken for a provider payout.
create or replace function public.attach_withdrawal_provider_ref(
  p_withdrawal_id uuid,
  p_trans_id      text
)
returns public.withdrawals
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.withdrawals;
begin
  update public.withdrawals
     set provider_trans_id = p_trans_id,
         settlement_mode   = coalesce(settlement_mode, 'provider'),
         status = case when status = 'requested' then 'processing' else status end
   where id = p_withdrawal_id
     and provider_trans_id is null
  returning * into v_row;

  if not found then
    select * into v_row from public.withdrawals where id = p_withdrawal_id;
  end if;
  return v_row;
end;
$$;

revoke execute on function
  public.attach_withdrawal_provider_ref(uuid, text) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- 8. Grants
-- -----------------------------------------------------------------------------
grant select on public.platform_admins to authenticated;

-- END 20260816000000_manual_payouts.sql


-- ===========================================================================
-- BEGIN 20260816010000_admin_payments.sql
-- ===========================================================================

-- =============================================================================
-- Camiva - admin visibility over payments
-- =============================================================================
--
-- An admin settles withdrawals by hand, which means answering "is this money
-- real, and where did it come from?". That requires seeing payments across the
-- platform: which parent paid which teacher, for which child, and whether the
-- provider actually confirmed it.
--
-- Scope of what an admin can see here, deliberately:
--   * the parties by NAME, the child, the amount, the status, and the provider
--     reference - everything needed to reconcile money and answer a support
--     question.
--   * NOT contact details. Nothing in these functions returns a phone number or
--     an email; relationship_contact() remains the only route to those and is
--     still gated on the relationship's own activation rules.
--
-- Admins are read-only over payments. There is no admin function that creates,
-- edits or settles a payment: collection state comes from Fapshi alone, so an
-- admin cannot mark a payment successful any more than a client can.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Admins may read the ledger
-- -----------------------------------------------------------------------------
-- Additive to the existing "party can select" policy, which is untouched:
-- parents and teachers keep seeing exactly their own transactions.
drop policy if exists "payments: admin can select all" on public.payment_transactions;
create policy "payments: admin can select all"
  on public.payment_transactions
  for select
  to authenticated
  using (public.is_platform_admin());

-- Still no insert/update/delete policy for anyone, admins included.


-- -----------------------------------------------------------------------------
-- 2. Payments across the platform, newest first
-- -----------------------------------------------------------------------------
create or replace function public.admin_recent_payments(
  p_limit  integer default 50,
  p_status text default null
)
returns table (
  id                uuid,
  purpose           text,
  amount            integer,
  currency          text,
  status            text,
  parent_name       text,
  teacher_name      text,
  child_name        text,
  provider_trans_id text,
  failure_reason    text,
  created_at        timestamptz,
  paid_at           timestamptz
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
    select t.id,
           t.purpose,
           t.amount,
           t.currency,
           t.status,
           parent.name,
           teacher.name,
           s.name,
           t.provider_trans_id,
           t.failure_reason,
           t.created_at,
           t.paid_at
      from public.payment_transactions t
      left join public.user_profiles parent  on parent.id  = t.parent_id
      left join public.user_profiles teacher on teacher.id = t.teacher_id
      left join public.students s            on s.id       = t.student_id
     where p_status is null or t.status = p_status
     order by t.created_at desc
     limit greatest(1, least(coalesce(p_limit, 50), 200));
end;
$$;

revoke execute on function
  public.admin_recent_payments(integer, text) from public, anon;
grant execute on function
  public.admin_recent_payments(integer, text) to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Platform totals
-- -----------------------------------------------------------------------------
-- Every figure is derived from the ledger at read time. Nothing is stored, so
-- these cannot drift from the transactions they describe.
create or replace function public.admin_payment_totals()
returns table (
  collected            bigint,
  successful_count     integer,
  pending_count        integer,
  failed_count         integer,
  owed_to_teachers     bigint,
  awaiting_withdrawal  integer,
  currency             text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  cfg public.platform_fee_config;
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;

  select * into cfg from public.platform_fee_config where id = 1;

  return query
    select
      coalesce(sum(t.amount) filter (where t.status = 'successful'), 0)::bigint,
      count(*) filter (where t.status = 'successful')::integer,
      count(*) filter (where t.status = 'pending')::integer,
      count(*) filter (where t.status in ('failed', 'cancelled'))::integer,
      -- What teachers have earned and not yet been paid out: successful
      -- tutoring payments, less everything already withdrawn or reserved.
      (
        coalesce((
          select sum((p.amount::bigint * coalesce(cfg.teacher_earning_bps, 10000)) / 10000)
            from public.payment_transactions p
           where p.purpose = 'tutoring_payment' and p.status = 'successful'
        ), 0)
        - coalesce((
          select sum(w.amount)
            from public.withdrawals w
           where w.status in ('requested', 'processing', 'successful')
        ), 0)
      )::bigint,
      (select count(*) from public.withdrawals w where w.status = 'requested')::integer,
      coalesce(cfg.currency, 'XAF')
    from public.payment_transactions t;
end;
$$;

revoke execute on function public.admin_payment_totals() from public, anon;
grant execute on function public.admin_payment_totals() to authenticated;

-- END 20260816010000_admin_payments.sql


-- ===========================================================================
-- BEGIN 20260817000000_monthly_billing.sql
-- ===========================================================================

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

-- END 20260817000000_monthly_billing.sql


-- ===========================================================================
-- BEGIN 20260817010000_reminders_and_push.sql
-- ===========================================================================

-- =============================================================================
-- Camiva - admin billing overview, parent reminders, push foundation
-- =============================================================================
--
-- WHAT IS AND IS NOT CLAIMED HERE
-- -----------------------------------------------------------------------------
-- An in-app reminder IS delivered the moment its row exists: the parent sees it
-- in the app. A PUSH notification is a separate thing that needs a device token
-- and a configured sender, so it is recorded separately and honestly:
--
--   push_status = 'not_attempted'   nothing tried yet
--                 'sent'            the push service accepted it
--                 'no_device'       the parent has no registered device
--                 'not_configured'  no push credentials on this project
--                 'failed'          the push service rejected it
--
-- Nothing in the app says "reminder sent" on the strength of a row existing.
-- The admin is told exactly which of the two happened.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Reminders gain a payment-due kind and a truthful push record
-- -----------------------------------------------------------------------------

alter table public.payment_reminders
  add column if not exists push_status text not null default 'not_attempted',
  add column if not exists push_at     timestamptz,
  add column if not exists sent_by     uuid references auth.users (id) on delete set null;

alter table public.payment_reminders
  drop constraint if exists payment_reminders_push_status_check;
alter table public.payment_reminders
  add constraint payment_reminders_push_status_check
  check (push_status in ('not_attempted', 'sent', 'no_device',
                         'not_configured', 'failed'));

-- The full set of kinds, including the ones added by later migrations. A
-- narrower list here would fail on re-run once rows of those later kinds exist,
-- so every definition of this constraint carries the same list.
alter table public.payment_reminders
  drop constraint if exists payment_reminders_kind_check;
alter table public.payment_reminders
  add constraint payment_reminders_kind_check
  check (kind in ('payment_received',
                  'payment_failed',
                  'payment_due',
                  'service_fee_due',
                  'service_fee_overdue',
                  'relationship_activated',
                  'verification_update',
                  'agreement_update',
                  'withdrawal_update'));

-- The guard allowed only read_at to change; push fields are written by the
-- server after the row exists, so they are now writable too - still never the
-- text of the reminder.
create or replace function public.payment_reminders_guard()
returns trigger
language plpgsql
as $$
begin
  if new.id                is distinct from old.id
     or new.user_id        is distinct from old.user_id
     or new.kind           is distinct from old.kind
     or new.title          is distinct from old.title
     or new.body           is distinct from old.body
     or new.payment_id     is distinct from old.payment_id
     or new.relationship_id is distinct from old.relationship_id
     or new.withdrawal_id  is distinct from old.withdrawal_id
     or new.created_at     is distinct from old.created_at
     or new.sent_by        is distinct from old.sent_by
  then
    raise exception 'payment_reminders: only read_at and push state may change';
  end if;
  return new;
end;
$$;


-- -----------------------------------------------------------------------------
-- 2. Device tokens for push
-- -----------------------------------------------------------------------------
-- Owned entirely by the user they belong to. Nobody can read another person's
-- device token; the sender runs with the service role.
-- -----------------------------------------------------------------------------

create table if not exists public.device_push_tokens (
  token        text        primary key,
  user_id      uuid        not null references auth.users (id) on delete cascade,
  platform     text        not null default 'android'
                 constraint device_push_tokens_platform_check
                 check (platform in ('android', 'ios', 'web')),
  created_at   timestamptz not null default now(),
  last_seen_at timestamptz not null default now()
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;

drop policy if exists "tokens: owner can select" on public.device_push_tokens;
create policy "tokens: owner can select"
  on public.device_push_tokens for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "tokens: owner can insert" on public.device_push_tokens;
create policy "tokens: owner can insert"
  on public.device_push_tokens for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "tokens: owner can update" on public.device_push_tokens;
create policy "tokens: owner can update"
  on public.device_push_tokens for update to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "tokens: owner can delete" on public.device_push_tokens;
create policy "tokens: owner can delete"
  on public.device_push_tokens for delete to authenticated
  using (auth.uid() = user_id);

grant select, insert, update, delete on public.device_push_tokens to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Admin billing overview
-- -----------------------------------------------------------------------------
-- One row per active monthly arrangement: who owes what, and by when. Derived
-- from relationship_billing_summary(), so it agrees with what the parent sees.
-- -----------------------------------------------------------------------------

create or replace function public.admin_billing_overview()
returns table (
  relationship_id  uuid,
  parent_id        uuid,
  parent_name      text,
  teacher_name     text,
  child_name       text,
  monthly_amount   integer,
  paid_this_period integer,
  balance          integer,
  currency         text,
  started_on       date,
  next_due_on      date,
  last_paid_at     timestamptz,
  last_reminded_at timestamptz
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
    select b.relationship_id,
           b.parent_id,
           parent.name,
           teacher.name,
           s.name,
           sum.monthly_amount,
           sum.paid_this_period,
           sum.balance,
           sum.currency,
           sum.started_on,
           sum.next_due_on,
           sum.last_paid_at,
           (select max(r.created_at) from public.payment_reminders r
             where r.relationship_id = b.relationship_id
               and r.kind = 'payment_due')
      from public.relationship_billing b
      join public.parent_teacher_relationships rel on rel.id = b.relationship_id
      left join public.user_profiles parent  on parent.id  = b.parent_id
      left join public.user_profiles teacher on teacher.id = b.teacher_id
      left join public.students s            on s.id       = rel.student_id
      cross join lateral public.relationship_billing_summary(b.relationship_id) sum
     where b.active
     order by sum.balance desc, sum.next_due_on asc;
end;
$$;

revoke execute on function public.admin_billing_overview() from public, anon;
grant execute on function public.admin_billing_overview() to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Creating a payment reminder
-- -----------------------------------------------------------------------------
-- Service-role only: the reminder is created by the send-reminder function,
-- which then attempts push and records what actually happened. Creating it here
-- and pushing separately is what keeps the two claims honest.
-- -----------------------------------------------------------------------------

create or replace function public.create_payment_due_reminder(
  p_relationship_id uuid,
  p_sent_by         uuid default null,
  p_message         text default null
)
returns public.payment_reminders
language plpgsql
security definer
set search_path = public
as $$
declare
  rel     public.parent_teacher_relationships;
  v_child text;
  v_row   public.payment_reminders;
  v_bal   integer;
  v_cur   text;
  v_due   date;
  v_body  text;
begin
  select * into rel from public.parent_teacher_relationships where id = p_relationship_id;
  if not found then
    raise exception 'Relationship not found';
  end if;

  select s.name into v_child from public.students s where s.id = rel.student_id;
  select balance, currency, next_due_on into v_bal, v_cur, v_due
    from public.relationship_billing_summary(p_relationship_id);

  v_body := coalesce(
    nullif(btrim(coalesce(p_message, '')), ''),
    coalesce(v_child, 'Your child') || ' - ' ||
      to_char(coalesce(v_bal, 0), 'FM999G999G999') || ' ' || coalesce(v_cur, 'XAF') ||
      ' left for this month' ||
      case when v_due is not null
           then ', due ' || to_char(v_due, 'DD Mon YYYY') else '' end
  );

  insert into public.payment_reminders
    (user_id, kind, title, body, relationship_id, sent_by)
  values
    (rel.parent_id, 'payment_due', 'Tutoring payment reminder', v_body,
     p_relationship_id, p_sent_by)
  returning * into v_row;

  return v_row;
end;
$$;

revoke execute on function
  public.create_payment_due_reminder(uuid, uuid, text) from public, anon, authenticated;


-- Records what the push attempt actually did. Service-role only.
create or replace function public.record_reminder_push(
  p_reminder_id uuid,
  p_status      text
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.payment_reminders
     set push_status = p_status,
         push_at = case when p_status = 'sent' then now() else push_at end
   where id = p_reminder_id;
$$;

revoke execute on function
  public.record_reminder_push(uuid, text) from public, anon, authenticated;


-- The devices to push to. Service-role only - device tokens are never exposed
-- to another user.
create or replace function public.push_tokens_for_user(p_user_id uuid)
returns table (token text, platform text)
language sql
stable
security definer
set search_path = public
as $$
  select t.token, t.platform from public.device_push_tokens t
   where t.user_id = p_user_id;
$$;

revoke execute on function
  public.push_tokens_for_user(uuid) from public, anon, authenticated;

-- END 20260817010000_reminders_and_push.sql


-- ===========================================================================
-- BEGIN 20260818000000_teacher_verification.sql
-- ===========================================================================

-- =============================================================================
-- Camiva - teacher verification (trust gate, not a revenue gate)
-- =============================================================================
--
-- A teacher submits an identity document and a qualification document. Camiva
-- reviews them remotely - there is no in-person requirement.
--
-- Statuses, and what each one honestly means:
--   'required'  nothing submitted yet
--   'pending'   documents submitted, Camiva has not reviewed them
--   'verified'  an Camiva admin approved them
--   'rejected'  an admin asked for a correction, with a reason
--
-- A teacher is NEVER called verified before an admin approves. Submitting
-- moves them to 'pending' and no further; only admin_review_verification()
-- can write 'verified', and it is admin-only.
--
-- Verification gates the tutoring relationship, NOT payment. It comes before
-- the Platform Charge in the flow because Camiva should not take money to
-- activate a teacher it has not checked.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. Private bucket for the documents
-- -----------------------------------------------------------------------------
-- Unlike profile photos, these are identity documents: the bucket is PRIVATE,
-- and nobody can read another teacher's files. Admin review happens through
-- signed URLs generated server-side.
-- -----------------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('verification-docs', 'verification-docs', false)
on conflict (id) do nothing;

drop policy if exists "verification-docs: owner can read" on storage.objects;
create policy "verification-docs: owner can read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification-docs: admin can read" on storage.objects;
create policy "verification-docs: admin can read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'verification-docs'
    and public.is_platform_admin()
  );

drop policy if exists "verification-docs: owner can insert" on storage.objects;
create policy "verification-docs: owner can insert"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "verification-docs: owner can update" on storage.objects;
create policy "verification-docs: owner can update"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'verification-docs'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- No delete policy: a submitted document stays until Camiva removes it.


-- -----------------------------------------------------------------------------
-- 2. teacher_verifications
-- -----------------------------------------------------------------------------

create table if not exists public.teacher_verifications (
  teacher_id        uuid        primary key references auth.users (id) on delete cascade,
  status            text        not null default 'required'
                      constraint teacher_verifications_status_check
                      check (status in ('required', 'pending', 'verified', 'rejected')),

  -- Storage paths inside the private bucket, never public URLs.
  identity_doc_path      text,
  identity_doc_type      text
                           constraint teacher_verifications_id_type_check
                           check (identity_doc_type is null
                                  or identity_doc_type in ('national_id', 'passport',
                                                           'drivers_licence')),
  qualification_doc_path text,
  qualification_title    text,

  submitted_at      timestamptz,
  reviewed_at       timestamptz,
  reviewed_by       uuid        references auth.users (id) on delete set null,
  rejection_reason  text,

  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists teacher_verifications_status_idx
  on public.teacher_verifications (status);

drop trigger if exists teacher_verifications_set_updated_at on public.teacher_verifications;
create trigger teacher_verifications_set_updated_at
  before update on public.teacher_verifications
  for each row execute function public.set_updated_at();

alter table public.teacher_verifications enable row level security;

-- A teacher reads their own record; admins read all. A parent never sees
-- another person's documents or review notes.
drop policy if exists "verification: owner can select" on public.teacher_verifications;
create policy "verification: owner can select"
  on public.teacher_verifications
  for select
  to authenticated
  using (auth.uid() = teacher_id or public.is_platform_admin());

-- Deliberately no insert/update policy: submission and review both go through
-- the functions below, so a teacher can never write their own 'verified'.
grant select on public.teacher_verifications to authenticated;


-- -----------------------------------------------------------------------------
-- 3. Submitting documents
-- -----------------------------------------------------------------------------
-- Moves the teacher to 'pending' and nothing further. Re-submitting after a
-- rejection is allowed and clears the previous decision.
-- -----------------------------------------------------------------------------

create or replace function public.submit_teacher_verification(
  p_identity_doc_path      text,
  p_identity_doc_type      text,
  p_qualification_doc_path text,
  p_qualification_title    text default null
)
returns public.teacher_verifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.teacher_verifications;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce(btrim(p_identity_doc_path), '') = '' then
    raise exception 'An identity document is required';
  end if;
  if coalesce(btrim(p_qualification_doc_path), '') = '' then
    raise exception 'A qualification document is required';
  end if;

  insert into public.teacher_verifications
    (teacher_id, status, identity_doc_path, identity_doc_type,
     qualification_doc_path, qualification_title, submitted_at,
     reviewed_at, reviewed_by, rejection_reason)
  values
    (v_uid, 'pending', p_identity_doc_path, p_identity_doc_type,
     p_qualification_doc_path, nullif(btrim(coalesce(p_qualification_title, '')), ''),
     now(), null, null, null)
  on conflict (teacher_id) do update
    set status                 = 'pending',
        identity_doc_path      = excluded.identity_doc_path,
        identity_doc_type      = excluded.identity_doc_type,
        qualification_doc_path = excluded.qualification_doc_path,
        qualification_title    = excluded.qualification_title,
        submitted_at           = now(),
        reviewed_at            = null,
        reviewed_by            = null,
        rejection_reason       = null
    -- A teacher who is already verified stays verified; re-submitting does not
    -- knock them back to pending.
    where teacher_verifications.status <> 'verified'
  returning * into v_row;

  if v_row is null then
    select * into v_row from public.teacher_verifications where teacher_id = v_uid;
  end if;
  return v_row;
end;
$$;

revoke execute on function
  public.submit_teacher_verification(text, text, text, text) from public, anon;
grant execute on function
  public.submit_teacher_verification(text, text, text, text) to authenticated;


-- The signed-in teacher's own status. Returns 'required' when nothing exists
-- yet, so the app never has to guess.
create or replace function public.my_verification_status()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select v.status from public.teacher_verifications v
      where v.teacher_id = auth.uid()),
    'required'
  );
$$;

grant execute on function public.my_verification_status() to authenticated;


create or replace function public.is_teacher_verified(p_teacher_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.teacher_verifications v
     where v.teacher_id = p_teacher_id and v.status = 'verified'
  );
$$;

grant execute on function public.is_teacher_verified(uuid) to authenticated;


-- -----------------------------------------------------------------------------
-- 4. Admin review
-- -----------------------------------------------------------------------------
-- Reviews notify the teacher through the existing in-app reminder inbox, so a
-- verification kind is added rather than borrowing an unrelated one.
alter table public.payment_reminders
  drop constraint if exists payment_reminders_kind_check;
alter table public.payment_reminders
  add constraint payment_reminders_kind_check
  check (kind in ('payment_received',
                  'payment_failed',
                  'payment_due',
                  'service_fee_due',
                  'service_fee_overdue',
                  'relationship_activated',
                  'verification_update',
                  'agreement_update',
                  'withdrawal_update'));


create or replace function public.admin_pending_verifications()
returns table (
  teacher_id             uuid,
  teacher_name           text,
  identity_doc_path      text,
  identity_doc_type      text,
  qualification_doc_path text,
  qualification_title    text,
  submitted_at           timestamptz
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
    select v.teacher_id, p.name, v.identity_doc_path, v.identity_doc_type,
           v.qualification_doc_path, v.qualification_title, v.submitted_at
      from public.teacher_verifications v
      left join public.user_profiles p on p.id = v.teacher_id
     where v.status = 'pending'
     order by v.submitted_at asc;
end;
$$;

revoke execute on function public.admin_pending_verifications() from public, anon;
grant execute on function public.admin_pending_verifications() to authenticated;


create or replace function public.admin_review_verification(
  p_teacher_id uuid,
  p_approve    boolean,
  p_reason     text default null
)
returns public.teacher_verifications
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row    public.teacher_verifications;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if not public.is_platform_admin() then
    raise exception 'Not authorised';
  end if;
  if not p_approve and v_reason is null then
    raise exception 'A reason is required when asking for a correction';
  end if;

  update public.teacher_verifications
     set status           = case when p_approve then 'verified' else 'rejected' end,
         reviewed_at      = now(),
         reviewed_by      = auth.uid(),
         rejection_reason = case when p_approve then null else v_reason end
   where teacher_id = p_teacher_id
     and status = 'pending'
  returning * into v_row;

  if not found then
    select * into v_row from public.teacher_verifications where teacher_id = p_teacher_id;
    return v_row;
  end if;

  insert into public.payment_reminders
    (user_id, kind, title, body)
  values
    (p_teacher_id, 'verification_update',
     case when p_approve then 'You are verified' else 'Verification needs a correction' end,
     case when p_approve
          then 'Camiva has approved your documents. You can now set up tutoring.'
          else v_reason end);

  return v_row;
end;
$$;

revoke execute on function
  public.admin_review_verification(uuid, boolean, text) from public, anon;
grant execute on function
  public.admin_review_verification(uuid, boolean, text) to authenticated;

-- END 20260818000000_teacher_verification.sql


-- ===========================================================================
-- BEGIN 20260818010000_tutoring_agreements.sql
-- ===========================================================================

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

-- END 20260818010000_tutoring_agreements.sql


-- ===========================================================================
-- BEGIN 20260818020000_platform_charge_gate.sql
-- ===========================================================================

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

-- END 20260818020000_platform_charge_gate.sql


-- ===========================================================================
-- BEGIN 20260819000000_teacher_service_plan.sql
-- ===========================================================================

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

-- END 20260819000000_teacher_service_plan.sql


-- ===========================================================================
-- BEGIN 20260820000000_push_token_register.sql
-- ===========================================================================

-- =============================================================================
-- Camiva - registering a device push token
-- =============================================================================
--
-- THE PROBLEM THIS FIXES
-- -----------------------------------------------------------------------------
-- A push token identifies a DEVICE, not a person, and one phone is used by more
-- than one account: a teacher signs in, then a parent, or someone tests both
-- roles on the same handset.
--
-- The client used to upsert the token directly. On a second account that becomes
-- INSERT ... ON CONFLICT DO UPDATE against a row owned by the previous user, and
-- the update policy's USING clause correctly refuses it:
--
--   new row violates row-level security policy (USING expression)
--
-- The token then never stored, so reminders reported "no phone registered" -
-- accurately, but for a reason nobody could see.
--
-- THE FIX
-- -----------------------------------------------------------------------------
-- Registration goes through a function that REASSIGNS the token to whoever is
-- signed in now. That is the correct semantics: the device belongs to the
-- current session, and the previous user must stop receiving notifications on a
-- phone they have signed out of.
--
-- This does not widen anyone's reach. The function only ever writes auth.uid()
-- as the owner, so a caller cannot register a token against another person.
-- =============================================================================

create or replace function public.register_push_token(
  p_token    text,
  p_platform text default 'android'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'A device token is required';
  end if;
  if p_platform not in ('android', 'ios', 'web') then
    raise exception 'Unknown platform: %', p_platform;
  end if;

  -- The owner is always the caller. A token handed over from another account
  -- moves to this one; it is never shared between two users.
  insert into public.device_push_tokens (token, user_id, platform, last_seen_at)
  values (btrim(p_token), v_uid, p_platform, now())
  on conflict (token) do update
    set user_id      = v_uid,
        platform     = excluded.platform,
        last_seen_at = now();
end;
$$;

revoke execute on function
  public.register_push_token(text, text) from public, anon;
grant execute on function
  public.register_push_token(text, text) to authenticated;


-- Signing out removes this device's token so the next person to use the phone
-- does not receive the previous user's reminders. Scoped to the caller's own
-- token: signing out cannot unregister someone else's device.
create or replace function public.forget_push_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.device_push_tokens
   where token = btrim(p_token)
     and user_id = auth.uid();
$$;

revoke execute on function public.forget_push_token(text) from public, anon;
grant execute on function public.forget_push_token(text) to authenticated;

-- END 20260820000000_push_token_register.sql
