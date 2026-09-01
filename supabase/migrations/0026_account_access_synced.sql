-- ===========================================================================
-- 0026: the grant plane moves onto the SYNC plane (forward-only).
--
-- WHAT CHANGES. account_access stops being an RPC-mutated control table and
-- becomes an ordinary tenant collection: id, deleted, updated_at, the two
-- shared triggers, and an admin-scoped policy that governs writes as well as
-- reads. grant_account_access and revoke_account_access are DROPPED. An admin
-- now shares an account by writing a row locally, and it reaches the server
-- through the same outbox as every other edit she makes.
--
-- WHY, AND IT REVERSES D2 OF MIGRATION 0023 DELIBERATELY (operator, 2026-08-24).
-- Every other admin action in this app - rename an account, add a member,
-- retire a category - is a local write that syncs whenever. Sharing was the
-- only one that demanded connectivity at the instant of Save and failed with a
-- raw server error under the field. The delivery half already lives on the sync
-- plane (scope_version, 0025), so the two halves of one feature sat in two
-- architectures for a reason no user would recognise.
--
-- D2's OBJECTION IS REAL AND IS ANSWERED RATHER THAN DENIED. A synced grant row
-- merges last-write-wins, so a revocation can lose a race to a stale device
-- re-pushing an older grant. Four things bound that: this model is explicitly a
-- TRUST boundary and not a security one (0023 header, and the plan's "what the
-- copy may and may not claim"); LWW is how every other row in this system
-- already behaves; co-equal admins are out of scope for the alpha, so the race
-- has no instances; and everything the RPC enforced has moved to the write path
-- rather than being dropped - the admin check into the policy, the
-- server-derived granter into a trigger, the scope bump into a trigger.
--
-- THE FORCING SYMPTOM, measured 2026-08-24. A grant could not be test-family
-- scoped: grant_account_access resolves auth_family_id(), which routes to the
-- test family only when is_test_request() sees the x-bf-test header, and that
-- header is SERVER-SET by the Edge Function (_shared/http.ts testScopedClient)
-- so a browser client cannot send it. In test mode the RPC therefore resolved
-- the REAL family while the ids on screen were test-family rows, and every save
-- failed with 'no such account in this family'. Riding the action endpoint puts
-- the grant in the same test context as every other row.
--
-- ---------------------------------------------------------------------------
-- FOUR DECISIONS, each recorded because the alternative is live.
--
-- E1. THE ID IS DETERMINISTIC: '<account_id>__<member_id>'. Two admins granting
--     the same pair while offline mint the SAME row rather than two, so the
--     pair converges under LWW instead of duplicating. import_mappings (0018)
--     refused a deterministic id because a digest of a low-entropy header would
--     publish the shape of a family's bank file; nothing is disclosed here,
--     because both halves of this id are already plaintext columns ON the row
--     it names. The client derives it, and a client guard pins the derivation.
--
-- E2. THE EXISTENCE CHECKS ARE GONE, AND A DANGLING GRANT IS INERT RATHER THAN
--     REFUSED. The RPC raised when the account or the member was not in the
--     caller's family. On a batch endpoint a raise is the 2026-08-19 shape: one
--     bad row takes the whole batchUpsert and with it the entire sync. So the
--     row is written and confers nothing - family_id is server-derived, so a
--     grant can only ever name an id inside the caller's own family, and an id
--     no account there carries resolves to nothing through can_see_account.
--     The client already reconciles orphans out of what it renders
--     (accessModel.visibleGrantedAccountIds), for the same reason and since
--     0023: this table has no foreign keys.
--
-- E3. REVOCATION IS A SOFT DELETE. A hard delete leaves no tombstone, a delta
--     read is `updated_at > since`, and a row that is simply absent is
--     indistinguishable from one that has not changed - so a second admin
--     device would never learn the grant had been withdrawn. `deleted` is what
--     makes a withdrawal deliverable at all. can_see_account and
--     visible_account_ids therefore filter it, and that filter is the whole
--     security content of this migration: without it a tombstone still grants.
--
-- E4. THE BUMP MOVES FROM A FUNCTION BODY INTO A TRIGGER, AND THE
--     DISCRIMINATOR HAD TO MOVE WITH IT. 0025 bumped scope_version only when
--     FOUND said a real change had happened, because the client answers a bump
--     by DELETING local rows. A trigger has no FOUND: it fires on every INSERT
--     and every UPDATE, including the ordinary ON CONFLICT DO UPDATE the client
--     emits for an UNCHANGED row on every single push. An unconditional trigger
--     would therefore evict a member on routine traffic. The WHEN clauses below
--     are that discrimination, and the suite asserts all four arms.
--
-- ---------------------------------------------------------------------------
-- NOT DESTRUCTIVE, AND IT DID NOT NEED TO BE. Existing grant rows are carried
-- forward: the id is populated from the pair they already hold, which is the
-- same value the client would mint for them. The pre-alpha permission to scrap
-- test data was available and is deliberately not spent - a reshape that keeps
-- its rows needs no argument about who might be holding them.
--
-- DEPLOY ORDER IS UNCHANGED AND ABSOLUTE: this migration, then the v1.28 client.
-- A pre-v1.28 client never names ACCOUNT_ACCESS, so it is unaffected by this
-- running early. A v1.28 client against a pre-0026 server names a table the
-- seam does not know, and validation.ts throws on an unknown table, which
-- aborts the client's ENTIRE pull rather than one collection.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Reshape the table into the tenant shape every synced collection uses.
--    PRIMARY KEY (family_id, id) per 0009: families seed identical fixed ids,
--    so a global id PK collides across tenants.
-- ---------------------------------------------------------------------------
alter table public.account_access add column if not exists id           text;
alter table public.account_access add column if not exists deleted      boolean not null default false;
alter table public.account_access add column if not exists updated_at   timestamptz not null default now();
alter table public.account_access add column if not exists is_immutable boolean not null default false;

update public.account_access
   set id = account_id || '__' || member_id
 where id is null;

alter table public.account_access alter column id set not null;

alter table public.account_access drop constraint if exists account_access_pkey;
alter table public.account_access add primary key (family_id, id);

-- THE PAIR STAYS UNIQUE, AND THIS IS THE ONE PLACE A REFUSAL IS WORTH ITS COST.
-- E2 removes the checks that raise on ROUTINE input; this one can only fire on a
-- client that minted an id not derived from the pair, which no code path does.
-- What it prevents is two rows for one pair disagreeing on `deleted` - and since
-- can_see_account asks EXISTS, the live one would win and a revocation would
-- silently not take. On a permission table a loud failure beats a quiet
-- disclosure, which is the opposite trade from E2 and is why both are written down.
create unique index if not exists account_access_pair_idx
  on public.account_access (family_id, account_id, member_id);

-- Delta-sync read path: read(since) filters family_id + updated_at.
create index if not exists account_access_family_updated_idx
  on public.account_access (family_id, updated_at);

comment on table public.account_access is
  'An admin has granted one member sight of one account. Since 0026 this is an ordinary '
  'synced collection: the admin writes it locally and it arrives through the action endpoint '
  'like any other row. Revocation is a SOFT delete, because a delta read cannot express a row '
  'that is simply gone. granted_by_member_id and family_id are server-derived; scope_version '
  'is bumped by trigger on a real change only.';

-- ---------------------------------------------------------------------------
-- 2. The shared triggers. Without set_updated_at the delta sync would SILENTLY
--    drop every grant - updated_at would never move, so `read since` would
--    never return the row again.
-- ---------------------------------------------------------------------------
drop trigger if exists account_access_set_updated_at on public.account_access;
create trigger account_access_set_updated_at before insert or update on public.account_access
  for each row execute function public.set_updated_at();

drop trigger if exists account_access_set_family_id on public.account_access;
create trigger account_access_set_family_id before insert or update on public.account_access
  for each row execute function public.set_family_id();

-- ---------------------------------------------------------------------------
-- 3. granted_by_member_id is SERVER-DERIVED and WRITE-ONCE, exactly as
--    created_by is (0024) and for the same two reasons: a client value would be
--    a claim about identity, and a trigger that RAISED on an attempted change
--    would turn one row into a failed batch. The update arm restores the old
--    value silently instead. The client cannot send the column anyway - it is
--    in STRIPPED_KEYS - and a strip DROPS where a non-writable key REJECTS.
--
--    UNCONDITIONAL on insert. 0024's first draft wrote
--    coalesce(new.created_by, auth_member_id()) and its control caught it: a
--    supplied value SURVIVED. A server-derived column that honours a client
--    value is not server-derived.
--
--    The zz_ prefix sorts it after account_access_set_family_id, and Postgres
--    fires per-row triggers in NAME order.
-- ---------------------------------------------------------------------------
create or replace function public.set_granted_by()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, auth
as $$
begin
  new.granted_by_member_id := public.auth_member_id();
  return new;
end;
$$;

create or replace function public.preserve_granted_by()
  returns trigger
  language plpgsql
as $$
begin
  new.granted_by_member_id := old.granted_by_member_id;
  return new;
end;
$$;

drop trigger if exists zz_account_access_set_granted_by on public.account_access;
create trigger zz_account_access_set_granted_by before insert on public.account_access
  for each row execute function public.set_granted_by();

drop trigger if exists zz_account_access_preserve_granted_by on public.account_access;
create trigger zz_account_access_preserve_granted_by before update on public.account_access
  for each row execute function public.preserve_granted_by();

-- ---------------------------------------------------------------------------
-- 4. The scope_version bump (E4). SECURITY DEFINER because the caller's own RLS
--    on `members` is not what should decide whether a scope change is recorded,
--    and because that is what the RPC it replaces did.
--
--    THERE IS NO DELETE ARM, DELIBERATELY. The sync plane never hard-deletes a
--    grant - revocation is E3's soft delete - so the only DELETE reaching this
--    table is the `on delete cascade` from families, which means the family is
--    gone and there is nobody left to notify. An arm for it would be a bump
--    nothing could ever deliver.
-- ---------------------------------------------------------------------------
create or replace function public.bump_member_scope_version()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, auth
as $$
begin
  update public.members
     set scope_version = scope_version + 1
   where family_id = new.family_id
     and id        = new.member_id;
  return null;
end;
$$;

comment on function public.bump_member_scope_version() is
  'Records that what a member may RECEIVE has changed. Attached with WHEN clauses so an '
  'idempotent re-upsert of an unchanged grant does not bump: the client answers a bump by '
  'deleting local rows, so a spurious one costs a member a clear-and-refetch.';

-- A grant that ARRIVES already tombstoned is a member who never had it: nothing
-- to withdraw and nothing to deliver, so the insert arm requires a live row.
drop trigger if exists zzz_account_access_bump_on_insert on public.account_access;
create trigger zzz_account_access_bump_on_insert
  after insert on public.account_access
  for each row when (new.deleted = false)
  execute function public.bump_member_scope_version();

-- The only UPDATE that changes what a member may receive is one in which
-- `deleted` actually transitions. Everything else - a re-push of an unchanged
-- row, a granted_by preserve, an updated_at touch - is traffic.
drop trigger if exists zzz_account_access_bump_on_update on public.account_access;
create trigger zzz_account_access_bump_on_update
  after update on public.account_access
  for each row when (old.deleted is distinct from new.deleted)
  execute function public.bump_member_scope_version();

-- ---------------------------------------------------------------------------
-- 5. A TOMBSTONED GRANT MUST CONFER NOTHING. This is the security content of
--    the migration: without the `not deleted` filter a revocation would write a
--    row the predicates keep honouring, and every assertion about revocation
--    would pass while access was retained.
--
--    Both functions are restated whole because `create or replace` needs the
--    entire body and a migration is forward-only. can_see_account's creator arm
--    is 0024's, unchanged - and it must keep reading `accounts.created_by`
--    rather than being folded anywhere else, for the reason 0024 records.
-- ---------------------------------------------------------------------------
create or replace function public.can_see_account(p_account_id text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = public, auth
as $$
  select public.is_family_admin()
     or (p_account_id is not null and exists (
           select 1
           from public.account_access a
           where a.family_id  = public.auth_family_id()
             and a.account_id = p_account_id
             and a.member_id  = public.auth_member_id()
             and not a.deleted
         ))
     or (p_account_id is not null and public.auth_member_id() is not null and exists (
           select 1
           from public.accounts acc
           where acc.family_id  = public.auth_family_id()
             and acc.id         = p_account_id
             and acc.created_by = public.auth_member_id()
         ))
$$;

create or replace function public.visible_account_ids()
  returns text[]
  language sql
  stable
  security definer
  set search_path = public, auth
as $$
  select coalesce(array_agg(a.account_id), '{}'::text[])
  from public.account_access a
  where a.family_id = public.auth_family_id()
    and a.member_id = public.auth_member_id()
    and not a.deleted
$$;

-- ---------------------------------------------------------------------------
-- 6. The write path. ONE policy, `for all`, admin on BOTH sides.
--
--    A SECOND, PERMISSIVE POLICY HERE WOULD SILENTLY UNDO ALL OF THIS, exactly
--    as 0023 warns for the four narrowed tables: permissive policies OR
--    together, so a family-scoped `for all` sitting beside this one would let
--    any member write her own grant. If this table ever needs a second policy
--    it is RESTRICTIVE or it is a bug.
--
--    THE TWO HALVES FAIL DIFFERENTLY AND BOTH ARE ASSERTED. WITH CHECK makes a
--    member's INSERT raise 42501; USING makes her UPDATE match nothing at all,
--    silently, because the row is invisible to her. A policy narrowed on only
--    one of them would leave the other open with no symptom.
--
--    Members are still not shown the ledger: their own data simply contains
--    what they may see, and knowing that an account EXISTS is the information
--    this feature withholds.
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on public.account_access to authenticated;

drop policy if exists account_access_admin_read on public.account_access;

create policy account_access_admin_scoped on public.account_access
  for all to authenticated
  using      (family_id = public.auth_family_id() and public.is_family_admin())
  with check (family_id = public.auth_family_id() and public.is_family_admin());

-- ---------------------------------------------------------------------------
-- 7. Register the table in the family high-water mark.
--    THE SILENT BREAK THIS GUARDS (0016, 0018, 0020): family_version() is a
--    hardcoded union per tenant table. Leave account_access out and nothing
--    errors - the `version` probe just returns a stale timestamp, so an admin
--    device whose ONLY change is a share is told "nothing changed" and never
--    syncs. Pinned by an assertion in rls_isolation.test.sql.
-- ---------------------------------------------------------------------------
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
    union all select max(updated_at)  from public.account_access      where family_id = public.auth_family_id()
  ) s;
$$;

grant execute on function public.family_version() to authenticated;

-- ---------------------------------------------------------------------------
-- 8. ONE WRITER PER TABLE. The two functions are dropped rather than left
--    standing: leaving them would give this table a second write path that
--    bypasses the policy, the granted_by trigger and the WHEN-guarded bump -
--    which is the concentration D2 was protecting and would now be the thing
--    breaking it. Nothing in either repo calls them; grepped 2026-08-25.
-- ---------------------------------------------------------------------------
drop function if exists public.grant_account_access(text, text);
drop function if exists public.revoke_account_access(text, text);
