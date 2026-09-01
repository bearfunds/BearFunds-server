do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'transactions' and column_name = 'wallet_id'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'transactions' and column_name = 'account_id'
  ) then
    alter table public.transactions rename column wallet_id to account_id;
  end if;

  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'staged_transactions' and column_name = 'wallet_id'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'staged_transactions' and column_name = 'account_id'
  ) then
    alter table public.staged_transactions rename column wallet_id to account_id;
  end if;
end $$;

create table if not exists public.account_access (
  id                   text not null,
  family_id            uuid not null references public.families(id) on delete cascade,
  account_id           text not null,
  member_id            text not null,
  granted_by_member_id  text,
  granted_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted              boolean not null default false,
  is_immutable         boolean not null default false,
  primary key (family_id, id),
  constraint account_access_id_pair_check check (id = account_id || '__' || member_id)
);

create unique index if not exists account_access_family_pair_idx
  on public.account_access (family_id, account_id, member_id);
create index if not exists account_access_family_updated_idx
  on public.account_access (family_id, updated_at);

drop trigger if exists account_access_set_updated_at on public.account_access;
create trigger account_access_set_updated_at before insert or update on public.account_access
  for each row execute function public.set_updated_at();
drop trigger if exists account_access_set_family_id on public.account_access;
create trigger account_access_set_family_id before insert or update on public.account_access
  for each row execute function public.set_family_id();

create or replace function public.set_account_access_identity()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, auth
as $$
begin
  if tg_op = 'INSERT' then
    new.granted_by_member_id := public.auth_member_id();
    new.granted_at := coalesce(new.granted_at, now());
  else
    new.granted_by_member_id := old.granted_by_member_id;
    new.granted_at := old.granted_at;
  end if;
  return new;
end;
$$;

drop trigger if exists account_access_set_identity on public.account_access;
create trigger account_access_set_identity before insert or update on public.account_access
  for each row execute function public.set_account_access_identity();

grant select, insert, update, delete on public.account_access to authenticated;
alter table public.account_access enable row level security;

create or replace function public.is_family_admin(p_family_id uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public, auth
as $$
  select exists (
    select 1
    from public.members m
    where m.family_id = p_family_id
      and m.user_id = auth.uid()
      and m.role = 'admin'
      and m.deleted = false
  )
$$;

create or replace function public.account_is_visible(p_family_id uuid, p_account_id text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public, auth
as $$
  select p_family_id = public.auth_family_id()
    and (
      public.is_test_request()
      or public.is_family_admin(p_family_id)
      or exists (
        select 1
        from public.account_access aa
        where aa.family_id = p_family_id
          and aa.account_id = p_account_id
          and aa.member_id = public.auth_member_id()
          and aa.deleted = false
      )
    )
$$;

revoke all on function public.is_family_admin(uuid) from public;
revoke all on function public.account_is_visible(uuid, text) from public;
grant execute on function public.is_family_admin(uuid) to authenticated;
grant execute on function public.account_is_visible(uuid, text) to authenticated;

drop policy if exists accounts_family_isolation on public.accounts;
drop policy if exists wallets_family_isolation on public.accounts;
drop policy if exists accounts_family_isolation on public.transactions;
drop policy if exists wallets_family_isolation on public.transactions;
drop policy if exists accounts_family_isolation on public.staged_transactions;
drop policy if exists wallets_family_isolation on public.staged_transactions;
drop policy if exists accounts_visibility on public.accounts;
drop policy if exists transactions_visibility on public.transactions;
drop policy if exists staged_transactions_visibility on public.staged_transactions;
drop policy if exists account_access_admin_scoped on public.account_access;
create policy accounts_visibility on public.accounts
  for all to authenticated
  using (
    family_id = public.auth_family_id()
    and (
      public.account_is_visible(family_id, id)
      or created_by = public.auth_member_id()
    )
  )
  with check (
    family_id = public.auth_family_id()
    and (
      public.is_test_request()
      or public.is_family_admin(family_id)
      or created_by = public.auth_member_id()
      or public.account_is_visible(family_id, id)
    )
  );

drop policy if exists transactions_family_isolation on public.transactions;
create policy transactions_visibility on public.transactions
  for all to authenticated
  using (
    family_id = public.auth_family_id()
    and (
      public.account_is_visible(family_id, account_id)
      or created_by = public.auth_member_id()
    )
  )
  with check (
    family_id = public.auth_family_id()
    and (
      public.is_test_request()
      or public.is_family_admin(family_id)
      or created_by = public.auth_member_id()
      or public.account_is_visible(family_id, account_id)
    )
  );

drop policy if exists staged_transactions_family_isolation on public.staged_transactions;
create policy staged_transactions_visibility on public.staged_transactions
  for all to authenticated
  using (
    family_id = public.auth_family_id()
    and (
      created_by = public.auth_member_id()
      or public.account_is_visible(family_id, account_id)
    )
  )
  with check (
    family_id = public.auth_family_id()
    and (
      public.is_test_request()
      or public.is_family_admin(family_id)
      or created_by = public.auth_member_id()
      or public.account_is_visible(family_id, account_id)
    )
  );

create policy account_access_admin_scoped on public.account_access
  for all to authenticated
  using (
    family_id = public.auth_family_id()
    and public.is_family_admin(family_id)
  )
  with check (
    family_id = public.auth_family_id()
    and public.is_family_admin(family_id)
  );
