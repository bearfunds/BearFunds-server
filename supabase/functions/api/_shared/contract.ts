// Schema Contract v1.16 - the single source of allowed tables, logical->physical
// table mapping, and per-table writable column allowlists (snake_case logical keys).
// Keys the client must never set (tenancy/sync-internal) are stripped, not errored.
// v1.14 (RLE): sensitive fields ride an opaque client-encrypted `enc` envelope on
// TRANSACTIONS / WALLETS / ENTITIES / STAGED_TRANSACTIONS; their plaintext keys are
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
// v1.22 (additive): IMPORT_MAPPINGS - the family's memory of which source column header maps
// to which import field. ENTIRELY opaque: no plaintext columns beyond the standard tenancy/
// sync scaffolding, so its WRITABLE set is GLOBAL_WRITABLE + enc only, same shape as budgets
// pre-0017 but with nothing left plaintext at all.

export type LogicalTable =
  | "TRANSACTIONS" | "CATEGORIES" | "SUBCATEGORIES" | "WALLETS" | "ENTITIES" | "MEMBERS" | "STAGED_TRANSACTIONS"
  | "BUDGETS" | "IMPORT_MAPPINGS";

export const PHYSICAL: Record<LogicalTable, string> = {
  TRANSACTIONS: "transactions",
  CATEGORIES: "categories",
  SUBCATEGORIES: "subcategories",
  WALLETS: "wallets",
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
    "entity_id", "wallet_id", "member_id", "status", "enc",
  ]),
  CATEGORIES: new Set([
    ...GLOBAL_WRITABLE, "name", "type", "icon", "color", "description",
  ]),
  SUBCATEGORIES: new Set([
    ...GLOBAL_WRITABLE, "category_id", "name", "is_default",
  ]),
  WALLETS: new Set([
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
    "entity_id", "wallet_id", "member_id", "status", "enc",
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
  // IMPORT_MAPPINGS (v1.22): header / header_norm / verdict all ride enc. Nothing plaintext
  // to write beyond the global set, so a plaintext 'header' or 'verdict' key is REJECTED
  // (VALIDATION), not merely ignored - same enforcement style as budgets' enc surface.
  IMPORT_MAPPINGS: new Set([
    ...GLOBAL_WRITABLE, "enc",
  ]),
};

export const ACTIONS = new Set([
  "read", "batchCreate", "batchUpdate", "batchUpsert", "wipe", "version", "deleteAccount",
]);

export function isLogicalTable(t: unknown): t is LogicalTable {
  return typeof t === "string" && t in PHYSICAL;
}
