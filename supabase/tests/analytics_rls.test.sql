-- Usage-analytics ingest + RLS + retention suite (Slice 2, extended by 0019). Proves
-- the out-of-band analytics_events destination: RPC-only ingest with SERVER-DERIVED
-- identity, no direct table access for authenticated, at-least-once dedup on idk, and
-- the 6-month purge. Since 0019 it also proves the OPAQUE IDENTITY KEYS: analytics_users
-- and analytics_families are the only bridges between a person or a household and their
-- telemetry, so deleting either severs the identity WITHOUT destroying the behaviour.
-- Run order: auth_shim.sql -> migrations 0001-0019 -> THIS.
-- Rolled-back tx; psql with ON_ERROR_STOP exits nonzero on the first failed ASSERT.
\set ON_ERROR_STOP on
begin;

-- Two Google sign-ins (fixed ids so we can forge claims). handle_new_user fires,
-- but analytics is user-keyed and independent of the family bootstrap.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'alice@fam.test', '{"full_name":"Alice"}'),
  ('00000000-0000-0000-0000-00000000000b', 'bob@fam.test',   '{"full_name":"Bob"}');

-- ============ Act as Alice: ingest via the RPC ============
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';

-- A batch of two events. The first row also carries a FORGED "user_id":Bob to prove
-- the server ignores client identity and stamps auth.uid().
do $$
declare inserted int;
begin
  inserted := public.ingest_events($json$[
    {"user_id":"00000000-0000-0000-0000-00000000000b",
     "idk":"11111111-1111-1111-1111-111111111111","e":"app_opened",
     "client_ts":"2026-07-04T10:00:00Z","tz":"Europe/Lisbon",
     "props":{"cold_start":true,"source":"direct"},"sv":1},
    {"idk":"55555555-5555-5555-5555-555555555555","e":"activity_viewed",
     "client_ts":"2026-07-04T10:01:00Z","tz":"Europe/Lisbon","props":{},"sv":1}
  ]$json$::jsonb);
  assert inserted = 2, 'ingest_events inserted both new rows';
end $$;

-- Dedup: re-ingesting the same idk is a no-op (returns 0 inserted).
do $$
declare inserted int;
begin
  inserted := public.ingest_events($json$[
    {"idk":"11111111-1111-1111-1111-111111111111","e":"app_opened",
     "client_ts":"2026-07-04T10:00:00Z","tz":"UTC","props":{},"sv":1}
  ]$json$::jsonb);
  assert inserted = 0, 'duplicate idk is deduped (on conflict do nothing)';
end $$;

-- No direct READ for authenticated: either a permission error (privileges revoked)
-- or an RLS-empty result (deny-all policy) - both mean the data is unreadable.
-- Environment-robust so it holds on both stock Postgres and Supabase (whose default
-- privileges auto-grant new public tables until the migration's REVOKE strips them).
do $$
declare visible int := -1;
begin
  begin
    select count(*) into visible from public.analytics_events;
  exception when others then visible := 0;
  end;
  assert visible = 0, 'authenticated must NOT be able to READ analytics_events data (denied or RLS-empty)';
end $$;
do $$
declare denied boolean := false;
begin
  begin
    insert into public.analytics_events (user_key, idk, e, client_ts, tz, sv)
      values ('aaaaaaaa-0000-0000-0000-00000000000a',
              '99999999-9999-9999-9999-999999999999','x', now(), 'UTC', 1);
  exception when others then denied := true; end;
  assert denied, 'authenticated must NOT be able to INSERT analytics_events directly';
end $$;

reset role;
reset request.jwt.claims;

-- ============ As the table owner (bypasses RLS): verify server-stamped identity ============
do $$ begin
  assert (select e.user_key from public.analytics_events e
            where e.idk = '11111111-1111-1111-1111-111111111111')
         = (select au.user_key from public.analytics_users au
              where au.user_id = '00000000-0000-0000-0000-00000000000a'),
         'user_key is server-derived from auth.uid(), NOT the forged payload value';
  assert (select count(*) from public.analytics_events
            where idk = '11111111-1111-1111-1111-111111111111') = 1,
         'duplicate idk stored exactly once';
  assert (select count(*) from public.analytics_events e
            join public.analytics_users au on au.user_key = e.user_key
            where au.user_id = '00000000-0000-0000-0000-00000000000b') = 0,
         'nothing was written under the forged Bob identity';
end $$;

-- ============ Unauthenticated call is rejected ============
set role authenticated;
reset request.jwt.claims;  -- auth.uid() -> null
do $$
declare rejected boolean := false;
begin
  begin perform public.ingest_events('[]'::jsonb);
  exception when others then rejected := true; end;
  assert rejected, 'ingest_events requires an authenticated session';
end $$;
reset role;

-- ============ Symmetry: Bob's ingest is stamped with Bob's uid ============
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000b"}';
do $$ begin
  perform public.ingest_events($json$[
    {"idk":"66666666-6666-6666-6666-666666666666","e":"activity_viewed",
     "client_ts":"2026-07-04T11:00:00Z","tz":"UTC","props":{},"sv":1}
  ]$json$::jsonb);
end $$;
reset role;
reset request.jwt.claims;
do $$ begin
  assert (select e.user_key from public.analytics_events e
            where e.idk = '66666666-6666-6666-6666-666666666666')
         = (select au.user_key from public.analytics_users au
              where au.user_id = '00000000-0000-0000-0000-00000000000b'),
         'Bob''s event is stamped with Bob''s own key';
end $$;

-- ============ Retention purge: 6-month cutoff ============
insert into public.analytics_events (user_key, idk, e, client_ts, tz, received_at, sv) values
  ('aaaaaaaa-0000-0000-0000-00000000000a', '33333333-3333-3333-3333-333333333333',
   'app_opened', now(), 'UTC', now() - interval '7 months', 1),
  ('aaaaaaaa-0000-0000-0000-00000000000a', '44444444-4444-4444-4444-444444444444',
   'app_opened', now(), 'UTC', now() - interval '1 month', 1);

do $$
declare deleted int;
begin
  deleted := public.purge_old_analytics_events();
  assert deleted >= 1, 'purge deleted at least the 7-month-old row';
  assert (select count(*) from public.analytics_events
            where idk = '33333333-3333-3333-3333-333333333333') = 0,
         'row older than 6 months is purged';
  assert (select count(*) from public.analytics_events
            where idk = '44444444-4444-4444-4444-444444444444') = 1,
         'row within 6 months is kept';
end $$;

-- ===========================================================================
-- 0019: the opaque identity keys.
-- ===========================================================================

-- Both keys are minted server-side. A forged user_key/family_key in the payload is
-- ignored exactly as a forged user_id was. Alice and Bob must land on DIFFERENT keys:
-- discrimination, not mere presence - a predicate that could not tell them apart would
-- pass just as happily on one shared key for the whole tenant base.
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $$ begin
  perform public.ingest_events($json$[
    {"user_key":"deadbeef-0000-0000-0000-000000000001",
     "family_key":"deadbeef-0000-0000-0000-000000000002",
     "idk":"77777777-7777-7777-7777-777777777777","e":"app_opened",
     "client_ts":"2026-07-04T12:00:00Z","tz":"UTC","props":{},"sv":1}
  ]$json$::jsonb);
end $$;
reset role;
reset request.jwt.claims;

do $$
declare v_alice uuid; v_bob uuid; v_fam uuid; v_famkey uuid;
begin
  select user_key into v_alice from public.analytics_users
    where user_id = '00000000-0000-0000-0000-00000000000a';
  select user_key into v_bob from public.analytics_users
    where user_id = '00000000-0000-0000-0000-00000000000b';
  assert v_alice is not null and v_bob is not null,
         'both users have a minted analytics key';
  assert v_alice <> v_bob, 'Alice and Bob carry DIFFERENT user keys';
  assert v_alice <> '00000000-0000-0000-0000-00000000000a'::uuid,
         'the user key is OPAQUE, not a copy of the auth uid';
  assert (select user_key from public.analytics_events
            where idk = '77777777-7777-7777-7777-777777777777') = v_alice,
         'a forged user_key in the payload is ignored';
  assert (select family_key from public.analytics_events
            where idk = '77777777-7777-7777-7777-777777777777')
         <> 'deadbeef-0000-0000-0000-000000000002'::uuid,
         'a forged family_key in the payload is ignored';

  select family_id into v_fam from public.members
    where user_id = '00000000-0000-0000-0000-00000000000a';
  select family_key into v_famkey from public.analytics_families where family_id = v_fam;
  assert v_famkey is not null, 'the family bridge row is minted on first ingest';
  assert (select family_key from public.analytics_events
            where idk = '77777777-7777-7777-7777-777777777777') = v_famkey,
         'family_key is server-derived from auth_family_id()';
end $$;

-- The three new tables are as unreadable as analytics_events: no grant, no policy.
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000a"}';
do $$
declare visible int;
begin
  visible := -1;
  begin select count(*) into visible from public.analytics_users;
  exception when others then visible := 0; end;
  assert visible = 0, 'authenticated must NOT read analytics_users';

  visible := -1;
  begin select count(*) into visible from public.analytics_families;
  exception when others then visible := 0; end;
  assert visible = 0, 'authenticated must NOT read analytics_families';

  visible := -1;
  begin select count(*) into visible from public.analytics_family_tombstones;
  exception when others then visible := 0; end;
  assert visible = 0, 'authenticated must NOT read analytics_family_tombstones';
end $$;
reset role;
reset request.jwt.claims;

-- ============ A caller with no members row ingests with a NULL family_key ============
-- join_family DELETES the caller's members row before inserting the new one, so
-- auth_family_id() is NULL across that window (0007 says so in its own comment). Under
-- NOT NULL the RPC would raise; drainOnce catches, RETAINS the batch and re-peeks the
-- same FIFO head next trigger, so one poison batch would block that user's entire
-- stream until the 1000-event cap evicted it. This asserts the window is survivable.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000c', 'carol@fam.test', '{"full_name":"Carol"}');
delete from public.members where user_id = '00000000-0000-0000-0000-00000000000c';

set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-00000000000c"}';
do $$
declare inserted int;
begin
  inserted := public.ingest_events($json$[
    {"idk":"88888888-8888-8888-8888-888888888888","e":"app_opened",
     "client_ts":"2026-07-04T13:00:00Z","tz":"UTC","props":{},"sv":1}
  ]$json$::jsonb);
  assert inserted = 1, 'a caller with no members row can still ingest';
end $$;
reset role;
reset request.jwt.claims;

do $$ begin
  assert (select family_key from public.analytics_events
            where idk = '88888888-8888-8888-8888-888888888888') is null,
         'family_key is NULL when the caller has no members row';
  assert (select user_key from public.analytics_events
            where idk = '88888888-8888-8888-8888-888888888888') is not null,
         'the user key is still stamped when there is no family';
end $$;

-- ============ REGRESSION: a deleted family KEEPS its grouping ============
-- The defect this design exists to prevent: an FK with on delete set null (or cascade)
-- would wipe the family dimension for exactly the cohort whose behaviour explains the
-- departure. join_family HARD-DELETES the caller's family whenever they were its sole
-- member (0007 lines 159-165), which is every ordinary invitee - so this is the routine
-- path, not an edge case. The tombstone carries WHY, because most deletions here are a
-- successful activation rather than churn and conflating them would poison the metric.
do $$
declare v_fam uuid; v_key uuid; v_before int;
begin
  select family_id into v_fam from public.members
    where user_id = '00000000-0000-0000-0000-00000000000a';
  select family_key into v_key from public.analytics_families where family_id = v_fam;
  select count(*) into v_before from public.analytics_events where family_key = v_key;
  assert v_before > 0, 'control: Alice has events carrying her family key';

  perform public.record_family_deletion(v_fam, 'joined_another_family');
  delete from public.families where id = v_fam;

  assert (select count(*) from public.analytics_events where family_key = v_key) = v_before,
         'events KEEP their family_key after the family row is deleted';
  assert (select count(*) from public.analytics_families where family_id = v_fam) = 0,
         'the bridge row cascades away with the family';
  assert (select reason from public.analytics_family_tombstones where family_key = v_key)
         = 'joined_another_family',
         'the tombstone outlives the bridge and records WHY the family went';
  assert (select deleted_at from public.analytics_family_tombstones where family_key = v_key)
         is not null,
         'the tombstone carries WHEN, which is what a churn window needs';
end $$;

-- ============ REGRESSION: erasure severs the identity and KEEPS the behaviour ============
-- 0014 used `references auth.users on delete cascade`, which destroyed a departing
-- user's telemetry - the evidence for the very churn it was needed to explain. The
-- bridge row is now the only link, so deleting it anonymises the events in place.
-- Note this is the house convention already: members.user_id, invites.created_by and
-- invites.redeemed_by are all `on delete set null` - sever, do not delete.
do $$
declare v_key uuid; v_before int;
begin
  select user_key into v_key from public.analytics_users
    where user_id = '00000000-0000-0000-0000-00000000000b';
  select count(*) into v_before from public.analytics_events where user_key = v_key;
  assert v_before > 0, 'control: Bob has events carrying his user key';

  delete from auth.users where id = '00000000-0000-0000-0000-00000000000b';

  assert (select count(*) from public.analytics_users
            where user_id = '00000000-0000-0000-0000-00000000000b') = 0,
         'the bridge row cascades away with the auth user';
  assert (select count(*) from public.analytics_events where user_key = v_key) = v_before,
         'the events SURVIVE the erasure, now unlinkable to any person';
end $$;

do $$ begin raise notice 'analytics_rls.test.sql: all assertions passed'; end $$;

rollback;
