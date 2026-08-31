-- 0012: family_version() -- the family-scoped sync high-water mark.
--
-- The `version` action (Schema Contract v1.13) calls this so the client can ask, on app
-- open, "has anything changed since my last sync?" WITHOUT pulling every collection.
-- Returns max(updated_at) across all tenant tables for the caller's family (null when the
-- family has no rows). Tenancy is the same auth_family_id() the read/write/RLS path uses
-- (test-aware via migration 0011), so the value is automatically scoped to the caller's
-- real or TEST family. The existing (family_id, updated_at) indexes make each per-table
-- max() an index scan.
--
-- SECURITY INVOKER: runs under the caller's RLS; the explicit `family_id = auth_family_id()`
-- filter is defense-in-depth, not the primary guard. STABLE: read-only. Forward-only.

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
  ) s;
$$;

grant execute on function public.family_version() to authenticated;
