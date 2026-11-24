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
