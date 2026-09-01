alter table public.members
  add column if not exists scope_version integer not null default 0;

create or replace function public.bump_account_access_scope()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, auth
as $$
begin
  if tg_op = 'INSERT'
     or new.account_id is distinct from old.account_id
     or new.member_id is distinct from old.member_id
     or new.deleted is distinct from old.deleted then
    update public.members
       set scope_version = scope_version + 1
     where family_id = new.family_id
       and id = new.member_id;

    if tg_op = 'UPDATE' and old.member_id is distinct from new.member_id then
      update public.members
         set scope_version = scope_version + 1
       where family_id = old.family_id
         and id = old.member_id;
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.bump_account_access_scope() from public;

create trigger account_access_bump_scope
  after insert or update on public.account_access
  for each row execute function public.bump_account_access_scope();
