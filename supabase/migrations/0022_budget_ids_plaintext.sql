-- BearFunds server - Schema Contract v1.26 (forward-only; BREAKING + DESTRUCTIVE).
--
-- BUDGET IDS LEAVE THE ENVELOPE. Four plaintext columns join BUDGETS - line_id, account_ids,
-- ignored_category_ids and category_ids - and the first three leave the encrypted envelope
-- entirely.
--
-- WHY. A server cannot scope what it cannot read. A Budget's visibility to a family member is
-- resolved from the accounts it aggregates, and BUDGETS was the ONLY table whose foreign keys were
-- sealed while TRANSACTIONS and STAGED_TRANSACTIONS have carried account_id in plaintext since
-- v1.23. An opaque id discloses nothing those columns do not already disclose.
--
-- category_ids IS DIFFERENT IN KIND, and the difference is the point. It is a FLATTENED UNION of
-- every Area's category_ids - a PROJECTION of the envelope's per-Area grouping, not a move out of
-- it. The server therefore learns WHICH categories a Budget watches and never HOW THEY ARE GROUPED.
-- The grouping is the plan, and the plan stays sealed. The envelope remains the source of truth:
-- anything that reads this column as authoritative is reading a derived value.
--
-- area_id is NOT promoted. It exists only inside adjustments, beside an amount, and is meaningless
-- apart from it. Period bounds, live, targets, names, notes and every Area amount stay inside the
-- envelope, as do the per-Area category_ids this column projects.
--
-- THIS SUPERSEDES HALF OF THE v1.17 DECISION, AND ONLY HALF. Migration 0017 sealed the period
-- bounds AND the line id together, reasoning that the pair published a family's cadence and a
-- one-off's exact date range. The BOUNDS half stands and is not reopened. The line-id half was
-- always a claim about the PAIR: with the bounds sealed, a line id is a random UUID whose only
-- disclosure is grouping - how many lines exist and how many instances each has - which row counts,
-- updated_at and the still-plaintext period_type already approximate. It also buys back what 0017
-- booked as its accepted cost: budget dedup is the one path in this app that deletes a row nobody
-- asked it to delete, and diagnosing a canonicalisation fault across two devices needs the line.
--
-- THIS MIGRATION IS A WIPE, NOT A MIGRATION - the same shape as 0017 and for the same reason. The
-- promoted fields are ciphertext the server cannot read, so it could not lift them into columns
-- even if a mapping existed. Rows are deleted rather than transformed. The reason this is allowed
-- to be brutal is unchanged and is DATED: the app is pre-alpha and every existing Budget is test
-- data (operator's explicit call, 2026-08-20). It expires on the first real family's first Budget.
--
-- LOCAL ROWS OUTLIVE THIS. A hard delete leaves no tombstone, a delta read is updated_at > since
-- and cannot express a row that is simply gone, and nothing enqueues an untouched local row - so
-- each device keeps its own orphans until someone clears them. 0017 shipped no local migration for
-- the identical reason: there is nothing to migrate when the only rows are test data.
--
-- DEPLOY GATE: server FIRST, then the client, with no window in which the two coexist. A client
-- emitting these columns at a pre-v1.26 server is rejected as an unknown key, and the seam REFUSES
-- rather than drops - one unknown key fails the whole batch and takes the sync with it.
--
-- RLS IS UNCHANGED. budgets_family_isolation already scopes this table by family; adding columns
-- does not touch it. No index is added here: the visibility predicate that will query account_ids
-- does not exist yet, and an index for a query nobody makes is a guess.

-- 1. The wipe. Forward-only: the rows are dropped, not transformed.
delete from public.budgets;

-- 2. The promoted columns.
--    NULLABLE, DELIBERATELY, AND NOT BECAUSE THE VALUES ARE OPTIONAL. A not-null constraint here
--    would be a second refusing layer at a BATCH endpoint: sanitizeRow already throws on an unknown
--    key, and a null violation would likewise fail the whole upsert and take every sibling row of
--    the batch with it. Presence is enforced where it can fail one row at a time - the client's
--    adapter always emits all four, and tests/budgetWireShape pins that it does.
alter table public.budgets
  add column if not exists line_id              text,
  add column if not exists account_ids          text[] not null default '{}'::text[],
  add column if not exists ignored_category_ids text[] not null default '{}'::text[],
  add column if not exists category_ids         text[] not null default '{}'::text[];

comment on column public.budgets.line_id is
  'Groups the instances of one recurring Budget. Random, minted on the creating device and copied on duplication; it coordinates nothing, so two devices may hold different ids for the same period.';
comment on column public.budgets.account_ids is
  'The accounts this Budget aggregates. Plaintext because a Budget''s visibility to a family member is resolved from it server-side.';
comment on column public.budgets.ignored_category_ids is
  'Categories this Budget deliberately does not watch. Empty means none ignored.';
comment on column public.budgets.category_ids is
  'The union of every Area''s category_ids, flattened. A PROJECTION of the envelope and never the source of truth: which categories are watched, never how they are grouped.';
