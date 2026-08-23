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
// v1.24 (ADDITIVE): FAMILY_SETTINGS - the family's name, picture, plan and date format. The FIRST
// table added since RLE that carries NO envelope, and the asymmetry is deliberate rather than an
// oversight: nothing on the row describes the family's money or its people. The name is already
// plaintext on the tenancy root and peek_invite hands it to a joiner who holds no family key; the
// photo is one of four bundled asset paths; plan_type MUST stay readable because feature controls
// and analytics will gate on it; and a date format is not PII. Categories, subcategories and members
// are plaintext by the same test, so this is the house rule rather than an exception.
// v1.26 (BREAKING + DESTRUCTIVE): budget ids leave the envelope. line_id, account_ids and
// ignored_category_ids become plaintext columns, and category_ids joins them as a FLATTENED UNION
// of every Area's categories - a projection of the envelope rather than a move out of it, so the
// server learns which categories a Budget watches and never how they are grouped. A server cannot
// scope what it cannot read, and BUDGETS was the only table whose foreign keys were sealed while
// TRANSACTIONS has carried account_id in plaintext since v1.23. area_id is NOT promoted: it exists
// only inside adjustments, beside an amount. Period bounds, targets, names, notes and Area amounts
// stay sealed - this reopens the LINE-ID half of v1.17 and not the bounds half. Rows are WIPED by
// migration 0022 (pre-alpha; every existing Budget is test data).
export type LogicalTable =
  | "TRANSACTIONS" | "CATEGORIES" | "SUBCATEGORIES" | "ACCOUNTS" | "ENTITIES" | "MEMBERS" | "STAGED_TRANSACTIONS"
  | "BUDGETS" | "IMPORT_MAPPINGS" | "FAMILY_SETTINGS";

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
  FAMILY_SETTINGS: "family_settings",
};

// Server-managed / client-derived keys: silently removed from any inbound row.
// family_id & user_id are server-derived (never trusted); updated_at is trigger-managed;
// isDirty is a client-only transient flag that is never persisted.
//
// WHAT A STRIP DOES TO THE STORED VALUE, MEASURED RATHER THAN ASSUMED (2026-08-20). A stripped key
// is a column ABSENT from the row handed to .upsert(), so this whole mechanism rests on what
// PostgREST does with an absent column on the ON CONFLICT update path: it leaves it alone. Measured
// against the local stack - plan_type was set to a probe value directly in the database, a family
// rename was synced, and the probe value survived a push whose row demonstrably carried the new
// name. Had it default-filled instead, a strip would be a silent DELETE of whatever the server had
// stored, which is the exact opposite of the protection it resembles: family_settings would lose
// its plan on every push, and members.user_id would be nulled on every members batch.
//
// THE TRIGGERS ARE NOT WHAT MAKES THIS SAFE, though they look like it. family_id and updated_at are
// repopulated by the per-table triggers generated in 0002 and would survive either way; plan_type
// and user_id have no such trigger and survive purely on the retention property above. If a future
// column must be both stripped AND guaranteed, a trigger is the mechanism that guarantees it -
// this list is not.
//
// `plan_type` IS STRIPPED RATHER THAN REJECTED, and the two are not interchangeable. The client
// sends it on every family_settings push and is EXPECTED to keep doing so - the client's
// tests/planAuthority pins the send in place, on the grounds that the client may ask and the server
// dropping the key is the refusal. It was neither writable nor stripped between 2026-08-19 and this
// commit, which meant sanitizeRow threw and the family_settings batch would have failed exactly as
// MEMBERS did, one batch later in the same sync. The FAMILY_SETTINGS entry below already described
// the drop as the mechanism; this is the line that makes that description true.
//
// The key is stripped GLOBALLY because no other table declares a plan_type column, so a per-table
// strip would be machinery with one member. If a second table ever carries one, this becomes a
// per-table decision rather than a shared word.
// `created_by` (migration 0024) is STRIPPED for the same reason `user_id` is: it names WHO,
// it is derived from the session by a trigger, and a client value for it would be a claim
// about identity. It is stripped rather than made non-writable ON PURPOSE - a non-writable
// key makes sanitizeRow THROW and one such key killed every collection's sync on 2026-08-19,
// whereas a strip drops silently and the trigger repopulates. The read path is unaffected:
// the column comes back on pulled rows and the client simply has no adapter for it.
// `scope_version` (migration 0025, contract v1.27) is the server's statement of how many times
// what a member may RECEIVE has changed. The client reads it and answers a bump by clearing its
// scoped local stores and re-pulling; a client value for it would be a claim about its own
// permissions, and a false one would either suppress a needed re-pull or force a needless
// delete. Stripped rather than non-writable for the reason the two entries above share.
export const STRIPPED_KEYS = new Set<string>([
  "family_id", "user_id", "updated_at", "isDirty", "is_dirty", "plan_type", "created_by",
  "scope_version",
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
  // `role` IS WRITABLE, AND THE PROMOTION IS REFUSED ONE LAYER DOWN. A member issuing batchUpdate
  // on their own row with role 'admin' is rejected by `members_role_change_guard` (migration 0021),
  // which compares old.role to new.role and raises 'admin role required to change a member role'
  // unless the caller is an admin of that family. RLS cannot express this - `with check` sees only
  // the NEW row and the question is old-versus-new - so the trigger is the enforcement and this
  // allowlist is not. Both arms are demonstrated against real Postgres in the RLS suite.
  //
  // IT IS WRITABLE BECAUSE REMOVING IT WAS ONE DEFENCE TOO MANY. `role` was taken out of this set on
  // 2026-08-19 beside 0021; sanitizeRow THROWS on a non-writable key, so every members batchUpsert
  // began failing with "Unknown key 'role'" and the client's entire sync died at that batch - seven
  // ghost scenarios red for a reason none of them was about. 0021's own comment states the shape it
  // was written for: "The client sends `role` on every member update, so this branch is the common
  // case rather than an edge." That is only true if the key gets through.
  //
  // A REFUSAL THE CLIENT CAN SEE IS THE POINT. A stripped key vanishes silently and a rejected batch
  // takes the sync with it; a trigger exception is neither. A promote/demote UI needs exactly that,
  // and it is now the only thing standing between a client and a role change.
  //
  // WHAT THIS DOES NOT DEFEND, because a reader will otherwise assume it does: nothing here protects
  // a client from its OWN local store. mergePulledCollection is last-write-wins on updated_at, and
  // there is no server-authority override for role the way there is for plan_type, so a tampered
  // IndexedDB row keeps a forged 'admin' locally through every pull. That is a client-side hole and
  // an RLS role predicate is what closes it - filed against L2 in the brain, not solved here.
  MEMBERS: new Set([
    ...GLOBAL_WRITABLE, "name", "avatar", "color", "role",
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
  // v1.26: the four id columns are CLIENT-WRITABLE, unlike FAMILY_SETTINGS.plan_type. Nothing here
  // is a claim the server needs to own - an id names a row the client already holds, and the server
  // reads them only to answer "may this member see this Budget". A stripped or refused id would
  // make the Budget invisible to the predicate that exists to scope it.
  BUDGETS: new Set([
    ...GLOBAL_WRITABLE,
    "period_type", "kind", "enc",
    "line_id", "account_ids", "ignored_category_ids", "category_ids",
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
  // FAMILY_SETTINGS is the inverse of IMPORT_MAPPINGS: every column is writable and NONE is an
  // envelope. There is no `enc` here to reject a plaintext write against, because the plaintext IS
  // the design - see the type union above for why each column earns that.
  //
  // `family_name` IS WRITABLE AND THE TENANCY ROOT IS NOT. A rename lands here rather than on
  // families.name, which keeps its select-only grant from migration 0002 - so the client never gains
  // a write path to the row every tenant table's family_id points at. peek_invite reads this name
  // and falls back to the root's, which is what makes that split invisible to a joiner.
  //
  // `plan_type` IS NOT WRITABLE EITHER, and for the same reason one level along (operator,
  // 2026-08-19). The comment above says it must stay server-READABLE because feature controls will
  // gate on it; a field the client can also WRITE is a gate the client sets for itself. The client
  // may still send it - that is the request channel, and the server dropping it is the refusal -
  // but nothing the client says about its own plan is believed. The column stays nullable with no
  // default: absent means the default tier, which is a fact the client can render without asserting,
  // and a server-side setter writes real values when feature controls land.
  FAMILY_SETTINGS: new Set([
    ...GLOBAL_WRITABLE, "family_name", "family_photo", "date_format",
  ]),
};

export const ACTIONS = new Set([
  "read", "batchCreate", "batchUpdate", "batchUpsert", "wipe", "version",
]);

export function isLogicalTable(t: unknown): t is LogicalTable {
  return typeof t === "string" && t in PHYSICAL;
}
