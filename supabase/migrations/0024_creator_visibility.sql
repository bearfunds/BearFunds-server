-- ===========================================================================
-- 0024: a member can see what she created (forward-only).
--
-- WHY THIS EXISTS, AND IT IS A DEFECT REPAIR RATHER THAN A FEATURE. 0023 made
-- reads per-member and fail-closed. The client's push is
-- `supabase.from(t).upsert(rows).select()`, which emits
-- `INSERT ... ON CONFLICT ... RETURNING`, and RETURNING RE-READS THE ROW UNDER
-- THE SELECT POLICY. So a member creating any row she cannot see back was
-- refused with 42501 and THE ROW WAS NOT WRITTEN AT ALL - measured against real
-- Postgres 16, table count zero afterwards. Under fail-closed that is a newly
-- joined member creating her first account, which is the first thing a tester
-- does. A mixed batch is refused whole: one invisible row also discards the
-- visible row's edit in the same statement.
--
-- TWO OTHER DESIGNS WERE MEASURED AND REFUTED. Recorded because both are the
-- obvious idea and a future session will have it again.
--   * An AFTER INSERT trigger auto-granting the creator in account_access:
--     refused, 42501. The RLS check on RETURNING precedes AFTER triggers.
--   * The same trigger as BEFORE INSERT, named to sort after
--     accounts_set_family_id so family_id is populated: ALSO refused, 42501.
--     The policy predicate is STABLE, so it sees the statement's opening
--     snapshot and a grant written mid-statement is invisible to it.
-- A ROW'S OWN COLUMN IS THE ONLY THING THE PREDICATE CAN SEE IN TIME. That is
-- the whole reason this is created_by and not an auto-grant.
--
-- IT IS ALSO THE created_by THE ACCESS PLAN ALREADY OWED, arriving earlier than
-- expected. It was scoped for the revocation lock ("rows the member created
-- stay available"); it turns out to be load-bearing for CREATION, which is a
-- stronger reason and the same column.
--
-- WRITE-ONCE IS ENFORCED BY PRESERVING, NOT BY RAISING. A trigger that raised
-- on an attempted change would turn one bad row into a failed batch and take
-- the whole sync with it - the 2026-08-19 shape, which this repo has now paid
-- for twice. The update trigger silently restores the old value instead. The
-- client cannot send the column anyway (STRIPPED_KEYS), and a strip DROPS where
-- a non-writable key REJECTS: the dropping layer is the safe one and it is the
-- one used.
--
-- NULL MEANS "CREATED BEFORE THIS MIGRATION, OR CREATED BY AN ADMIN IN A TEST
-- CONTEXT". `created_by = auth_member_id()` is NULL rather than true when either
-- side is null, so a legacy row matches nothing and stays admin-only until
-- granted. No backfill is owed and none would be correct.
-- ===========================================================================

alter table public.accounts             add column if not exists created_by text;
alter table public.transactions         add column if not exists created_by text;
alter table public.staged_transactions  add column if not exists created_by text;

comment on column public.accounts.created_by is
  'The member id that created this row, server-derived and write-once. Read by the '
  'visibility predicate so a creator can see back what she just wrote - which is what '
  'makes INSERT ... RETURNING succeed under a fail-closed read policy.';

-- ---------------------------------------------------------------------------
-- 1. Stamp on insert, preserve on update.
--    UNCONDITIONAL on insert: an earlier draft wrote
--    `coalesce(new.created_by, auth_member_id())` and its control caught it -
--    a client-supplied value SURVIVED, which would let a member hand visibility
--    of a row she is creating to somebody else. A server-derived column that
--    honours a client value is not server-derived.
-- ---------------------------------------------------------------------------
create or replace function public.set_created_by()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, auth
as $$
begin
  new.created_by := public.auth_member_id();
  return new;
end;
$$;

create or replace function public.preserve_created_by()
  returns trigger
  language plpgsql
as $$
begin
  new.created_by := old.created_by;
  return new;
end;
$$;

-- The name sorts after accounts_set_family_id / accounts_set_updated_at, which matters:
-- Postgres fires per-row triggers in NAME order, and this one is only correct once
-- family_id has been derived. Measured the hard way - the same trigger named earlier
-- failed with 23502 because new.family_id was still null.
do $$
declare t text;
begin
  foreach t in array array['accounts','transactions','staged_transactions']
  loop
    execute format('drop trigger if exists zz_%1$s_set_created_by on public.%1$I;', t);
    execute format('create trigger zz_%1$s_set_created_by before insert on public.%1$I
                      for each row execute function public.set_created_by();', t);
    execute format('drop trigger if exists zz_%1$s_preserve_created_by on public.%1$I;', t);
    execute format('create trigger zz_%1$s_preserve_created_by before update on public.%1$I
                      for each row execute function public.preserve_created_by();', t);
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. An account you created behaves like an account granted to you.
--    Folding the creator arm into can_see_account() rather than only into the
--    accounts policy keeps the model coherent: otherwise a member would own an
--    account and be unable to see its transactions, which is a distinction with
--    no meaning to anyone using the app.
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
     or (p_account_id is not null and public.auth_member_id() is not null and exists (
           select 1
           from public.accounts acc
           where acc.family_id  = public.auth_family_id()
             and acc.id         = p_account_id
             and acc.created_by = public.auth_member_id()
         ))
$$;

-- ---------------------------------------------------------------------------
-- 3. Widen the three read predicates with the creator arm.
--    This is an OR into a FAIL-CLOSED predicate, so the assertion that matters
--    is the negative one: a member must still not see rows she did not create
--    and was not granted. The suite asserts that arm beside every positive one.
--
--    The transactions and staged arms carry created_by directly rather than
--    only through can_see_account, because the case they exist for is a row
--    whose account_id is NULL - a staged import before classification, which
--    can be attributed to no account and would otherwise be invisible to its
--    own author.
-- ---------------------------------------------------------------------------
drop policy if exists accounts_member_scoped            on public.accounts;
drop policy if exists transactions_member_scoped        on public.transactions;
drop policy if exists staged_transactions_member_scoped on public.staged_transactions;

-- ACCOUNTS READS created_by DIRECTLY, AND MUST NOT ROUTE IT THROUGH can_see_account().
-- The function's creator arm is a SUBQUERY over public.accounts, and a STABLE function sees
-- the statement's opening snapshot - so for the row being inserted RIGHT NOW it returns
-- false and the RETURNING re-read is refused, which is the exact defect 0024 exists to fix.
-- Reading the column off the row under test has no such problem. This was written the wrong
-- way first and the suite caught it on the same run: a subquery is not a substitute for a
-- column, however identical the two look in prose.
create policy accounts_member_scoped on public.accounts
  for all to authenticated
  using (family_id = public.auth_family_id()
         and (public.can_see_account(id)
              or created_by = public.auth_member_id()))
  with check (family_id = public.auth_family_id());

create policy transactions_member_scoped on public.transactions
  for all to authenticated
  using (family_id = public.auth_family_id()
         and (public.can_see_account(account_id)
              or created_by = public.auth_member_id()))
  with check (family_id = public.auth_family_id());

create policy staged_transactions_member_scoped on public.staged_transactions
  for all to authenticated
  using (family_id = public.auth_family_id()
         and (public.can_see_account(account_id)
              or created_by = public.auth_member_id()))
  with check (family_id = public.auth_family_id());

create index if not exists accounts_created_by_idx
  on public.accounts (family_id, created_by);
create index if not exists transactions_created_by_idx
  on public.transactions (family_id, created_by);
create index if not exists staged_transactions_created_by_idx
  on public.staged_transactions (family_id, created_by);
