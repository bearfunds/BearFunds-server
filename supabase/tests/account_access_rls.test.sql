\set ON_ERROR_STOP on
begin;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'access-alice@fam.test', '{"full_name":"Access Alice"}'),
  ('00000000-0000-0000-0000-00000000000b', 'access-bob@fam.test', '{"full_name":"Access Bob"}');

do $$ begin
  assert (select count(*) from public.members where user_id in
    ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b')) = 2,
    'the access suite users must have bootstrap memberships';
end $$;

create temporary table access_ids as
  select
    (select family_id from public.members where user_id = '00000000-0000-0000-0000-00000000000a') as family_id,
    (select id from public.members where user_id = '00000000-0000-0000-0000-00000000000a') as admin_id,
    (select id from public.members where user_id = '00000000-0000-0000-0000-00000000000b') as old_member_id;
grant select on access_ids to authenticated;

delete from public.members where user_id = '00000000-0000-0000-0000-00000000000b';
insert into public.members (id, family_id, user_id, name, role)
select 'm_access_b', family_id, '00000000-0000-0000-0000-00000000000b', 'Access Bob', 'member'
from access_ids;

set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.accounts (id, currency, enc, created_by)
  values ('a_access_1', 'EUR', 'v1.account.alice', 'forged');
insert into public.transactions (id, date, currency, type, category_id, entity_id, account_id, member_id, enc, created_by)
  values ('t_access_1', '2026-08-01', 'EUR', 'expense', 'c1', 'e1', 'a_access_1', 'm_access_b', 'v1.transaction.alice', 'forged');
insert into public.staged_transactions (id, batch_id, account_id, enc, created_by)
  values ('st_access_1', 'batch_access', null, 'v1.staged.alice', 'forged');
insert into public.budgets (id, period_type, kind, account_ids, enc)
  values ('b_access_1', 'monthly', 'instance', array['a_access_1'], 'v1.budget.alice');

do $$ begin
  assert (select created_by from public.accounts where id = 'a_access_1') = (select admin_id from access_ids),
    'account created_by must be the authenticated member';
  assert (select created_by from public.transactions where id = 't_access_1') = (select admin_id from access_ids),
    'transaction created_by must be the authenticated member';
  assert (select created_by from public.staged_transactions where id = 'st_access_1') = (select admin_id from access_ids),
    'staged transaction created_by must be the authenticated member';
  assert (select scope_version from public.members where id = 'm_access_b') = 0,
    'new members must start with scope_version zero';
end $$;

insert into public.account_access (id, account_id, member_id, family_id)
select 'a_access_1__m_access_b', 'a_access_1', 'm_access_b', '00000000-0000-0000-0000-0000000000ff';

do $$ begin
  assert (select family_id from public.account_access where id = 'a_access_1__m_access_b') = (select family_id from access_ids),
    'account access must be scoped to the admin family';
  assert (select granted_by_member_id from public.account_access where id = 'a_access_1__m_access_b') = (select admin_id from access_ids),
    'granted_by_member_id must be server-derived';
  assert (select granted_at from public.account_access where id = 'a_access_1__m_access_b') is not null,
    'granted_at must be server-defaulted';
  assert (select scope_version from public.members where id = 'm_access_b') = 1,
    'a new grant must bump the target member scope_version';
end $$;

set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $$ begin
  assert (select count(*) from public.account_access) = 0,
    'a non-admin must read an empty account access ledger';
  assert (select count(*) from public.accounts where id = 'a_access_1') = 1,
    'a member must read an explicitly shared account';
  assert (select count(*) from public.transactions where id = 't_access_1') = 1,
    'a member must read transactions on an explicitly shared account';
  assert (select count(*) from public.budgets where id = 'b_access_1') = 1,
    'a member must read budgets whose accounts are all shared';
end $$;

do $$ begin
  begin
    insert into public.account_access (id, account_id, member_id)
      values ('a_access_2__m_access_b', 'a_access_2', 'm_access_b');
    raise exception 'EXPECTED non-admin account access insert to fail';
  exception when others then
    if sqlerrm like 'EXPECTED %' then raise; end if;
  end;
end $$;

reset role;
reset request.jwt.claims;
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $$ begin
  begin
    insert into public.account_access (id, account_id, member_id)
      values ('wrong-id', 'a_access_1', 'm_access_b');
    raise exception 'EXPECTED derived account access id constraint to fail';
  exception when others then
    if sqlerrm like 'EXPECTED %' then raise; end if;
  end;
end $$;

update public.account_access
   set deleted = true
 where id = 'a_access_1__m_access_b';

do $$ begin
  assert (select scope_version from public.members where id = 'm_access_b') = 2,
    'a revoke must bump the target member scope_version';
  assert exists (select 1 from public.account_access where id = 'a_access_1__m_access_b' and deleted = true),
    'a revoke must retain the account access row as a tombstone';
end $$;

reset role;
reset request.jwt.claims;
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $$ begin
  assert (select count(*) from public.accounts where id = 'a_access_1') = 0,
    'a revoked account must disappear from the member read path';
  assert (select count(*) from public.transactions where id = 't_access_1') = 0,
    'transactions on a revoked account must disappear from the member read path';
  assert (select count(*) from public.budgets where id = 'b_access_1') = 0,
    'budgets containing a revoked account must disappear from the member read path';
end $$;
reset role;
reset request.jwt.claims;

rollback;
select 'account_access RLS suite passed' as result;
