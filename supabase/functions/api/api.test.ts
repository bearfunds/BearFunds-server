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
    // BUDGETS (v1.26): the PAYLOAD rides enc - name, amount, target, note and the period bounds.
    // The four IDS do not: line_id, account_ids, ignored_category_ids and category_ids are plaintext
    // columns, because a server cannot scope what it cannot read and a Budget's visibility resolves
    // from the accounts it aggregates. They are therefore absent from this list by contract.
    //
    // `areas` STAYS SEALED AND THAT IS THE WHOLE DISTINCTION. category_ids is a FLATTENED UNION of
    // every Area's categories - a projection, not a move out of the envelope - so the server learns
    // WHICH categories a Budget watches and never HOW THEY ARE GROUPED. The grouping is the plan,
    // and the plan stays sealed (migration 0022).
    //
    // THE ACCEPTANCE HALF IS WITNESSED ELSEWHERE, so do not re-add the four ids here inverted into
    // accept-assertions: contractTables.test.ts holds "every client-writable column the contract
    // declares is ACCEPTED by the seam", with its subject list DERIVED from the contract XML. A
    // hand-typed copy here would be a second, hand-maintained version of a property already derived
    // from the one artifact both repos share.
    ["BUDGETS", { id: "b1", name: "Groceries" }],
    ["BUDGETS", { id: "b1", amount: 400 }],
    ["BUDGETS", { id: "b1", target: 2000 }],
    ["BUDGETS", { id: "b1", note: "new coffee machine" }],
    ["BUDGETS", { id: "b1", areas: "[]" }],
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
  for (const table of ["TRANSACTIONS", "WALLETS", "ENTITIES", "STAGED_TRANSACTIONS", "BUDGETS", "IMPORT_MAPPINGS"]) {
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

// MEMBERS ACCEPTS `role`, AND THE SEAM IS NOT WHERE A PROMOTION IS REFUSED.
//
// `role` was removed from WRITABLE.MEMBERS on 2026-08-19 alongside migration 0021, which was one
// defence too many: sanitizeRow THROWS on a key that is not writable, so every members batchUpsert
// began failing with "Unknown key 'role' for table MEMBERS" and the client's whole sync died at
// that batch. Seven ghost scenarios went red for a reason none of them was about. The two halves of
// that commit also contradicted each other in writing - 0021's own comment says "The client sends
// `role` on every member update, so this branch is the common case rather than an edge", which is
// only true if the key reaches the trigger.
//
// THE ENFORCEMENT IS THE TRIGGER, NOT THE ALLOWLIST. `members_role_change_guard` (0021) compares
// old.role to new.role and raises 'admin role required to change a member role' for a non-admin
// caller, which is a refusal the client can SEE - a stripped key is silently dropped and a rejected
// batch takes the whole sync with it. The RLS suite demonstrates both arms against real Postgres.
// This test pins the seam open so a future tidy-up cannot close it again without going red here.
Deno.test("MEMBERS: role is writable - the role-change guard (0021) is the refusal, not the seam", () => {
  const req = parseRequest({
    action: "batchUpsert", table: "MEMBERS",
    rows: [{ id: "m1", name: "Art", role: "admin", avatar: "/a.png", color: "#3b82f6", family_id: "forged", updated_at: "2000" }],
  });
  if (req.action !== "batchUpsert") throw new Error("wrong action");
  assertEquals(req.rows[0], { id: "m1", name: "Art", role: "admin", avatar: "/a.png", color: "#3b82f6" });
});

// PLAN_TYPE IS DROPPED, NOT REJECTED, AND THE DIFFERENCE IS THE WHOLE FEATURE.
//
// The client sends plan_type on every family_settings push and is expected to keep doing so: the
// client half of this property is pinned by the client's own tests/planAuthority, which says in
// writing that "the client may ASK, and the server dropping the key is the refusal. Removing the
// send would be a different design and should be a decision rather than a tidy-up."
//
// So the server owes a DROP. It was not dropping: plan_type was neither writable nor stripped, so
// sanitizeRow threw and the family_settings batch would have failed exactly as MEMBERS did, one
// batch later in the same sync. The FAMILY_SETTINGS comment in contract.ts already described the
// drop as the mechanism; the code now does what that comment says.
//
// A dropped key is silent BY DESIGN here and loud for role, which is the asymmetry worth keeping:
// nothing the client says about its own plan is believed, and there is no client surface that could
// act on a refusal it received. A server-side setter writes real values when feature controls land.
Deno.test("FAMILY_SETTINGS: plan_type is stripped, not rejected - the client may ask and is not answered", () => {
  const req = parseRequest({
    action: "batchUpsert", table: "FAMILY_SETTINGS",
    rows: [{ id: "family-settings", family_name: "Bear", family_photo: "/f.png", date_format: "dayFirst", plan_type: "Enterprise" }],
  });
  if (req.action !== "batchUpsert") throw new Error("wrong action");
  assertEquals(req.rows[0], { id: "family-settings", family_name: "Bear", family_photo: "/f.png", date_format: "dayFirst" });
  assert(!("plan_type" in req.rows[0]), "a forged plan must not reach the row the server writes");
});

// created_by (migration 0024) names WHO created a row, and the visibility predicate READS it -
// a member sees back what she created, which is what lets INSERT ... RETURNING succeed under a
// fail-closed read policy. So a client value for it would be a claim about identity that buys
// visibility, and it is stripped exactly like user_id. Stripped rather than non-writable for the
// same reason as plan_type: a non-writable key makes sanitizeRow THROW and takes the batch with
// it, where a strip drops and the BEFORE INSERT trigger repopulates from the session.
Deno.test("created_by is stripped on every table that carries it - it is a session fact, not a client one", () => {
  for (const table of ["ACCOUNTS", "TRANSACTIONS", "STAGED_TRANSACTIONS"] as const) {
    const req = parseRequest({
      action: "batchUpsert", table,
      rows: [{ id: "r1", enc: "v1.iv.ct", created_by: "m_someone_else" }],
    });
    if (req.action !== "batchUpsert") throw new Error("wrong action");
    assert(!("created_by" in req.rows[0]), `${table}: a forged created_by must not reach the row`);
    assertEquals(req.rows[0].id, "r1", `${table}: the rest of the row survives the strip`);
    assertEquals(req.rows[0].enc, "v1.iv.ct", `${table}: the envelope survives the strip`);
  }
});

// CONTROL: the strip is a DROP, not a rejection. A key the contract does not know at all still
// throws - which is the property that tells "silently ignored" apart from "quietly accepted",
// and the reason the assertion above is meaningful rather than vacuous.
Deno.test("CONTROL: an unknown key still throws, so the strip above is a drop and not a shrug", () => {
  let threw = false;
  try {
    parseRequest({
      action: "batchUpsert", table: "ACCOUNTS",
      rows: [{ id: "r1", enc: "v1.iv.ct", not_a_real_column: "x" }],
    });
  } catch {
    threw = true;
  }
  assert(threw, "an undeclared key must still be refused");
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
