// =============================================================================
// payments-verify — reconcile one transaction on demand
// =============================================================================
//
// The app calls this while a payment screen is waiting, and when a teacher
// reopens a pending withdrawal. It exists because a webhook can be late or
// lost — NOT as a way for the client to declare success: the status still comes
// from Fapshi's own /payment-status answer, and is applied through exactly the
// same idempotent function the webhook uses.
//
// The caller may only verify a transaction they are party to: the row is read
// with the user's JWT, so RLS decides.
// =============================================================================

import {
  collectionCredentials,
  paymentStatus,
  payoutCredentials,
} from "../_shared/fapshi.ts";
import {
  callerClient,
  corsHeaders,
  failure,
  json,
  requireAuth,
  serviceClient,
} from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authorization = requireAuth(req);
    const body = await req.json().catch(() => ({}));
    const caller = callerClient(authorization);
    const service = serviceClient();

    if (typeof body.paymentId === "string") {
      const { data: payment } = await caller
        .from("payment_transactions")
        .select("id, status, provider_trans_id")
        .eq("id", body.paymentId)
        .maybeSingle();

      if (!payment) return json({ error: "Payment not found" }, 404);
      if (!payment.provider_trans_id || payment.status !== "pending") {
        return json({ paymentId: payment.id, status: payment.status });
      }

      const verified = await paymentStatus(
        collectionCredentials(),
        payment.provider_trans_id,
      );
      const { data: updated, error } = await service
        .rpc("apply_payment_provider_status", {
          p_trans_id: payment.provider_trans_id,
          p_status: verified.status,
          p_payload: verified,
          p_source: "verify",
        })
        .single();
      if (error) return failure(error, 500);

      return json({ paymentId: updated.id, status: updated.status });
    }

    if (typeof body.withdrawalId === "string") {
      const { data: withdrawal } = await caller
        .from("withdrawals")
        .select("id, status, provider_trans_id")
        .eq("id", body.withdrawalId)
        .maybeSingle();

      if (!withdrawal) return json({ error: "Withdrawal not found" }, 404);
      if (
        !withdrawal.provider_trans_id ||
        !["requested", "processing"].includes(withdrawal.status)
      ) {
        return json({ withdrawalId: withdrawal.id, status: withdrawal.status });
      }

      const verified = await paymentStatus(
        payoutCredentials(),
        withdrawal.provider_trans_id,
      );
      const { data: updated, error } = await service
        .rpc("apply_payout_provider_status", {
          p_trans_id: withdrawal.provider_trans_id,
          p_status: verified.status,
          p_payload: verified,
          p_source: "verify",
        })
        .single();
      if (error) return failure(error, 500);

      return json({ withdrawalId: updated.id, status: updated.status });
    }

    return json({ error: "Nothing to verify" }, 400);
  } catch (error) {
    return failure(error, 400);
  }
});
