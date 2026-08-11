-- BearFunds server - Schema Contract v1.17 (forward-only; BREAKING + DESTRUCTIVE).
--
-- THE BUDGETS/AREAS REMODEL. A Budget stops being a flat "amount + one category set" and becomes a
-- period-scoped CONTAINER OF AREAS (named category groups whose amounts sum to the allocated
-- total). The v1 template/instance pair is gone: every row is now an INSTANCE - the instructions
-- for computing ONE Budget for ONE period.
--
-- THIS MIGRATION IS A WIPE, NOT A MIGRATION. There is no mapping from a v1 row to a v2 one (a flat
-- Budget is not an Area, and templates have no successor), and the whole payload is CIPHERTEXT the
-- server cannot read, so it could not rewrite the rows even if a mapping existed. The reason this
-- is allowed to be brutal: the app is in alpha and NO USER HAS BUDGET DATA (operator's explicit
-- call, 2026-07-12; accepted residual - any budget a tester creates before the deploy is lost).
--
-- PLAINTEXT SHRINKS (risk map S1). Plaintext `period_start` on a custom-dated Budget published a
-- family's holiday dates to the server, and `template_id` published their budgeting cadence.
-- Neither was ever computed over server-side - delta sync needs only id + updated_at + enc - so
-- both move INSIDE the envelope at no functional cost. What is left plaintext is deliberately
-- inert: `kind` (a single constant) and `period_type` (a coarse cadence), kept for debuggability.
--
-- The envelope now carries: { line_id, live, period_start, period_end, target?, account_ids[],
-- areas[{ id, name, amount, category_ids[] }], adjustments[{ area_id, amount }], name, note? }.
--
-- CONSEQUENCE, stated deliberately: the one-category-per-AREA rule cannot be a database constraint
-- (the membership is ciphertext). It is enforced client-side by core/budgetPolicy.ts with a unit
-- matrix - and so is convergence: two devices may now mint DIFFERENT ids for the same period, and
-- the client collapses the twins by comparing the decrypted instructions (core/budgetDedup.ts).
-- The server stays dumb on purpose; there is nothing here for it to reason about.
--
-- DEPLOY GATE: this ships in ONE coordinated release with the R1+R2 client. A deployed v1 client
-- writing `currency` / `template_id` / `period_start` at a v1.17 server is REJECTED as an unknown
-- key (contract.ts allowlist), so there must be no window in which the two versions coexist.

-- 1. The wipe. Forward-only: the rows are dropped, not transformed.
delete from public.budgets;

-- 2. The dead plaintext columns.
--    currency     - a Budget's currency is now DERIVED from its accounts (the first one selected
--                   fixed it, and the picker filtered the rest to match). A stored currency can
--                   drift out of step with the accounts it claims to describe; a derived one cannot.
--    template_id  - templates no longer exist. Lineage rides `line_id` INSIDE the envelope, and its
--                   only job is grouping a line's history: it coordinates nothing.
--    stopped_at   - stopping a line is now clearing `live` on its latest instance. No date, no flag
--                   to go stale, nothing to repair after a delete.
--    period_start / period_end - moved into the envelope (S1).
alter table public.budgets drop column if exists currency;
alter table public.budgets drop column if exists template_id;
alter table public.budgets drop column if exists stopped_at;
alter table public.budgets drop column if exists period_start;
alter table public.budgets drop column if exists period_end;

-- 3. Everything else is UNCHANGED and stays that way, deliberately:
--    - the composite PK (family_id, id), the RLS family-isolation policy, and the two triggers
--      (server-managed updated_at, server-derived family_id) from 0016;
--    - budgets_family_updated_idx, which is the delta-read path (family_id + updated_at) and does
--      not reference any dropped column;
--    - family_version(), whose union still includes budgets. Dropping it from that union would not
--      error - the `version` probe would just return a stale timestamp, so a device whose only
--      change is a budget edit would be told "nothing changed" and would never sync. That silent
--      break is pinned by an assertion in rls_isolation.test.sql.
