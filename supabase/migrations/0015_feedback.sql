-- BearFunds server - in-app tester feedback (Area 029, forward-only, additive).
-- Destination for the in-app feedback button raised in the alpha first-testers
-- call (brain [[Feature Backlog]] 2026-07-06).
--
-- CONTROL-PLANE, NOT THE SYNC CONTRACT. Like invites (0007) and analytics_events
-- (0014), feedback is out-of-band: it is NOT a synced/Dexie collection, it is
-- written through a SECURITY DEFINER RPC (public.submit_feedback), NOT the single
-- POST action endpoint, and 2_SCHEMA_CONTRACT.xml is UNCHANGED (no version bump).
--
-- INGEST IS RPC-ONLY (mirrors analytics 0014). The client cannot touch the table
-- directly: authenticated gets EXECUTE on submit_feedback ONLY (no table grants at
-- all). The operator reads rows out-of-band (service_role / SQL editor), joining
-- auth.users for the reporter email.
--
-- Privacy / tenancy invariants (0_AI_INSTRUCTIONS.md, brain QA Areas 008/019):
--   * user_id is SERVER-DERIVED inside submit_feedback (auth.uid()); there is no
--     client-supplied identity parameter. Never trust a client identity.
--   * NO grant to authenticated on the table (no select/insert/update/delete). RLS
--     is enabled with NO permissive policy, so any accidental future grant still
--     denies all. Only service_role (bypassrls) and the definer RPC (owner) reach
--     the rows.
--   * message is user-authored free text BY DESIGN (unlike content-free analytics);
--     it is the tester's own words. context is opaque jsonb (content-free device
--     facts assembled client-side: app_version, platform, viewport, route).
--   * received_at (server clock) is the authoritative UTC ordering; client_ts + tz
--     derive user-local wall-clock.

create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null check (kind in ('bug','idea','other')),
  message     text not null check (char_length(message) between 1 and 4000),
  context     jsonb not null default '{}'::jsonb,
  client_ts   timestamptz,
  tz          text,
  received_at timestamptz not null default now(),
  sv          int not null default 1
);

create index if not exists feedback_received_at_idx
  on public.feedback (received_at);

-- Supabase auto-grants table privileges to anon/authenticated via ALTER DEFAULT
-- PRIVILEGES on public (every new public table). Revoke them so the table is truly
-- RPC-only: belt (no table privilege) AND suspenders (RLS deny-all). service_role
-- keeps its access for triage; the SECURITY DEFINER RPC (owner) writes.
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    revoke all on public.feedback from authenticated;
  end if;
  if exists (select 1 from pg_roles where rolname = 'anon') then
    revoke all on public.feedback from anon;
  end if;
end $$;

-- RLS enabled with NO policy: authenticated has no table grant and no policy, so it
-- can never reach the table directly (deny-all backstop). service_role bypasses RLS
-- for triage; the SECURITY DEFINER RPC below writes as the table owner.
alter table public.feedback enable row level security;

-- submit_feedback(...): the ONLY write path for authenticated users. Stamps user_id
-- from the session (auth.uid()), NEVER from a payload; validates kind + message.
-- Returns the new row id. Mirrors the invites / analytics SECURITY DEFINER pattern.
create or replace function public.submit_feedback(
  p_kind      text,
  p_message   text,
  p_context   jsonb   default '{}'::jsonb,
  p_client_ts timestamptz default null,
  p_tz        text    default null,
  p_sv        int     default 1
)
  returns uuid
  language plpgsql
  security definer
  set search_path = public
as $fn$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
begin
  if v_uid is null then
    raise exception 'authentication required';
  end if;
  if p_kind is null or p_kind not in ('bug','idea','other') then
    raise exception 'invalid feedback kind';
  end if;
  if p_message is null or char_length(btrim(p_message)) = 0 then
    raise exception 'feedback message required';
  end if;
  if char_length(p_message) > 4000 then
    raise exception 'feedback message too long';
  end if;

  insert into public.feedback (user_id, kind, message, context, client_ts, tz, sv)
  values (
    v_uid,
    p_kind,
    p_message,
    coalesce(p_context, '{}'::jsonb),
    p_client_ts,
    p_tz,
    coalesce(p_sv, 1)
  )
  returning id into v_id;

  return v_id;
end;
$fn$;

grant execute on function
  public.submit_feedback(text, text, jsonb, timestamptz, text, int)
  to authenticated;
