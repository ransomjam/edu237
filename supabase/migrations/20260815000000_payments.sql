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
