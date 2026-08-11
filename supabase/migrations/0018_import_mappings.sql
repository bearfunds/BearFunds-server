-- BearFunds server - Schema Contract v1.22 (forward-only, additive).
-- Adds IMPORT_MAPPINGS: the family's memory of which source column header maps to which
-- import field, so a bank's file that has been mapped once is mapped automatically the
-- next time. Synced across the family by operator decision (2026-08-09): two people
-- importing from the same bank should not each teach the app the same thing.
--
-- WHY THIS IS SAFE TO PERSIST WHEN THE OTHER IMPORT MAPPINGS WERE NOT. The client used to
-- carry walletMapping / categoryMapping / nameMapping and they were deleted, because each
-- stored a RECORD ID: a saved session could name a wallet or category that had since been
-- deleted, and the user found out only when a step re-rendered blank. A column mapping's
-- target is a FIELD NAME from a closed set (the client's TARGET_FIELDS), so it cannot go
-- stale that way. That difference is the entire argument for this table and is written
-- here so a later reader does not re-open a question that was already answered.
--
-- THE VERDICT IS A UNION, NOT A NULLABLE FIELD. "This column is ignored" is worth exactly
-- as much as "this column is the date" - it is what stops a bank's reference-number column
-- being re-proposed every month - so the stored value is field-or-ignored. On the client
-- this collapses two parallel maps (mapping and ignoredColumns) that were held mutually
-- exclusive BY HAND at two call sites; the union removes that invariant rather than adding
-- a third thing to keep in step with it.
--
-- RLE: the ENTIRE payload rides the opaque `enc` envelope - { header, header_norm, verdict }.
-- A bank's column names describe the account, so they are user data, and this table has NO
-- plaintext columns beyond the tenancy and sync scaffolding. Migration 0017 dropped five
-- plaintext columns from budgets because a period range publishes a family's holiday dates;
-- the same reasoning applies harder here, so none are introduced.
--
-- CONSEQUENCE, STATED DELIBERATELY: the server cannot dedupe or index on the header,
-- because the header is ciphertext. DEDUP IS THE CLIENT'S JOB. And because ids are minted
-- with crypto.randomUUID() like every other row in this system, two devices that map the
-- same header while offline WILL create two rows for it. That is expected, not a defect.
-- The client's merge must therefore converge WITHOUT COORDINATION: both devices have to
-- pick the same survivor from the same inputs, so the rule is newest updated_at, ties
-- broken by the lexicographically smallest id, loser tombstoned. Any rule that depends on
-- which device ran first would leave the two fighting forever.
--
-- THE ROAD NOT TAKEN, recorded so it is not re-proposed as an obvious improvement: a
-- DETERMINISTIC id (a digest of the normalised header) would make the two devices mint one
-- row and delete the dedup problem outright. It is rejected because a plain hash of a
-- low-entropy string is not opaque - "date", "amount", "description" fall to a wordlist in
-- milliseconds - so it would publish the shape of a family's bank file to a server that is
-- specifically not allowed to read it. An HMAC under the family key would be sound, but
-- this codebase mints every id with randomUUID and has no keyed-digest primitive; adding
-- one to save a client-side merge rule is the wrong trade at this size.
--
-- Tenancy invariants (0_AI_INSTRUCTIONS.md, brain QA Areas 008/019): server-derived
-- family_id, server-managed updated_at, explicit RLS family isolation. The trigger and
-- policy loops in 0001/0002 are HARDCODED arrays that exclude this table, so everything is
-- wired explicitly below (as budgets did in 0016 and staged_transactions in 0006).
--
-- Forward-only, additive, non-destructive: no existing table or column is touched.

-- 1. New tenant table: import_mappings.
--    PRIMARY KEY (family_id, id) inline, per migration 0009: families seed identical fixed
--    ids, so a global `id` PK made the second family collide into an RLS-denied upsert.
--    0009 has already run and will not re-key a table that did not exist yet.
create table if not exists public.import_mappings (
  id            text not null,
  family_id     uuid not null references public.families(id) on delete cascade,
  enc           text,
  updated_at    timestamptz not null default now(),
  deleted       boolean not null default false,
  is_immutable  boolean not null default false,
  primary key (family_id, id)
);

-- Delta-sync read path: read(since) filters family_id + updated_at.
create index if not exists import_mappings_family_updated_idx
  on public.import_mappings (family_id, updated_at);

-- 2. Shared triggers: server-managed updated_at + server-derived family_id.
--    Without set_updated_at the delta sync would SILENTLY drop every edit - updated_at
--    would never move, so `read since` would never return the row again.
create trigger import_mappings_set_updated_at before insert or update on public.import_mappings
  for each row execute function public.set_updated_at();
create trigger import_mappings_set_family_id before insert or update on public.import_mappings
  for each row execute function public.set_family_id();

-- 3. Grants + RLS family isolation (mirrors migration 0002 for every tenant table).
grant select, insert, update, delete on public.import_mappings to authenticated;
alter table public.import_mappings enable row level security;
create policy import_mappings_family_isolation on public.import_mappings
  for all to authenticated
  using (family_id = public.auth_family_id())
  with check (family_id = public.auth_family_id());

-- 4. Re-register the table in the family high-water mark.
--    THE SILENT BREAK THIS GUARDS: family_version() is a hardcoded union per tenant table
--    (0012). Leave import_mappings out and nothing errors - the `version` probe just
--    returns a stale timestamp, so a device whose ONLY change is a remembered mapping is
--    told "nothing changed" and never syncs. Pinned by an assertion in rls_isolation.test.sql.
create or replace function public.family_version()
  returns timestamptz
  language sql
  stable
  security invoker
  set search_path = public
as $$
  select max(v) from (
    select max(updated_at) as v from public.transactions        where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.categories          where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.subcategories       where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.accounts             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.entities            where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.members             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.staged_transactions where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.budgets             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.import_mappings     where family_id = public.auth_family_id()
  ) s;
$$;

grant execute on function public.family_version() to authenticated;
