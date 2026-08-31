// send-feedback-notification handler: fired by a Supabase Database Webhook on
// public.feedback INSERT (configured in the dashboard, not in a migration - see
// api/CLAUDE.md / plan notes). This is NOT a user-facing endpoint: the caller is the
// webhook, not a session, so it is gated by a shared secret (WEBHOOK_SECRET) rather
// than requireUser's Bearer-JWT check. Out-of-contract (not a data action): no
// Schema Contract change, feedback stays control-plane.
//
// Fail-open by design: an email failure (bad key, Resend outage, invalid recipient)
// must never surface as a webhook failure that Supabase retries into a storm. Every
// branch below still returns 200 except auth/validation errors on the request itself.
import { json } from "../_shared/http.ts";

export interface SendFeedbackEmailArgs {
  kind: string;
  message: string;
  route: string;
  userId: string;
  reporterEmail: string;
  subject: string;
}

export type SendFeedbackEmailFn = (args: SendFeedbackEmailArgs) => Promise<void>;
export type LookupEmailFn = (userId: string) => Promise<string>;

export interface Deps {
  sendFn: SendFeedbackEmailFn;
  // Injectable for tests; defaults to reading WEBHOOK_SECRET from the server env.
  webhookSecret?: string;
  // Injectable for tests; resolves auth.users.email for the reporter via service role.
  lookupEmailFn?: LookupEmailFn;
}

// Supabase Database Webhook payload shape for an INSERT on public.feedback (subset).
interface FeedbackWebhookPayload {
  type?: string;
  table?: string;
  record?: {
    id?: string;
    user_id?: string;
    kind?: string;
    message?: string;
    context?: { route?: string } | null;
    received_at?: string;
  };
}

const KIND_LABELS: Record<string, string> = {
  bug: "Bug report",
  idea: "Feature idea",
  other: "Feedback",
};

export async function handleSendFeedbackNotification(req: Request, deps: Deps): Promise<Response> {
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

  const payload = body as FeedbackWebhookPayload;
  const record = payload.record;
  const kind = record?.kind;
  const message = record?.message;
  if (typeof kind !== "string" || kind.trim().length === 0) {
    return json({ status: "error", message: "Missing record.kind in webhook payload." }, 400);
  }
  if (typeof message !== "string" || message.trim().length === 0) {
    return json({ status: "error", message: "Missing record.message in webhook payload." }, 400);
  }

  const userId = typeof record?.user_id === "string" ? record.user_id : "";
  const route = typeof record?.context?.route === "string" ? record.context.route : "";

  let reporterEmail = "";
  if (userId && deps.lookupEmailFn) {
    try {
      reporterEmail = await deps.lookupEmailFn(userId);
    } catch (e) {
      // Non-fatal: notification still goes out, just without the reporter address.
      console.warn("[send-feedback-notification] reporter email lookup failed:", e);
    }
  }

  const label = KIND_LABELS[kind] ?? "Feedback";
  const subject = `[BearFunds] ${label} from ${route || "app"}`;

  try {
    await deps.sendFn({ kind, message, route, userId, reporterEmail, subject });
  } catch (e) {
    // Log full detail server-side; still answer 200 so Supabase does not retry-storm
    // the webhook over a transient Resend failure.
    console.error("[send-feedback-notification] Resend send failed:", e);
    return json({ status: "success", data: { sent: false } });
  }

  return json({ status: "success", data: { sent: true } });
}
