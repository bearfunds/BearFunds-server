// THE API SEAM KNOWS EVERY TABLE THE CONTRACT DECLARES.
// Run with: deno test --allow-read supabase/functions/api/contractTables.test.ts
//
// WHY THIS EXISTS. On 2026-08-09 contract v1.22 added IMPORT_MAPPINGS. The migration created the
// table, the RLS policy landed, the isolation test passed, the contract XML declared it, and the
// whole client sync layer shipped - and this function's own registry in _shared/contract.ts was
// never updated. Nothing anywhere could say so: the client's compiler walks its OWN four sites, the
// migration knows nothing about TypeScript, and the contract XML is prose to both.
//
// THE SYMPTOM WAS NOT A MISSING FEATURE, WHICH IS THE PART WORTH REMEMBERING. validation.ts throws
// ValidationError on an unknown table, so the client's pull - which reads every collection in turn -
// ABORTED at the last one. Every earlier table had already been read successfully and none of it was
// committed. So a single missing registry entry stopped ALL syncing, for every collection, on any
// client build that knew the name. It surfaced as two unrelated-looking red scenarios about a sync
// indicator and a tombstone.
//
// THE SUBJECT LIST IS DERIVED FROM THE CONTRACT XML, never hand-typed here - a check that had to be
// remembered would have been forgotten by the same slice that forgot the registry.
//
// WHAT THIS DOES NOT COVER: whether the PHYSICAL name matches a table that actually exists in the
// database (that is the migration's business, and a typo here would surface as an upstream error at
// runtime), and whether the WRITABLE set is correct - only that it is present and non-empty. A
// column allowed here but absent from the table is caught by Postgres, loudly, on first write.
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { PHYSICAL, WRITABLE, isLogicalTable } from "./_shared/contract.ts";

const CONTRACT = new URL("../../../contracts/2_SCHEMA_CONTRACT.xml", import.meta.url);

/** Every <Table name="..."> the contract declares, minus the tenancy root the API never serves. */
function declaredTables(xml: string): string[] {
  const names = [...xml.matchAll(/<Table\s+name="([A-Z_]+)"/g)].map((m) => m[1]);
  // FAMILIES is the tenancy ROOT, not a synced collection: the client never names it in a request,
  // and rows are created by the sign-up trigger rather than through this seam. Excluded with its
  // reason rather than silently, so a future reader can argue with the exclusion.
  return names.filter((n) => n !== "FAMILIES");
}

Deno.test("every contract table is in the API's registry", async () => {
  const xml = await Deno.readTextFile(CONTRACT);
  const declared = declaredTables(xml);

  // CONTROL FIRST: the parser must have found real tables, or an empty list would make every
  // assertion below pass by having no subjects.
  assert(declared.length >= 8, `the contract parse found real tables (got ${declared.length})`);
  assert(declared.includes("TRANSACTIONS"), "CONTROL: a table known to exist was parsed");

  const missing = declared.filter((t) => !isLogicalTable(t));
  assertEquals(
    missing,
    [],
    `contract tables the API seam does not know: ${missing.join(", ")}. ` +
    `A request naming one is rejected as "Unknown or missing table", which ABORTS the client's ` +
    `whole pull - not just this collection.`,
  );

  for (const t of declared) {
    assert(t in PHYSICAL, `${t} has a physical table name`);
    assert(PHYSICAL[t as keyof typeof PHYSICAL].length > 0, `${t}'s physical name is not empty`);
    assert(WRITABLE[t as keyof typeof WRITABLE] instanceof Set, `${t} has a writable-column set`);
    assert(WRITABLE[t as keyof typeof WRITABLE].size > 0, `${t}'s writable set is non-empty`);
  }
});

Deno.test("the registry declares nothing the contract does not", async () => {
  // The other direction, and it is not symmetric: a table here that the contract has never heard of
  // is a seam accepting writes to something outside the agreed interface, which is worse than a
  // missing one because it fails silently rather than loudly.
  const xml = await Deno.readTextFile(CONTRACT);
  const declared = new Set(declaredTables(xml));
  const extra = Object.keys(PHYSICAL).filter((t) => !declared.has(t));
  assertEquals(extra, [], `API tables absent from the contract: ${extra.join(", ")}`);
});

Deno.test("CONTROL: the membership predicate rejects a table nobody declared", () => {
  assert(!isLogicalTable("IMPORT_MAPPING"), "a near-miss singular is NOT accepted");
  assert(!isLogicalTable("DROP TABLE"), "nor is arbitrary text");
  assert(isLogicalTable("IMPORT_MAPPINGS"), "and the real one IS - so this check can fail");
});
