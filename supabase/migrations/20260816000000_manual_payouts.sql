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
