-- Usage-analytics ingest + RLS + retention suite (Slice 2). Proves the out-of-band
-- analytics_events destination: RPC-only ingest with SERVER-DERIVED identity, no
-- direct table access for authenticated, at-least-once dedup on idk, and the
-- 6-month purge. Run order: auth_shim.sql -> migrations 0001-0014 -> THIS.
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

-- No direct table access for authenticated: neither SELECT nor INSERT is granted.
do $$
declare denied boolean := false;
begin
  begin perform 1 from public.analytics_events limit 1;
  exception when others then denied := true; end;
  assert denied, 'authenticated must NOT be able to SELECT analytics_events directly';
end $$;
do $$
declare denied boolean := false;
begin
  begin
    insert into public.analytics_events (user_id, idk, e, client_ts, tz, sv)
      values ('00000000-0000-0000-0000-00000000000a',
              '99999999-9999-9999-9999-999999999999','x', now(), 'UTC', 1);
  exception when others then denied := true; end;
  assert denied, 'authenticated must NOT be able to INSERT analytics_events directly';
end $$;

reset role;
reset request.jwt.claims;

-- ============ As the table owner (bypasses RLS): verify server-stamped identity ============
do $$ begin
  assert (select user_id from public.analytics_events
            where idk = '11111111-1111-1111-1111-111111111111')
         = '00000000-0000-0000-0000-00000000000a'::uuid,
         'user_id is server-derived (auth.uid()), NOT the forged payload value';
  assert (select count(*) from public.analytics_events
            where idk = '11111111-1111-1111-1111-111111111111') = 1,
         'duplicate idk stored exactly once';
  assert (select count(*) from public.analytics_events
            where user_id = '00000000-0000-0000-0000-00000000000b') = 0,
         'nothing was written under the forged Bob user_id';
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
  assert (select user_id from public.analytics_events
            where idk = '66666666-6666-6666-6666-666666666666')
         = '00000000-0000-0000-0000-00000000000b'::uuid,
         'Bob''s event is stamped with Bob''s uid';
end $$;

-- ============ Retention purge: 6-month cutoff ============
insert into public.analytics_events (user_id, idk, e, client_ts, tz, received_at, sv) values
  ('00000000-0000-0000-0000-00000000000a', '33333333-3333-3333-3333-333333333333',
   'app_opened', now(), 'UTC', now() - interval '7 months', 1),
  ('00000000-0000-0000-0000-00000000000a', '44444444-4444-4444-4444-444444444444',
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

do $$ begin raise notice 'analytics_rls.test.sql: all assertions passed'; end $$;

rollback;
