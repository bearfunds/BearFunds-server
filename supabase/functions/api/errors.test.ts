// Q21 regression net: the classifier must never pass upstream detail to the
// wire. Run with: deno test supabase/functions/api/errors.test.ts
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { classifyApiError, UpstreamDbError } from "./_shared/errors.ts";
import { ValidationError } from "./_shared/validation.ts";

Deno.test("RLS violation (42501) -> RLS_DENIED 403 with a fixed message", () => {
  const c = classifyApiError(new UpstreamDbError('new row violates row-level security policy for table "entities"', "42501"));
  assertEquals(c.code, "RLS_DENIED");
  assertEquals(c.http, 403);
  assert(!c.message.includes("entities"), "table names must never reach the wire");
  assert(!c.message.includes("row-level security"), "policy detail must never reach the wire");
});

Deno.test("unique violation (23505) -> CONFLICT 409, no constraint detail", () => {
  const c = classifyApiError(new UpstreamDbError('duplicate key value violates unique constraint "transactions_pkey"', "23505"));
  assertEquals(c.code, "CONFLICT");
  assertEquals(c.http, 409);
  assert(!c.message.includes("transactions_pkey"));
});

Deno.test("unknown SQLSTATE -> INTERNAL 500 generic", () => {
  const c = classifyApiError(new UpstreamDbError('deadlock detected on relation "wallets"', "40P01"));
  assertEquals(c.code, "INTERNAL");
  assertEquals(c.http, 500);
  assert(!c.message.includes("wallets") && !c.message.includes("deadlock"));
});

Deno.test("plain Error (unexpected throw) -> INTERNAL, message NOT passed through", () => {
  const c = classifyApiError(new Error('permission denied for table members'));
  assertEquals(c.code, "INTERNAL");
  assert(!c.message.includes("members"));
});

Deno.test("ValidationError keeps its authored message (no DB detail by construction)", () => {
  const c = classifyApiError(new ValidationError("Unknown key 'amount' for table TRANSACTIONS."));
  assertEquals(c.code, "VALIDATION");
  assertEquals(c.http, 400);
  assertEquals(c.message, "Unknown key 'amount' for table TRANSACTIONS.");
});

Deno.test("non-Error throw -> INTERNAL generic", () => {
  const c = classifyApiError("boom");
  assertEquals(c.code, "INTERNAL");
  assertEquals(c.message, "The request could not be completed.");
});
