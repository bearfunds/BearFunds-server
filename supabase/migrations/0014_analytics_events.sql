-- BearFunds server - usage analytics events (Slice 2, forward-only, additive).
-- Product-telemetry destination for the first-party analytics effort
-- (brain [[Plan - Usage Analytics]] / [[Plan - Usage Analytics Slice 2 (Destination + Flush)]]).
--
-- CONTROL-PLANE, NOT THE SYNC CONTRACT. Like invites (0007), analytics_events is
-- out-of-band: it is NOT a synced/Dexie collection, it is written through a
-- SECURITY DEFINER RPC (public.ingest_events), NOT the single POST action
-- endpoint, and 2_SCHEMA_CONTRACT.xml is UNCHANGED (no version bump).
--
-- INGEST IS RPC-ONLY (decided 2026-07-04). The client cannot write the table
-- directly: a plain `INSERT ... ON CONFLICT DO NOTHING` under RLS needs the
-- conflicting row to be readable, which would force a SELECT grant and break the
-- least-visibility stance. Instead authenticated gets EXECUTE on ingest_events
-- ONLY (no table grants at all), mirroring the invites control-plane RPCs.
--
-- Privacy / tenancy invariants (0_AI_INSTRUCTIONS.md, brain QA Areas 008/019/028):
--   * user_id is SERVER-DERIVED inside ingest_events (auth.uid()); a client-supplied
--     user_id in the payload is ignored. Never trust a client identity.
--   * NO grant to authenticated on the table (no select/insert/update/delete). RLS
--     is enabled with NO permissive policy, so any accidental future grant still
--     denies all. Only service_role (bypassrls) and a future Slice-4 read see rows;
--     the definer RPC (owner) writes.
--   * Content-free is enforced CLIENT-SIDE (brain taxonomy); props is opaque jsonb.
--   * received_at (server clock) is the authoritative UTC ordering; client_ts + tz
--     derive user-local wall-clock and expose device-clock skew.
--   * idk is the at-least-once dedup key (unique); ingest_events upserts
--     on conflict (idk) do nothing, so a retried batch is harmless.

create table if not exists public.analytics_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  idk         uuid not null unique,
  e           text not null,
  client_ts   timestamptz not null,
  tz          text not null,
  received_at timestamptz not null default now(),
  props       jsonb not null default '{}'::jsonb,
  sv          int not null
);

create index if not exists analytics_events_received_at_idx
  on public.analytics_events (received_at);

-- Supabase auto-grants table privileges to anon/authenticated via ALTER DEFAULT
-- PRIVILEGES on public (every new public table). Revoke them so the table is truly
-- RPC-only: belt (no table privilege) AND suspenders (RLS deny-all). service_role
-- keeps its access for analysis; the SECURITY DEFINER RPC (owner) writes.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on public.analytics_events from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on public.analytics_events from anon;
  end if;
end $$;

-- RLS enabled with NO policy: authenticated has no table grant and no policy, so
-- it can never reach the table directly (deny-all backstop). service_role bypasses
-- RLS for analysis; the SECURITY DEFINER RPC below writes as the table owner.
alter table public.analytics_events enable row level security;

-- ingest_events(p_rows): the ONLY write path for authenticated users. Stamps
-- user_id from the session (auth.uid()), NEVER from the payload; dedups on idk.
-- Returns the number of rows actually inserted (dups ignored). Mirrors the invites
-- SECURITY DEFINER RPC pattern (0007).
create or replace function public.ingest_events(p_rows jsonb)
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $fn$
declare
  v_uid   uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;

  insert into public.analytics_events (user_id, idk, e, client_ts, tz, props, sv)
  select
    v_uid,
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

-- Retention: 6-month purge. Plain SECURITY DEFINER function (sandbox-testable);
-- scheduling attached below only where pg_cron exists.
create or replace function public.purge_old_analytics_events()
  returns integer
  language plpgsql
  security definer
  set search_path = public
as $fn$
declare
  v_rows int;
begin
  delete from public.analytics_events
    where received_at < now() - interval '6 months';
  get diagnostics v_rows = row_count;
  return v_rows;
end;
$fn$;

-- Schedule the nightly purge via pg_cron WHERE AVAILABLE. Guarded so stock Postgres
-- (the sandbox test harness) is a no-op; on Supabase (pg_cron available) it installs
-- the extension and a daily job. Fallback if pg_cron is not enabled on the project:
-- a Supabase scheduled Edge Function calling purge_old_analytics_events().
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule(
      'purge-analytics-events',
      '30 3 * * *',
      $cron$ select public.purge_old_analytics_events(); $cron$
    );
  end if;
end $$;
