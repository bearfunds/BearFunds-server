// Thin Resend API client for the feedback notification email. Plain fetch against
// Resend's REST API - no SDK dependency, matching the rest of this function's
// zero-extra-imports footprint. RESEND_API_KEY is a server secret (Deno.env), never
// exposed to the client bundle.
import type { SendFeedbackEmailFn, LookupEmailFn } from "./handler.ts";

const RESEND_API_URL = "https://api.resend.com/emails";
// Resend's shared test sender; swap for a verified domain address once one exists
// (operator step - DNS verification in the Resend dashboard).
const FROM_ADDRESS = "BearFunds <onboarding@resend.dev>";
// Admin inbox that receives every feedback notification.
const ADMIN_EMAIL = Deno.env.get("FEEDBACK_ADMIN_EMAIL") ?? "";

// Escape user-authored free text for safe inclusion in the HTML body.
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

export const resendSendFeedbackNotification: SendFeedbackEmailFn = async ({
  kind,
  message,
  route,
  userId,
  reporterEmail,
  subject,
}) => {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) throw new Error("RESEND_API_KEY is not configured on the server.");
  if (!ADMIN_EMAIL) throw new Error("FEEDBACK_ADMIN_EMAIL is not configured on the server.");

  const text = [
    `Type: ${kind}`,
    `Route: ${route || "unknown"}`,
    `Reporter: ${reporterEmail || userId || "unknown"}`,
    "",
    message,
  ].join("\n");

  const html = `
    <div style="font-family:system-ui,sans-serif;max-width:560px">
      <h2 style="margin:0 0 12px">${escapeHtml(subject)}</h2>
      <table style="font-size:14px;color:#334155;border-collapse:collapse">
        <tr><td style="padding:4px 12px 4px 0;font-weight:700">Type</td><td>${escapeHtml(kind)}</td></tr>
        <tr><td style="padding:4px 12px 4px 0;font-weight:700">Route</td><td>${escapeHtml(route || "unknown")}</td></tr>
        <tr><td style="padding:4px 12px 4px 0;font-weight:700">Reporter</td><td>${escapeHtml(reporterEmail || userId || "unknown")}</td></tr>
      </table>
      <div style="margin-top:16px;padding:16px;background:#f8fafc;border-radius:12px;font-size:14px;line-height:1.6;white-space:pre-wrap">${escapeHtml(message)}</div>
    </div>
  `;

  const res = await fetch(RESEND_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to: [ADMIN_EMAIL],
      subject,
      text,
      html,
    }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => res.statusText);
    throw new Error(`Resend request failed: ${res.status} ${detail}`);
  }
};

// Resolve the reporter's auth.users.email via the Supabase admin API (service role).
// Runs server-side only; the webhook payload carries user_id, not email.
export const lookupReporterEmail: LookupEmailFn = async (userId) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) return "";

  const res = await fetch(`${supabaseUrl}/auth/v1/admin/users/${userId}`, {
    headers: {
      "apikey": serviceRoleKey,
      "Authorization": `Bearer ${serviceRoleKey}`,
    },
  });
  if (!res.ok) return "";
  const user = await res.json().catch(() => null);
  return typeof user?.email === "string" ? user.email : "";
};
