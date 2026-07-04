// BearFunds API - single POST Edge Function honoring the Schema Contract. Auth: the
// Bearer JWT is verified by the shared requireUser gate. Tenancy: family_id is
// server-derived by the DB (trigger + RLS); this function never reads a family_id from
// the body. Envelope: { status: 'success', data } | { status: 'error', code, message }
// (v1.15: `code` is a closed enum; raw upstream detail never reaches the wire - Q21).
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CORS, json, requireUser, isAuthed, testScopedClient } from "../_shared/http.ts";
import { parseRequest } from "./_shared/validation.ts";
import { classifyApiError, UpstreamDbError } from "./_shared/errors.ts";
import { DbExecutor, runAction } from "./_shared/actions.ts";

// supabase-js-backed executor. The client carries the caller's JWT, so every query
// runs under that session's RLS - isolation does not depend on this function's logic.
function makeExecutor(supabase: SupabaseClient): DbExecutor {
  // Preserve the SQLSTATE for classification; the raw message goes to logs only.
  const fail = (e: { message: string; code?: string }) => { throw new UpstreamDbError(e.message, e.code); };
  return {
    async read(table, since) {
      let q = supabase.from(table).select("*");
      if (since) q = q.gt("updated_at", since);
      const { data, error } = await q;
      if (error) fail(error);
      return data ?? [];
    },
    async insert(table, rows) {
      const { data, error } = await supabase.from(table).insert(rows).select();
      if (error) fail(error);
      return data ?? [];
    },
    async update(table, id, changed) {
      const { data, error } = await supabase.from(table).update(changed).eq("id", id).select();
      if (error) fail(error);
      return data ?? [];
    },
    async upsert(table, rows) {
      const { data, error } = await supabase.from(table).upsert(rows).select();
      if (error) fail(error);
      return data ?? [];
    },
    async version() {
      // family_version() (migration 0012) returns the family high-water mark, RLS/auth_family_id
      // scoped (test-aware via 0011), as a single timestamptz (null when the family has no rows).
      const { data, error } = await supabase.rpc("family_version");
      if (error) fail(error);
      return { version: (data as string | null) ?? null };
    },
    async wipe(table) {
      let q = supabase.from(table).delete({ count: "exact" }).neq("id", "__never_matches__");
      // Never delete account-linking members (user_id set): that row establishes the
      // caller's tenancy (auth_family_id reads it), so wiping it strands the user with no
      // family. Only app-data members (user_id null) are test data. Other tables unaffected.
      if (table === "members") q = q.is("user_id", null);
      const { count, error } = await q;
      if (error) fail(error);
      return count ?? 0;
    },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ status: "error", code: "VALIDATION", message: "POST only." }, 405);

  const auth = await requireUser(req);
  if (!isAuthed(auth)) return auth; // ready 401 Response (missing bearer / unauthenticated)

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ status: "error", code: "VALIDATION", message: "Body must be valid JSON." }, 400);
  }

  try {
    const request = parseRequest(body);
    const isTest = (body as { isTest?: unknown }).isTest === true;
    // Test context: provision the caller's test family (idempotent), then run the action
    // through a client carrying the `x-bf-test` header so DB tenancy resolves to that test
    // family (migration 0011). The non-test path is unchanged.
    let supabase = auth.supabase;
    if (isTest) {
      const { error: provisionError } = await auth.supabase.rpc("ensure_test_family");
      if (provisionError) throw new UpstreamDbError(provisionError.message, (provisionError as { code?: string }).code);
      supabase = testScopedClient(req);
    }
    const data = await runAction(request, makeExecutor(supabase), { isTest });
    return json({ status: "success", data });
  } catch (e) {
    const classified = classifyApiError(e);
    // Full detail stays in the function logs; the wire gets the fixed message.
    if (classified.code !== "VALIDATION") console.error("[api]", e);
    return json({ status: "error", code: classified.code, message: classified.message }, classified.http);
  }
});
