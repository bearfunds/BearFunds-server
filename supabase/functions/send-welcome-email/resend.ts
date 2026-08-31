// Thin Resend API client for the welcome email. Plain fetch against Resend's REST API -
// no SDK dependency, matching the rest of this function's zero-extra-imports footprint.
// RESEND_API_KEY is a server secret (Deno.env), never exposed to the client bundle.
import type { SendEmailFn } from "./handler.ts";

const RESEND_API_URL = "https://api.resend.com/emails";
// Sender address must use a verified Resend domain. Override via RESEND_FROM_ADDRESS in .env.
const FROM_ADDRESS = Deno.env.get("RESEND_FROM_ADDRESS");
// Template is managed in the Resend dashboard (Templates), not in code. Requires a
// "first_name" variable in the template body (operator step).
const WELCOME_TEMPLATE_ID = Deno.env.get("RESEND_WELCOME_TEMPLATE_ID") ?? "";

export const resendSendWelcomeEmail: SendEmailFn = async ({ to, name }) => {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) throw new Error("RESEND_API_KEY is not configured on the server.");
  if (!FROM_ADDRESS) throw new Error("RESEND_FROM_ADDRESS is not configured on the server.");
  if (!WELCOME_TEMPLATE_ID) throw new Error("RESEND_WELCOME_TEMPLATE_ID is not configured on the server.");

  const res = await fetch(RESEND_API_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      from: FROM_ADDRESS,
      to: [to],
      template: {
        id: WELCOME_TEMPLATE_ID,
        variables: { first_name: name },
      },
    }),
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => res.statusText);
    throw new Error(`Resend request failed: ${res.status} ${detail}`);
  }
};
