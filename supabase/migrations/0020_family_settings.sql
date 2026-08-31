-- BearFunds server - Schema Contract v1.24 (forward-only, additive).
-- Adds FAMILY_SETTINGS: the family's shared, user-facing settings - its name, its picture, its plan
-- and the date format everyone in it reads. Until now none of these synced at all: FamilyProfile is
-- a client-local singleton and 'profile' mutations are never pushed, so a family NAME set on one
-- device has never reached another member. That is the gap this closes (brain [BF-Q103]).
--
-- THIS TABLE CARRIES NO `enc` ENVELOPE, AND IT IS THE FIRST ONE ADDED SINCE RLE THAT DOES NOT.
-- The test every table has been held to is "does anything on this row describe the family's money or
-- its people". Migration 0017 dropped five plaintext columns from budgets because a period range
-- publishes a family's holiday dates; 0018 made import_mappings pure enc because a bank's column
-- headers describe the account. Applied here the answer is no, four times, and each for its own
-- reason (operator decision, 2026-08-19):
--
--   family_name   Already plaintext on the tenancy root today, and peek_invite hands it to a joiner
--                 who is NOT YET A MEMBER and holds no family key at all. Encrypting it would make
--                 it unreadable to precisely the person it exists for.
--   family_photo  One of four BUNDLED ASSET PATHS. The client's picker is fed a fixed list and there
--                 is no upload path, no data URL and no storage bucket anywhere in it, so the value
--                 is a choice from a shipped set rather than user imagery.
--   plan_type     MUST stay server-readable. It is a stub today, carrying the constant 'Alpha Test',
--                 and it will carry feature controls and analytics - a server that cannot read a
--                 plan cannot gate a feature on it, so encoding it would have to be undone the
--                 moment it means anything.
--   date_format   Not PII, and knowing which conventions families choose is useful product insight.
--                 Hiding a display preference costs that and buys no privacy.
--
-- Categories, subcategories and members are already plaintext by the same test, so this is the house
-- rule rather than an exception: encrypt what describes the family, publish what describes the app.
--
-- WHAT IS DELIBERATELY ABSENT: a week-start column. The client's QA Area 005 "Week Start" states the
-- convention is not user-configurable, because a Budget's anchor is PERSISTED and two devices
-- disagreeing would write different anchors for one plan. It joins as a column when that rule
-- changes, in the same slice that changes it.
--
-- NO SETTINGS ROW IS SEEDED AT SIGN-UP, deliberately. handle_new_user already creates the family and
-- its admin member and is revised through three later migrations; adding a fourth responsibility to
-- it to save one client upsert is the wrong trade. A family simply has no settings row until it
-- writes one, and peek_invite below falls back to families.name for exactly that window.
--
-- Tenancy invariants (0_AI_INSTRUCTIONS.md, brain QA Areas 008/019): server-derived family_id,
-- server-managed updated_at, explicit RLS family isolation. The trigger and policy loops in
-- 0001/0002 are HARDCODED arrays that exclude this table, so everything is wired explicitly below
-- (as budgets did in 0016 and import_mappings in 0018).
--
-- Forward-only, additive, non-destructive: no existing table or column is touched. The tenancy root
-- is NOT made writable - families keeps its select-only grant, and the live family name lives here.

-- 1. New tenant table: family_settings. One row per family.
--    PRIMARY KEY (family_id, id) inline, per migration 0009: every family uses the SAME fixed id
--    ('family-settings'), so a global `id` PK would make the second family collide into an
--    RLS-denied upsert. This table is the clearest case of that hazard yet - the id is not merely
--    often shared, it is shared by construction.
create table if not exists public.family_settings (
  id            text not null,
  family_id     uuid not null references public.families(id) on delete cascade,
  family_name   text,
  family_photo  text,
  plan_type     text,
  date_format   text,
  updated_at    timestamptz not null default now(),
  deleted       boolean not null default false,
  is_immutable  boolean not null default false,
  primary key (family_id, id)
);

-- Delta-sync read path: read(since) filters family_id + updated_at.
create index if not exists family_settings_family_updated_idx
  on public.family_settings (family_id, updated_at);

-- 2. Shared triggers: server-managed updated_at + server-derived family_id.
--    Without set_updated_at the delta sync would SILENTLY drop every edit - updated_at would never
--    move, so `read since` would never return the row again.
create trigger family_settings_set_updated_at before insert or update on public.family_settings
  for each row execute function public.set_updated_at();
create trigger family_settings_set_family_id before insert or update on public.family_settings
  for each row execute function public.set_family_id();

-- 3. Grants + RLS family isolation (mirrors migration 0002 for every tenant table).
grant select, insert, update, delete on public.family_settings to authenticated;
alter table public.family_settings enable row level security;
create policy family_settings_family_isolation on public.family_settings
  for all to authenticated
  using (family_id = public.auth_family_id())
  with check (family_id = public.auth_family_id());

-- 4. Re-register the table in the family high-water mark.
--    THE SILENT BREAK THIS GUARDS (0016, 0018): family_version() is a hardcoded union per tenant
--    table. Leave family_settings out and nothing errors - the `version` probe just returns a stale
--    timestamp, so a device whose ONLY change is a renamed family or a switched date format is told
--    "nothing changed" and never syncs. Pinned by an assertion in rls_isolation.test.sql.
create or replace function public.family_version()
  returns timestamptz
  language sql
  stable
  security invoker
  set search_path = public
as $$
  select max(v) from (
    select max(updated_at) as v from public.transactions        where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.categories          where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.subcategories       where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.accounts             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.entities            where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.members             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.staged_transactions where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.budgets             where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.import_mappings     where family_id = public.auth_family_id()
    union all select max(updated_at)  from public.family_settings     where family_id = public.auth_family_id()
  ) s;
$$;

grant execute on function public.family_version() to authenticated;

-- 5. peek_invite reads the LIVE family name.
--    THE DISCLOSURE IS UNCHANGED IN KIND AND IN AMOUNT - still the family display name and the
--    invite role, still only for a valid pending token, still SECURITY DEFINER because the joiner is
--    not a member yet and RLS would hide both rows. What changes is WHICH name: families.name is the
--    sign-up default and never moves again, so without this a family that renamed itself would
--    introduce itself to new members by its old name.
--
--    LEFT JOIN + coalesce, because a family that has not written settings yet has no row here. A
--    plain join would return NO ROWS for that family, which the client reads as an invalid token -
--    turning a missing optional row into a broken invite.
create or replace function public.peek_invite(p_token text)
  returns table(family_name text, invite_role text)
  language sql
  stable
  security definer
  set search_path = public, auth
as $fn$
  select coalesce(nullif(fs.family_name, ''), f.name), i.role
  from public.invites i
  join public.families f on f.id = i.family_id
  left join public.family_settings fs
    on fs.family_id = i.family_id and fs.deleted = false
  where i.token = p_token
    and i.status = 'pending'
    and i.expires_at > now();
$fn$;

grant execute on function public.peek_invite(text) to authenticated;
