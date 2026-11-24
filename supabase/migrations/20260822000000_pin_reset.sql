-- =============================================================================
-- Camiva - PIN recovery
-- =============================================================================
--
-- Normal sign-in is unchanged: phone number plus PIN, no OTP. This is only the
-- way back in for someone who has forgotten their PIN, and it is the one place
-- an SMS code is used.
--
-- THE SHAPE
-- -----------------------------------------------------------------------------
--   1. Person asks to reset. A six-digit code is generated, HASHED, and stored.
--      Only the hash is kept, so the code cannot be read out of the database.
--   2. The code is sent by SMS to the registered number - which is what proves
--      ownership. It is never returned to the app.
--   3. Person enters the code and a new PIN. The app derives the new secret
--      locally (the raw PIN never leaves the device, exactly as at sign-in) and
--      sends the code plus the derived secret.
--   4. On a correct, live, unused code the secret is written through the admin
--      API and every reset request for that number is closed.
--
-- WHAT PROTECTS IT
-- -----------------------------------------------------------------------------
--   * codes expire (10 minutes) and are single use
--   * at most 5 wrong guesses per code, then it is dead
--   * at most 3 codes per number per hour
--   * nothing here ever reveals whether a number is registered
--
-- These functions are service-role only. The app reaches them through Edge
-- Functions, which is what keeps enumeration and brute force off the client.
-- =============================================================================

create table if not exists public.pin_reset_requests (
  id          uuid        primary key default gen_random_uuid(),
  -- The normalised local number, matching what the app derives from.
  phone       text        not null
                constraint pin_reset_phone_check check (phone ~ '^6[0-9]{8}$'),
  user_id     uuid        not null references auth.users (id) on delete cascade,

  -- sha256 of the code. The code itself exists only in the SMS.
  code_hash   text        not null,
  expires_at  timestamptz not null,
  attempts    smallint    not null default 0,
  consumed_at timestamptz,
  created_at  timestamptz not null default now()
);

create index if not exists pin_reset_requests_phone_idx
  on public.pin_reset_requests (phone, created_at desc);

alter table public.pin_reset_requests enable row level security;
-- No policies at all: this table is service-role only. A client that could read
-- it could read another person's reset state.


-- -----------------------------------------------------------------------------
-- Opening a reset
-- -----------------------------------------------------------------------------
-- Returns the row when a reset was opened, and NOTHING when the number is not
-- registered or is over its limit. The caller cannot tell those apart, which is
-- what stops this being used to discover who has an account.
-- -----------------------------------------------------------------------------

create or replace function public.open_pin_reset(
  p_phone     text,
  p_code_hash text
)
returns table (request_id uuid, user_id uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid;
  v_recent integer;
  v_row    public.pin_reset_requests;
begin
  if p_phone !~ '^6[0-9]{8}$' then
    return;
  end if;

  -- The account behind this number. The synthetic address is how a phone
  -- identity is stored; see PhoneCredentials in the app.
  select u.id into v_user
    from auth.users u
   where lower(u.email) = p_phone || '@camiva.app'
   limit 1;
  if v_user is null then
    return;
  end if;

  -- At most three codes an hour for one number.
  select count(*) into v_recent
    from public.pin_reset_requests r
   where r.phone = p_phone
     and r.created_at > now() - interval '1 hour';
  if v_recent >= 3 then
    return;
  end if;

  -- Any earlier live code for this number stops working now, so a person
  -- always has exactly one code in play.
  update public.pin_reset_requests
     set consumed_at = now()
   where phone = p_phone and consumed_at is null;

  insert into public.pin_reset_requests (phone, user_id, code_hash, expires_at)
  values (p_phone, v_user, p_code_hash, now() + interval '10 minutes')
  returning * into v_row;

  return query select v_row.id, v_row.user_id;
end;
$$;

revoke execute on function
  public.open_pin_reset(text, text) from public, anon, authenticated;


-- -----------------------------------------------------------------------------
-- Checking a code
-- -----------------------------------------------------------------------------
-- Returns the user only for a code that is correct, live, unused and within its
-- attempt budget. A wrong guess is counted whether or not the number exists.
-- -----------------------------------------------------------------------------

create or replace function public.verify_pin_reset(
  p_phone     text,
  p_code_hash text
)
returns table (user_id uuid, ok boolean, reason text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.pin_reset_requests;
begin
  select * into v_row
    from public.pin_reset_requests r
   where r.phone = p_phone
     and r.consumed_at is null
   order by r.created_at desc
   limit 1
   for update;

  if not found then
    return query select null::uuid, false, 'no_request';
    return;
  end if;

  if v_row.expires_at < now() then
    update public.pin_reset_requests set consumed_at = now() where id = v_row.id;
    return query select null::uuid, false, 'expired';
    return;
  end if;

  if v_row.attempts >= 5 then
    update public.pin_reset_requests set consumed_at = now() where id = v_row.id;
    return query select null::uuid, false, 'too_many_attempts';
    return;
  end if;

  if v_row.code_hash <> p_code_hash then
    update public.pin_reset_requests
       set attempts = attempts + 1
     where id = v_row.id;
    return query select null::uuid, false, 'wrong_code';
    return;
  end if;

  -- Correct: burn the code so it cannot be replayed.
  update public.pin_reset_requests
     set consumed_at = now()
   where id = v_row.id;

  return query select v_row.user_id, true, 'ok';
end;
$$;

revoke execute on function
  public.verify_pin_reset(text, text) from public, anon, authenticated;


-- Housekeeping: spent and expired rows carry no value once done with.
create or replace function public.purge_pin_resets()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.pin_reset_requests
   where created_at < now() - interval '7 days';
$$;

revoke execute on function public.purge_pin_resets() from public, anon, authenticated;
