// =============================================================================
// pin-reset-request - sends a recovery code by SMS
// =============================================================================
//
// The only place Camiva sends an OTP. Normal sign-in is phone plus PIN with no
// code; this exists solely so a forgotten PIN is recoverable by proving you
// hold the registered number.
//
// The reply is ALWAYS the same, whether or not the number is registered and
// whether or not it is over its rate limit. Anything else turns this endpoint
// into a way to discover who has an account.
//
// The code is generated here, hashed before storage, and sent by SMS. It is
// never returned to the app.
//
// SMS PROVIDER: configured through secrets. Without them nothing is sent and
// the function says so in its logs — it never pretends a code went out.
// =============================================================================

import {
  corsHeaders,
  json,
  serviceClient,
} from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // Deliberately identical for every outcome below.
  const sameAnswer = json({
    sent: true,
    message: "If that number has an account, a code has been sent to it.",
  });

  let phone = "";
  try {
    const body = await req.json();
    phone = normalisePhone(String(body.phone ?? ""));
  } catch {
    return sameAnswer;
  }
  if (!phone) return sameAnswer;

  const service = serviceClient();

  try {
    // Six digits, from the platform's cryptographic source rather than
    // Math.random.
    const code = generateCode();
    const codeHash = await sha256(code);

    const { data, error } = await service
      .rpc("open_pin_reset", { p_phone: phone, p_code_hash: codeHash })
      .maybeSingle();

    // No row: unknown number, or over the limit. The caller cannot tell.
    if (error || !data) return sameAnswer;

    await sendSms(
      phone,
      `Camiva: your PIN reset code is ${code}. It expires in 10 minutes. ` +
        `If you did not ask for this, ignore this message.`,
    );

    return sameAnswer;
  } catch (error) {
    console.error("[camiva-auth] pin reset request failed", error);
    // Still the same answer: a failure here must not become a signal either.
    return sameAnswer;
  }
});

function normalisePhone(input: string): string | "" {
  let digits = input.replace(/\D/g, "");
  if (digits.startsWith("00237")) digits = digits.slice(5);
  else if (digits.startsWith("237") && digits.length > 9) digits = digits.slice(3);
  return /^6\d{8}$/.test(digits) ? digits : "";
}

function generateCode(): string {
  const bytes = new Uint32Array(1);
  crypto.getRandomValues(bytes);
  return (bytes[0] % 1_000_000).toString().padStart(6, "0");
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// Sends the code. Twilio-shaped, because that is what most providers imitate;
/// swap the body for another gateway if you use one.
async function sendSms(phone: string, message: string): Promise<void> {
  const sid = Deno.env.get("SMS_ACCOUNT_SID") ?? "";
  const token = Deno.env.get("SMS_AUTH_TOKEN") ?? "";
  const from = Deno.env.get("SMS_FROM") ?? "";

  if (!sid || !token || !from) {
    // Nothing is sent, and nothing claims otherwise.
    console.error(
      "[camiva-auth] SMS is not configured; no recovery code was sent",
    );
    return;
  }

  const response = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${sid}:${token}`)}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        To: `+237${phone}`,
        From: from,
        Body: message,
      }),
    },
  );

  if (!response.ok) {
    console.error(
      "[camiva-auth] SMS provider rejected",
      response.status,
      await response.text(),
    );
  }
}
