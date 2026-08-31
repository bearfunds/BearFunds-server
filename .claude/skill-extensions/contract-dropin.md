# contract-dropin extension: BearFunds server

_Repo-local extension of the `contract-dropin` skill (`code-skills` plugin). **The skill is canonical for the discipline**; this file answers the questions it declines to answer here._

**This file states what IS.**

---

## E1. The schema contract is CANONICAL here, and that raises the cost rather than lowering it

`contracts/2_SCHEMA_CONTRACT.xml` is the producer's copy - the interface belongs to the repo that implements it. It is operator-hands like any contract, and a change to it is a **deliberate versioned bump**, never a casual edit: the `Canonical:` header line carries the live version and moves with the change.

**A bump lands in the client too.** The client holds a downstream copy the operator refreshes, and it is part of the same change rather than a follow-up. A drop-in that changes the wire shape and says nothing about the consumer is incomplete.

`0_AI_INSTRUCTIONS.md` is the engineering protocol and is operator-hands on the same terms. `CLAUDE.md` is not a contract and may be edited directly.

## E2. There is a gate, and the drop-in does not pass it

`0_AI_INSTRUCTIONS.md` requires an Impact Analysis and an explicit Approval Lock before code is written, and the analysis carries a tenancy and auth check of its own. A drop-in is a proposal, not authorisation. Never simulate an approval.

## E3. Nothing here checks a citation

There is no `contractCitations` equivalent in this repo. **A deleted element is silent**, in the contract and in any code comment naming it. After any drop-in is applied, diff the file and confirm the change is a pure addition unless a deletion was the proposal.

## E4. A schema change is usually also a migration, and migrations are forward-only

An applied migration is never edited. A contract change that renames or retypes anything in the datastore means a NEW migration, and the drop-in and the migration are one slice. The sweep covers both the schema and every statement naming the old identifier.

## E5. What the sandbox cannot verify

`deno.land` is network-blocked and there is no browser, so Deno-native runs, `supabase functions serve` and any live-function check are operator-side. A read-back can prove the contract file says what it should; it cannot prove the deployed function agrees with it.

**And a migration ledger describes the LINKED REMOTE, not the local stack the app talks to.** Before believing any Supabase CLI output about what exists, establish which instance it is describing.
