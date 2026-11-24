// =============================================================================
// fapshi-webhook — the authoritative source of payment state
// =============================================================================
//
// Fapshi POSTs here when a transaction becomes SUCCESSFUL, FAILED or EXPIRED,
// with an `x-wh-secret` header carrying the secret configured on the Fapshi
// dashboard, and a body identical to the /payment-status response.
//
// Three layers of defence, in this order:
//
//   1. Secret check      — the header must match FAPSHI_WEBHOOK_SECRET
//                          (constant-time compare).
//   2. Re-verification   — the posted body is treated as a NOTIFICATION, not as
//                          truth. We call GET /payment-status/{transId}
//                          ourselves and act on that answer, so a forged body
//                          that somehow passed step 1 still cannot mark a
//                          payment successful.
//   3. Idempotency       — apply_payment_provider_status() /
//                          apply_payout_provider_status() log the event under a
//                          unique (transId, status) key and only apply the
//                          transition on the first delivery. Repeated delivery
//                          is a no-op, so a redelivered "successful" webhook
//                          cannot double-activate or double-count earnings.
//
// This function is deployed with verify_jwt = false (Fapshi has no Supabase
// JWT); the shared secret is the authentication.
//
// It always answers 200 quickly once the request is authenticated, because
// Fapshi sends only one webhook per event regardless of the response.
// =============================================================================

import {
  collectionCredentials,
  paymentStatus,
  payoutCredentials,
  secretMatches,
} from "../_shared/fapshi.ts";
import { json, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // ---- 1. Authenticate the caller -----------------------------------------
  // On LIVE the shared secret is mandatory and the endpoint fails closed
  // without it.
  //
  // In SANDBOX, where the dashboard may not offer a secret at all, an
  // unconfigured secret is allowed. That is safe here specifically because of
  // step 2: the posted body is never believed. Whatever arrives, we ask Fapshi
  // ourselves what the transaction's status is, and the transId must already
  // match a payment we created. So the worst an unauthenticated POST can do is
  // make us re-check a real transaction's real status — exactly what our own
  // verify endpoint does on demand. It can never invent a payment or mark one
  // successful.
  const expected = Deno.env.get("FAPSHI_WEBHOOK_SECRET") ?? "";
  const isLive = Deno.env.get("FAPSHI_ENV") === "live";

  if (isLive && !expected) {
    console.error(
      "[camiva-payments] FAPSHI_WEBHOOK_SECRET is required on live",
    );
    return json({ error: "Not configured" }, 500);
  }
  if (expected && !secretMatches(req.headers.get("x-wh-secret"), expected)) {
    // Do not describe what was wrong.
    return json({ error: "Unauthorized" }, 401);
  }
  if (!expected) {
    console.warn(
      "[camiva-payments] webhook accepted without a shared secret (sandbox); " +
        "status still verified with Fapshi before being applied",
    );
  }

  let notification: Record<string, unknown>;
  try {
    notification = await req.json();
  } catch {
    return json({ error: "Invalid payload" }, 400);
  }

  const transId = typeof notification.transId === "string"
    ? notification.transId
    : "";
  if (!transId) return json({ error: "Missing transId" }, 400);

  const service = serviceClient();

  try {
    // ---- 2. Ask Fapshi directly; never trust the posted status -------------
    // A payout transaction belongs to the payout service, a collection to the
    // collection service, so the lookup is tried against the credentials that
    // match the transaction type, falling back to the other pair.
    const isPayout = String(notification.transType ?? "").toLowerCase() === "payout";
    const verified = await verifyTransaction(transId, isPayout);

    if (isPayout || String(verified.transType ?? "").toLowerCase() === "payout") {
      const { error } = await service.rpc("apply_payout_provider_status", {
        p_trans_id: transId,
        p_status: verified.status,
        p_payload: verified,
        p_source: "webhook",
      });
      if (error) throw error;
    } else {
      const { error } = await service.rpc("apply_payment_provider_status", {
        p_trans_id: transId,
        p_status: verified.status,
        p_payload: verified,
        p_source: "webhook",
      });
      if (error) throw error;
    }

    return json({ received: true });
  } catch (error) {
    // Logged for investigation. The transaction can still be reconciled later
    // through payments-verify, which applies the identical transition.
    console.error("[camiva-payments] webhook handling failed", error);
    return json({ received: true, applied: false }, 200);
  }
});

async function verifyTransaction(transId: string, preferPayout: boolean) {
  const pairs = preferPayout
    ? [safe(payoutCredentials), safe(collectionCredentials)]
    : [safe(collectionCredentials), safe(payoutCredentials)];

  let lastError: unknown = new Error("No Fapshi credentials configured");
  for (const creds of pairs) {
    if (!creds) continue;
    try {
      return await paymentStatus(creds, transId);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

function safe<T>(read: () => T): T | null {
  try {
    return read();
  } catch {
    return null;
  }
}
