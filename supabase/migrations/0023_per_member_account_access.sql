-- ===========================================================================
-- 0023: per-member account visibility (forward-only).
--
-- WHAT THIS IS. Until now every tenant policy read the same predicate:
-- `family_id = auth_family_id()`. A family was the smallest unit of visibility,
-- so every member saw every row. This adds a second, narrower unit: an ADMIN
-- grants a MEMBER access to an ACCOUNT, and transactions, staged rows and
-- budgets derive their visibility from the account they name. Nothing else is
-- granted; there is no per-transaction state to drift.
--
-- DEFAULT HIDDEN, FAIL CLOSED. A member with no grants sees no accounts and
-- therefore no ledger. That is a designed state, not an error: showing
-- something that should have been hidden is unrecoverable, and hiding
-- something that should have been shown is a support ticket.
--
-- WHAT IT IS NOT. This is a TRUST boundary, not a security boundary. One family
-- key exists (the recovery code IS the key, and every device holds it), so a
-- member who defeats this reads whatever the server hands over. It shapes what
-- members see day to day and prevents accidents. Product copy must never claim
-- more than that.
--
-- ---------------------------------------------------------------------------
-- FIVE DECISIONS, taken 2026-08-22, each recorded because the alternative was
-- live and a future reader will otherwise re-open it.
--
-- D1. THE PREDICATE READS IDENTITY THROUGH NAMED RESOLVERS, NEVER auth.uid()
--     INLINE. auth_member_id() and is_family_admin() join auth_family_id() as
--     the seam every policy goes through. This costs nothing today and is the
--     difference between one function changing and every policy changing when
--     authentication moves out of Supabase into its own service. The rule for
--     anyone adding a policy after this: if you are typing `auth.uid()` in a
--     policy, you are widening the surface this migration exists to narrow.
--
-- D2. GRANTS ARE RPC-MUTATED, NOT A SYNCED TABLE. account_access carries no
--     grant to authenticated beyond SELECT; the only write path is the two
--     SECURITY DEFINER functions below. The reason is not tidiness: a synced
--     grant row would merge by last-write-wins like every other collection, so
--     a revocation could LOSE A RACE to a stale device re-pushing an older
--     grant. A silent re-grant is the worst available failure on the one table
--     where being wrong is a disclosure. Authorization wants a single writer.
--     Precedent: invites (0007) are RPC-driven and appear nowhere in the schema
--     contract. This table does not either, so no contract bump rides here.
--
-- D3. THE ROW IDENTIFIES A MEMBER, AND CARRIES ITS FAMILY. `members.user_id` is
--     globally UNIQUE today (0001, restated by 0009: "one member per user"), so
--     member and user are 1:1 - but that is a PLACEHOLDER. When a person may
--     belong to several families they hold one member row per family, and a
--     grant is only meaningful inside one; keyed on member it survives that,
--     keyed on user it does not. family_id is in the key because tenant tables
--     are keyed (family_id, id) since 0009, so account_id alone is ambiguous:
--     every family seeds the same fixed ids and `w_main` exists in all of them.
--     NO FK TO accounts, deliberately. It would be the schema's first
--     cross-tenant FK (0009: "no tenant table references another tenant
--     table's id via a FK"), and accounts are SOFT deleted, so the FK would
--     almost never fire while the grant outlived the account anyway. The
--     predicate filters on `deleted` instead.
--
-- D4. "READS NARROW, WRITES STAY FAMILY-SCOPED" WAS CHOSEN AND IS NOT
--     EXPRESSIBLE. Recording the refutation rather than the intent, because the
--     intent is the thing a future reader would otherwise try again.
--
--     The plan was to leave INSERT / UPDATE / DELETE at family scope so that a
--     member's device holding a row it may no longer read could still push it -
--     the point being that `sanitizeRow` REJECTS rather than drops, so one
--     refused row takes the whole batch and with it the entire sync, which is
--     what happened on 2026-08-19. Revocation makes that the normal path rather
--     than an edge, so it was worth designing around.
--
--     POSTGRES DOES NOT SEPARATE THE TWO. Measured against real Postgres 16 with
--     these policies in place, two arms differing only in whether the row was
--     visible to the caller:
--       - upsert of a VISIBLE row   -> succeeds
--       - upsert of an INVISIBLE row -> ERROR: new row violates row-level
--                                       security policy for table "transactions"
--     and a plain `update ... where id = ...` on an invisible row matches
--     nothing at all, silently. A narrowed SELECT policy gates the write however
--     permissive the write policies are, because ON CONFLICT DO UPDATE has to
--     read the conflicting row and an UPDATE's WHERE clause reads columns.
--
--     So A and B were the same option wearing two names, and the mitigation has
--     to move OFF the policy. It belongs in one of two places, neither of which
--     is this migration: the client stops enqueuing a mutation for a row it
--     cannot see, or the seam tolerates a per-row refusal instead of failing the
--     batch. Until one exists, THE SYNC-KILLING REJECTION IS LIVE for any device
--     that pushes a revoked row - which is why revocation is not shipped here.
--     Each table therefore carries ONE policy, in the shape 0002 already uses:
--     narrowed USING (select, update, delete) and family-scoped WITH CHECK
--     (insert), which is the honest description of what Postgres does anyway.
--
-- D5. AN ACCOUNT-LESS BUDGET IS AN IMPOSSIBLE STATE, AND IS NOW IMPOSSIBLE.
--     The budget predicate is array containment, and `'{}' <@ anything` is
--     TRUE - so an empty account_ids would be visible to everyone, vacuously,
--     defeating fail-closed at exactly the point it matters. The client already
--     refuses to save one (BudgetForm.handleSave: "Pick at least one account
--     for this budget to watch"), so the empty array was never a legal value,
--     only an unenforced one. The CHECK below makes the schema agree with the
--     form. The column's `default '{}'` from 0022 goes with it: a default that
--     cannot satisfy its own table's CHECK is a trap that fires on whoever next
--     omits the column.
--
-- ---------------------------------------------------------------------------
-- TWO CONSEQUENCES A READER WILL OTHERWISE MEET AS BUGS.
--
-- A ROW WITH A NULL account_id IS HIDDEN FROM EVERY NON-ADMIN. account_id is
-- nullable on transactions (0001) and staged_transactions (0006), and a row
-- that names no account cannot be attributed to one, so fail-closed hides it.
-- The realistic case is a member's own staged import before classification:
-- they will watch their rows vanish. Closing it properly needs `created_by`
-- (server-derived, write-once), which is deferred to the eviction slice - so
-- this is a KNOWN GAP with a named owner, not an oversight.
--
-- family_version() (0012) IS SECURITY INVOKER AND AGGREGATES UNDER THE CALLER'S
-- RLS, so a member's sync high-water mark now differs from an admin's. That is
-- correct rather than broken - their delta should track what they can see - but
-- anything assuming the version is family-uniform is now wrong.
--
-- WHAT THIS MIGRATION DOES NOT DO. It delivers no grants to an existing device:
-- the read action is `updated_at > since` strictly, so granting access to an
-- account that already exists delivers NOTHING until its rows are touched or
-- the member re-pulls. It also cannot EVICT: RLS filtering produces silence,
-- and mergePulledCollection needs a row carrying `deleted: true` to build a
-- tombstone, so a revoked member's client keeps what it has. Delivery and
-- eviction are one problem and they are the next slice.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. The resolver seam (D1). SECURITY DEFINER + STABLE for the same reason
--    auth_family_id() is: they read `members`, which has RLS, and a policy that
--    consults them must not recurse into it. The test branch mirrors
--    auth_family_id()'s CASE exactly.
--
--    THE TEST BRANCH IS LOAD-BEARING, AND IT IS NOT A CONVENIENCE.
--    ensure_test_family() (0011) provisions a families row and a
--    user_test_family mapping and NO members row, and `user_id` is stripped
--    from every client write - so inside a test family auth.uid() resolves to
--    no member and to no role. Without this branch a fail-closed predicate
--    shows the ghost suite zero of everything, and 199 scenarios go red for a
--    reason none of them is about. The caller owning the test family IS its
--    administrator; there is nobody else in it.
-- ---------------------------------------------------------------------------
create or replace function public.auth_member_id()
  returns text
  language sql
  stable
  security definer
  set search_path = public, auth
as $$
  select case
    when public.is_test_request() then null::text
    else (select m.id from public.members m where m.user_id = auth.uid() limit 1)
  end
$$;

comment on function public.auth_member_id() is
  'The caller''s member id within their resolved family, or NULL in a test request. '
  'One of the three identity resolvers every RLS policy goes through. The `limit 1` '
  'is the single-family placeholder: it becomes a set when a user may hold several '
  'member rows, and this function is where that change lands.';

create or replace function public.is_family_admin()
  returns boolean
  language sql
  stable
  security definer
  set search_path = public, auth
as $$
  select case
    when public.is_test_request()
      then exists (select 1 from public.user_test_family t where t.user_id = auth.uid())
    else coalesce(
      (select m.role = 'admin' from public.members m where m.user_id = auth.uid() limit 1),
      false)
  end
$$;

comment on function public.is_family_admin() is
  'True when the caller administers their resolved family. COALESCEd to false so an '
  'unresolvable caller is never an admin (fail closed). Never read the client''s own '
  'role for this: it is forgeable in local storage.';

-- ---------------------------------------------------------------------------
-- 2. The grant table (D2, D3).
-- ---------------------------------------------------------------------------
create table if not exists public.account_access (
  family_id            uuid not null references public.families(id) on delete cascade,
  account_id           text not null,
  member_id            text not null,
  granted_by_member_id text,
  granted_at           timestamptz not null default now(),
  primary key (family_id, account_id, member_id)
);

comment on table public.account_access is
  'An admin has granted one member sight of one account. Written ONLY by '
  'grant_account_access / revoke_account_access - never by the sync protocol, because a '
  'last-write-wins grant row lets a revocation lose a race and silently re-grant.';

alter table public.account_access enable row level security;
alter table public.account_access force row level security;

-- Members are not shown the grant ledger: their ledger simply contains what they may
-- see, and knowing that an account exists is itself the information this feature
-- withholds. SELECT only - the write path is the two functions below.
grant select on public.account_access to authenticated;

create policy account_access_admin_read on public.account_access
  for select to authenticated
  using (family_id = public.auth_family_id() and public.is_family_admin());

create index if not exists account_access_member_idx
  on public.account_access (family_id, member_id);

-- ---------------------------------------------------------------------------
-- 3. The visibility predicates. SECURITY DEFINER so a policy consulting them does
--    not re-enter account_access's own RLS (which would evaluate as the member and
--    find nothing, hiding every row from everybody - a fail-closed bug that looks
--    exactly like the feature working).
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
         ))
$$;

comment on function public.can_see_account(text) is
  'Admins see every account; a member sees a granted one. A NULL account_id is FALSE '
  'for a member, deliberately: a row naming no account cannot be attributed to one. '
  'That hides an unclassified staged import from its own author until created_by exists.';

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
$$;

comment on function public.visible_account_ids() is
  'The member''s granted account ids, for array containment on budgets. Admins do not '
  'consult it - their arm of the budget policy short-circuits on is_family_admin().';

revoke all on function public.auth_member_id()        from public;
revoke all on function public.is_family_admin()       from public;
revoke all on function public.can_see_account(text)   from public;
revoke all on function public.visible_account_ids()   from public;
grant execute on function public.auth_member_id()      to authenticated;
grant execute on function public.is_family_admin()     to authenticated;
grant execute on function public.can_see_account(text) to authenticated;
grant execute on function public.visible_account_ids() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. Narrow the reads (D4). ONE policy per table, in the shape 0002 already uses:
--    `for all` with a NARROWED using and a FAMILY-SCOPED with check. Postgres reads
--    that as: SELECT / UPDATE / DELETE see only granted rows, INSERT may create any
--    row in the family. That last asymmetry is the only part of the original D4
--    intent that survives, and it is the part that matters - a member must be able
--    to CREATE, or the app is read-only for everyone but the admin.
--
--    A SECOND, PERMISSIVE POLICY ON THESE TABLES WOULD SILENTLY UNDO ALL OF THIS.
--    Permissive policies OR together, so a family-scoped `for all` sitting beside
--    this one restores family-wide visibility completely - every assertion in the
--    suite would still pass except the ones that matter, and the feature would be
--    absent with no symptom. If a table here ever needs a second policy, it is
--    RESTRICTIVE (`as restrictive`) or it is a bug.
--
--    A soft-deleted account is NOT excluded from the read: its tombstone must still
--    reach a member who could see it, or the stale live row resurrects on their next
--    reload and the delta cursor never re-pulls it (Area 012, Soft Deletes).
--    Grantability is where `deleted` belongs, and grant_account_access refuses one.
-- ---------------------------------------------------------------------------
drop policy if exists accounts_family_isolation            on public.accounts;
drop policy if exists transactions_family_isolation        on public.transactions;
drop policy if exists staged_transactions_family_isolation on public.staged_transactions;

-- ACCOUNTS is the ROOT of the model: the grant lives here and everything else derives.
create policy accounts_member_scoped on public.accounts
  for all to authenticated
  using (family_id = public.auth_family_id() and public.can_see_account(id))
  with check (family_id = public.auth_family_id());

-- DERIVED: a transaction's visibility is its account's, through the plaintext
-- account_id. There is no per-transaction grant and there must never be one.
create policy transactions_member_scoped on public.transactions
  for all to authenticated
  using (family_id = public.auth_family_id() and public.can_see_account(account_id))
  with check (family_id = public.auth_family_id());

create policy staged_transactions_member_scoped on public.staged_transactions
  for all to authenticated
  using (family_id = public.auth_family_id() and public.can_see_account(account_id))
  with check (family_id = public.auth_family_id());

-- ---------------------------------------------------------------------------
-- 5. BUDGETS: hidden entirely if ANY account it references is hidden (D5).
--    Containment, not intersection: showing a budget with only the visible half of
--    its accounts would leak the hidden account's spending through a total that is
--    also quietly wrong, which is worse than hiding it.
-- ---------------------------------------------------------------------------
alter table public.budgets
  alter column account_ids drop default;

alter table public.budgets
  drop constraint if exists budgets_account_ids_not_empty;
alter table public.budgets
  add constraint budgets_account_ids_not_empty
  check (cardinality(account_ids) > 0);

drop policy if exists budgets_family_isolation on public.budgets;

create policy budgets_member_scoped on public.budgets
  for all to authenticated
  using (family_id = public.auth_family_id()
         and (public.is_family_admin()
              or account_ids <@ public.visible_account_ids()))
  with check (family_id = public.auth_family_id());

-- ---------------------------------------------------------------------------
-- 6. IMPORT_MAPPINGS is ADMIN-ONLY. It was family-isolation only, gated in the
--    client's navigation alone - which is a display gate. This makes it real.
-- ---------------------------------------------------------------------------
drop policy if exists import_mappings_family_isolation on public.import_mappings;

create policy import_mappings_admin_scoped on public.import_mappings
  for all to authenticated
  using (family_id = public.auth_family_id() and public.is_family_admin())
  with check (family_id = public.auth_family_id());

-- ---------------------------------------------------------------------------
-- 7. The grant control plane (D2). Admin-gated, SECURITY DEFINER, and tenancy
--    resolved through auth_family_id().
--
--    THE TENANCY LINE IS A DELIBERATE DEPARTURE FROM THE INVITES PRECEDENT, NOT A
--    COPY OF IT. create_invite (0007) reads the caller's REAL members row, so it is
--    blind to test context and a ghost run's invites land in the caller's PRODUCTION
--    family. Following that shape here would put test grants on real accounts.
--    auth_family_id() is test-aware, so these two are not.
-- ---------------------------------------------------------------------------
create or replace function public.grant_account_access(p_account_id text, p_member_id text)
  returns void
  language plpgsql
  security definer
  set search_path = public, auth
as $$
declare
  v_family uuid;
begin
  if auth.uid() is null then
    raise exception 'grant_account_access requires an authenticated user';
  end if;
  if not public.is_family_admin() then
    raise exception 'admin role required to grant account access';
  end if;

  v_family := public.auth_family_id();
  if v_family is null then
    raise exception 'no family resolved for this caller';
  end if;

  -- Both existence checks are inside the caller's family by construction, so a forged
  -- id from another tenant simply finds nothing rather than being refused specifically.
  if not exists (select 1 from public.accounts a
                  where a.family_id = v_family and a.id = p_account_id and not a.deleted) then
    raise exception 'no such account in this family';
  end if;
  if not exists (select 1 from public.members m
                  where m.family_id = v_family and m.id = p_member_id) then
    raise exception 'no such member in this family';
  end if;

  insert into public.account_access (family_id, account_id, member_id, granted_by_member_id)
  values (v_family, p_account_id, p_member_id, public.auth_member_id())
  on conflict (family_id, account_id, member_id) do nothing;
end;
$$;

create or replace function public.revoke_account_access(p_account_id text, p_member_id text)
  returns void
  language plpgsql
  security definer
  set search_path = public, auth
as $$
declare
  v_family uuid;
begin
  if auth.uid() is null then
    raise exception 'revoke_account_access requires an authenticated user';
  end if;
  if not public.is_family_admin() then
    raise exception 'admin role required to revoke account access';
  end if;

  v_family := public.auth_family_id();

  -- Idempotent: revoking what was never granted is the desired end state either way.
  -- The row leaving this table stops the server SENDING it; the member's device keeps
  -- whatever it already pulled until the eviction slice exists. Nothing here evicts.
  delete from public.account_access
   where family_id = v_family and account_id = p_account_id and member_id = p_member_id;
end;
$$;

revoke all on function public.grant_account_access(text, text)  from public;
revoke all on function public.revoke_account_access(text, text) from public;
grant execute on function public.grant_account_access(text, text)  to authenticated;
grant execute on function public.revoke_account_access(text, text) to authenticated;
