// Handler tests for the send-feedback-notification Edge Function (pure; no network/DB).
// The Resend sender is injected as a fake, so every branch - method guard, secret gate,
// body validation, success, and send failure - is exercised without a real Resend call.
// Run: deno test supabase/functions/send-feedback-notification/send-feedback-notification.test.ts
import { assert, assertEquals, assertStringIncludes } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleSendFeedbackNotification } from "./handler.ts";
import type { SendFeedbackEmailArgs } from "./handler.ts";

const SECRET = "test-webhook-secret";

function post(body: unknown, secret: string | null = SECRET): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (secret !== null) headers["Authorization"] = `Bearer ${secret}`;
  return new Request("http://localhost/send-feedback-notification", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const feedbackInsertPayload = {
  type: "INSERT",
  table: "feedback",
  record: {
    id: "f1",
    user_id: "u1",
    kind: "bug",
    message: "Save button crashes on iOS Safari",
    context: { route: "dashboard", platform: "ios", viewport: "sm" },
    received_at: "2026-07-28T11:00:00Z",
  },
};

Deno.test("CORS preflight (OPTIONS) returns ok", async () => {
  const res = await handleSendFeedbackNotification(
    new Request("http://localhost/send-feedback-notification", { method: "OPTIONS" }),
    { sendFn: () => Promise.resolve(), webhookSecret: SECRET },
  );
  assertEquals(res.status, 200);
});

Deno.test("rejects non-POST with 405", async () => {
  const res = await handleSendFeedbackNotification(
    new Request("http://localhost/send-feedback-notification", { method: "GET" }),
    { sendFn: () => Promise.resolve(), webhookSecret: SECRET },
  );
  assertEquals(res.status, 405);
});

Deno.test("401 when the webhook secret is missing", async () => {
  const res = await handleSendFeedbackNotification(post(feedbackInsertPayload, null), {
    sendFn: () => Promise.resolve(),
    webhookSecret: SECRET,
  });
  assertEquals(res.status, 401);
});

Deno.test("401 when the webhook secret does not match", async () => {
  const res = await handleSendFeedbackNotification(post(feedbackInsertPayload, "wrong-secret"), {
    sendFn: () => Promise.resolve(),
    webhookSecret: SECRET,
  });
  assertEquals(res.status, 401);
});

Deno.test("400 on malformed JSON body", async () => {
  const req = new Request("http://localhost/send-feedback-notification", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SECRET}` },
    body: "{not json",
  });
  const res = await handleSendFeedbackNotification(req, { sendFn: () => Promise.resolve(), webhookSecret: SECRET });
  assertEquals(res.status, 400);
});

Deno.test("400 when record.kind is missing", async () => {
  const res = await handleSendFeedbackNotification(
    post({ type: "INSERT", table: "feedback", record: { id: "f1", message: "x" } }),
    { sendFn: () => Promise.resolve(), webhookSecret: SECRET },
  );
  assertEquals(res.status, 400);
});

Deno.test("400 when record.message is missing", async () => {
  const res = await handleSendFeedbackNotification(
    post({ type: "INSERT", table: "feedback", record: { id: "f1", kind: "bug" } }),
    { sendFn: () => Promise.resolve(), webhookSecret: SECRET },
  );
  assertEquals(res.status, 400);
});

Deno.test("success: sends with kind, message, and context", async () => {
  let captured: SendFeedbackEmailArgs | null = null;
  const sendFn = (args: SendFeedbackEmailArgs) => {
    captured = args;
    return Promise.resolve();
  };
  const res = await handleSendFeedbackNotification(post(feedbackInsertPayload), { sendFn, webhookSecret: SECRET });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "success");
  assertEquals(body.data.sent, true);
  assert(captured !== null);
  const sent = captured as SendFeedbackEmailArgs;
  assertEquals(sent.kind, "bug");
  assertEquals(sent.message, "Save button crashes on iOS Safari");
  assertEquals(sent.route, "dashboard");
  assertEquals(sent.userId, "u1");
});

Deno.test("success: includes reporter email when lookup resolves", async () => {
  let captured: SendFeedbackEmailArgs | null = null;
  const sendFn = (args: SendFeedbackEmailArgs) => {
    captured = args;
    return Promise.resolve();
  };
  const lookupEmailFn = (userId: string) => {
    assertEquals(userId, "u1");
    return Promise.resolve("reporter@bearfunds.test");
  };
  const res = await handleSendFeedbackNotification(post(feedbackInsertPayload), {
    sendFn,
    webhookSecret: SECRET,
    lookupEmailFn,
  });
  assertEquals(res.status, 200);
  assert(captured !== null);
  assertEquals((captured as SendFeedbackEmailArgs).reporterEmail, "reporter@bearfunds.test");
});

Deno.test("success: reporterEmail is empty when lookup fails", async () => {
  let captured: SendFeedbackEmailArgs | null = null;
  const sendFn = (args: SendFeedbackEmailArgs) => {
    captured = args;
    return Promise.resolve();
  };
  const lookupEmailFn = () => Promise.reject(new Error("auth lookup down"));
  const res = await handleSendFeedbackNotification(post(feedbackInsertPayload), {
    sendFn,
    webhookSecret: SECRET,
    lookupEmailFn,
  });
  assertEquals(res.status, 200);
  assert(captured !== null);
  assertEquals((captured as SendFeedbackEmailArgs).reporterEmail, "");
});

Deno.test("fail-open: a Resend failure still returns 200 (no retry storm)", async () => {
  const boom = () => Promise.reject(new Error("Resend outage"));
  const res = await handleSendFeedbackNotification(post(feedbackInsertPayload), { sendFn: boom, webhookSecret: SECRET });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "success");
  assertEquals(body.data.sent, false);
});

Deno.test("subject line includes the feedback kind", async () => {
  let captured: SendFeedbackEmailArgs | null = null;
  const sendFn = (args: SendFeedbackEmailArgs) => {
    captured = args;
    return Promise.resolve();
  };
  const res = await handleSendFeedbackNotification(post(feedbackInsertPayload), { sendFn, webhookSecret: SECRET });
  assertEquals(res.status, 200);
  assert(captured !== null);
  const sent = captured as SendFeedbackEmailArgs;
  assertStringIncludes(sent.subject.toLowerCase(), "bug");
});
