// =============================================================================
// push-fanout - pushes every Camiva reminder
// =============================================================================
//
// Called by a Supabase database webhook on INSERT into payment_reminders. Every
// notifiable event already writes one of those rows, so wiring push to the
// TABLE rather than to individual actions means anything that creates a
// reminder is pushed — including reminders added later, with no further wiring.
//
//   event -> payment_reminders row -> webhook -> here -> FCM
//
// Honest reporting is the same as everywhere else: the row is the in-app
// notification and always lands. Push is separate, and its outcome is written
// back onto the row (sent / no_device / not_configured / failed).
//
// A token FCM reports as dead is deleted. Devices are reinstalled, restored and
// wiped constantly; keeping a dead token means retrying it forever.
//
// Deployed with verify_jwt = false: the webhook has no Supabase JWT. It carries
// the service-role key in a header instead, which is checked below.
// =============================================================================

import { json, serviceClient } from "../_shared/supabase.ts";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  // The webhook is configured to send the service-role key. Nothing else may
  // trigger a fanout: it reads other people's device tokens.
  const expected = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const provided = req.headers.get("x-webhook-secret") ??
    (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  if (!expected || provided !== expected) {
    return json({ error: "Unauthorized" }, 401);
  }

  let payload: { record?: { id?: string } };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Invalid payload" }, 400);
  }

  const reminderId = payload.record?.id;
  if (!reminderId) return json({ error: "Missing reminder" }, 400);

  const service = serviceClient();

  try {
    const { data, error } = await service
      .rpc("reminder_for_push", { p_reminder_id: reminderId })
      .single();
    if (error || !data) return json({ error: "Reminder not found" }, 404);

    const tokens = (data.tokens ?? []) as string[];
    let status = "not_configured";

    const rawAccount = Deno.env.get("FCM_SERVICE_ACCOUNT");
    if (!rawAccount) {
      status = "not_configured";
    } else if (tokens.length === 0) {
      status = "no_device";
    } else {
      const account = JSON.parse(rawAccount) as ServiceAccount;
      const accessToken = await getAccessToken(account);
      let anySent = false;

      for (const token of tokens) {
        const result = await sendPush(account.project_id, accessToken, token, {
          title: data.title as string,
          body: data.body as string,
        });
        anySent = anySent || result.ok;

        // A token the provider says is gone is removed rather than retried on
        // every future reminder.
        if (result.dead) {
          await service.rpc("forget_dead_push_token", { p_token: token });
        }
      }
      status = anySent ? "sent" : "failed";
    }

    await service.rpc("record_reminder_push", {
      p_reminder_id: reminderId,
      p_status: status,
    });

    return json({ reminderId, push: status });
  } catch (error) {
    console.error("[camiva-push] fanout failed", error);
    // The in-app reminder already exists; a push failure must not retry the
    // webhook forever.
    return json({ reminderId, push: "failed" }, 200);
  }
});

async function getAccessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();
  const toBase64Url = (data: Uint8Array | string) => {
    const bytes = typeof data === "string" ? encoder.encode(data) : data;
    return btoa(String.fromCharCode(...bytes))
      .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };

  const unsigned = `${toBase64Url(JSON.stringify(header))}.${
    toBase64Url(JSON.stringify(claims))
  }`;

  const pem = account.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(unsigned)),
  );

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${toBase64Url(signature)}`,
    }),
  });

  if (!response.ok) {
    throw new Error(`Token exchange failed (${response.status})`);
  }
  return (await response.json()).access_token as string;
}

async function sendPush(
  projectId: string,
  accessToken: string,
  token: string,
  notification: { title: string; body: string },
): Promise<{ ok: boolean; dead: boolean }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification,
          // Branding, stated in the payload rather than left to the manifest
          // defaults. Android draws the small icon from its alpha channel
          // only, so ic_stat_camiva is a white silhouette of the mark, and
          // the colour behind it is the blue the app icon starts from.
          android: {
            notification: {
              icon: "ic_stat_camiva",
              color: "#0330DB",
            },
          },
        },
      }),
    },
  );

  if (response.ok) return { ok: true, dead: false };

  const body = await response.text();
  console.error("[camiva-push] fcm rejected", response.status, body);

  // 404 UNREGISTERED / 400 with an invalid-argument token both mean this
  // device will never receive anything again.
  const dead = response.status === 404 ||
    body.includes("UNREGISTERED") ||
    body.includes("InvalidRegistration");
  return { ok: false, dead };
}
