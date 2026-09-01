// BearFunds send-welcome-email - fired by a Supabase Database Webhook on auth.users INSERT
// (dashboard-configured, shared-secret gated). Sends a hardcoded welcome email via Resend.
// Out-of-contract: no table, no family_id, no RLS surface, no Schema Contract change.
import { handleSendWelcomeEmail } from "./handler.ts";
import { resendSendWelcomeEmail } from "./resend.ts";

Deno.serve((req: Request) => handleSendWelcomeEmail(req, { sendFn: resendSendWelcomeEmail }));
