// =============================================================================
// pin-reset-confirm - checks the code and sets the new PIN
// =============================================================================
//
// The app sends the phone number, the SMS code, and the secret DERIVED from the
// new PIN. The raw PIN never leaves the device — exactly as at sign-in, so this
// flow adds no new exposure.
//
// The secret is written with the admin API, which is why this runs server-side:
// changing someone's credentials requires the service role, and the service
// role must never be in the app.
//
// Every refusal is reported as the same thing to the caller: whether the code
// was wrong, expired, already used, or over its attempt budget, the answer is
// "that code is not valid". The database counts the attempts and closes the
// request; the caller learns nothing it could use to work through the space.
// =============================================================================

import {
  createClient,
} from "https://esm.sh/@supabase/supabase-js@2.47.10";
import { corsHeaders, json, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let phone = "";
  let code = "";
  let secret = "";
  try {
    const body = await req.json();
    phone = normalisePhone(String(body.phone ?? ""));
    code = String(body.code ?? "").replace(/\D/g, "");
    secret = String(body.secret ?? "");
  } catch {
    return json({ error: "Invalid request" }, 400);
  }

  // The secret is a sha-256 hex digest produced by the app. Anything else means
  // a caller is not using the real flow.
  if (!phone || code.length !== 6 || !/^[0-9a-f]{64}$/.test(secret)) {
    return json({ error: "That code is not valid." }, 400);
  }

  const service = serviceClient();

  try {
    const codeHash = await sha256(code);
    const { data, error } = await service
      .rpc("verify_pin_reset", { p_phone: phone, p_code_hash: codeHash })
      .maybeSingle();

    if (error || !data?.ok || !data?.user_id) {
      // One message for every kind of refusal.
      return json({ error: "That code is not valid." }, 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
      { auth: { persistSession: false } },
    );

    const { error: updateError } = await admin.auth.admin.updateUserById(
      data.user_id as string,
      { password: secret },
    );
    if (updateError) {
      console.error("[camiva-auth] could not set new PIN", updateError);
      return json({ error: "Could not set your new PIN. Please try again." }, 500);
    }

    return json({ reset: true });
  } catch (error) {
    console.error("[camiva-auth] pin reset confirm failed", error);
    return json({ error: "Could not set your new PIN. Please try again." }, 500);
  }
});

function normalisePhone(input: string): string | "" {
  let digits = input.replace(/\D/g, "");
  if (digits.startsWith("00237")) digits = digits.slice(5);
  else if (digits.startsWith("237") && digits.length > 9) digits = digits.slice(3);
  return /^6\d{8}$/.test(digits) ? digits : "";
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
