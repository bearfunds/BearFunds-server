# blast-radius extension: BearFunds server

_Repo-local extension of the `blast-radius` skill (`second-brain-skills` plugin). **The skill is canonical for the discipline**; this file answers the questions it declines to answer here, and carries the hazards true only of this repo._

---

## E1. THERE IS A GATE, AND THE SWEEP DOES NOT PASS IT

`0_AI_INSTRUCTIONS.md` requires an **Impact Analysis** and an explicit **Approval Lock** before any code is written. A sweep is evidence, not authorisation: it feeds the analysis, and no edit happens until an approval keyword arrives. Never simulate an approval.

## E2. Migrations are forward-only, so a rename is an ADDITION

An applied migration is never edited. Renaming a column, a table or a constraint means a NEW migration, and the sweep has to cover both the schema and every statement that names the old identifier.

## E3. The wire shape is shared, so a rename here lands in the other repo

`contracts/2_SCHEMA_CONTRACT.xml` is canonical HERE and consumed by the client as a downstream drop-in. **A rename that reaches the wire is a versioned contract bump**, propagated by the operator, and the client's copy is part of the same change rather than a follow-up. A sweep of this repo alone is incomplete for anything the contract names.

## E4. What the sandbox cannot tell you

`deno.land` is network-blocked and there is no browser, so Deno-native test runs, `supabase functions serve` and any live-function check are operator-side. A sweep can establish what names a thing; it cannot establish that the deployed function still works.

**And a migration ledger describes the LINKED REMOTE, not the local stack the app talks to.** Before believing any Supabase CLI output about what exists, establish which instance it is describing.
