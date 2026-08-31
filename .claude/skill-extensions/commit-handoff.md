# commit-handoff extension: BearFunds server

_Repo-local extension of the `commit-handoff` skill (`second-brain-skills` plugin). **The skill is canonical for the discipline**; this file answers the questions it declines to answer here._

---

## E1. THERE IS A GATE, AND THE SCRIPT COMES AFTER IT

`0_AI_INSTRUCTIONS.md` requires an **Impact Analysis** and an explicit **Approval Lock** before any code is written, and a Verification step - including RLS-isolation results - after. A commit script belongs at the end of that sequence, never beside the plan. Never simulate an approval.

## E2. MIGRATIONS ARE FORWARD-ONLY, SO A FIX IS A NEW FILE

An applied migration is never edited. A correction is a NEW migration, which means it is a NEW file, which is the case the skill's staging rule exists for: stage it explicitly and call it out.

## E3. THE WIRE CONTRACT IS CANONICAL HERE, AND A BUMP RIDES THIS COMMIT

`contracts/2_SCHEMA_CONTRACT.xml` is owned by this repo and consumed by the client as a downstream drop-in. When a slice includes an operator-applied versioned bump, **stage the contract with the slice's code in the same commit and name it in the message**. The client's copy is part of the same change and gets its own commit in that repo - two repos, two scripts, neither folded into the other.

## E4. Never commit a secret, and never touch `.env*`

Secrets are server-side and live outside the repo. If a new key is needed, say so in chat; do not write it, and do not let a script stage a file that carries one.

## E5. What the sandbox cannot verify before the script goes out

`deno.land` is network-blocked and there is no browser, so Deno-native test runs, `supabase functions serve` and any live-function check are operator-side. Postgres RLS-isolation suites DO run in-sandbox via `pgserver`. A green claim in the hand-off names which of those ran and says "not run" for the rest.

**And a migration ledger describes the LINKED REMOTE, not the local stack.** Do not let a hand-off imply a database was verified when the tool describing it was pointed somewhere else.

## E6. Message style

Conventional Commits with a scope - `feat(family-settings):`, `fix(security):`, `docs(contract):`. No authorship or session trailers, on operator preference.
