-- BearFunds server - Schema Contract v1.16 (forward-only, additive).
-- Adds BUDGETS: a synced, RLS-scoped, family-shared informational layer above
-- transactions/accounts/categories. A Budget NEVER holds or moves money - it is a
-- reporting/decision helper that aggregates existing transactions over a period, so
-- there is no server-side math here and no FK constraint to transactions.
--
-- Two-row model (design: "recurring = template copied into a live instance"):
--   kind='template' -- the recurring series definition. period_start = the series start
--                      point; period_end null (open-ended); stopped_at set when the user
--                      stops the series (no instances materialise after it).
--   kind='instance' -- a live, independently editable period. template_id points at its
--                      series (null for a one-off Budget, which is always an instance).
-- Instances are real rows precisely because the design requires editing a PAST period
-- retroactively and deleting one instance without deleting the series.
--
-- RLE (contract v1.15/v1.16): the entire meaningful payload rides the opaque `enc`
-- envelope -- { name, amount, note?, percent?, category_ids[], account_ids[] }. The server
-- stores it verbatim and can never read inside it. CONSEQUENCE, stated deliberately: the
-- one-category-per-Budget-per-period rule CANNOT be a database constraint (the membership
-- is ciphertext); it is enforced client-side by core/budgetPolicy.ts with a unit matrix.
-- Only the period/currency scaffolding is plaintext, and none of it is sensitive.
--
-- Utilization (spent / left / %) is COMPUTED ON DEVICE from the local ledger ([Q33]),
-- like account balances - nothing is snapshotted here, so nothing can go stale when a
-- past transaction is edited.
--
-- Tenancy invariants (0_AI_INSTRUCTIONS.md, brain QA Areas 008/019): server-derived
-- family_id, server-managed updated_at, explicit RLS family isolation. The trigger and
-- policy loops in 0001/0002 are HARDCODED arrays that exclude this table, so everything
-- is wired explicitly below (same as subcategories in 0005 and staged_transactions in 0006).
--
-- Forward-only, additive, non-destructive: no existing table or column is touched.

-- 1. New tenant table: budgets.
--    PRIMARY KEY (family_id, id) inline. Migration 0009 re-keyed every tenant table onto
--    the composite PK because families seed identical fixed ids (w001, c001, ...), and a
--    global `id` PK made the second family collide -> RLS-denied upsert -> 500. 0009 has
--    already run and will not re-key a table that did not exist yet, so budgets declares
--    the composite PK itself. (0005/0006 wrote `id text primary key` only because they
--    predate 0009.)
--    template_id is an UNCONSTRAINED self-reference: like every other FK on the wire it is
--    a logical id, and an offline client may create an instance before its template lands.
create table if not exists public.budgets (
  id            text not null,
  family_id     uuid not null references public.families(id) on delete cascade,
  currency      text,
  period_type   text,
  kind          text,
  template_id   text,
  period_start  text,
  period_end    text,
  stopped_at    text,
  enc           text,
  updated_at    timestamptz not null default now(),
  deleted       boolean not null default false,
  is_immutable  boolean not null default false,
  primary key (family_id, id)
);

-- Delta-sync read path: read(since) filters family_id + updated_at.
create index if not exists budgets_family_updated_idx
  on public.budgets (family_id, updated_at);

-- 2. Shared triggers: server-managed updated_at + server-derived family_id.
--    Without set_updated_at the delta sync would SILENTLY drop every budget edit
--    (updated_at would never move, so `read since` would never return the row).
create trigger budgets_set_updated_at before insert or update on public.budgets
  for each row execute function public.set_updated_at();
create trigger budgets_set_family_id before insert or update on public.budgets
  for each row execute function public.set_family_id();

-- 3. Grants + RLS family isolation (mirrors migration 0002 for every tenant table).
grant select, insert, update, delete on public.budgets to authenticated;
alter table public.budgets enable row level security;
create policy budgets_family_isolation on public.budgets
  for all to authenticated
  using (family_id = public.auth_family_id())
  with check (family_id = public.auth_family_id());

-- 4. Re-register the table in the family high-water mark.
--    THE SILENT BREAK THIS GUARDS: family_version() is a hardcoded union per tenant table
--    (0012). Leave budgets out and nothing errors - the `version` probe just returns a
--    stale timestamp, so a device whose ONLY change is a budget edit is told "nothing
--    changed" and never syncs. Pinned by an assertion in rls_isolation.test.sql.
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
  ) s;
$$;

grant execute on function public.family_version() to authenticated;
