-- BearFunds edge-function webhooks - MANUAL ops script, NOT a migration.
--
-- Why not a migration: the trigger definitions carry WEBHOOK_SECRET as a literal
-- Bearer token, and secrets never enter the repo or git history. So webhook
-- creation lives here as a documented, repeatable SQL-editor paste instead of in
-- supabase/migrations/. Triggers created this way do NOT appear under
-- Database > Webhooks in the dashboard; they are visible only via pg_trigger.
--
-- When to run:
--   * Bootstrapping a NEW environment (staging, local, rebuilt prod): run PART 1
--     then PART 2.
--   * Rotating WEBHOOK_SECRET: re-run PART 2 only (drops + recreates both
--     triggers with the new token). The function secret must be rotated first:
--       supabase secrets set WEBHOOK_SECRET=<new-value>
--
-- The deployment wrapper replaces <WEBHOOK_SECRET> and <SUPABASE_URL> in a
-- temporary file. Never commit the file with real values in it.
--
-- Verify after running (delivery log):
--   select status_code, left(content, 200) from net._http_response order by id desc limit 5;
--   select tgname, pg_get_triggerdef(oid) from pg_trigger where not tgisinternal;
--
-- Verify the URL substitution survived (2026-08-31: the wrapper's perl used \Q...\E on
-- the replacement side, writing an escaped "https\:\/\/..." into the trigger; pg_net
-- rejected it and every sign-up failed with "Database error saving new user"). The
-- triggerdef above must show a clean URL - no backslashes. Then probe the real path,
-- which exercises BOTH auth.users triggers and keeps nothing:
--   begin;
--   insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
--   values (gen_random_uuid(), '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
--           'probe-' || gen_random_uuid() || '@example.com',
--           '{"full_name":"Probe User"}'::jsonb, now(), now());
--   rollback;

-- ===========================================================================
-- PART 1: supabase_functions schema bootstrap (one-time per environment).
-- The hosted platform normally provisions this at project creation; this
-- project was missing it (webhook creation failed with 3F000 schema
-- "supabase_functions" does not exist). Mirrors the platform's own
-- docker/volumes/db/webhooks.sql from supabase/supabase.
-- ===========================================================================

create extension if not exists pg_net with schema extensions;

create schema if not exists supabase_functions;
grant usage on schema supabase_functions
  to postgres, anon, authenticated, service_role, supabase_auth_admin;

create table if not exists supabase_functions.migrations (
  version text primary key,
  inserted_at timestamptz not null default now()
);

create table if not exists supabase_functions.hooks (
  id bigserial primary key,
  hook_table_id integer not null,
  hook_name text not null,
  created_at timestamptz not null default now(),
  request_id bigint
);

-- supabase_auth_admin is the role GoTrue uses to insert into auth.users; it needs
-- write access to hooks so the send_welcome_email trigger (fires on that insert)
-- does not abort the whole signup transaction with a permission error.
grant insert on supabase_functions.hooks to postgres, anon, authenticated, service_role, supabase_auth_admin;
grant usage, select on sequence supabase_functions.hooks_id_seq to postgres, anon, authenticated, service_role, supabase_auth_admin;

-- RLS is enabled on this table with no policy (deny-all for non-owner roles),
-- which blocks the trigger-firing role's own insert. hooks only stores internal
-- request bookkeeping (table id, hook name, timestamp, pg_net request id), so an
-- open insert policy for the roles that fire these triggers is not a data exposure.
drop policy if exists hooks_insert on supabase_functions.hooks;
create policy hooks_insert on supabase_functions.hooks
  for insert
  to postgres, anon, authenticated, service_role, supabase_auth_admin
  with check (true);

create or replace function supabase_functions.http_request()
returns trigger language plpgsql as $function$
declare
  request_id bigint;
  payload jsonb;
  url text := TG_ARGV[0]::text;
  method text := TG_ARGV[1]::text;
  headers jsonb default '{}'::jsonb;
  params jsonb default '{}'::jsonb;
  timeout_ms integer default 1000;
begin
  if url is null or url = 'null' then raise exception 'url argument is missing'; end if;
  if method is null or method = 'null' then raise exception 'method argument is missing'; end if;
  if TG_ARGV[2] is null or TG_ARGV[2] = 'null' then
    headers = '{"Content-Type": "application/json"}'::jsonb;
  else
    headers = TG_ARGV[2]::jsonb;
  end if;
  if TG_ARGV[3] is not null and TG_ARGV[3] <> 'null' then params = TG_ARGV[3]::jsonb; end if;
  if TG_ARGV[4] is not null and TG_ARGV[4] <> 'null' then timeout_ms = TG_ARGV[4]::integer; end if;
  case
    when method = 'GET' then
      select http_get into request_id from net.http_get(url, params, headers, timeout_ms);
    when method = 'POST' then
      payload = jsonb_build_object(
        'old_record', OLD, 'record', NEW,
        'type', TG_OP, 'table', TG_TABLE_NAME, 'schema', TG_TABLE_SCHEMA
      );
      select http_post into request_id from net.http_post(url, payload, params, headers, timeout_ms);
    else
      raise exception 'method argument % is invalid', method;
  end case;
  insert into supabase_functions.hooks (hook_table_id, hook_name, request_id)
    values (TG_RELID, TG_NAME, request_id);
  return NEW;
end
$function$;

-- ===========================================================================
-- PART 2: the two BearFunds webhook triggers. Safe to re-run (drop + create).
-- Both functions verify Authorization: Bearer <WEBHOOK_SECRET> against the
-- WEBHOOK_SECRET function secret; a mismatch returns 401 and pg_net retries.
-- ===========================================================================

-- Feedback -> admin notification email (functions/send-feedback-notification).
drop trigger if exists feedback on public.feedback;
create trigger feedback
after insert on public.feedback
for each row
execute function supabase_functions.http_request(
  '<SUPABASE_URL>/functions/v1/send-feedback-notification',
  'POST',
  '{"Content-type":"application/json","Authorization":"Bearer <WEBHOOK_SECRET>"}',
  '{}',
  '5000'
);

-- Signup -> welcome email (functions/send-welcome-email).
drop trigger if exists send_welcome_email on auth.users;
create trigger send_welcome_email
after insert on auth.users
for each row
execute function supabase_functions.http_request(
  '<SUPABASE_URL>/functions/v1/send-welcome-email',
  'POST',
  '{"Content-type":"application/json","Authorization":"Bearer <WEBHOOK_SECRET>"}',
  '{}',
  '5000'
);
