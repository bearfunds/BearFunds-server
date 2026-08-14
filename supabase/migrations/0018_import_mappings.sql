-- BearFunds server - Schema Contract v1.22 (forward-only, additive).
-- Adds IMPORT_MAPPINGS: the family's memory of which source column header maps to which
-- import field, so a bank file mapped once is mapped automatically next time. Synced
-- across the family (two people importing from the same bank should not each teach the
-- app the same thing).
--
-- ENTIRELY OPAQUE: a bank's column names describe the account, so this table has NO
-- plaintext columns beyond the standard tenancy/sync scaffolding. The envelope carries
-- { header, header_norm, verdict } - see contract.ts and client/core/api/schema.ts for
-- the full shape. The server cannot dedupe or index on the header; that is the client's
-- job (newest updated_at wins, ties broken by lexicographically smallest id, loser
-- tombstoned - see client/features/import/mappingMemory.ts).
--
-- Tenancy invariants (0_AI_INSTRUCTIONS.md, QA Areas 008/019): server-derived family_id,
-- server-managed updated_at, explicit RLS family isolation. Same pattern as budgets
-- (0016): the trigger/policy loops in 0001/0002 are hardcoded arrays that exclude this
-- table, so everything is wired explicitly below.

-- 1. New tenant table: import_mappings.
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
--    returns a stale timestamp, so a device whose ONLY change is an import mapping is
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
    union all select max(updated_at)  from public.wallets             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.entities            where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.members             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.staged_transactions where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.budgets             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.import_mappings     where family_id = public.auth_family_id()
  ) s;
$$;

grant execute on function public.family_version() to authenticated;
