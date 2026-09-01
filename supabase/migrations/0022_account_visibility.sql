alter table public.accounts add column if not exists created_by text;
alter table public.transactions add column if not exists created_by text;
alter table public.staged_transactions add column if not exists created_by text;

create or replace function public.auth_member_id()
  returns text
  language sql
  stable
  security definer
  set search_path = public, auth
as $$
  select m.id
  from public.members m
  where m.user_id = auth.uid()
    and m.family_id = public.auth_family_id()
    and m.deleted = false
  limit 1
$$;

grant execute on function public.auth_member_id() to authenticated;

create or replace function public.set_created_by()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, auth
as $$
begin
  if tg_op = 'INSERT' then
    new.created_by := public.auth_member_id();
  else
    new.created_by := old.created_by;
  end if;
  return new;
end;
$$;

create trigger accounts_set_created_by before insert or update on public.accounts
  for each row execute function public.set_created_by();
create trigger transactions_set_created_by before insert or update on public.transactions
  for each row execute function public.set_created_by();
create trigger staged_transactions_set_created_by before insert or update on public.staged_transactions
  for each row execute function public.set_created_by();
