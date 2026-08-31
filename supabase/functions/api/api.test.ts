// Action-handler + boundary-validation tests (pure; no network/DB).
// Run: deno test supabase/functions/api/api.test.ts
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseRequest, ValidationError } from "./_shared/validation.ts";
import { DbExecutor, runAction } from "./_shared/actions.ts";
import { isLogicalTable } from "./_shared/contract.ts";

// A fake executor that records calls and returns echo data.
function fakeDb() {
  const calls: { op: string; table: string; arg: unknown }[] = [];
  const db: DbExecutor = {
    read: (t, since) => { calls.push({ op: "read", table: t, arg: since }); return Promise.resolve([{ id: "r1" }]); },
    insert: (t, rows) => { calls.push({ op: "insert", table: t, arg: rows }); return Promise.resolve(rows); },
    update: (t, id, ch) => { calls.push({ op: "update", table: t, arg: { id, ch } }); return Promise.resolve([{ id, ...ch }]); },
    upsert: (t, rows) => { calls.push({ op: "upsert", table: t, arg: rows }); return Promise.resolve(rows); },
    wipe: (t) => { calls.push({ op: "wipe", table: t, arg: null }); return Promise.resolve(3); },
    version: () => { calls.push({ op: "version", table: "", arg: null }); return Promise.resolve({ version: "2026-01-01T00:00:00.000Z" }); },
    deleteAccount: () => { calls.push({ op: "deleteAccount", table: "", arg: null }); return Promise.resolve({ deleted: true }); },
  };
  return { db, calls };
}

Deno.test("strips server-derived & internal keys, keeps writable keys", () => {
  const req = parseRequest({
    action: "batchUpsert", table: "ACCOUNTS",
    rows: [{ id: "w1", enc: "v1.aaa.bbb", currency: "EUR", family_id: "forged", user_id: "x", updated_at: "2000", isDirty: true }],
  });
  if (req.action !== "batchUpsert") throw new Error("wrong action");
  assertEquals(req.rows[0], { id: "w1", enc: "v1.aaa.bbb", currency: "EUR" });
});

// RLE enforcement (contract v1.14): scoped plaintext keys are gone from the wire.
// The server REJECTS them as unknown keys - encryption is enforced, not conventional.
Deno.test("RLE: plaintext sensitive keys are rejected per table", () => {
  const cases: [string, Record<string, unknown>][] = [
    ["TRANSACTIONS", { id: "t1", amount: 5 }],
    ["TRANSACTIONS", { id: "t1", description: "memo" }],
    ["TRANSACTIONS", { id: "t1", tags: "[\"A\"]" }],
    ["ACCOUNTS", { id: "w1", name: "Main" }],
    ["ACCOUNTS", { id: "w1", description: "d" }],
    ["ENTITIES", { id: "e1", name: "ACME" }],
    ["ENTITIES", { id: "e1", aliases: "[]" }],
    ["ENTITIES", { id: "e1", match_patterns: "[]" }],
    ["STAGED_TRANSACTIONS", { id: "st1", amount: "-1,5" }],
    ["STAGED_TRANSACTIONS", { id: "st1", source_row: "{}" }],
    ["STAGED_TRANSACTIONS", { id: "st1", source_name: "x" }],
    // BUDGETS (v1.17): the WHOLE plan rides enc - name, target, Areas, category + account
    // membership, the period bounds AND the recurring line id. The only writable plaintext left is
    // kind + period_type.
    ["BUDGETS", { id: "b1", name: "Groceries" }],
    ["BUDGETS", { id: "b1", amount: 400 }],
    ["BUDGETS", { id: "b1", target: 2000 }],
    ["BUDGETS", { id: "b1", note: "new coffee machine" }],
    ["BUDGETS", { id: "b1", category_ids: "[\"c1\"]" }],
    ["BUDGETS", { id: "b1", account_ids: "[\"w1\"]" }],
    ["BUDGETS", { id: "b1", areas: "[]" }],
    ["BUDGETS", { id: "b1", line_id: "line_1" }],
    // The v1 plaintext columns. These are the keys a STALE DEPLOYED CLIENT would send, and the
    // rejection is exactly what makes that failure loud instead of silent - which is why the
    // server and client ship in one coordinated deploy.
    ["BUDGETS", { id: "b1", currency: "EUR" }],
    ["BUDGETS", { id: "b1", template_id: "t1" }],
    ["BUDGETS", { id: "b1", period_start: "2026-07-01" }],
    ["BUDGETS", { id: "b1", period_end: "2026-07-31" }],
    ["BUDGETS", { id: "b1", stopped_at: "2026-07-01" }],
    // IMPORT_MAPPINGS (v1.22): entirely opaque - header/header_norm/verdict all ride enc,
    // nothing plaintext beyond the global set.
    ["IMPORT_MAPPINGS", { id: "im1", header: "Date" }],
    ["IMPORT_MAPPINGS", { id: "im1", header_norm: "date" }],
    ["IMPORT_MAPPINGS", { id: "im1", verdict: "date" }],
  ];
  for (const [table, row] of cases) {
    assertThrows(
      () => parseRequest({ action: "batchUpsert", table, rows: [row] }),
      ValidationError, "Unknown key",
      `${table} must reject ${Object.keys(row)[1]}`,
    );
  }
});

Deno.test("RLE: enc is writable only on envelope tables", () => {
  for (const table of ["TRANSACTIONS", "ACCOUNTS", "ENTITIES", "STAGED_TRANSACTIONS", "BUDGETS", "IMPORT_MAPPINGS"]) {
    const req = parseRequest({ action: "batchUpsert", table, rows: [{ id: "x1", enc: "v1.i.c" }] });
    if (req.action !== "batchUpsert") throw new Error("wrong action");
    assertEquals(req.rows[0], { id: "x1", enc: "v1.i.c" });
  }
  for (const table of ["CATEGORIES", "SUBCATEGORIES", "MEMBERS"]) {
    assertThrows(
      () => parseRequest({ action: "batchUpsert", table, rows: [{ id: "x1", enc: "v1.i.c" }] }),
      ValidationError, "Unknown key 'enc'",
      `${table} must not accept enc`,
    );
  }
});

Deno.test("rejects unknown row key (strict contract)", () => {
  assertThrows(
    () => parseRequest({ action: "batchCreate", table: "ACCOUNTS", rows: [{ id: "w1", bogus: 1 }] }),
    ValidationError, "Unknown key 'bogus'",
  );
});

Deno.test("SUBCATEGORIES: strips server keys, keeps writable (category_id,name,is_default)", () => {
  const req = parseRequest({
    action: "batchUpsert", table: "SUBCATEGORIES",
    rows: [{ id: "sc1", category_id: "c1", name: "General", is_default: true, family_id: "forged", updated_at: "2000", isDirty: true }],
  });
  if (req.action !== "batchUpsert") throw new Error("wrong action");
  assertEquals(req.rows[0], { id: "sc1", category_id: "c1", name: "General", is_default: true });
});

Deno.test("SUBCATEGORIES: rejects unknown row key and read maps logical->physical", async () => {
  assertThrows(
    () => parseRequest({ action: "batchCreate", table: "SUBCATEGORIES", rows: [{ id: "sc1", bogus: 1 }] }),
    ValidationError, "Unknown key 'bogus'",
  );
  const { db, calls } = fakeDb();
  await runAction(parseRequest({ action: "read", table: "SUBCATEGORIES" }), db, { isTest: false });
  assertEquals(calls[0].table, "subcategories");
});

// A NEGATIVE FIXTURE MUST NAME SOMETHING THE CONTRACT CAN NEVER DECLARE, AND A CONTROL PROVES IT.
// The unknown-table arm needs a table that is absent, so its literal is a standing bet about what
// the contract will never contain - and a rename can win that bet silently, because a sweep over
// the OLD word cannot see a line the old word never appears on. On 2026-08-11 this arm read
// "ACCOUNTS", which was absent when it was written and became a real table at contract v1.23, so
// the assert could no longer fail. It surfaced only because the arm throws for one reason; the
// sibling arm below survives on its ACTION being unknown and would have passed regardless.
// The control is what makes the fixture self-reporting: promote either name into the union and it
// goes red here, naming the cause, instead of quietly turning the assert into a formality.
const ABSENT_TABLES = ["ACCOUNT", "NOT_A_TABLE"];

Deno.test("rejects unknown action and unknown table", () => {
  // CONTROL FIRST: these are still counter-examples. "ACCOUNT" is the near-miss singular of a real
  // table, which is the shape most likely to become real; "NOT_A_TABLE" cannot.
  for (const t of ABSENT_TABLES) {
    assert(!isLogicalTable(t), `CONTROL: ${t} is absent from the registry, so the assert below can fail`);
  }
  assert(isLogicalTable("ACCOUNTS"), "CONTROL: a real table IS accepted, so the predicate discriminates");

  // The action is unknown; the table is deliberately a REAL one, so this arm can only throw on the action.
  assertThrows(() => parseRequest({ action: "delete", table: "ACCOUNTS" }), ValidationError);
  for (const t of ABSENT_TABLES) {
    assertThrows(() => parseRequest({ action: "read", table: t }), ValidationError);
  }
});

Deno.test("batchUpsert requires id; batchCreate does not", () => {
  assertThrows(() => parseRequest({ action: "batchUpsert", table: "ACCOUNTS", rows: [{ enc: "v1.i.c" }] }), ValidationError);
  const ok = parseRequest({ action: "batchCreate", table: "ACCOUNTS", rows: [{ enc: "v1.i.c", currency: "EUR" }] });
  assert(ok.action === "batchCreate");
});

Deno.test("read routes with since and maps logical->physical table", async () => {
  const { db, calls } = fakeDb();
  const out = await runAction(parseRequest({ action: "read", table: "TRANSACTIONS", since: "2024-01-01T00:00:00Z" }), db, { isTest: false });
  assertEquals(calls[0], { op: "read", table: "transactions", arg: "2024-01-01T00:00:00Z" });
  assertEquals(out, [{ id: "r1" }]);
});

Deno.test("batchUpdate fans out per row id", async () => {
  const { db, calls } = fakeDb();
  await runAction(parseRequest({ action: "batchUpdate", table: "TRANSACTIONS", updates: [{ id: "t1", enc: "v1.a.b" }, { id: "t2", enc: "v1.c.d" }] }), db, { isTest: false });
  assertEquals(calls.map((c) => c.op), ["update", "update"]);
  assertEquals(calls[0].arg, { id: "t1", ch: { enc: "v1.a.b" } });
});

Deno.test("wipe is blocked outside test context, allowed inside", async () => {
  const { db } = fakeDb();
  let threw = false;
  try { await runAction(parseRequest({ action: "wipe", table: "MEMBERS" }), db, { isTest: false }); }
  catch (e) { threw = e instanceof ValidationError; }
  assert(threw, "wipe must throw when isTest=false");
  const res = await runAction(parseRequest({ action: "wipe", table: "MEMBERS" }), db, { isTest: true });
  assertEquals(res, { wiped: 3 });
});

Deno.test("empty batches are no-ops", async () => {
  const { db, calls } = fakeDb();
  assertEquals(await runAction(parseRequest({ action: "batchCreate", table: "ACCOUNTS", rows: [] }), db, { isTest: false }), []);
  assertEquals(calls.length, 0);
});

Deno.test("STAGED_TRANSACTIONS: strips server keys, keeps writable (enc envelope, null FKs)", () => {
  const req = parseRequest({
    action: "batchCreate", table: "STAGED_TRANSACTIONS",
    rows: [{
      id: "st1", batch_id: "b1", enc: "v1.iv.ct", category_id: null,
      family_id: "forged", updated_at: "2000", isDirty: true,
    }],
  });
  if (req.action !== "batchCreate") throw new Error("wrong action");
  assertEquals(req.rows[0], { id: "st1", batch_id: "b1", enc: "v1.iv.ct", category_id: null });
});

Deno.test("STAGED_TRANSACTIONS: rejects unknown row key and read maps logical->physical", async () => {
  assertThrows(
    () => parseRequest({ action: "batchCreate", table: "STAGED_TRANSACTIONS", rows: [{ id: "st1", bogus: 1 }] }),
    ValidationError, "Unknown key 'bogus'",
  );
  const { db, calls } = fakeDb();
  await runAction(parseRequest({ action: "read", table: "STAGED_TRANSACTIONS" }), db, { isTest: false });
  assertEquals(calls[0].table, "staged_transactions");
});

Deno.test("IMPORT_MAPPINGS: strips server keys, keeps writable (id, enc only)", () => {
  const req = parseRequest({
    action: "batchUpsert", table: "IMPORT_MAPPINGS",
    rows: [{ id: "im1", enc: "v1.iv.ct", family_id: "forged", user_id: "x", updated_at: "2000", isDirty: true }],
  });
  if (req.action !== "batchUpsert") throw new Error("wrong action");
  assertEquals(req.rows[0], { id: "im1", enc: "v1.iv.ct" });
});

Deno.test("IMPORT_MAPPINGS: rejects unknown row key and read maps logical->physical", async () => {
  assertThrows(
    () => parseRequest({ action: "batchCreate", table: "IMPORT_MAPPINGS", rows: [{ id: "im1", bogus: 1 }] }),
    ValidationError, "Unknown key 'bogus'",
  );
  const { db, calls } = fakeDb();
  await runAction(parseRequest({ action: "read", table: "IMPORT_MAPPINGS" }), db, { isTest: false });
  assertEquals(calls[0].table, "import_mappings");
});

Deno.test("version: table-less action routes to db.version()", async () => {
  const { db, calls } = fakeDb();
  const out = await runAction(parseRequest({ action: "version" }), db, { isTest: false });
  assertEquals(calls[0].op, "version");
  assertEquals(out, { version: "2026-01-01T00:00:00.000Z" });
});

Deno.test("version: parses with no table; a stray table is ignored", () => {
  const a = parseRequest({ action: "version" });
  assert(a.action === "version");
  const b = parseRequest({ action: "version", table: "TRANSACTIONS" });
  assert(b.action === "version");
});

Deno.test("deleteAccount: table-less action routes to db.deleteAccount()", async () => {
  const { db, calls } = fakeDb();
  const out = await runAction(parseRequest({ action: "deleteAccount" }), db, { isTest: false });
  assertEquals(calls[0].op, "deleteAccount");
  assertEquals(out, { deleted: true });
});

Deno.test("deleteAccount: parses with no table; a stray table is ignored", () => {
  const a = parseRequest({ action: "deleteAccount" });
  assert(a.action === "deleteAccount");
  const b = parseRequest({ action: "deleteAccount", table: "TRANSACTIONS" });
  assert(b.action === "deleteAccount");
});

// Irreversible action: must never fire against the shared dev/CI test user. Inverse of
// wipe's gate (wipe requires isTest=true; deleteAccount requires isTest=false).
Deno.test("deleteAccount: blocked inside test context, allowed outside", async () => {
  const { db } = fakeDb();
  let threw = false;
  try { await runAction(parseRequest({ action: "deleteAccount" }), db, { isTest: true }); }
  catch (e) { threw = e instanceof ValidationError; }
  assert(threw, "deleteAccount must throw when isTest=true");
  const res = await runAction(parseRequest({ action: "deleteAccount" }), db, { isTest: false });
  assertEquals(res, { deleted: true });
});
