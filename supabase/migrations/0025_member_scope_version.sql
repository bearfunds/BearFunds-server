-- ===========================================================================
-- 0025: scope delivery (forward-only). Schema Contract v1.27.
--
-- THE PROBLEM, WHICH IS A PROPERTY OF DELTA SYNC RATHER THAN OF THIS FEATURE.
-- `read` returns rows whose updated_at is STRICTLY greater than the caller's
-- high-water mark. So:
--   * WIDENING a member's scope delivers NOTHING - every row she has just been
--     permitted to see is older than her mark, and always will be.
--   * NARROWING it delivers nothing either - a row that is no longer sent is
--     indistinguishable from a row that has not changed. RLS filtering produces
--     SILENCE, and mergePulledCollection needs a row carrying deleted:true to
--     build a tombstone, so nothing on the client can learn the row went away.
-- Both directions are the same gap: the protocol can say "this row got newer"
-- and nothing else.
--
-- THE MECHANISM. members.scope_version is a counter the server bumps whenever
-- what a member may receive changes. The member's own row is family-global and
-- therefore always reaches her; the existing set_updated_at trigger turns the
-- bump into an ordinary delta. A client seeing a HIGHER value than the one it
-- last recorded clears its scoped local stores and re-pulls them from the
-- beginning that same cycle - the one operation that both delivers
-- newly-permitted rows and drops newly-forbidden ones.
--
-- WHY A COLUMN RATHER THAN JUST TOUCHING updated_at. Bumping updated_at alone
-- would work and costs no contract change, but the member's row is touched by
-- every ordinary edit - a rename, an avatar, a colour - including the
-- round-trip of her OWN edit. Every one of those would trigger a clear and a
-- full re-pull. A destructive step needs a signal that says SCOPE changed, not
-- SOMETHING changed.
--
-- THE BUMP IS CONDITIONAL ON A REAL CHANGE, and that is load-bearing rather
-- than tidy: the client's response to it DELETES local rows. grant is
-- `on conflict do nothing` and revoke is a delete, so both can be no-ops -
-- a UI that double-fires, a retry, an admin re-granting what is already
-- granted. FOUND is checked so an idempotent call stays idempotent all the way
-- to the device.
--
-- SERVER-OWNED. The column is stripped at the seam (contract.ts STRIPPED_KEYS),
-- so a client value never reaches it: a client writing its own scope_version
-- would be making a claim about its own permissions. Stripped rather than
-- non-writable, because a non-writable key makes sanitizeRow THROW and takes
-- the whole batch with it.
-- ===========================================================================

alter table public.members
  add column if not exists scope_version integer not null default 0;

comment on column public.members.scope_version is
  'Monotonic counter of changes to what this member may receive. Server-owned and stripped '
  'on writes. A client observing a higher value than it last recorded must clear its scoped '
  'local stores and re-pull from the beginning: a delta read can deliver neither a widened '
  'nor a narrowed scope.';

-- ---------------------------------------------------------------------------
-- Re-issue the two grant-plane functions with the bump. Everything else about
-- them is unchanged from 0023; they are restated whole because a migration is
-- forward-only and `create or replace` needs the entire body.
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

  -- Only a REAL change bumps. The client answers a bump by deleting local rows.
  if found then
    update public.members
       set scope_version = scope_version + 1
     where family_id = v_family and id = p_member_id;
  end if;
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

  delete from public.account_access
   where family_id = v_family and account_id = p_account_id and member_id = p_member_id;

  -- Revoking what was never granted is idempotent and must NOT bump: it changes nothing,
  -- and a bump would cost the member a clear-and-refetch for no reason.
  if found then
    update public.members
       set scope_version = scope_version + 1
     where family_id = v_family and id = p_member_id;
  end if;
end;
$$;
