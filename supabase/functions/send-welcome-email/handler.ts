// send-welcome-email handler: fired by a Supabase Database Webhook on auth.users INSERT
// (configured in the dashboard, not in a migration - see api/CLAUDE.md / plan notes). This
// is NOT a user-facing endpoint: the caller is the webhook, not a session, so it is gated by
// a shared secret (WEBHOOK_SECRET) rather than requireUser's Bearer-JWT check. Out-of-contract
// (not a data action): no table, no family_id, no RLS surface, no Schema Contract change.
//
// Fail-open by design: an email failure (bad key, Resend outage, invalid recipient) must
// never surface as a webhook failure that Supabase retries into a storm. Every branch below
// still returns 200 except auth/validation errors on the request itself.
import { json } from "../_shared/http.ts";

export interface SendEmailArgs {
  to: string;
  name: string;
}

export type SendEmailFn = (args: SendEmailArgs) => Promise<void>;

export interface Deps {
  sendFn: SendEmailFn;
  // Injectable for tests; defaults to reading WEBHOOK_SECRET from the server env.
  webhookSecret?: string;
}

// Supabase Database Webhook payload shape for an INSERT on auth.users (subset we use).
interface AuthUserWebhookPayload {
  type?: string;
  table?: string;
  record?: {
    id?: string;
    email?: string;
    raw_user_meta_data?: { full_name?: string } | null;
  };
}

export async function handleSendWelcomeEmail(req: Request, deps: Deps): Promise<Response> {
  if (req.method === "OPTIONS") return json({ status: "success" });
  if (req.method !== "POST") return json({ status: "error", message: "POST only." }, 405);

  const expectedSecret = deps.webhookSecret ?? Deno.env.get("WEBHOOK_SECRET") ?? "";
  const authHeader = req.headers.get("Authorization") ?? "";
  const providedSecret = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7).trim()
    : "";
  if (!expectedSecret || providedSecret !== expectedSecret) {
    return json({ status: "error", message: "Unauthorized." }, 401);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ status: "error", message: "Body must be valid JSON." }, 400);
  }

  const payload = body as AuthUserWebhookPayload;
  const email = payload.record?.email;
  if (typeof email !== "string" || email.trim().length === 0) {
    return json({ status: "error", message: "Missing record.email in webhook payload." }, 400);
  }
  const name = payload.record?.raw_user_meta_data?.full_name?.trim() || "there";

  try {
    await deps.sendFn({ to: email, name });
  } catch (e) {
    // Log full detail server-side; still answer 200 so Supabase does not retry-storm the
    // webhook over a transient Resend failure. This mirrors the "logged failure only" bar
    // agreed for this alpha-stage integration.
    console.error("[send-welcome-email] Resend send failed:", e);
    return json({ status: "success", data: { sent: false } });
  }

  return json({ status: "success", data: { sent: true } });
}
