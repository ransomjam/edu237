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
