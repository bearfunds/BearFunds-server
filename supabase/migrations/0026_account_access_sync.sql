drop function if exists public.grant_account_access(text, text);
drop function if exists public.revoke_account_access(text, text);

drop policy if exists account_access_admin_read on public.account_access;
drop policy if exists account_access_admin_write on public.account_access;

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
    union all select max(updated_at)  from public.entities             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.members              where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.staged_transactions  where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.budgets               where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.import_mappings       where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.family_settings        where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.account_access         where family_id = public.auth_family_id()
  ) s;
$$;

grant execute on function public.family_version() to authenticated;
