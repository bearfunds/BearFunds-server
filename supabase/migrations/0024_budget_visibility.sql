alter table public.budgets add column if not exists line_id text;
alter table public.budgets add column if not exists account_ids text[] not null default '{}';
alter table public.budgets add column if not exists ignored_category_ids text[] not null default '{}';
alter table public.budgets add column if not exists category_ids text[] not null default '{}';

drop policy if exists budgets_family_isolation on public.budgets;
create policy budgets_visibility on public.budgets
  for all to authenticated
  using (
    family_id = public.auth_family_id()
    and (
      public.is_test_request()
      or public.is_family_admin(family_id)
      or not exists (
        select 1
        from unnest(coalesce(account_ids, '{}'::text[])) as requested_account(account_id)
        where not public.account_is_visible(family_id, requested_account.account_id)
      )
    )
  )
  with check (
    family_id = public.auth_family_id()
    and (
      public.is_test_request()
      or public.is_family_admin(family_id)
      or not exists (
        select 1
        from unnest(coalesce(account_ids, '{}'::text[])) as requested_account(account_id)
        where not public.account_is_visible(family_id, requested_account.account_id)
      )
    )
  );
