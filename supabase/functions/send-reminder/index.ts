// =============================================================================
// send-reminder - an admin nudges a parent about an outstanding balance
// =============================================================================
//
// Two deliveries, reported separately and truthfully:
//
//   IN-APP  the reminder row is created, and the parent sees it in the app.
//           This always happens, and is the one we can guarantee.
//
//   PUSH    attempted only if this project has push credentials AND the parent
//           has a registered device. The outcome is written back onto the
//           reminder (sent / no_device / not_configured / failed) and returned
//           to the admin, so the UI never claims a push that did not happen.
//
// Push transport is Firebase Cloud Messaging HTTP v1. It needs a service
// account for the Firebase project, in the FCM_SERVICE_ACCOUNT secret as JSON.
// Without it, everything else still works and push reports 'not_configured'.
// =============================================================================

import {
  callerClient,
  corsHeaders,
  failure,
  json,
  requireAuth,
  serviceClient,
} from "../_shared/supabase.ts";

interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authorization = requireAuth(req);
    const body = await req.json().catch(() => ({}));
    const relationshipId = String(body.relationshipId ?? "");
    if (!relationshipId) return json({ error: "Missing relationship" }, 400);

    // Admin status is decided by the database, not by the caller.
    const caller = callerClient(authorization);
    const { data: isAdmin } = await caller.rpc("is_platform_admin");
    if (isAdmin !== true) return json({ error: "Not authorised" }, 403);

    const { data: user } = await caller.auth.getUser();
    const service = serviceClient();

    // ---- 1. The in-app reminder, which is genuinely delivered -------------
    const { data: reminder, error: reminderError } = await service
      .rpc("create_payment_due_reminder", {
        p_relationship_id: relationshipId,
        p_sent_by: user?.user?.id ?? null,
        p_message: typeof body.message === "string" && body.message.trim()
          ? body.message.trim()
          : null,
      })
      .single();

    if (reminderError || !reminder) {
      return failure(reminderError ?? new Error("Could not create reminder"));
    }

    // ---- 2. Push, if it is actually possible ------------------------------
    let pushStatus = "not_configured";
    // Why push failed, when it did. Returned to the admin so a rejection is
    // diagnosable from the app instead of only from the function logs.
    let pushDetail: string | null = null;
    const rawAccount = Deno.env.get("FCM_SERVICE_ACCOUNT");

    if (rawAccount) {
      const { data: tokens } = await service.rpc("push_tokens_for_user", {
        p_user_id: reminder.user_id,
      });
      const list = (tokens ?? []) as Array<{ token: string }>;

      if (list.length === 0) {
        pushStatus = "no_device";
      } else {
        try {
          const account = JSON.parse(rawAccount) as ServiceAccount;
          const accessToken = await getAccessToken(account);
          let anySent = false;

          for (const { token } of list) {
            const result = await sendPush(account.project_id, accessToken, token, {
              title: reminder.title,
              body: reminder.body,
            });
            anySent = anySent || result.ok;
            if (!result.ok) pushDetail = result.detail;
          }
          pushStatus = anySent ? "sent" : "failed";
        } catch (pushError) {
          console.error("[camiva-payments] push failed", pushError);
          pushStatus = "failed";
          pushDetail = pushError instanceof Error
            ? pushError.message
            : String(pushError);
        }
      }
    }

    await service.rpc("record_reminder_push", {
      p_reminder_id: reminder.id,
      p_status: pushStatus,
    });

    return json({
      reminderId: reminder.id,
      inApp: true,
      push: pushStatus,
      pushDetail,
      body: reminder.body,
    });
  } catch (error) {
    return failure(error, 400);
  }
});

/** Signs a JWT with the service account key and exchanges it for a token. */
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
  const payload = await response.json();
  return payload.access_token as string;
}

async function sendPush(
  projectId: string,
  accessToken: string,
  token: string,
  notification: { title: string; body: string },
): Promise<{ ok: boolean; detail: string | null }> {
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
          // Same branding as push-fanout: a white silhouette of the mark,
          // tinted with the blue the app icon starts from. Android builds the
          // notification itself when the app is in the background, so this
          // has to travel with the message.
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
  if (response.ok) return { ok: true, detail: null };

  const body = await response.text();
  console.error("[camiva-payments] fcm rejected", response.status, body);

  // Google's own words, trimmed. This is shown to an admin, never to a parent
  // or teacher.
  let reason = body;
  try {
    reason = JSON.parse(body)?.error?.message ?? body;
  } catch {
    // Not JSON; the raw body is the best available answer.
  }
  return { ok: false, detail: `FCM ${response.status}: ${reason}`.slice(0, 300) };
}
