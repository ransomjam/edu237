// =============================================================================
// Supabase clients + shared HTTP helpers for the Camiva payment functions
// =============================================================================
//
// Two clients, used deliberately:
//
//   callerClient()  — carries the end user's JWT, so RLS and auth.uid() apply.
//                     Used for anything the user is entitled to do themselves
//                     (creating their own payment intent, requesting their own
//                     withdrawal).
//
//   serviceClient() — service role. Used ONLY to record provider-confirmed
//                     outcomes, through functions whose EXECUTE is revoked from
//                     authenticated. This is the boundary that makes it
//                     impossible for a client to forge a successful payment.
// =============================================================================

import {
  createClient,
  type SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.47.10";

export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
    { auth: { persistSession: false } },
  );
}

export function callerClient(authorization: string): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    {
      auth: { persistSession: false },
      global: { headers: { Authorization: authorization } },
    },
  );
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/**
 * Errors are returned as a short, user-safe message. Provider and database
 * detail is logged server-side only — it never reaches the app.
 */
export function failure(error: unknown, status = 400): Response {
  const message = error instanceof Error ? error.message : String(error);
  console.error("[camiva-payments]", message);
  return json({ error: message }, status);
}

export function requireAuth(req: Request): string {
  const authorization = req.headers.get("Authorization");
  if (!authorization) throw new Error("Not authenticated");
  return authorization;
}
