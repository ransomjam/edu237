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
