-- 0019: opaque analytics identity keys (forward-only, additive except the user_id drop).
--
-- WHY THIS EXISTS. Telemetry needed a family dimension so a funnel can follow one
-- household rather than one person. The obvious shape - a family_id foreign key - is
-- wrong here, and so was the shape already in the tree for users:
--
--   * join_family HARD-DELETES the caller's family whenever they were its sole member
--     (0007 lines 159-165), which is every ordinary invitee. An FK with `on delete set
--     null` or `on delete cascade` would therefore erase the family dimension on the
--     ROUTINE path, for exactly the cohort whose behaviour explains the departure.
--   * analytics_events.user_id was `references auth.users on delete cascade` (0014), so
--     deleting a person deleted the evidence of what led them to leave. Erasure should
--     remove the IDENTITY, not the behaviour.
--
-- THE SHAPE. analytics_events carries OPAQUE KEYS, never foreign keys. Two bridge
-- tables are the only link between a real entity and its telemetry:
--
--   analytics_users     user_id   -> user_key
--   analytics_families  family_id -> family_key
--
-- Deleting a user or a family cascades away its BRIDGE ROW. The events keep their key,
-- so the grouping survives while the link to a person or a household is gone. That is
-- also the pseudonymous analytics id the taxonomy deferred on 2026-07-04: after this
-- migration the whole telemetry store is detachable from accounts by construction.
--
-- This is the codebase's existing convention, not a new one: members.user_id,
-- invites.created_by and invites.redeemed_by are all `on delete set null`. Sever the
-- identity, keep the row. analytics_events and feedback were the two tables that broke
-- it; feedback is deliberately NOT changed here (free text is genuinely personal and
-- arguably SHOULD be deleted outright - a different question, not this one).
--
-- NAMING RULE: `_id` is a real entity id and may be a foreign key. `_key` is an opaque
-- analytics key and is never a foreign key. The distinction is greppable on purpose.
--
-- Still out-of-band: no Schema Contract change, no version bump, no wire union entry.
-- The client is UNCHANGED and sv stays 1 - it never sent an identity and still does not.

-- ===========================================================================
-- 1. The bridges. Each is the ONLY link between an entity and its telemetry.
-- ===========================================================================
create table if not exists public.analytics_users (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  user_key   uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);

create table if not exists public.analytics_families (
  family_id  uuid primary key references public.families(id) on delete cascade,
  family_key uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now()
);

-- ===========================================================================
-- 2. The tombstone. Keyed on the OPAQUE key, with no FK, so it outlives the bridge
-- it describes - a tombstone that died with its subject would be no tombstone.
--
-- `reason` is the column that matters most. Most family deletions in this system are
-- an invitee folding their throwaway solo family into a real household, which is a
-- SUCCESSFUL ACTIVATION. Without a reason every one of those reads as a family that
-- vanished, and a churn metric would be dominated by its own opposite.
--
-- The check admits only what is actually written today. Adding a reason (account
-- closure, admin purge) is a one-line forward migration at the point the path that
-- writes it is built - not a speculative member sitting here unwritten.
-- ===========================================================================
create table if not exists public.analytics_family_tombstones (
  family_key uuid primary key,
  deleted_at timestamptz not null default now(),
  reason     text not null check (reason in ('joined_another_family'))
);

-- ===========================================================================
-- 3. Same access stance as analytics_events: RLS enabled with NO permissive policy,
-- and Supabase's ALTER DEFAULT PRIVILEGES grants revoked. Belt and suspenders - no
-- table privilege AND no policy - so a future accidental grant still denies all.
-- Only service_role (bypassrls) reads; the definer functions below write.
-- ===========================================================================
do $$
declare t text;
begin
  foreach t in array array['analytics_users','analytics_families','analytics_family_tombstones']
  loop
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
      execute format('revoke all on public.%I from authenticated', t);
    end if;
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute format('revoke all on public.%I from anon', t);
    end if;
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- ===========================================================================
-- 4. Mint-or-return accessors. Both mirror ensure_test_family()'s race handling:
-- insert ... on conflict do nothing, then RE-READ, so a concurrent first ingest that
-- won the race hands back its key rather than a null.
--
-- Neither is granted to authenticated. They are internal: only ingest_events and
-- join_family call them, and both of those are SECURITY DEFINER.
-- ===========================================================================
create or replace function public.ensure_analytics_user_key()
  returns uuid
  language plpgsql
  security definer
  set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_key uuid;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  select user_key into v_key from public.analytics_users where user_id = v_uid;
  if v_key is not null then
    return v_key;
  end if;

  insert into public.analytics_users (user_id) values (v_uid)
    on conflict (user_id) do nothing;

  select user_key into v_key from public.analytics_users where user_id = v_uid;
  return v_key;
end;
$fn$;

-- NULL in, NULL out. The caller has no family during the join_family window (0007
-- deletes the members row before inserting the new one, and says so in its own
-- comment), and that window must stay ingestible - see the note in ingest_events.
create or replace function public.ensure_analytics_family_key(p_family_id uuid)
  returns uuid
  language plpgsql
  security definer
  set search_path = public
as $fn$
declare v_key uuid;
begin
  if p_family_id is null then
    return null;
  end if;

  select family_key into v_key from public.analytics_families where family_id = p_family_id;
  if v_key is not null then
    return v_key;
  end if;

  insert into public.analytics_families (family_id) values (p_family_id)
    on conflict (family_id) do nothing;

  select family_key into v_key from public.analytics_families where family_id = p_family_id;
  return v_key;
end;
$fn$;

revoke all on function public.ensure_analytics_user_key() from public;
revoke all on function public.ensure_analytics_family_key(uuid) from public;

-- ===========================================================================
-- 5. record_family_deletion: write the tombstone BEFORE the family row goes.
--
-- A family that never emitted telemetry has no bridge row and gets no tombstone -
-- minting one here would invent a grouping that never existed and put a row in the
-- churn table for a household that never appears in the events beside it.
-- ===========================================================================
create or replace function public.record_family_deletion(p_family_id uuid, p_reason text)
  returns void
  language plpgsql
  security definer
  set search_path = public
as $fn$
declare v_key uuid;
begin
  if p_family_id is null then
    return;
  end if;

  select family_key into v_key from public.analytics_families where family_id = p_family_id;
  if v_key is null then
    return;
  end if;

  insert into public.analytics_family_tombstones (family_key, reason)
    values (v_key, p_reason)
    on conflict (family_key) do nothing;
end;
$fn$;

revoke all on function public.record_family_deletion(uuid, text) from public;

-- ===========================================================================
-- 6. analytics_events: opaque keys in, user_id out.
--
-- Order is load-bearing: add nullable -> mint bridges for every existing user ->
-- backfill -> REFUSE to continue if anything is unmapped -> set not null -> drop.
-- The refusal is the point. A backfill that silently left rows unmapped would produce
-- a column that is NOT NULL by luck, and the failure would surface much later as a
-- funnel quietly missing its oldest cohort.
--
-- No family_key backfill: we cannot know which family an old event belonged to, and
-- deriving it from the CURRENT members row would assert something false for anyone who
-- has since joined a household. NULL is the honest value for "not recorded".
-- ===========================================================================
alter table public.analytics_events add column if not exists user_key   uuid;
alter table public.analytics_events add column if not exists family_key uuid;

do $$
declare v_unmapped int;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'analytics_events' and column_name = 'user_id'
  ) then
    insert into public.analytics_users (user_id)
      select distinct e.user_id from public.analytics_events e where e.user_id is not null
      on conflict (user_id) do nothing;

    update public.analytics_events e
      set user_key = au.user_key
      from public.analytics_users au
      where au.user_id = e.user_id and e.user_key is null;

    select count(*) into v_unmapped from public.analytics_events where user_key is null;
    if v_unmapped > 0 then
      raise exception 'backfill left % analytics_events row(s) with no user_key', v_unmapped;
    end if;

    alter table public.analytics_events drop column user_id;
  end if;
end $$;

alter table public.analytics_events alter column user_key set not null;

create index if not exists analytics_events_user_key_idx   on public.analytics_events (user_key);
create index if not exists analytics_events_family_key_idx on public.analytics_events (family_key);

-- ===========================================================================
-- 7. ingest_events: stamps BOTH keys server-side. A client-supplied user_key or
-- family_key in the payload is ignored, exactly as a client-supplied user_id was.
-- ===========================================================================
create or replace function public.ingest_events(p_rows jsonb)
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_ukey  uuid;
  v_fkey  uuid;
  v_count int;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  v_ukey := public.ensure_analytics_user_key();

  -- NULL when the caller has no members row - the join_family window. This MUST stay
  -- ingestible: raising here would make the client's drainOnce catch, RETAIN the batch
  -- and re-peek the same FIFO head on every later trigger, so one poison batch would
  -- block that user's entire analytics stream until the 1000-event cap evicted it.
  v_fkey := public.ensure_analytics_family_key(public.auth_family_id());

  insert into public.analytics_events (user_key, family_key, idk, e, client_ts, tz, props, sv)
  select
    v_ukey,
    v_fkey,
    (r->>'idk')::uuid,
    r->>'e',
    (r->>'client_ts')::timestamptz,
    r->>'tz',
    coalesce(r->'props', '{}'::jsonb),
    (r->>'sv')::int
  from jsonb_array_elements(p_rows) as r
  on conflict (idk) do nothing;

  get diagnostics v_count = row_count;
  return v_count;
end;
$fn$;

grant execute on function public.ingest_events(jsonb) to authenticated;

-- ===========================================================================
-- 8. join_family, replaced whole (migrations are forward-only; 0007 is not edited).
-- The ONLY change is the record_family_deletion call marked below, immediately before
-- the teardown, inside the same transaction - so a tombstone fault rolls the whole join
-- back rather than leaving a member re-homed with no record of where they came from.
-- ===========================================================================
create or replace function public.join_family(
    p_token  text,
    p_name   text default null,
    p_avatar text default null)
  returns uuid
  language plpgsql
  security definer
  set search_path = public, auth
as $fn$
declare
  v_uid           uuid := auth.uid();
  v_inv           public.invites%rowtype;
  v_target        uuid;
  v_caller_family uuid;
  v_caller_count  int;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  -- Lock the invite row so a concurrent redeem cannot double-spend it.
  select * into v_inv
  from public.invites
  where token = p_token
  for update;

  if not found or v_inv.status <> 'pending' or v_inv.expires_at <= now() then
    raise exception 'invalid or expired invite';
  end if;
  v_target := v_inv.family_id;

  -- Idempotent: already a member of the target family -> redeem (if still pending) + return.
  if exists (
    select 1 from public.members
    where user_id = v_uid and family_id = v_target and deleted = false
  ) then
    update public.invites
      set status = 'redeemed', redeemed_by = v_uid, redeemed_at = now()
      where id = v_inv.id and status = 'pending';
    return v_target;
  end if;

  -- The caller's current (throwaway) family, and whether they are its sole member.
  select family_id into v_caller_family
  from public.members
  where user_id = v_uid
  limit 1;

  select count(*) into v_caller_count
  from public.members
  where family_id = v_caller_family;

  -- Free the unique user_id (members.user_id is UNIQUE) before the new insert.
  -- This also drops auth_family_id() to NULL, so set_family_id() keeps the explicit
  -- target family_id on the insert below (same bootstrap path handle_new_user uses).
  delete from public.members where user_id = v_uid;

  -- Teardown the throwaway family ONLY if the caller was its sole member (data-loss
  -- guard: never delete a populated/shared family). Cascades any seeded rows.
  if v_caller_family is not null
     and v_caller_family <> v_target
     and v_caller_count = 1 then
    -- 0019: record WHY before the row goes. This deletion is an activation, not churn.
    perform public.record_family_deletion(v_caller_family, 'joined_another_family');
    delete from public.families where id = v_caller_family;
  end if;

  -- Create the fresh member in the invite's family. Columns mirror handle_new_user
  -- (members.is_me was dropped in 0004; Me is derived from user_id).
  insert into public.members (id, family_id, user_id, name, role, avatar)
  values (
    'm_' || replace(v_uid::text, '-', ''),
    v_target,
    v_uid,
    coalesce(nullif(p_name, ''), 'Member'),
    v_inv.role,
    nullif(p_avatar, '')
  );

  update public.invites
    set status = 'redeemed', redeemed_by = v_uid, redeemed_at = now()
    where id = v_inv.id;

  return v_target;
end;
$fn$;
