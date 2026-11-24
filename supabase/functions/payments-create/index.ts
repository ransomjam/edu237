// =============================================================================
// payments-create — start a payment
// =============================================================================
//
//   Flutter → payments-create → create_payment_intent (as the caller, RLS on)
//                             → Fapshi
//                             → attach_payment_provider_ref (service role)
//
// The client sends only WHAT it is paying for, never how much: the amount is
// computed inside create_payment_intent() from platform_fee_config or the
// teacher's rate. The response is always 'pending' — success can only ever come
// from Fapshi via the webhook or an explicit verification.
//
// Integration method
// -----------------------------------------------------------------------------
// DIRECT PAY is used when the payer gives a mobile money number: the prompt
// arrives on their phone and they never leave the app or see a provider page,
// which is the UX Camiva wants for parents and teachers here. Fapshi disables
// Direct Pay on live until they activate it for the service.
//
// INITIATE PAY (Fapshi-hosted checkout link) is the fallback — no phone number,
// or FAPSHI_PAYMENT_METHOD=initiate. It needs no provider-side activation, so
// the flow still works end-to-end before Direct Pay is activated.
// =============================================================================

import {
  collectionCredentials,
  directPay,
  initiatePay,
} from "../_shared/fapshi.ts";
import {
  callerClient,
  corsHeaders,
  failure,
  json,
  requireAuth,
  serviceClient,
} from "../_shared/supabase.ts";

const PURPOSES = [
  "teacher_service_fee",
  "match_activation",
  "tutoring_payment",
] as const;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authorization = requireAuth(req);
    const body = await req.json().catch(() => ({}));

    const purpose = String(body.purpose ?? "");
    if (!PURPOSES.includes(purpose as typeof PURPOSES[number])) {
      return json({ error: "Unknown payment purpose" }, 400);
    }

    const caller = callerClient(authorization);
    const { data: user } = await caller.auth.getUser();
    if (!user?.user) return json({ error: "Not authenticated" }, 401);

    // ---- 1. Internal record first, amount decided server-side --------------
    const { data: payment, error: intentError } = await caller
      .rpc("create_payment_intent", {
        p_purpose: purpose,
        p_relationship_id: body.relationshipId ?? null,
        p_units: Number(body.units ?? 1),
        p_session_id: body.sessionId ?? null,
      })
      .single();

    if (intentError || !payment) {
      return failure(intentError ?? new Error("Could not start this payment"));
    }

    // ---- 2. Provider call --------------------------------------------------
    const service = serviceClient();
    const creds = collectionCredentials();
    const useDirect = Deno.env.get("FAPSHI_PAYMENT_METHOD") !== "initiate" &&
      typeof body.phone === "string" && /^6\d{8}$/.test(body.phone);

    try {
      let transId: string;
      let checkoutUrl: string | null = null;

      if (useDirect) {
        const result = await directPay(creds, {
          amount: payment.amount,
          phone: body.phone,
          medium: body.medium === "orange money" ? "orange money" : undefined,
          userId: payment.payer_id,
          externalId: payment.id,
          message: payment.description ?? "Camiva",
        });
        transId = result.transId;
      } else {
        const redirectUrl = Deno.env.get("FAPSHI_REDIRECT_URL");
        const result = await initiatePay(creds, {
          amount: payment.amount,
          userId: payment.payer_id,
          externalId: payment.id,
          message: payment.description ?? "Camiva",
          email: user.user.email ?? undefined,
          redirectUrl: redirectUrl || undefined,
        });
        transId = result.transId;
        checkoutUrl = result.link;
      }

      const { data: updated, error: attachError } = await service
        .rpc("attach_payment_provider_ref", {
          p_payment_id: payment.id,
          p_trans_id: transId,
          p_checkout_url: checkoutUrl,
        })
        .single();
      if (attachError) return failure(attachError, 500);

      return json({
        paymentId: updated.id,
        status: updated.status,
        amount: updated.amount,
        currency: updated.currency,
        purpose: updated.purpose,
        checkoutUrl: updated.checkout_url,
        providerTransId: updated.provider_trans_id,
        method: useDirect ? "direct" : "initiate",
      });
    } catch (providerError) {
      // The provider never accepted the request, so nothing is in flight: the
      // intent is cancelled rather than left dangling as pending.
      await service.rpc("fail_payment_intent", {
        p_payment_id: payment.id,
        p_reason: providerError instanceof Error
          ? providerError.message
          : "Provider error",
      });
      return failure(new Error("Payment could not be started. Please try again."), 502);
    }
  } catch (error) {
    return failure(error, 400);
  }
});
