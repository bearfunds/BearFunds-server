// Schema Contract v1.14 - the single source of allowed tables, logical->physical
// table mapping, and per-table writable column allowlists (snake_case logical keys).
// Keys the client must never set (tenancy/sync-internal) are stripped, not errored.
// v1.14 (RLE): sensitive fields ride an opaque client-encrypted `enc` envelope on
// TRANSACTIONS / WALLETS / ENTITIES / STAGED_TRANSACTIONS; their plaintext keys are
// REMOVED from the allowlists so the server rejects any plaintext write (enforced,
// not conventional). Categories/subcategories/members stay plaintext by design.

export type LogicalTable =
  | "TRANSACTIONS" | "CATEGORIES" | "SUBCATEGORIES" | "WALLETS" | "ENTITIES" | "MEMBERS" | "STAGED_TRANSACTIONS";

export const PHYSICAL: Record<LogicalTable, string> = {
  TRANSACTIONS: "transactions",
  CATEGORIES: "categories",
  SUBCATEGORIES: "subcategories",
  WALLETS: "wallets",
  ENTITIES: "entities",
  MEMBERS: "members",
  STAGED_TRANSACTIONS: "staged_transactions",
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
};

export const ACTIONS = new Set([
  "read", "batchCreate", "batchUpdate", "batchUpsert", "wipe", "version",
]);

export function isLogicalTable(t: unknown): t is LogicalTable {
  return typeof t === "string" && t in PHYSICAL;
}
