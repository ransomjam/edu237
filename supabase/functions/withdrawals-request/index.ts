// =============================================================================
// withdrawals-request — teacher payout
// =============================================================================
//
//   Flutter → withdrawals-request → request_withdrawal (as the caller)
//                                 → Fapshi /payout
//                                 → attach_withdrawal_provider_ref (service role)
//
// The eligible amount is checked inside request_withdrawal(): it derives the
// balance from the ledger, takes an advisory lock so two taps cannot both pass,
// and refuses a second in-flight withdrawal. The client's number is never used
// as the destination — the payout goes to the teacher's stored payout account,
// which only they can change.
//
// The withdrawal ends this call as 'processing', never 'successful'. Only a
// confirmed payout status (webhook or verification) settles it.
//
// PROVIDER-SIDE ACTIVATION: payouts are disabled by default on live and need a
// separate, Fapshi-activated payout service. Without FAPSHI_PAYOUT_* secrets
// this function fails cleanly and the withdrawal is marked failed — it never
// pretends money moved.
// =============================================================================

import { FapshiError, payout, payoutCredentials } from "../_shared/fapshi.ts";
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
    const amount = Number(body.amount ?? 0);
    if (!Number.isInteger(amount) || amount <= 0) {
      return json({ error: "Enter a valid amount" }, 400);
    }

    const caller = callerClient(authorization);
    const { data: withdrawal, error: requestError } = await caller
      .rpc("request_withdrawal", { p_amount: amount })
      .single();

    if (requestError || !withdrawal) {
      return failure(requestError ?? new Error("Could not request withdrawal"));
    }

    const service = serviceClient();

    // ---- Manual settlement -------------------------------------------------
    // Fapshi disburses only through a separate, provider-activated payout
    // service. While payout_mode is 'manual' the provider is not called at all:
    // the withdrawal stays 'requested' until an Camiva admin sends the money
    // themselves and records it. Nothing here implies money has moved.
    const { data: config } = await service
      .from("platform_fee_config")
      .select("payout_mode")
      .eq("id", 1)
      .maybeSingle();

    if (config?.payout_mode !== "provider") {
      return json({
        withdrawalId: withdrawal.id,
        status: withdrawal.status,
        amount: withdrawal.amount,
        currency: withdrawal.currency,
        settlementMode: "manual",
      });
    }

    try {
      const result = await payout(payoutCredentials(), {
        amount: withdrawal.amount,
        phone: withdrawal.payout_phone,
        medium: withdrawal.payout_medium === "orange money"
          ? "orange money"
          : "mobile money",
        userId: withdrawal.teacher_id,
        externalId: withdrawal.id,
        message: "Camiva earnings withdrawal",
      });

      const { data: updated, error: attachError } = await service
        .rpc("attach_withdrawal_provider_ref", {
          p_withdrawal_id: withdrawal.id,
          p_trans_id: result.transId,
        })
        .single();
      if (attachError) return failure(attachError, 500);

      return json({
        withdrawalId: updated.id,
        status: updated.status,
        amount: updated.amount,
        currency: updated.currency,
      });
    } catch (providerError) {
      const reason = providerError instanceof FapshiError
        ? providerError.message
        : "Payout could not be started";
      await service.rpc("fail_withdrawal", {
        p_withdrawal_id: withdrawal.id,
        p_reason: reason,
      });
      return json({
        withdrawalId: withdrawal.id,
        status: "failed",
        error: "Withdrawal could not be started. Your earnings are unchanged.",
      }, 502);
    }
  } catch (error) {
    return failure(error, 400);
  }
});
