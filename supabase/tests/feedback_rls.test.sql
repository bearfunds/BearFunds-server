-- In-app feedback ingest + RLS suite (Area 029). Proves the out-of-band feedback
-- destination: RPC-only writes with SERVER-DERIVED identity, no direct table access
-- for authenticated, kind/message validation, and per-user row isolation.
-- Run order: auth_shim.sql -> migrations 0001-0015 -> THIS.
-- Rolled-back tx; psql with ON_ERROR_STOP exits nonzero on the first failed ASSERT.
\set ON_ERROR_STOP on
begin;

-- Two Google sign-ins (fixed ids so we can forge claims).
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000fa', 'fa-alice@fam.test', '{"full_name":"Alice"}'),
  ('00000000-0000-0000-0000-0000000000fb', 'fa-bob@fam.test',   '{"full_name":"Bob"}');

-- ============ Act as Alice: submit via the RPC ============
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000fa"}';

do $$
declare new_id uuid;
begin
  new_id := public.submit_feedback(
    'bug',
    'Sync icon stuck spinning after I add a transaction offline.',
    '{"app_version":"1.4.2","platform":"web","viewport":"mobile","route":"activity"}'::jsonb,
    '2026-07-06T10:00:00Z', 'Europe/Lisbon', 1);
  assert new_id is not null, 'submit_feedback returns the new row id';
end $$;

-- No direct READ for authenticated: either a permission error (privileges revoked)
-- or an RLS-empty result (deny-all policy) - both mean the data is unreadable.
do $$
declare visible int := -1;
begin
  begin
    select count(*) into visible from public.feedback;
  exception when others then visible := 0;
  end;
  assert visible = 0, 'authenticated must NOT be able to READ feedback data (denied or RLS-empty)';
end $$;

-- No direct INSERT for authenticated.
do $$
declare denied boolean := false;
begin
  begin
    insert into public.feedback (user_id, kind, message)
      values ('00000000-0000-0000-0000-0000000000fa', 'bug', 'direct write');
  exception when others then denied := true; end;
  assert denied, 'authenticated must NOT be able to INSERT feedback directly';
end $$;

-- Validation: bad kind is rejected.
do $$
declare rejected boolean := false;
begin
  begin perform public.submit_feedback('spam', 'hello', '{}'::jsonb, null, null, 1);
  exception when others then rejected := true; end;
  assert rejected, 'submit_feedback rejects an invalid kind';
end $$;

-- Validation: empty / whitespace-only message is rejected.
do $$
declare rejected boolean := false;
begin
  begin perform public.submit_feedback('idea', '   ', '{}'::jsonb, null, null, 1);
  exception when others then rejected := true; end;
  assert rejected, 'submit_feedback rejects a blank message';
end $$;

reset role;
reset request.jwt.claims;

-- ============ As the table owner (bypasses RLS): verify server-stamped identity ============
do $$ begin
  assert (select count(*) from public.feedback
            where user_id = '00000000-0000-0000-0000-0000000000fa'::uuid
              and kind = 'bug') = 1,
         'Alice''s feedback row is stored under Alice''s server-derived uid';
  assert (select context->>'route' from public.feedback
            where user_id = '00000000-0000-0000-0000-0000000000fa'::uuid
              and kind = 'bug') = 'activity',
         'context jsonb is persisted verbatim';
end $$;

-- ============ Unauthenticated call is rejected ============
set role authenticated;
reset request.jwt.claims;  -- auth.uid() -> null
do $$
declare rejected boolean := false;
begin
  begin perform public.submit_feedback('other', 'anon try', '{}'::jsonb, null, null, 1);
  exception when others then rejected := true; end;
  assert rejected, 'submit_feedback requires an authenticated session';
end $$;
reset role;

-- ============ Isolation: Bob cannot read Alice's rows (no direct table access) ============
set role authenticated;
set request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000fb"}';
do $$
declare new_id uuid;
begin
  new_id := public.submit_feedback('idea', 'Add budgeting envelopes please.',
    '{}'::jsonb, null, null, 1);
  assert new_id is not null, 'Bob can submit his own feedback';
end $$;
do $$
declare visible int := -1;
begin
  begin
    select count(*) into visible from public.feedback
      where user_id = '00000000-0000-0000-0000-0000000000fa'::uuid;
  exception when others then visible := 0;
  end;
  assert visible = 0, 'Bob must NOT be able to read Alice''s feedback rows';
end $$;
reset role;
reset request.jwt.claims;

-- ============ As owner: Bob's row is stamped with Bob's uid ============
do $$ begin
  assert (select count(*) from public.feedback
            where user_id = '00000000-0000-0000-0000-0000000000fb'::uuid
              and kind = 'idea') = 1,
         'Bob''s feedback is stamped with Bob''s uid';
end $$;

do $$ begin raise notice 'feedback_rls.test.sql: all assertions passed'; end $$;

rollback;
