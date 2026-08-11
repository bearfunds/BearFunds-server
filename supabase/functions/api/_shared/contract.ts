// Schema Contract v1.16 - the single source of allowed tables, logical->physical
// table mapping, and per-table writable column allowlists (snake_case logical keys).
// Keys the client must never set (tenancy/sync-internal) are stripped, not errored.
// v1.14 (RLE): sensitive fields ride an opaque client-encrypted `enc` envelope on
// TRANSACTIONS / ACCOUNTS / ENTITIES / STAGED_TRANSACTIONS; their plaintext keys are
// REMOVED from the allowlists so the server rejects any plaintext write (enforced,
// not conventional). Categories/subcategories/members stay plaintext by design.
// v1.16 (additive): BUDGETS - a synced informational layer over transactions. It is an
// ENC table: name/amount/note/percent AND the category+account membership all ride the
// envelope, so only the period/currency scaffolding is plaintext.
// v1.17 (BREAKING + DESTRUCTIVE): the Budgets/Areas remodel. Budgets become period-scoped
// containers of Areas; templates are gone (every row is an instance). The plaintext surface
// shrinks to kind + period_type - the period bounds, the line id and the entire plan move
// inside the envelope, so the server can no longer read a family's cadence, currency, or a
// one-off's exact date range. Budget rows are WIPED by migration 0017 (alpha; no user data).

// v1.22 (ADDITIVE): IMPORT_MAPPINGS - the family's memory of which source column header maps to
// which import field. A pure ENC table: the header, its normalised key and the verdict all ride the
// envelope, so there is no plaintext surface at all beyond the tenancy and sync scaffolding.
//
// THIS LIST IS THE THIRD HAND-MAINTAINED REGISTER A NEW COLLECTION HAS TO JOIN, AND IT IS THE ONE
// NOTHING WALKS YOU TO. The client's core/collections.ts drives four sites by compile error; its
// `collectionsToUpdate` is documented as the trap the compiler misses. This file is a fourth, in a
// different repo, reachable from neither - and on 2026-08-09 slice 6 shipped the migration, the RLS
// policy, the isolation test, the contract XML and the whole client sync layer WITHOUT it. The
// symptom was not a missing feature: `validation.ts` throws on an unknown table, so the entire
// pull aborted and EVERY collection stopped syncing for any client build that knew the name.
// Guarded now by contractTables.test.ts, which derives this set from the contract XML.
export type LogicalTable =
  | "TRANSACTIONS" | "CATEGORIES" | "SUBCATEGORIES" | "ACCOUNTS" | "ENTITIES" | "MEMBERS" | "STAGED_TRANSACTIONS"
  | "BUDGETS" | "IMPORT_MAPPINGS";

export const PHYSICAL: Record<LogicalTable, string> = {
  TRANSACTIONS: "transactions",
  CATEGORIES: "categories",
  SUBCATEGORIES: "subcategories",
  ACCOUNTS: "accounts",
  ENTITIES: "entities",
  MEMBERS: "members",
  STAGED_TRANSACTIONS: "staged_transactions",
  BUDGETS: "budgets",
  IMPORT_MAPPINGS: "import_mappings",
};

// Server-managed / client-derived keys: silently removed from any inbound row.
// family_id & user_id are server-derived (never trusted); updated_at is trigger-managed;
// isDirty is a client-only transient flag that is never persisted.
export const STRIPPED_KEYS = new Set<string>([
  "family_id", "user_id", "updated_at", "isDirty", "is_dirty",
]);

const GLOBAL_WRITABLE = ["id", "deleted", "is_immutable"];

export const WRITABLE: Record<LogicalTable, Set<string>> = {
  TRANSACTIONS: new Set([
    ...GLOBAL_WRITABLE,
    "date", "currency", "type", "category_id", "sub_category_id",
    "entity_id", "account_id", "member_id", "status", "enc",
  ]),
  CATEGORIES: new Set([
    ...GLOBAL_WRITABLE, "name", "type", "icon", "color", "description",
  ]),
  SUBCATEGORIES: new Set([
    ...GLOBAL_WRITABLE, "category_id", "name", "is_default",
  ]),
  ACCOUNTS: new Set([
    ...GLOBAL_WRITABLE, "currency", "icon", "color", "is_default", "enc",
  ]),
  ENTITIES: new Set([
    ...GLOBAL_WRITABLE,
    "default_category_id", "default_sub_category_id", "icon", "color", "enc",
  ]),
  MEMBERS: new Set([
    ...GLOBAL_WRITABLE, "name", "role", "avatar", "color",
  ]),
  STAGED_TRANSACTIONS: new Set([
    ...GLOBAL_WRITABLE,
    "batch_id", "date", "currency", "type", "category_id", "sub_category_id",
    "entity_id", "account_id", "member_id", "status", "enc",
  ]),
  // BUDGETS is an ENC table, and at v1.17 it is very nearly ONLY an enc table. The whole plan -
  // name, target, Areas, category + account membership, the period bounds, the recurring line id -
  // rides the envelope, so a plaintext write of any of it is REJECTED (VALIDATION), not merely
  // ignored. That rejection is load-bearing: it is what makes an old v1 client fail LOUDLY against
  // a v1.17 server instead of silently writing rows nobody can read back. Hence the deploy gate -
  // server and client ship together.
  //
  // What remains writable is deliberately inert: `kind` is a single constant ('instance'), and
  // `period_type` is a coarse cadence. Neither is sensitive, neither is computed over server-side,
  // and both exist for debuggability. currency / template_id / period_start / period_end /
  // stopped_at are GONE (migration 0017 drops the columns).
  BUDGETS: new Set([
    ...GLOBAL_WRITABLE,
    "period_type", "kind", "enc",
  ]),
  // IMPORT_MAPPINGS is a PURE enc table - the only one. A bank's column names describe the account,
  // so the header, the normalised key and the verdict are all user data and none of them has a
  // plaintext column to be written to. Nothing is added here "for debuggability" the way BUDGETS
  // keeps `kind` and `period_type`: there is no coarse, insensitive fact about a remembered mapping
  // worth publishing to the server, and a column added later to make one visible would be a
  // privacy decision rather than a convenience.
  IMPORT_MAPPINGS: new Set([
    ...GLOBAL_WRITABLE, "enc",
  ]),
};

export const ACTIONS = new Set([
  "read", "batchCreate", "batchUpdate", "batchUpsert", "wipe", "version",
]);

export function isLogicalTable(t: unknown): t is LogicalTable {
  return typeof t === "string" && t in PHYSICAL;
}
