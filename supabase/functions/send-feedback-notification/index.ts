// BearFunds send-feedback-notification - fired by a Supabase Database Webhook on
// public.feedback INSERT (dashboard-configured, shared-secret gated). Sends a
// notification email with the feedback content to the admin inbox via Resend.
// Out-of-contract: no table, no family_id, no RLS surface, no Schema Contract change.
import { handleSendFeedbackNotification } from "./handler.ts";
import { resendSendFeedbackNotification, lookupReporterEmail } from "./resend.ts";

Deno.serve((req: Request) =>
  handleSendFeedbackNotification(req, {
    sendFn: resendSendFeedbackNotification,
    lookupEmailFn: lookupReporterEmail,
  })
);
