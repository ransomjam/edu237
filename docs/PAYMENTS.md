# Camiva — commercial layer

How money moves through Camiva, what is configurable, and what still needs to
be switched on by Fapshi.

---

## 1. Architecture

```
Flutter screen
   → Camiva Edge Function (holds the Fapshi credentials)
      → Fapshi API
         → Fapshi webhook  →  Camiva Edge Function
                               → Supabase ledger (payment_transactions)
                                  → relationship activation / earnings / reminders
```

The Flutter app never talks to Fapshi and never holds `apiuser` / `apikey`.
Three properties are enforced structurally rather than by convention:

| Rule | How it is enforced |
|---|---|
| The client cannot set an amount | Amounts come from `payment_quote()`, computed from `platform_fee_config` or the teacher's rate. The API takes no amount. |
| The client cannot declare success | `payment_transactions` has no INSERT/UPDATE policy. Status is written only by `apply_payment_provider_status()`, whose EXECUTE is revoked from `authenticated`. |
| The client cannot see what it should not | RLS restricts every row to the parties to it; contact details come only from `relationship_contact()`, which returns nothing until activation is satisfied. |

There is no stored balance anywhere. Earnings are recomputed from the ledger by
`teacher_earnings_summary()` on every read.

### Files

| Area | Path |
|---|---|
| Migration | `supabase/migrations/20260815000000_payments.sql` |
| Fapshi client | `supabase/functions/_shared/fapshi.ts` |
| Start a payment | `supabase/functions/payments-create/` |
| Webhook | `supabase/functions/fapshi-webhook/` |
| Re-check a transaction | `supabase/functions/payments-verify/` |
| Withdrawals | `supabase/functions/withdrawals-request/` |
| App services | `lib/core/services/payment_service.dart`, `earnings_service.dart` |
| App screens | `lib/features/payments/` |
| DB tests | `supabase/tests/payments_test.sql` |
| Sandbox check | `tool/fapshi_sandbox_check.dart` |

---

## 2. Integration method

Both documented collection methods are implemented, and the choice is made per
payment:

- **Direct Pay** (default) — when the payer gives a mobile money number, the
  approval prompt goes to their phone. They never leave the app or see a
  provider page, which is the right UX for parents and teachers here.
- **Initiate Pay** (fallback) — a Fapshi-hosted checkout link, used when no
  phone number is given or `FAPSHI_PAYMENT_METHOD=initiate`. It needs no
  provider-side activation, so the whole flow works on live before Direct Pay is
  enabled.

Endpoints used, per the official documentation: `POST /initiate-pay`,
`POST /direct-pay`, `GET /payment-status/{transId}`, `POST /payout`.
Base URLs: `https://sandbox.fapshi.com` and `https://live.fapshi.com`.
Auth: the `apiuser` and `apikey` headers.

---

## 3. Pricing is configuration, not code

`platform_fee_config` ships with **null amounts and activation switched off**,
so nothing is charged until an operator sets values:

```sql
update public.platform_fee_config set
  teacher_service_fee_amount  = 1000,   -- current target range 500–1000 XAF
  match_activation_fee_amount = 1000,
  match_activation_required   = true
where id = 1;
```

Other knobs: `teacher_service_fee_interval_days`, `settlement_delay_hours`
(how long earnings stay "Pending"), `min_withdrawal_amount`, and
`teacher_earning_bps`, which ships at **10000 = 100%** — Camiva takes no
percentage of a lesson by default. There is no commission engine.

Only the service role can write this row; every signed-in user can read it,
because the app must show the exact fee before charging.

---

## 4. Setup

### Secrets

```bash
cp supabase/functions/.env.example supabase/functions/.env   # local only
supabase secrets set --env-file supabase/functions/.env       # deployed
```

`supabase/functions/.env` is gitignored. Never put these in the Flutter app.

### Deploy

```bash
supabase db push
supabase functions deploy payments-create payments-verify withdrawals-request
supabase functions deploy fapshi-webhook --no-verify-jwt
```

`fapshi-webhook` must be deployed with JWT verification off — Fapshi has no
Supabase token. It authenticates with the `x-wh-secret` header instead, and the
same secret must be set on the Fapshi dashboard and in `FAPSHI_WEBHOOK_SECRET`.

Webhook URL to configure at Fapshi:

```
https://<project-ref>.supabase.co/functions/v1/fapshi-webhook
```

---

## 5. Webhook handling

1. **Authenticate** — `x-wh-secret` is compared to `FAPSHI_WEBHOOK_SECRET` in
   constant time. A mismatch gets a bare 401.
2. **Re-verify** — the posted body is treated as a notification, not as truth.
   The function calls `GET /payment-status/{transId}` itself and acts on that
   answer, so a forged body cannot settle a payment even if it passed step 1.
3. **Apply idempotently** — the event is logged under a unique
   `(provider, transId, status)` key. A redelivery collides and returns without
   re-applying, so repeated delivery cannot double-activate a relationship or
   double-count earnings. The ledger trigger independently rejects illegal
   transitions and no-ops on repeats.

Status mapping: `SUCCESSFUL → successful`, `FAILED → failed`,
`EXPIRED → cancelled`, `CREATED`/`PENDING → pending` (no state change).

Payout transactions arrive on the same endpoint and are routed to
`apply_payout_provider_status()`.

`payments-verify` exists because a webhook can be late or lost. It applies the
identical function with `source = 'verify'`; it is a reconciliation path, not a
way for the client to declare success.

---

## 6. Flows

**Teacher activation** — accept a request → if `relationship_activation_state`
is `required`, the activation screen opens: *"Activate your Camiva teaching
relationship"*, the exact fee, *Pay & activate*. The parent's contact details
appear only once the payment is confirmed. The charge is never called an unlock
fee.

**Parent payment** — *Pay for tutoring* → the amount is quoted by the server
from the teacher's rate → *Pay with Mobile Money* → processing → receipt, saved
in **Payments** with its reference.

**Teacher earnings** — Available / Pending / Earned so far, all derived from the
ledger, plus the payments behind them. *Withdraw* → destination and amount →
*Request withdrawal* → `requested` → `processing` → settled only by a confirmed
payout.

**Reminders** — in-app rows created by the server at real events (payment
confirmed, relationship activated, payout settled, fee period opened). There is
no push transport in the app yet, so nothing claims a push was sent.

**Support** — *Need help?* records the message with the payment/relationship
reference. No refund or outcome is promised, because no policy exists yet.

---

## 7. Testing

```bash
flutter test                                                    # app-side
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/payments_test.sql
dart run tool/fapshi_sandbox_check.dart --apiuser=... --apikey=...
```

The SQL script covers what Dart cannot: RLS isolation, function grants, webhook
idempotency, ledger immutability and withdrawal eligibility. It runs in a
transaction and rolls back. Point it at a local or staging database only.

---

## 8. Provider-side requirements (not done in code)

These need action at Fapshi and cannot be completed from this repository:

1. **Sandbox credentials** for a collection service → `FAPSHI_COLLECTION_*`.
2. **Webhook secret** set on the dashboard → `FAPSHI_WEBHOOK_SECRET`, and the
   webhook URL pointed at the deployed function.
3. **Direct Pay activation on live** — disabled by default. Until it is enabled,
   live payments use the hosted checkout link automatically.
4. **A separate payout service, activated by Fapshi** — payouts are disabled by
   default on live, and an activated payout service *cannot also collect
   payments*. That is why collections and payouts use two credential pairs.
   Without `FAPSHI_PAYOUT_*`, withdrawals fail cleanly and the teacher's
   earnings are left untouched.
5. **Live credentials** — `FAPSHI_ENV=live` is the only way to reach live, and
   should only be set deliberately.

---

## 9. Deliberately not built

- No billing scheduler. `service_fee_periods` gives due / reminded / paid /
  overdue; nothing charges automatically.
- No dispute system beyond recording a support request with its reference.
- No refund flow. `refunded` exists in the ledger's status model; nothing writes
  it yet.
- No push notifications.
