-- RLS isolation suite — proves per-family tenancy (brain QA Area 008 Identity / 019 Isolation).
-- Run order: auth_shim.sql -> migrations 0001-0005 -> THIS. Wrapped in a rolled-back tx.
-- Asserts via DO/ASSERT; psql with ON_ERROR_STOP exits nonzero on the first failure.
\set ON_ERROR_STOP on
begin;

-- Two Google sign-ins (fixed ids so we can forge claims). Each fires handle_new_user.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@fam.test', '{"full_name":"Alice"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@fam.test',   '{"full_name":"Bob"}');

-- Bootstrap: each user got a family + one admin member.
-- Bootstrap asserts are scoped to the suite's two fixed uids (not whole-table
-- counts) so the suite is order-independent: a prior sign-up on the local stack
-- (e.g. a dev-shim user from a ghost run) no longer trips it (brain Hygiene 2026-06-05).
do $$ begin
  assert (select count(*) from public.members where user_id in
            ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b')) = 2,
         'expected the 2 suite linking members';
  assert (select count(*) from public.members where role = 'admin' and user_id in
            ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b')) = 2,
         'expected 2 admin linking members for the suite uids';
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000a') = 'admin', 'Alice should be admin';
end $$;

-- Capture family ids for assertions; expose to the authenticated role.
create temporary table fam as
  select 'A'::text as who, family_id from public.members where user_id = '00000000-0000-0000-0000-00000000000a'
  union all
  select 'B'::text,        family_id from public.members where user_id = '00000000-0000-0000-0000-00000000000b';
grant select on fam to authenticated;

-- ============ Act as Alice ============
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';

do $$ begin
  assert (select count(*) from public.families) = 1, 'Alice must see only her own family';
end $$;

-- Create an account with family_id omitted -> server-derived to Alice.
insert into public.accounts (id, currency, enc) values ('w_a1', 'EUR', 'v1.iv_a1.ct_alice_eur');
do $$ begin
  assert (select family_id from public.accounts where id = 'w_a1') = (select family_id from fam where who = 'A'),
         'new account must be scoped to Alice family';
  assert (select count(*) from public.accounts) = 1, 'Alice sees exactly her account';
end $$;

reset role; reset request.jwt.claims;

-- ============ Act as Bob ============
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';

-- READ isolation: Bob cannot see Alice's account.
do $$ begin
  assert (select count(*) from public.accounts) = 0, 'Bob must not see Alice account (read isolation)';
end $$;

-- WRITE isolation: Bob's update of Alice's row hits nothing (row invisible).
update public.accounts set enc = 'HACKED' where id = 'w_a1';
do $$ begin
  assert not exists (select 1 from public.accounts where id = 'w_a1'), 'Alice account stays invisible to Bob';
end $$;

-- FORGERY: Bob inserts with Alice family_id in the body -> trigger forces it to Bob.
insert into public.accounts (id, currency, family_id)
  values ('w_b_forge', 'USD', (select family_id from fam where who = 'A'));
do $$ begin
  assert (select family_id from public.accounts where id = 'w_b_forge') = (select family_id from fam where who = 'B'),
         'forged family_id must be overwritten to Bob family';
end $$;

reset role; reset request.jwt.claims;

-- ============ Superuser: confirm Alice survived Bob entirely ============
do $$ begin
  assert (select enc from public.accounts where id = 'w_a1') = 'v1.iv_a1.ct_alice_eur', 'Alice account must be unchanged';
  assert (select count(*) from public.accounts where family_id = (select family_id from fam where who = 'A')) = 1,
         'Alice family still has exactly one account';
  assert (select count(*) from public.accounts where family_id = (select family_id from fam where who = 'B')) = 1,
         'Bob family has only the forged-then-corrected account';
end $$;

-- ============ updated_at is server-managed ============
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.accounts (id, currency, updated_at) values ('w_a2', 'EUR', '2000-01-01T00:00:00Z');
do $$ begin
  assert (select updated_at from public.accounts where id = 'w_a2') > now() - interval '1 minute',
         'updated_at must be overwritten to server now()';
end $$;

-- ============ family_id is immutable on update ============
update public.accounts set family_id = (select family_id from fam where who = 'B') where id = 'w_a2';
do $$ begin
  assert (select family_id from public.accounts where id = 'w_a2') = (select family_id from fam where who = 'A'),
         'family_id must not move families on update';
end $$;
reset role; reset request.jwt.claims;

-- ============ subcategories: per-family isolation (v1.9 new tenant table) ============
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
-- Alice creates a subcategory with family_id omitted -> server-derived to Alice.
insert into public.subcategories (id, category_id, name) values ('sc_a1', 'c1', 'Groceries');
do $$ begin
  assert (select family_id from public.subcategories where id = 'sc_a1') = (select family_id from fam where who = 'A'),
         'new subcategory must be scoped to Alice family';
  assert (select count(*) from public.subcategories) = 1, 'Alice sees exactly her subcategory';
end $$;
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $$ begin
  assert (select count(*) from public.subcategories) = 0, 'Bob must not see Alice subcategory (read isolation)';
end $$;
update public.subcategories set name = 'HACKED' where id = 'sc_a1';
do $$ begin
  assert not exists (select 1 from public.subcategories where id = 'sc_a1'), 'Alice subcategory stays invisible to Bob';
end $$;
insert into public.subcategories (id, category_id, name, family_id)
  values ('sc_b_forge', 'c1', 'forged', (select family_id from fam where who = 'A'));
do $$ begin
  assert (select family_id from public.subcategories where id = 'sc_b_forge') = (select family_id from fam where who = 'B'),
         'forged family_id must be overwritten to Bob family';
end $$;
reset role; reset request.jwt.claims;

do $$ begin
  assert (select name from public.subcategories where id = 'sc_a1') = 'Groceries', 'Alice subcategory must be unchanged by Bob';
end $$;

-- ============ staged_transactions: per-family isolation + opaque enc envelope (v1.14) ============
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
-- Alice stages a partially-mapped import row: family_id omitted -> server-derived; the
-- sensitive payload (raw amount text, source name/row) rides the opaque enc envelope
-- (v1.14 RLE); FKs left null. Proves a not-yet-valid row can persist while staged.
insert into public.staged_transactions (id, batch_id, enc)
  values ('st_a1', 'batch_a', 'v1.iv_st_a1.ct_acme_row');
do $$ begin
  assert (select family_id from public.staged_transactions where id = 'st_a1') = (select family_id from fam where who = 'A'),
         'new staged row must be scoped to Alice family';
  assert (select count(*) from public.staged_transactions) = 1, 'Alice sees exactly her staged row';
  assert (select enc from public.staged_transactions where id = 'st_a1') = 'v1.iv_st_a1.ct_acme_row',
         'opaque enc envelope must persist verbatim (server never touches it)';
  assert (select category_id from public.staged_transactions where id = 'st_a1') is null,
         'an unmapped FK may stay null while staged';
end $$;
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $$ begin
  assert (select count(*) from public.staged_transactions) = 0, 'Bob must not see Alice staged row (read isolation)';
end $$;
update public.staged_transactions set enc = 'HACKED' where id = 'st_a1';
do $$ begin
  assert not exists (select 1 from public.staged_transactions where id = 'st_a1'), 'Alice staged row stays invisible to Bob';
end $$;
insert into public.staged_transactions (id, batch_id, enc, family_id)
  values ('st_b_forge', 'batch_b', 'v1.iv_forge.ct_9', (select family_id from fam where who = 'A'));
do $$ begin
  assert (select family_id from public.staged_transactions where id = 'st_b_forge') = (select family_id from fam where who = 'B'),
         'forged family_id must be overwritten to Bob family';
end $$;
reset role; reset request.jwt.claims;

do $$ begin
  assert (select enc from public.staged_transactions where id = 'st_a1') = 'v1.iv_st_a1.ct_acme_row', 'Alice staged row must be unchanged by Bob';
end $$;

-- ============ invites + join_family: control-plane RPCs (S9a / [Q8]) ============
-- Two more sign-ins: Carol (joins via invite) and Dave (exercises the teardown guard).
-- Each fires handle_new_user -> their own throwaway family + admin member.
reset role; reset request.jwt.claims;
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000c', 'carol@fam.test', '{"full_name":"Carol"}'),
  ('00000000-0000-0000-0000-00000000000d', 'dave@fam.test',  '{"full_name":"Dave"}');

-- Snapshot Carol's + Dave's original throwaway family ids (superuser temp tables).
create temporary table cfam as
  select family_id from public.members where user_id = '00000000-0000-0000-0000-00000000000c';
create temporary table dfam as
  select family_id from public.members where user_id = '00000000-0000-0000-0000-00000000000d';

-- Make Dave's family NON-solo: a second (placeholder) member. The teardown guard must
-- therefore NOT delete Dave's family when he joins elsewhere.
insert into public.members (id, family_id, user_id, name, role)
  values ('m_extra_d', (select family_id from dfam), null, 'Extra D', 'member');

-- Token relay table (create_invite returns the token; stash it across role switches).
create temporary table inv (slot text primary key, token text);
grant select, insert on inv to authenticated;

-- ---- Alice (admin of A) mints invites ----
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into inv values ('i1',   public.create_invite('member'));
insert into inv values ('i2',   public.create_invite('member'));
insert into inv values ('i3',   public.create_invite('member'));
insert into inv values ('iexp', public.create_invite('member'));
-- Alice sees only her own family's invites (RLS select scope).
do $t$ begin
  assert (select count(*) from public.invites) = 4, 'Alice sees her 4 invites';
end $t$;
reset role; reset request.jwt.claims;

-- Expire one invite (superuser) to test the expiry rejection.
update public.invites set expires_at = now() - interval '1 day'
  where token = (select token from inv where slot = 'iexp');

-- ---- RLS isolation: Bob (family B) cannot see family A's invites ----
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert (select count(*) from public.invites) = 0, 'Bob must not see family A invites (read isolation)';
end $t$;
-- Invalid token is rejected.
do $t$ begin
  begin
    perform public.join_family('not-a-real-token-0000000000000000');
    raise exception 'EXPECTED join_family to reject an invalid token';
  exception when others then
    if sqlerrm like 'EXPECTED %' then raise; end if;
  end;
end $t$;
-- Expired (still-pending) token is rejected.
do $t$ begin
  begin
    perform public.join_family((select token from inv where slot = 'iexp'));
    raise exception 'EXPECTED join_family to reject an expired invite';
  exception when others then
    if sqlerrm like 'EXPECTED %' then raise; end if;
  end;
end $t$;
reset role; reset request.jwt.claims;

-- ---- Carol joins family A via i1 (happy path: re-home + fresh member) ----
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
select public.join_family((select token from inv where slot = 'i1'), 'Carol Joiner', 'http://avatars.test/c.png');
do $t$ begin
  assert public.auth_family_id() = (select family_id from fam where who = 'A'),
         'Carol auth_family_id() now resolves to family A';
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000c') = 'member',
         'Carol joined as role member (not admin)';
  assert (select name from public.members where user_id = '00000000-0000-0000-0000-00000000000c') = 'Carol Joiner',
         'Carol member carries the Join-Form name';
end $t$;
reset role; reset request.jwt.claims;
-- Superuser: Carol's throwaway family is gone; A now has exactly Alice + Carol.
do $t$ begin
  assert not exists (select 1 from public.families where id = (select family_id from cfam)),
         'Carol throwaway family was torn down (sole-member)';
  assert (select count(*) from public.members where family_id = (select family_id from fam where who = 'A')) = 2,
         'family A now has Alice + Carol';
end $t$;

-- ---- Idempotent re-join: Carol redeems i2 while already in A -> no-op, no dup member ----
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
select public.join_family((select token from inv where slot = 'i2'), 'Carol Again', null);
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select count(*) from public.members where family_id = (select family_id from fam where who = 'A')) = 2,
         'idempotent re-join created no duplicate member';
  assert (select status from public.invites where token = (select token from inv where slot = 'i2')) = 'redeemed',
         'i2 marked redeemed on idempotent join';
end $t$;

-- ---- Admin-gate: Carol (now a plain member of A) cannot mint invites ----
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
do $t$ begin
  begin
    perform public.create_invite('member');
    raise exception 'EXPECTED create_invite to reject a non-admin member';
  exception when others then
    if sqlerrm like 'EXPECTED %' then raise; end if;
  end;
end $t$;
reset role; reset request.jwt.claims;

-- ---- Teardown guard: Dave (family D has 2 members) joins A; D must survive ----
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000d"}';
select public.join_family((select token from inv where slot = 'i3'), 'Dave Joiner', null);
do $t$ begin
  assert public.auth_family_id() = (select family_id from fam where who = 'A'), 'Dave now in family A';
end $t$;
reset role; reset request.jwt.claims;
do $t$ begin
  assert exists (select 1 from public.families where id = (select family_id from dfam)),
         'Dave family D was NOT deleted (non-solo; teardown guard held)';
  assert (select count(*) from public.members where family_id = (select family_id from dfam)) = 1,
         'family D keeps its other member; only Dave row was removed';
  assert (select count(*) from public.members where family_id = (select family_id from fam where who = 'A')) = 3,
         'family A now has Alice + Carol + Dave';
end $t$;

-- ---- Final invite-state + invariant checks ----
do $t$ begin
  assert (select status from public.invites where token = (select token from inv where slot = 'i1')) = 'redeemed', 'i1 redeemed';
  assert (select status from public.invites where token = (select token from inv where slot = 'i3')) = 'redeemed', 'i3 redeemed';
  assert (select status from public.invites where token = (select token from inv where slot = 'iexp')) = 'pending',
         'expired invite was never redeemed (stays pending)';
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000a') = 'admin',
         'Alice remains admin of family A';
end $t$;

-- ============ peek_invite: token-gated family-name disclosure (S9b-2) ============
-- A fresh pending invite minted by Alice (admin of A) must be peekable by Bob, who is
-- NOT a member of A - proving a not-yet-member joiner can read the family name.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into inv values ('ipeek', public.create_invite('member'));
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$
declare v_name text; v_role text;
begin
  select family_name, invite_role into v_name, v_role
    from public.peek_invite((select token from inv where slot = 'ipeek'));
  assert v_name = 'Alice''s Family', 'peek returns the inviting family name; got ' || coalesce(v_name, '<null>');
  assert v_role = 'member', 'peek returns the invite role';
end $t$;
-- Expired invite -> no rows.
do $t$
declare n int;
begin
  select count(*) into n from public.peek_invite((select token from inv where slot = 'iexp'));
  assert n = 0, 'peek returns nothing for an expired invite';
end $t$;
-- Unknown token -> no rows.
do $t$
declare n int;
begin
  select count(*) into n from public.peek_invite('no-such-token-0000000000000000');
  assert n = 0, 'peek returns nothing for an unknown token';
end $t$;
reset role; reset request.jwt.claims;

-- ============ composite (family_id, id) PK: families share fixed seed ids ([Q20]) ============
-- Alice and Bob (different families) each "seed" the SAME fixed category id. Under the old
-- global PK the 2nd insert collided with the 1st family's row (RLS-denied 500); under
-- (family_id, id) it does not. Uses the EXACT upsert shape PostgREST emits: ON CONFLICT
-- (family_id, id) with family_id ABSENT from the insert column list (set by the trigger).
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.categories (id, name) values ('c001', 'Alice Food')
  on conflict (family_id, id) do update set name = excluded.name;
do $t$ begin
  assert (select name from public.categories where id = 'c001') = 'Alice Food', 'Alice c001 seeded';
end $t$;
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
-- Must NOT collide with Alice's (A, c001) - lands as Bob's own (B, c001).
insert into public.categories (id, name) values ('c001', 'Bob Food')
  on conflict (family_id, id) do update set name = excluded.name;
do $t$ begin
  assert (select name from public.categories where id = 'c001') = 'Bob Food', 'Bob c001 is his own row';
  assert (select count(*) from public.categories where id = 'c001') = 1, 'Bob sees only his c001 (RLS)';
end $t$;
reset role; reset request.jwt.claims;

do $t$ begin
  assert (select count(*) from public.categories where id = 'c001') = 2, 'both families hold a c001 row';
  assert (select name from public.categories where id='c001' and family_id=(select family_id from fam where who='A')) = 'Alice Food', 'Alice c001 unchanged by Bob';
  assert (select name from public.categories where id='c001' and family_id=(select family_id from fam where who='B')) = 'Bob Food', 'Bob c001 distinct from Alice';
end $t$;

-- ============ budgets: per-family isolation + opaque enc envelope (v1.17) ============
-- RESHAPED BY 0017 (the Budgets/Areas remodel). Every row is now an INSTANCE, and the plaintext
-- surface is down to kind + period_type: the period bounds, the recurring line id and the WHOLE
-- plan (target, accounts, Areas, category membership) ride the enc envelope. The isolation
-- properties below are re-asserted against the new shape - a tenant table that changes shape gets
-- its own RLS test (server convention; risk map S3).
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
-- Alice creates a monthly Budget. family_id omitted -> server-derived.
-- account_ids is REQUIRED since 0023 (the check that makes an account-less Budget an
-- impossible state rather than an unenforced one). Every insert below carries it.
insert into public.budgets (id, period_type, kind, enc, account_ids)
  values ('b_a1', 'monthly', 'instance', 'v1.aXY=.Zm9v', array['w_a1']);
do $t$ begin
  assert (select family_id from public.budgets where id = 'b_a1') = (select family_id from fam where who = 'A'),
         'new budget must be scoped to Alice family';
  assert (select count(*) from public.budgets) = 1, 'Alice sees exactly her budget';
  assert (select updated_at from public.budgets where id = 'b_a1') is not null,
         'budgets_set_updated_at trigger must stamp updated_at (without it, delta sync silently drops every budget edit)';
end $t$;
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert (select count(*) from public.budgets) = 0, 'Bob must not see Alice budget (read isolation)';
end $t$;
update public.budgets set enc = 'v1.HACKED.HACKED' where id = 'b_a1';
do $t$ begin
  assert not exists (select 1 from public.budgets where id = 'b_a1'), 'Alice budget stays invisible to Bob';
end $t$;
-- A forged family_id must be overwritten to the CALLER's family, not honoured.
insert into public.budgets (id, period_type, kind, enc, account_ids, family_id)
  values ('b_b_forge', 'monthly', 'instance', 'v1.aXY=.Zm9v', array['w_b1'], (select family_id from fam where who = 'A'));
do $t$ begin
  assert (select family_id from public.budgets where id = 'b_b_forge') = (select family_id from fam where who = 'B'),
         'forged family_id must be overwritten to Bob family';
end $t$;
reset role; reset request.jwt.claims;

do $t$ begin
  assert (select enc from public.budgets where id = 'b_a1') = 'v1.aXY=.Zm9v', 'Alice budget must be unchanged by Bob';
end $t$;

-- Composite PK (family_id, id): both families may hold the SAME budget id. Budget ids are random
-- at v1.17, so a collision is now vanishingly unlikely rather than routine - but B5 will seed
-- Budgets with fixed ids, and a global id PK would collide -> RLS-denied upsert -> 500 (the 0009
-- bug). The property is cheap to keep and expensive to rediscover.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.budgets (id, period_type, kind, enc, account_ids)
  values ('b001', 'monthly', 'instance', 'v1.alice.enc', array['w_a1']);
reset role; reset request.jwt.claims;
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
insert into public.budgets (id, period_type, kind, enc, account_ids)
  values ('b001', 'monthly', 'instance', 'v1.bob.enc', array['w_b1']);
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select count(*) from public.budgets where id = 'b001') = 2, 'both families hold a b001 row';
  assert (select enc from public.budgets where id='b001' and family_id=(select family_id from fam where who='A')) = 'v1.alice.enc', 'Alice b001 unchanged by Bob';
end $t$;

-- v1.17: the behavioural-metadata columns are GONE from the wire AND from the table.
-- This is the S1 mitigation, and it is only real if the columns actually do not exist: a
-- server that still HAS `period_start` can still be made to store it. CONTROL first, so the
-- assertion below can fail - `enc` is a column that certainly exists.
do $t$ begin
  assert exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'budgets' and column_name = 'enc'
  ), 'CONTROL: budgets.enc exists (so the absence checks below can actually fail)';

  assert not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'budgets'
      and column_name in ('currency', 'template_id', 'stopped_at', 'period_start', 'period_end')
  ), 'v1.17: currency / template_id / stopped_at / period_start / period_end must be DROPPED - a one-off Budget period range in plaintext publishes a family holiday dates to the server';
end $t$;

-- ============ import_mappings: per-family isolation + opaque enc envelope (v1.22) ============
-- Entirely opaque: no plaintext columns beyond id/updated_at/deleted/is_immutable - header,
-- header_norm and verdict all ride enc. Same isolation shape as budgets, minus the plaintext
-- column checks (there is no plaintext to check).
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
-- Alice creates an import mapping. family_id omitted -> server-derived.
insert into public.import_mappings (id, enc)
  values ('im_a1', 'v1.aXY=.Zm9v');
do $t$ begin
  assert (select family_id from public.import_mappings where id = 'im_a1') = (select family_id from fam where who = 'A'),
         'new import mapping must be scoped to Alice family';
  assert (select count(*) from public.import_mappings) = 1, 'Alice sees exactly her import mapping';
  assert (select updated_at from public.import_mappings where id = 'im_a1') is not null,
         'import_mappings_set_updated_at trigger must stamp updated_at (without it, delta sync silently drops every mapping edit)';
end $t$;
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert (select count(*) from public.import_mappings) = 0, 'Bob must not see Alice import mapping (read isolation)';
end $t$;
update public.import_mappings set enc = 'v1.HACKED.HACKED' where id = 'im_a1';
do $t$ begin
  assert not exists (select 1 from public.import_mappings where id = 'im_a1'), 'Alice import mapping stays invisible to Bob';
end $t$;
-- A forged family_id must be overwritten to the CALLER's family, not honoured.
insert into public.import_mappings (id, enc, family_id)
  values ('im_b_forge', 'v1.aXY=.Zm9v', (select family_id from fam where who = 'A'));
do $t$ begin
  assert (select family_id from public.import_mappings where id = 'im_b_forge') = (select family_id from fam where who = 'B'),
         'forged family_id must be overwritten to Bob family';
end $t$;
reset role; reset request.jwt.claims;

do $t$ begin
  assert (select enc from public.import_mappings where id = 'im_a1') = 'v1.aXY=.Zm9v', 'Alice import mapping must be unchanged by Bob';
end $t$;

-- Composite PK (family_id, id): both families may hold the SAME mapping id.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.import_mappings (id, enc)
  values ('im001', 'v1.alice.enc');
reset role; reset request.jwt.claims;
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
insert into public.import_mappings (id, enc)
  values ('im001', 'v1.bob.enc');
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select count(*) from public.import_mappings where id = 'im001') = 2, 'both families hold an im001 row';
  assert (select enc from public.import_mappings where id='im001' and family_id=(select family_id from fam where who='A')) = 'v1.alice.enc', 'Alice im001 unchanged by Bob';
end $t$;

-- ============ family_version(): family-scoped sync high-water mark (v1.13) ============
-- The `version` action returns max(updated_at) across the caller's tenant tables. The suite
-- runs in ONE transaction, so now() (and every trigger-set updated_at) is frozen -- which
-- would make Alice's and Bob's versions identical. To prove ISOLATION, forge a single
-- far-future updated_at on Alice's account with the updated_at trigger disabled
-- (session_replication_role=replica, superuser), then assert only Alice's version reflects it.
set session_replication_role = replica;
update public.accounts set updated_at = '2099-01-01T00:00:00Z' where id = 'w_a1';
set session_replication_role = origin;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$ begin
  assert public.family_version() is not null, 'Alice version is non-null (she has rows)';
  assert public.family_version() = '2099-01-01T00:00:00Z'::timestamptz,
         'Alice version reflects her newest (forged-future) row';
end $t$;
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert public.family_version() is not null, 'Bob version is non-null (he has rows)';
  assert public.family_version() < '2099-01-01T00:00:00Z'::timestamptz,
         'Bob version does NOT see Alice future row (per-family isolation)';
end $t$;
reset role; reset request.jwt.claims;

-- budgets must be REGISTERED in family_version() (v1.16). The silent break this pins:
-- family_version() is a hardcoded union per tenant table, so omitting budgets returns a
-- stale high-water mark and a device whose ONLY change is a budget edit is told "nothing
-- changed" and never syncs -- with no error anywhere.
-- CONTROL first: before the forge, Bob's version sits BELOW the probe timestamp - so the
-- assert after it can actually fail (a check that cannot fail is not a check).
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert public.family_version() < '2098-01-01T00:00:00Z'::timestamptz,
         'CONTROL: Bob version is below the budgets probe timestamp before the forge';
end $t$;
reset role; reset request.jwt.claims;

-- Forge a far-future updated_at on Bob's budget with the trigger disabled (the suite runs in
-- one transaction, so now() is frozen and every updated_at would otherwise be identical).
set session_replication_role = replica;
update public.budgets set updated_at = '2098-01-01T00:00:00Z' where id = 'b_b_forge';
set session_replication_role = origin;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert public.family_version() = '2098-01-01T00:00:00Z'::timestamptz,
         'a budgets row MUST move family_version() (budgets registered in the union)';
end $t$;
reset role; reset request.jwt.claims;

-- ============ import_mappings: tenancy + registration (v1.22) ============
-- The family's memory of which source column header maps to which import field. Everything
-- meaningful rides `enc`; this table has no plaintext columns beyond the scaffolding, so the
-- asserts below are about ISOLATION and REGISTRATION rather than about any payload.

-- Alice writes one with family_id omitted -> it must be server-derived to her family.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.import_mappings (id, enc) values ('im_a2', 'v1.iv_im_a2.ct_alice_date');
do $t$ begin
  assert (select family_id from public.import_mappings where id = 'im_a2') = (select family_id from fam where who = 'A'),
         'a new import mapping must be scoped to the Alice family by the trigger, not by the client';
  assert (select count(*) from public.import_mappings where id = 'im_a2') = 1, 'Alice sees her new mapping';
end $t$;
reset role; reset request.jwt.claims;

-- Bob must not see it, must not be able to read it by id, and must not be able to write into
-- her family by naming it. The third is the one that matters: the first two are SELECT
-- filtering, and only the WITH CHECK half proves a forged family_id is refused.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert (select count(*) from public.import_mappings where id = 'im_a2') = 0,
         'Bob cannot see Alice''s mapping from this block';
end $t$;
-- A FORGED family_id IS OVERWRITTEN, NOT REFUSED, and the distinction is worth an explicit
-- assert rather than an exception test. set_family_id() forces every inserted row onto the
-- CALLER's family and ignores whatever the client sent (0001), so the insert succeeds and
-- lands harmlessly in Bob's family. A test asserting "denied" would pin a mechanism this
-- system deliberately does not use, and would go red against correct code - which is exactly
-- what it did when this block was first written. The property that matters is where the row
-- ENDS UP, and that is what is asserted here, mirroring the accounts forge earlier in this file.
insert into public.import_mappings (id, family_id, enc)
  values ('im_b_forge_2', (select family_id from fam where who = 'A'), 'v1.iv_im_b_2.ct_bob_amount');
do $t$ begin
  assert (select family_id from public.import_mappings where id = 'im_b_forge_2') = (select family_id from fam where who = 'B'),
         'a forged family_id on import_mappings must be overwritten to the Bob family';
  assert (select count(*) from public.import_mappings where id = 'im_b_forge_2') = 1,
         'and Bob has one mapping for this test block';
end $t$;
reset role; reset request.jwt.claims;

-- And nothing crossed the fence: Alice is untouched by Bob's attempt.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$ begin
  assert (select count(*) from public.import_mappings where id = 'im_a2') = 1, 'Alice still has her new mapping';
  assert (select enc from public.import_mappings where id = 'im_a2') = 'v1.iv_im_a2.ct_alice_date',
         'and its payload is unchanged';
end $t$;
reset role; reset request.jwt.claims;

-- import_mappings must be REGISTERED in family_version() (v1.22) - the same silent break
-- budgets pins above: omit it from the hardcoded union and a device whose ONLY change is a
-- remembered mapping is told "nothing changed" and never syncs, with no error anywhere.
-- CONTROL first, so the assert that follows is one that can actually fail.
-- THE PROBE TIMESTAMP MUST SIT ABOVE EVERY EARLIER FORGE IN THIS FILE, which is why it is
-- 2100 and not the next number down. Alice's account is forged to 2099 and Bob's budget to
-- 2098, so a probe at 2097 makes this control assert that Bob is below a time he is already
-- past - and it goes red against a perfectly correct schema. A forged-future timestamp is a
-- shared resource in a single-transaction suite, not a local choice.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert public.family_version() < '2100-01-01T00:00:00Z'::timestamptz,
         'CONTROL: Bob version is below the import_mappings probe timestamp before the forge';
end $t$;
reset role; reset request.jwt.claims;

set session_replication_role = replica;
update public.import_mappings set updated_at = '2100-01-01T00:00:00Z' where id = 'im_b_forge_2';
set session_replication_role = origin;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert public.family_version() = '2100-01-01T00:00:00Z'::timestamptz,
         'an import_mappings row MUST move family_version() (import_mappings registered in the union)';
end $t$;
reset role; reset request.jwt.claims;

-- And the forge stays on Bob's side of the fence.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$ begin
  assert public.family_version() <> '2100-01-01T00:00:00Z'::timestamptz,
         'Alice version does NOT see Bob import_mappings forge (per-family isolation holds for the new table)';
end $t$;
reset role; reset request.jwt.claims;

-- ============ family_settings: tenancy + registration + the shared id (v1.24) ============
-- The family's name, picture, plan and date format. NO enc envelope - nothing here describes the
-- family's money or its people - so unlike import_mappings the asserts below can read the payload,
-- and one of them does exactly that to prove a second family cannot.
--
-- THE SHARED ID IS THE POINT OF THE COMPOSITE KEY. Every family writes the SAME id here by
-- construction ('family-settings'), so this table is the sharpest test of migration 0009's
-- (family_id, id) primary key that exists: under a global `id` PK the second family's insert would
-- collide into an RLS-denied upsert rather than creating its own row.

-- Alice writes hers with family_id omitted -> it must be server-derived to her family.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.family_settings (id, family_name, family_photo, plan_type, date_format)
  values ('family-settings', 'Alice Family', '/avatars/family/family-01.png', 'Alpha Test', 'dayFirst');
do $t$ begin
  assert (select family_id from public.family_settings where family_name = 'Alice Family') = (select family_id from fam where who = 'A'),
         'a new settings row must be scoped to the Alice family by the trigger, not by the client';
end $t$;
reset role; reset request.jwt.claims;

-- Bob writes his under the IDENTICAL id. This is the collision 0009 exists to prevent.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
insert into public.family_settings (id, family_name, family_photo, plan_type, date_format)
  values ('family-settings', 'Bob Family', '/avatars/family/family-02.png', 'Alpha Test', 'monthFirst');
do $t$ begin
  assert (select count(*) from public.family_settings) = 1,
         'Bob sees exactly ONE settings row - his own - though both families share the id';
  assert (select family_name from public.family_settings) = 'Bob Family',
         'and it is HIS: a second family reading this table must never see the first family name';
  assert (select date_format from public.family_settings) = 'monthFirst',
         'including its date format, which is plaintext and therefore genuinely readable if isolation failed';
end $t$;
reset role; reset request.jwt.claims;

-- Bob cannot rename Alice's family, by id or otherwise. The write half of isolation.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
update public.family_settings set family_name = 'Hijacked' where family_name = 'Alice Family';
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select count(*) from public.family_settings where family_name = 'Hijacked') = 0,
         'Bob cannot rename the Alice family - the update matched nothing under RLS';
  assert (select count(*) from public.family_settings where family_name = 'Alice Family') = 1,
         'and the Alice row is untouched';
end $t$;

-- family_settings must be REGISTERED in family_version(). Same silent break as budgets and
-- import_mappings: omit it and a device whose ONLY change is a renamed family or a switched date
-- format is told "nothing changed" and never syncs, with no error anywhere.
-- CONTROL first, so the assert after the forge can actually fail.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert public.family_version() < '2101-01-01T00:00:00Z'::timestamptz,
         'CONTROL: Bob version is below the family_settings probe timestamp before the forge';
end $t$;
reset role; reset request.jwt.claims;

set session_replication_role = replica;
update public.family_settings set updated_at = '2101-01-01T00:00:00Z' where family_name = 'Bob Family';
set session_replication_role = origin;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $t$ begin
  assert public.family_version() = '2101-01-01T00:00:00Z'::timestamptz,
         'a family_settings row MUST move family_version() (family_settings registered in the union)';
end $t$;
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$ begin
  assert public.family_version() <> '2101-01-01T00:00:00Z'::timestamptz,
         'Alice version does NOT see Bob family_settings forge (per-family isolation holds for the new table)';
end $t$;
reset role; reset request.jwt.claims;

-- ============ peek_invite reads the LIVE family name (v1.24) ============
-- The joiner is not a member and holds no family key, so this is the one disclosure path that must
-- keep working after the name moves. Two cases, and the FALLBACK is the one that would break
-- silently: a family with no settings row yet must still introduce itself, not return zero rows and
-- read to the client as an invalid token.
-- id defaults to gen_random_uuid() and created_by references auth.users, not members - spelled out
-- against the real table rather than assumed, because a forged shape here would test nothing.
insert into public.invites (family_id, token, role, status, expires_at, created_by)
  select (select family_id from fam where who = 'A'), 'tok_peek_a', 'member', 'pending',
         now() + interval '7 days', '00000000-0000-0000-0000-00000000000a'::uuid;
do $t$ begin
  assert (select family_name from public.peek_invite('tok_peek_a')) = 'Alice Family',
         'peek_invite returns the LIVE name from family_settings, not the sign-up default';
end $t$;

-- Now the fallback: drop the settings row and the invite must still name the family.
delete from public.family_settings where family_name = 'Alice Family';
do $t$ begin
  assert (select count(*) from public.peek_invite('tok_peek_a')) = 1,
         'a family with NO settings row still returns a row - the left join is what stops a missing optional row reading as an invalid token';
  -- handle_new_user names the family from the Google display name, so Alice's is "Alice's Family" -
  -- read off the row rather than assumed, because the column DEFAULT is 'My Family' and never used.
  assert (select family_name from public.peek_invite('tok_peek_a'))
         = (select name from public.families where id = (select family_id from fam where who = 'A')),
         'and falls back to the tenancy root name seeded at sign-up';
end $t$;

-- ============ Role escalation: a member cannot promote themselves ============
-- THE SUITE HAS ALWAYS BEEN GREEN ABOUT ROLES AND NEVER ASKED THIS QUESTION. Four assertions above
-- mention `role`, and every one checks a role that was set LEGITIMATELY - Alice is admin, Carol
-- joined as member. None asked whether a member can BECOME an admin, and until migration 0021 the
-- answer was yes: `role` sat in the MEMBERS writable allowlist, RLS on that table is family-tenancy
-- only (no policy anywhere mentions role), and there was no trigger. A member issuing batchUpdate on
-- their own row with role 'admin' was simply promoted. The invite path has always been admin-gated,
-- which is the asymmetry that made this a bug rather than a decision.
--
-- Carol is a member of family A (she joined via invite i1 above), so she is the right subject.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
do $t$ begin
  begin
    update public.members set role = 'admin'
      where user_id = '00000000-0000-0000-0000-00000000000c';
    raise exception 'EXPECTED the role-change guard to reject a member promoting themselves';
  exception when others then
    if sqlstate = 'P0001' and sqlerrm like 'EXPECTED%' then raise; end if;
  end;
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000c') = 'member',
         'Carol is still a member after the refused promotion';
end $t$;

-- CONTROL: the guard discriminates rather than refusing every update. A member editing a NON-role
-- field on their own row must still succeed - otherwise the assertion above passes for the wrong
-- reason and the trigger has broken ordinary member edits.
do $t$ begin
  update public.members set name = 'Carol Renamed'
    where user_id = '00000000-0000-0000-0000-00000000000c';
  assert (select name from public.members where user_id = '00000000-0000-0000-0000-00000000000c') = 'Carol Renamed',
         'CONTROL: a member may still edit their own non-role fields';
end $t$;
reset role; reset request.jwt.claims;

-- CONTROL: and an ADMIN may still change a role, so the guard gates on who the caller is rather
-- than forbidding the column outright. This is the path a future promote/demote UI would use.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$ begin
  update public.members set role = 'admin'
    where user_id = '00000000-0000-0000-0000-00000000000c';
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000c') = 'admin',
         'CONTROL: an admin of the same family MAY change a member role';
  -- put it back, so anything appended after this sees the fixture it expects
  update public.members set role = 'member'
    where user_id = '00000000-0000-0000-0000-00000000000c';
end $t$;
reset role; reset request.jwt.claims;

-- CONTROL: the INSERT paths are untouched - the guard is BEFORE UPDATE, and both legitimate role
-- assignments are inserts. Asserted rather than assumed, because a trigger written as BEFORE INSERT
-- OR UPDATE would break sign-up and join_family and every symptom would be somewhere else.
do $t$ begin
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000a') = 'admin',
         'the sign-up trigger still seeds a founding admin';
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000c') = 'member',
         'and join_family still seeds an invited member at the invite role';
end $t$;

-- ============ Per-member account visibility (0023) ============
-- The first predicate in this schema narrower than a family. Every assertion below is
-- about what a NON-ADMIN member of Alice's family can see; Carol is that member (she
-- joined via join_family above and the role-escalation section left her at 'member').
--
-- WHAT WOULD HAVE PASSED BEFORE 0023: the very first assert. Carol saw every account in
-- her family, because `family_id = auth_family_id()` was the narrowest unit that existed.
-- That assert is therefore the fails-before control for this whole section, and it needs
-- no synthetic fixture - the tree itself was the counter-example until this migration.

create temporary table vis as
  select (select family_id from fam where who = 'A')                                          as fam_a,
         (select id from public.members where user_id = '00000000-0000-0000-0000-00000000000c') as carol_member,
         (select id from public.members where user_id = '00000000-0000-0000-0000-00000000000a') as alice_member;
grant select on vis to authenticated;

do $t$ begin
  assert (select carol_member from vis) is not null, 'FIXTURE: Carol must hold a member row in Alice family';
  assert (select role from public.members where user_id = '00000000-0000-0000-0000-00000000000c') = 'member',
         'FIXTURE: Carol must be a plain member, or every assertion below tests the admin arm';
end $t$;

-- Alice (admin) builds the fixture: two accounts, three transactions, two budgets.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.accounts (id, currency, enc) values
  ('w_shared',  'EUR', 'v1.iv_sh.ct_shared'),
  ('w_private', 'EUR', 'v1.iv_pr.ct_private');
insert into public.transactions (id, date, currency, type, account_id, enc) values
  ('t_shared',  '2026-08-01', 'EUR', 'expense', 'w_shared',  'v1.iv_t1.ct1'),
  ('t_private', '2026-08-01', 'EUR', 'expense', 'w_private', 'v1.iv_t2.ct2'),
  ('t_noacct',  '2026-08-01', 'EUR', 'expense', null,        'v1.iv_t3.ct3');
insert into public.staged_transactions (id, batch_id, date, currency, type, account_id, status, enc) values
  ('s_shared',  'batch1', '2026-08-01', 'EUR', 'expense', 'w_shared',  'staged', 'v1.iv_s1.cs1');
insert into public.budgets (id, period_type, kind, enc, account_ids) values
  ('b_shared', 'monthly', 'instance', 'v1.iv_b1.cb1', array['w_shared']),
  ('b_mixed',  'monthly', 'instance', 'v1.iv_b2.cb2', array['w_shared','w_private']);

-- ADMIN ARM: the predicate must not simply hide everything from everybody. An admin sees
-- the whole family, and this is the control that tells a working narrow policy apart from
-- one that is broken in the fail-closed direction (which looks identical from the member).
do $t$ begin
  assert (select count(*) from public.accounts where id in ('w_shared','w_private')) = 2,
         'CONTROL: an admin still sees every account in her family';
  assert (select count(*) from public.transactions where id in ('t_shared','t_private','t_noacct')) = 3,
         'CONTROL: an admin still sees every transaction, including one with a null account_id';
  assert (select count(*) from public.budgets where id in ('b_shared','b_mixed')) = 2,
         'CONTROL: an admin still sees every budget';
  assert public.is_family_admin(), 'CONTROL: is_family_admin() is true for the founding admin';
end $t$;
reset role; reset request.jwt.claims;

-- ============ Carol, ungranted: DEFAULT HIDDEN ============
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
do $t$ begin
  assert not public.is_family_admin(), 'Carol is not an admin';
  -- THE FAILS-BEFORE ASSERT. Green only because 0023 exists.
  assert (select count(*) from public.accounts) = 0,
         'an ungranted member sees NO accounts (default hidden, fail closed)';
  assert (select count(*) from public.transactions) = 0,
         'and therefore no transactions, including the null-account row';
  assert (select count(*) from public.staged_transactions) = 0, 'and no staged rows';
  assert (select count(*) from public.budgets) = 0, 'and no budgets';
  assert public.visible_account_ids() = '{}'::text[], 'visible_account_ids is empty for an ungranted member';
end $t$;

-- The grant ledger is not readable by the member it describes: knowing an account EXISTS
-- is the information this feature withholds, so a count would defeat it.
do $t$ begin
  assert (select count(*) from public.account_access) = 0, 'a member cannot read the grant ledger';
end $t$;

-- A MEMBER CANNOT GRANT HERSELF ANYTHING, AND SINCE 0026 THE WRITE POLICY IS WHAT SAYS SO.
-- Authoring moved onto the sync plane, so there is no admin-gated function left to refuse the
-- call: the refusal is the policy WITH CHECK, and a member INSERT raises 42501 exactly as an
-- invisible row upsert does. Written in the shape the client push actually emits, per the
-- lesson at (d) below - a bare insert would prove a permissiveness the app can never reach.
do $t$
declare raised boolean := false;
begin
  begin
    insert into public.account_access (id, account_id, member_id)
      values ('w_private__' || (select carol_member from vis), 'w_private', (select carol_member from vis))
      on conflict (family_id, id) do update set deleted = false;
  exception when others then
    raised := true;
  end;
  assert raised, 'a member writing her own grant row must be refused';
  assert (select count(*) from public.accounts) = 0, 'and the refusal changed nothing';
end $t$;
reset role; reset request.jwt.claims;

-- ============ Alice grants ONE account, as an ordinary synced row (0026) ============
-- THE ID IS DETERMINISTIC: '<account_id>__<member_id>'. Two admins granting the same pair while
-- offline therefore mint the SAME row rather than two, so the pair converges under last-write-wins
-- instead of duplicating. import_mappings refused a deterministic id (0018) because a digest of a
-- low-entropy header would publish the shape of a family bank file; nothing is disclosed here,
-- because both halves of this id are already plaintext columns on the row it names.
--
-- THE EXISTENCE CHECKS ARE GONE AND THAT IS DELIBERATE. The RPC refused a grant naming an account
-- this family does not hold. On the sync plane a refusal is a 42501 that takes the whole
-- batchUpsert with it - the 2026-08-19 shape this repo has paid for twice - so a dangling grant is
-- written and is INERT instead: family_id is server-derived, so the row can only ever name an id
-- inside the caller own family, and an id no account there carries resolves to nothing. The client
-- reconciles orphans out of what it renders (accessModel.visibleGrantedAccountIds). The tenancy
-- property the check used to carry is asserted directly in the cross-family section below.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.account_access (id, account_id, member_id, granted_by_member_id)
  values ('w_shared__' || (select carol_member from vis), 'w_shared', (select carol_member from vis), 'm_forged');
do $t$ begin
  assert (select count(*) from public.account_access) = 1, 'the admin can read the grant she just made';
  assert (select granted_by_member_id from public.account_access) = (select alice_member from vis),
         'granted_by is server-derived from the caller, and a SUPPLIED value is overwritten rather than honoured';
  assert (select deleted from public.account_access) = false, 'and a new grant is live';
end $t$;
reset role; reset request.jwt.claims;

-- ============ Carol, granted: EXACTLY the granted account ============
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
do $t$ begin
  assert (select count(*) from public.accounts) = 1, 'a granted member sees exactly one account';
  assert (select id from public.accounts) = 'w_shared', 'and it is the granted one';

  -- DERIVED: visibility follows account_id, with no per-transaction state anywhere.
  assert (select count(*) from public.transactions) = 1, 'she sees only the granted account transaction';
  assert (select id from public.transactions) = 't_shared', 'and it is the right one';
  assert not exists (select 1 from public.transactions where id = 't_noacct'),
         'a NULL account_id row stays hidden from a member - it cannot be attributed to an account';
  assert (select count(*) from public.staged_transactions) = 1, 'staged rows derive identically';

  -- CONTAINMENT, not intersection: the mixed budget spans a hidden account, so it is hidden
  -- entirely. A partial total would leak the hidden account and be quietly wrong.
  assert (select count(*) from public.budgets) = 1, 'she sees only the single-account budget';
  assert (select id from public.budgets) = 'b_shared', 'and the mixed budget is hidden entirely';
end $t$;

-- D4, AS MEASURED RATHER THAN AS INTENDED. The plan was to leave writes at family scope so
-- a member could still push a row she may no longer read - the point being that a refused
-- row takes the whole batch with it (2026-08-19). Postgres does not allow the separation:
-- a narrowed USING gates UPDATE and DELETE too, and ON CONFLICT DO UPDATE must read the
-- conflicting row. Both halves are asserted here so the next person does not re-derive it.
--
-- (a) a plain UPDATE ... WHERE on an invisible row matches nothing, SILENTLY.
update public.transactions set status = 'cleared' where id = 't_private';
do $t$ begin
  assert not exists (select 1 from public.transactions where id = 't_private'),
         'the private row is invisible to Carol, so her UPDATE had nothing to match';
end $t$;

-- (b) an UPSERT of an invisible row RAISES - this is the sync-killing rejection, and it is
--     live until the delivery slice either filters the outbox or makes the seam tolerate a
--     per-row refusal. Asserted so that a future mitigation has something to turn green.
do $t$
declare raised boolean := false;
begin
  begin
    insert into public.transactions (id, date, currency, type, account_id, enc)
      values ('t_private', '2026-08-09', 'EUR', 'expense', 'w_private', 'v1.iv_t2.EDITED')
      on conflict (family_id, id) do update set enc = excluded.enc;
  exception when others then raised := true;
  end;
  assert raised, 'upserting an invisible row is REFUSED (known: one such row kills the batch)';
end $t$;

-- (c) CONTROL: the same upsert on a VISIBLE row succeeds. Without this the assert above
--     passes for the wrong reason - it would be satisfied by a policy that refuses every
--     write from a member, which is a different and much worse bug.
insert into public.transactions (id, date, currency, type, account_id, enc)
  values ('t_shared', '2026-08-09', 'EUR', 'expense', 'w_shared', 'v1.iv_t1.EDITED')
  on conflict (family_id, id) do update set enc = excluded.enc;
do $t$ begin
  assert (select enc from public.transactions where id = 't_shared') = 'v1.iv_t1.EDITED',
         'CONTROL: a member CAN still write a row she can see';
end $t$;

-- (d) CREATION IN THE CLIENT'S OWN SHAPE. supabase-js `upsert(rows).select()` emits
--     INSERT ... ON CONFLICT ... RETURNING, and RETURNING RE-READS the row under the SELECT
--     policy - so this is the assertion that decides whether a member can use the app at all.
--     Under 0023 alone it was REFUSED (42501, row not written); 0024's created_by is what
--     makes it pass, because a row's own column is the only thing a STABLE predicate can see
--     inside the same statement. Asserted in the client's shape rather than the convenient
--     one: an earlier version used a bare insert and "proved" a permissiveness the app can
--     never reach.
do $t$
declare n int;
begin
  with ins as (
    insert into public.accounts (id, currency, enc) values ('w_carol', 'EUR', 'v1.iv_cw.ct_carol')
    on conflict (family_id, id) do update set enc = excluded.enc
    returning *
  ) select count(*) into n from ins;
  assert n = 1, 'the CLIENT-SHAPED create returns the row it wrote';
  assert (select count(*) from public.accounts where id = 'w_carol') = 1,
         'and the member can read back the account she just created';
end $t$;

-- (e) THE NEGATIVE CONTROL FOR (d), and it is the one that matters. The creator arm is an OR
--     into a fail-closed predicate, so the question is not whether it lets her see her own
--     row - it is whether it let anything else through with it.
do $t$ begin
  assert not exists (select 1 from public.accounts where id = 'w_private'),
         'CONTROL: creating her own account did NOT reveal the admin private account';
  assert (select count(*) from public.accounts) = 2,
         'CONTROL: she sees exactly the granted account and the one she created, nothing more';
end $t$;

-- (f) created_by IS SERVER-DERIVED. A supplied value must be overwritten, not honoured - an
--     earlier draft of the trigger used coalesce() and THIS control caught it: a forged value
--     survived, which would have let a member hand visibility of a new row to someone else.
insert into public.accounts (id, currency, enc, created_by)
  values ('w_forge', 'EUR', 'v1.iv_fg.ct_forge', 'm_someone_else');
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select created_by from public.accounts where id = 'w_forge') <> 'm_someone_else',
         'a client-supplied created_by must be overwritten by the session value';
  assert (select created_by from public.accounts where id = 'w_forge')
       = (select carol_member from vis),
         'and it must be the CALLER, derived from the session like family_id';
end $t$;

-- (g) WRITE-ONCE, ENFORCED BY PRESERVING RATHER THAN RAISING. A raise would turn one row into
--     a failed batch and take the sync with it, which is the failure shape this repo has paid
--     for twice. The old value is silently restored instead.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
update public.accounts set created_by = 'm_hijack' where id = 'w_forge';
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select created_by from public.accounts where id = 'w_forge') = (select carol_member from vis),
         'created_by survives an update attempt unchanged, and the update itself did not error';
end $t$;

-- (h) A NULL-ACCOUNT ROW IS VISIBLE TO ITS AUTHOR AND TO NOBODY ELSE. This is the staged-import
--     case: a row before classification names no account, so it can be attributed to none, and
--     under 0023 alone it was hidden from the member who created it.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
insert into public.transactions (id, date, currency, type, account_id, enc)
  values ('t_carol_noacct', '2026-08-10', 'EUR', 'expense', null, 'v1.iv_cn.ct_cn');
insert into public.staged_transactions (id, batch_id, date, currency, type, account_id, status, enc)
  values ('s_carol_noacct', 'batch2', '2026-08-10', 'EUR', 'expense', null, 'staged', 'v1.iv_sn.ct_sn');
do $t$ begin
  assert exists (select 1 from public.transactions where id = 't_carol_noacct'),
         'a member sees her own unclassified transaction';
  assert exists (select 1 from public.staged_transactions where id = 's_carol_noacct'),
         'and her own staged import row';
  assert not exists (select 1 from public.transactions where id = 't_noacct'),
         'CONTROL: but NOT the admin unclassified row - the arm is authorship, not null-ness';
end $t$;

-- ============ Revocation is a TOMBSTONE, and evicts nothing ============
-- A MEMBER CANNOT REVOKE HER OWN GRANT EITHER, AND THIS ARM FAILS DIFFERENTLY FROM THE INSERT
-- ONE. The policy USING clause is admin-only, so the row is invisible to her and the UPDATE
-- matches nothing - SILENTLY, the same shape as (a) above. Both halves are asserted because a
-- policy narrowed on only one of them would leave the other open and nothing would say so.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
update public.account_access set deleted = true where account_id = 'w_shared';
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select deleted from public.account_access where account_id = 'w_shared') = false,
         'a member UPDATE on the grant ledger matched nothing - her own grant is still live';
end $t$;

-- THE REVOKE ITSELF. A hard delete leaves no tombstone and a delta read cannot express a row that
-- is simply gone, so the admin device would never learn the grant had been withdrawn. Soft delete
-- is what makes revocation deliverable on the sync plane at all.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
update public.account_access set deleted = true
  where id = 'w_shared__' || (select carol_member from vis);
do $t$ begin
  assert (select count(*) from public.account_access where not deleted) = 0, 'the grant is gone';
  assert (select count(*) from public.account_access) = 1,
         'but the ROW survives as a tombstone - which is the only way the withdrawal reaches another device';
end $t$;
-- Idempotent: re-writing the same tombstone is the same end state, and a UI that double-fires
-- must not error. The scope_version section below asserts it does not BUMP either.
update public.account_access set deleted = true
  where id = 'w_shared__' || (select carol_member from vis);
reset role; reset request.jwt.claims;

set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
-- REVOCATION TAKES THE GRANT AND LEAVES WHAT SHE CREATED. That asymmetry is the point rather
-- than a side effect: "rows the member created stay available" is what makes the eventual lock
-- proportionate instead of punitive, and it falls out of created_by for free.
do $t$ begin
  assert not exists (select 1 from public.accounts where id = 'w_shared'),
         'after revocation the granted account is no longer sent';
  assert not exists (select 1 from public.transactions where id = 't_shared'),
         'and its derived transactions go with it';
  assert exists (select 1 from public.accounts where id = 'w_carol'),
         'but the account she created herself stays - revocation is not confiscation';
  assert exists (select 1 from public.transactions where id = 't_carol_noacct'),
         'as does her own unclassified row';
end $t$;
reset role; reset request.jwt.claims;

-- ============ scope_version: the only channel a scope change has (0025) ============
-- A delta read can deliver neither a widened nor a narrowed scope, so the server counts the
-- changes on the member's own row and the client answers a bump by clearing and re-pulling.
-- The asserts below are about the SERVER half: that the counter moves exactly when scope moves.
do $t$ begin
  assert (select scope_version from public.members where id = (select carol_member from vis)) = 2,
         'the grant and the revoke above bumped Carol scope_version exactly twice';
  assert (select scope_version from public.members where user_id = '00000000-0000-0000-0000-00000000000a') = 0,
         'and nobody else moved - a bump is per MEMBER, not per family';
end $t$;

-- IDEMPOTENT WRITES MUST NOT BUMP, and this is load-bearing rather than tidy: the client answers
-- a bump by DELETING local rows, so a re-grant of what is already granted would cost a member a
-- clear-and-refetch for no reason.
--
-- THE DISCRIMINATOR CHANGED WITH THE MECHANISM, AND THAT IS THE WHOLE RISK OF 0026. The RPC could
-- ask FOUND, because `on conflict do nothing` and `delete` each either touched a row or did not. A
-- trigger has no FOUND: it fires on every INSERT and every UPDATE, including the ordinary
-- ON CONFLICT DO UPDATE the client emits on EVERY push for a row that has not changed. So the
-- discrimination moved into the trigger WHEN clause - a live INSERT, or an UPDATE in which
-- `deleted` actually transitions. Without it every routine re-push would evict the member.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$
declare before_v integer;
declare grant_id text := 'w_shared__' || (select carol_member from vis);
begin
  select scope_version into before_v from public.members where id = (select carol_member from vis);

  update public.account_access set deleted = true where id = grant_id;
  assert (select scope_version from public.members where id = (select carol_member from vis)) = before_v,
         'revoking what is already revoked changes nothing and must NOT bump';

  update public.account_access set deleted = false where id = grant_id;
  assert (select scope_version from public.members where id = (select carol_member from vis)) = before_v + 1,
         'CONTROL: a real re-grant DOES bump - so the assert above is not passing because bumps never happen';

  update public.account_access set deleted = false where id = grant_id;
  assert (select scope_version from public.members where id = (select carol_member from vis)) = before_v + 1,
         'and re-granting what is already granted must NOT bump';

  -- THE ONE THE RPC NEVER HAD TO SURVIVE. Every push re-sends the whole outbox row, so an
  -- unchanged grant arrives as an upsert over and over. This is the client push shape verbatim.
  insert into public.account_access (id, account_id, member_id)
    values (grant_id, 'w_shared', (select carol_member from vis))
    on conflict (family_id, id) do update set account_id = excluded.account_id, deleted = excluded.deleted;
  assert (select scope_version from public.members where id = (select carol_member from vis)) = before_v + 1,
         'an idempotent re-UPSERT of an unchanged grant must NOT bump - a routine push must not evict anybody';

  -- A grant that arrives ALREADY tombstoned is a member who never had it: nothing to withdraw,
  -- nothing to deliver. An INSERT arm that bumped unconditionally would evict on this row.
  insert into public.account_access (id, account_id, member_id, deleted)
    values ('w_private__' || (select carol_member from vis), 'w_private', (select carol_member from vis), true);
  assert (select scope_version from public.members where id = (select carol_member from vis)) = before_v + 1,
         'and an INSERT of an already-tombstoned grant must NOT bump either';
end $t$;

reset role; reset request.jwt.claims;

-- The bump must REACH her, which means riding updated_at like any other change. Without that the
-- counter is correct and undeliverable, which is exactly the failure it exists to fix.
--
-- ASSERTED BY BACKDATING RATHER THAN BY COMPARING TWO READINGS. This suite runs inside ONE
-- transaction and set_updated_at stamps now(), which is transaction-constant - so "read the
-- stamp, act, read it again" compares a value to itself and fails against a working trigger.
-- Backdating the row first gives the trigger something to visibly move.
--
-- THE BACKDATE HAS TO DISABLE members_set_updated_at, AND WITHOUT THAT THIS WHOLE BLOCK WAS A
-- CHECK THAT COULD NOT FAIL (found 2026-08-25 while rewriting the section for 0026). That trigger
-- is `before insert or update` and assigns `new.updated_at := now()` UNCONDITIONALLY, so the
-- backdate below was overwritten by the very statement that wrote it. Both asserts then held
-- whatever the grant plane did - including if it did nothing at all - because now() is
-- transaction-constant and the row already carried it. The disable is what gives the assert
-- something it can be wrong about; the CONTROL after it proves the backdate actually landed.
alter table public.members disable trigger members_set_updated_at;
update public.members set updated_at = '2000-01-01T00:00:00Z'
  where id = (select carol_member from vis);
alter table public.members enable trigger members_set_updated_at;
do $t$ begin
  assert (select updated_at from public.members where id = (select carol_member from vis))
         = '2000-01-01T00:00:00Z'::timestamptz,
         'CONTROL: the backdate took - otherwise the two asserts below cannot fail';
end $t$;
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
update public.account_access set deleted = true
  where id = 'w_shared__' || (select carol_member from vis);
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select updated_at from public.members where id = (select carol_member from vis))
         > '2000-01-01T00:00:00Z'::timestamptz,
         'a bump moves updated_at, so the row enters the member next delta pull';
  assert (select updated_at from public.members where id = (select carol_member from vis)) = now(),
         'CONTROL: it was the set_updated_at trigger that moved it, not the backdate lingering';
end $t$;

-- ============ import_mappings is ADMIN-ONLY (was a navigation gate only) ============
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
insert into public.import_mappings (id, enc) values ('im_vis1', 'v1.iv_im.ct_im');
do $t$ begin
  assert (select count(*) from public.import_mappings where id = 'im_vis1') = 1, 'an admin reads import mappings';
end $t$;
reset role; reset request.jwt.claims;
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
do $t$ begin
  assert (select count(*) from public.import_mappings) = 0, 'a member reads none';
end $t$;
reset role; reset request.jwt.claims;

-- ============ Cross-family: the grant plane respects tenancy (0026) ============
-- THE RPC USED TO REFUSE THIS AND NOW THERE IS NOTHING TO REFUSE, WHICH IS A STRONGER PROPERTY
-- RATHER THAN A WEAKER ONE. family_id is derived by the same set_family_id trigger every tenant
-- table has used since 0001, so a row Bob writes naming an account id out of Alice family lands in
-- BOB family and grants nothing to anybody. Tenancy is a property of the write path here, not a
-- check inside a function that a second writer could bypass - and there is no second writer now.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
insert into public.account_access (id, account_id, member_id, family_id)
  values ('w_shared__cross', 'w_shared', (select carol_member from vis), (select fam_a from vis));
reset role; reset request.jwt.claims;
do $t$ begin
  assert (select family_id from public.account_access where id = 'w_shared__cross')
       = (select family_id from fam where who = 'B'),
         'Bob grant landed in HIS family, and a SUPPLIED family_id was overwritten rather than honoured';
  assert (select count(*) from public.account_access
           where family_id = (select fam_a from vis) and not deleted) = 0,
         'and Alice family ledger is untouched - every grant in it is a tombstone by now';
end $t$;

-- AND IT CONFERRED NOTHING, which is the assert that matters: the row exists, names a real account
-- id, and is inert because the id belongs to a family the row is not in.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
do $t$ begin
  assert not exists (select 1 from public.accounts where id = 'w_shared'),
         'Carol still cannot see w_shared - a grant row in another family reaches her not at all';
end $t$;
reset role; reset request.jwt.claims;

-- ============ D5: an account-less budget is an impossible state ============
-- The client already refuses to save one; this is the schema agreeing with the form. It
-- matters because '{}' <@ anything is TRUE, so an empty array would be visible to EVERY
-- member, vacuously - fail-closed defeated at exactly the point it is load-bearing.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$
declare raised boolean := false;
begin
  begin
    insert into public.budgets (id, period_type, kind, enc, account_ids)
      values ('b_empty', 'monthly', 'instance', 'v1.iv_be.cbe', '{}'::text[]);
  exception when check_violation then raised := true;
  end;
  assert raised, 'a budget with no accounts must be refused by the schema';
end $t$;
-- And the default is gone, so omitting the column is loud rather than quietly empty.
do $t$
declare raised boolean := false;
begin
  begin
    insert into public.budgets (id, period_type, kind, enc)
      values ('b_default', 'monthly', 'instance', 'v1.iv_bd.cbd');
  exception when not_null_violation then raised := true;
  end;
  assert raised, 'omitting account_ids must fail rather than default to the vacuous empty array';
end $t$;
reset role; reset request.jwt.claims;

-- ============ The TEST-FAMILY arm: without it the ghost suite sees nothing ============
-- ensure_test_family() provisions a families row and a user_test_family mapping and NO
-- members row, and user_id is stripped from every client write - so inside a test family
-- auth.uid() resolves to no member and to no role. A fail-closed predicate reading only
-- `members` would show 199 ghost scenarios zero of everything. The caller owning the test
-- family IS its administrator; there is nobody else in it.
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
set request.headers = '{"x-bf-test":"1"}';
do $t$
declare tf uuid;
begin
  tf := public.ensure_test_family();
  assert tf is not null, 'FIXTURE: a test family was provisioned';
  assert public.auth_family_id() = tf, 'tenancy resolves to the test family';
  assert not exists (select 1 from public.members m where m.family_id = tf and m.user_id is not null),
         'MEASURED: the test family holds no user-linked member row - this is why the arm exists';
  assert public.auth_member_id() is null, 'auth_member_id is null in a test family, by construction';
  assert public.is_family_admin(), 'and the caller is nonetheless its admin, or every ghost sees nothing';
end $t$;
-- The arm must not leak the other way: a test-context caller is an admin of the TEST family
-- and must still see nothing of their real one.
insert into public.accounts (id, currency, enc) values ('w_test1', 'EUR', 'v1.iv_tt.ct_test');
do $t$ begin
  assert (select count(*) from public.accounts) = 1, 'the test family sees only its own account';
  assert (select id from public.accounts) = 'w_test1', 'and the real family stays out of the test context';
end $t$;
reset role; reset request.jwt.claims; reset request.headers;

-- CONTROL: the header is what switched context, not the uid. Same caller, no header, and the
-- test row is invisible again - otherwise the assertion above passes for the wrong reason.
set role authenticated; set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $t$ begin
  assert not exists (select 1 from public.accounts where id = 'w_test1'),
         'CONTROL: without the test header the caller is back in her real family';
  assert (select count(*) from public.accounts where id in ('w_shared','w_private')) = 2,
         'CONTROL: and sees her real accounts again';
end $t$;
reset role; reset request.jwt.claims;

rollback;
\echo '================================'
\echo 'RLS ISOLATION TESTS: ALL PASSED'
\echo '================================'
