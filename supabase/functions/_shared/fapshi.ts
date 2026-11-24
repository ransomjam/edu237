// =============================================================================
// Fapshi API client — server-side only
// =============================================================================
//
// Credentials live in Edge Function secrets and never leave the server. The
// Flutter app calls our own functions; it never sees `apiuser` / `apikey`.
//
// Endpoints and fields below follow the official documentation
// (https://docs.fapshi.com). Nothing here is invented:
//
//   POST /initiate-pay            → { message, link, transId, dateInitiated }
//   POST /direct-pay              → { message, transId, dateInitiated }
//   GET  /payment-status/{transId}→ full transaction object (also the webhook body)
//   POST /payout                  → { message, transId, dateInitiated }
//   GET  /balance                 → account balance
//
// Auth is two headers: `apiuser` and `apikey`.
//
// PROVIDER-SIDE ACTIVATION (documented, not assumed to be done):
//   * Direct Pay is disabled by default on live and must be activated by Fapshi.
//   * Payouts are disabled by default on live and must be activated by Fapshi,
//     and an activated payout service CANNOT also collect payments — so
//     collections and payouts use two different services, i.e. two credential
//     pairs. That is why this client takes the credential pair as an argument.
// =============================================================================

export type FapshiEnv = "sandbox" | "live";

export const FAPSHI_BASE_URLS: Record<FapshiEnv, string> = {
  sandbox: "https://sandbox.fapshi.com",
  live: "https://live.fapshi.com",
};

export interface FapshiCredentials {
  apiUser: string;
  apiKey: string;
}

/** The transaction shape returned by /payment-status and posted to webhooks. */
export interface FapshiTransaction {
  transId: string;
  status: "CREATED" | "PENDING" | "SUCCESSFUL" | "FAILED" | "EXPIRED";
  medium?: string;
  serviceName?: string;
  transType?: "Collection" | "Payout";
  amount?: number;
  revenue?: number;
  payerName?: string;
  email?: string;
  redirectUrl?: string;
  externalId?: string;
  userId?: string;
  webhook?: string;
  reason?: string;
  financialTransId?: string;
  dateInitiated?: string;
  dateConfirmed?: string;
}

export interface FapshiInitiateResponse {
  message: string;
  link: string;
  transId: string;
  dateInitiated?: string;
}

export interface FapshiTransIdResponse {
  message: string;
  transId: string;
  dateInitiated?: string;
}

export class FapshiError extends Error {
  constructor(message: string, readonly status: number, readonly body: unknown) {
    super(message);
    this.name = "FapshiError";
  }
}

/** Reads the environment (sandbox by default — live is never implicit). */
export function fapshiEnv(): FapshiEnv {
  return Deno.env.get("FAPSHI_ENV") === "live" ? "live" : "sandbox";
}

export function collectionCredentials(): FapshiCredentials {
  const apiUser = Deno.env.get("FAPSHI_COLLECTION_API_USER") ?? "";
  const apiKey = Deno.env.get("FAPSHI_COLLECTION_API_KEY") ?? "";
  if (!apiUser || !apiKey) {
    throw new Error("Fapshi collection credentials are not configured");
  }
  return { apiUser, apiKey };
}

/**
 * Payout credentials. Fapshi requires a SEPARATE service for disbursement, so
 * these fall back to nothing rather than silently reusing the collection pair.
 */
export function payoutCredentials(): FapshiCredentials {
  const apiUser = Deno.env.get("FAPSHI_PAYOUT_API_USER") ?? "";
  const apiKey = Deno.env.get("FAPSHI_PAYOUT_API_KEY") ?? "";
  if (!apiUser || !apiKey) {
    throw new Error("Fapshi payout credentials are not configured");
  }
  return { apiUser, apiKey };
}

async function call<T>(
  creds: FapshiCredentials,
  method: "GET" | "POST",
  path: string,
  body?: Record<string, unknown>,
): Promise<T> {
  const url = `${FAPSHI_BASE_URLS[fapshiEnv()]}${path}`;
  const response = await fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json",
      apiuser: creds.apiUser,
      apikey: creds.apiKey,
    },
    // The docs are explicit that GET requests carry no body.
    body: method === "POST" && body ? JSON.stringify(body) : undefined,
  });

  const text = await response.text();
  let parsed: unknown = null;
  try {
    parsed = text ? JSON.parse(text) : null;
  } catch {
    parsed = text;
  }

  if (!response.ok) {
    const message =
      (parsed as { message?: string } | null)?.message ??
        `Fapshi request failed (${response.status})`;
    throw new FapshiError(message, response.status, parsed);
  }
  return parsed as T;
}

/** Hosted checkout link. Works on live without provider-side activation. */
export function initiatePay(
  creds: FapshiCredentials,
  payload: {
    amount: number;
    email?: string;
    redirectUrl?: string;
    userId?: string;
    externalId?: string;
    message?: string;
  },
): Promise<FapshiInitiateResponse> {
  return call<FapshiInitiateResponse>(creds, "POST", "/initiate-pay", payload);
}

/** Push a payment prompt straight to a phone. Requires activation on live. */
export function directPay(
  creds: FapshiCredentials,
  payload: {
    amount: number;
    phone: string;
    medium?: "mobile money" | "orange money";
    name?: string;
    email?: string;
    userId?: string;
    externalId?: string;
    message?: string;
  },
): Promise<FapshiTransIdResponse> {
  return call<FapshiTransIdResponse>(creds, "POST", "/direct-pay", payload);
}

/**
 * Authoritative status of a transaction. Rate limited by Fapshi to 6 requests
 * per minute per transId, so this is only called on real state questions —
 * never in a polling loop.
 */
export function paymentStatus(
  creds: FapshiCredentials,
  transId: string,
): Promise<FapshiTransaction> {
  return call<FapshiTransaction>(
    creds,
    "GET",
    `/payment-status/${encodeURIComponent(transId)}`,
  );
}

/** Disbursement. Requires activation on live, on a payout-only service. */
export function payout(
  creds: FapshiCredentials,
  payload: {
    amount: number;
    phone?: string;
    medium?: "mobile money" | "orange money" | "fapshi";
    name?: string;
    email?: string;
    userId?: string;
    externalId?: string;
    message?: string;
  },
): Promise<FapshiTransIdResponse> {
  return call<FapshiTransIdResponse>(creds, "POST", "/payout", payload);
}

export function balance(creds: FapshiCredentials): Promise<unknown> {
  return call<unknown>(creds, "GET", "/balance");
}

/**
 * Constant-time comparison for the webhook secret, so a mismatch cannot be
 * narrowed down by timing.
 */
export function secretMatches(received: string | null, expected: string): boolean {
  if (!received || !expected) return false;
  const a = new TextEncoder().encode(received);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}
