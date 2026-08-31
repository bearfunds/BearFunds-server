// Handler tests for the send-welcome-email Edge Function (pure; no network/DB).
// The Resend sender is injected as a fake, so every branch - method guard, secret gate,
// body validation, success, and send failure - is exercised without a real Resend call.
// Run: deno test supabase/functions/send-welcome-email/send-welcome-email.test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleSendWelcomeEmail } from "./handler.ts";
import type { SendEmailArgs } from "./handler.ts";

const SECRET = "test-webhook-secret";

function post(body: unknown, secret: string | null = SECRET): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (secret !== null) headers["Authorization"] = `Bearer ${secret}`;
  return new Request("http://localhost/send-welcome-email", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

const authUserInsertPayload = {
  type: "INSERT",
  table: "users",
  record: { id: "u1", email: "new@bearfunds.test", raw_user_meta_data: { full_name: "Ada" } },
};

Deno.test("CORS preflight (OPTIONS) returns ok", async () => {
  const res = await handleSendWelcomeEmail(
    new Request("http://localhost/send-welcome-email", { method: "OPTIONS" }),
    { sendFn: () => Promise.resolve(), webhookSecret: SECRET },
  );
  assertEquals(res.status, 200);
});

Deno.test("rejects non-POST with 405", async () => {
  const res = await handleSendWelcomeEmail(
    new Request("http://localhost/send-welcome-email", { method: "GET" }),
    { sendFn: () => Promise.resolve(), webhookSecret: SECRET },
  );
  assertEquals(res.status, 405);
});

Deno.test("401 when the webhook secret is missing", async () => {
  const res = await handleSendWelcomeEmail(post(authUserInsertPayload, null), {
    sendFn: () => Promise.resolve(),
    webhookSecret: SECRET,
  });
  assertEquals(res.status, 401);
});

Deno.test("401 when the webhook secret does not match", async () => {
  const res = await handleSendWelcomeEmail(post(authUserInsertPayload, "wrong-secret"), {
    sendFn: () => Promise.resolve(),
    webhookSecret: SECRET,
  });
  assertEquals(res.status, 401);
});

Deno.test("400 on malformed JSON body", async () => {
  const req = new Request("http://localhost/send-welcome-email", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": `Bearer ${SECRET}` },
    body: "{not json",
  });
  const res = await handleSendWelcomeEmail(req, { sendFn: () => Promise.resolve(), webhookSecret: SECRET });
  assertEquals(res.status, 400);
});

Deno.test("400 when record.email is missing", async () => {
  const res = await handleSendWelcomeEmail(
    post({ type: "INSERT", table: "users", record: { id: "u1" } }),
    { sendFn: () => Promise.resolve(), webhookSecret: SECRET },
  );
  assertEquals(res.status, 400);
});

Deno.test("success: sends with the user's full_name", async () => {
  let captured: SendEmailArgs | null = null;
  const sendFn = (args: SendEmailArgs) => {
    captured = args;
    return Promise.resolve();
  };
  const res = await handleSendWelcomeEmail(post(authUserInsertPayload), { sendFn, webhookSecret: SECRET });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "success");
  assertEquals(body.data.sent, true);
  assert(captured !== null);
  const sent = captured as SendEmailArgs;
  assertEquals(sent.to, "new@bearfunds.test");
  assertEquals(sent.name, "Ada");
});

Deno.test("success: falls back to 'there' when full_name is absent", async () => {
  let captured: SendEmailArgs | null = null;
  const sendFn = (args: SendEmailArgs) => {
    captured = args;
    return Promise.resolve();
  };
  const payload = { type: "INSERT", table: "users", record: { id: "u2", email: "noname@bearfunds.test" } };
  const res = await handleSendWelcomeEmail(post(payload), { sendFn, webhookSecret: SECRET });
  assertEquals(res.status, 200);
  assert(captured !== null);
  assertEquals((captured as SendEmailArgs).name, "there");
});

Deno.test("fail-open: a Resend failure still returns 200 (no retry storm)", async () => {
  const boom = () => Promise.reject(new Error("Resend outage"));
  const res = await handleSendWelcomeEmail(post(authUserInsertPayload), { sendFn: boom, webhookSecret: SECRET });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.status, "success");
  assertEquals(body.data.sent, false);
});
