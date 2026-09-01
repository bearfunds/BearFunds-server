# search-code extension: BearFunds-server

_This is the repo-local extension of the `search-code` skill (`second-brain-skills` plugin). The skill carries the general discipline; this file carries what is only true HERE. A repo-specific finding is filed in this file, never in the skill._

**Seeded 2026-08-20.** Every entry below was verified against the working tree that day and quotes its evidence path, so a future session can re-check rather than re-trust. Git state was not consulted: these are properties of the tree as it stood, not of any commit. This repo had no `.claude/` directory at all before this file.

**Re-verify before quoting a number from this file.** It will decay the same way every register in this project has.

---

## Tooling

### T1. There are TWO `_shared` directories, and the only discriminator is the relative depth

`supabase/functions/_shared/` holds `http.ts`. `supabase/functions/api/_shared/` holds `actions.ts`, `contract.ts`, `errors.ts`, `validation.ts`. A grep for `_shared/` returns both trees, and the import lines are `from "../_shared/http.ts"` against `from "./_shared/actions.ts"` - one dot apart.

**Alternative:** search the full relative specifier, never the bare directory name, and state which `_shared` a finding is about. A count of "helpers in `_shared`" is meaningless without saying which.

### T2. Imports are relative and carry an explicit `.ts`, so a bare module-name grep finds nothing

Deno resolves by path, not by package. Every internal import in `supabase/functions/` reads `./contract.ts`, `./handler.ts`, `../_shared/http.ts`. There is no bare-specifier form to match.

**Alternative:** grep the filename with its extension (`contract.ts`), not the symbol you would use in Node. "No importer found" for a bare name is a property of the search, not of the tree.

### T3. `run_e2e.sh` suppresses errors in two places, and a suppressed SETUP step makes every assertion downstream of it vacuous

`supabase/tests/run_e2e.sh:12` and `:40` both carry `2>/dev/null || true`. Line 12 is a teardown kill and is harmless; line 40 is a request whose failure becomes `000`.

This is the live instance of a hazard this project has already paid for once: a `pgserver` runner reproduced Supabase's default grants BEFORE `auth_shim.sql` created the `authenticated` role, hid the error behind `2>/dev/null || true`, and every "authenticated must NOT read this table" assertion passed against a table nobody had been granted - including three written that hour to prove a new REVOKE.

**Alternative:** when reading a test result here, find the setup steps first and check whether any of them can fail silently. A green RLS suite is only evidence if its grants took.

### T4. The schema is the ACCUMULATION of 21 forward-only migrations, never any one file

`supabase/migrations/` runs `0001_init_schema.sql` through the current head, and migrations are forward-only by rule - a column's current shape is its CREATE plus every later ALTER.

**Alternative:** to answer "what does this table look like now", query a live database or read every migration touching it in order. A grep that finds the CREATE and stops is answering a question about 0001, not about today.

### T5. `supabase/snippets/Untitled query *.sql` are scratch, not schema

Two files, `261` and `597`. They match any repo-wide SQL grep and are not part of the contract, the migrations or the tests.

**Alternative:** scope SQL searches to `supabase/migrations/` or `supabase/tests/`, or exclude `supabase/snippets/` explicitly and say you did.

### T6. A migration ledger describes the LINKED REMOTE, not the database the app talks to

`supabase migration list` compares the files on disk against the linked remote project. Neither of its columns describes the LOCAL stack that a ghost run drives. On 2026-08-09 a table existed in the files and on the remote and not locally; the seam returned a generic 500, and a correct diagnosis was WITHDRAWN because the ledger disagreed with it.

**Alternative:** a claim about what a database CONTAINS is settled by querying that database. Establish which instance a CLI is describing first - the client's `VITE_SUPABASE_URL` for the app, `supabase/.temp/project-ref` for the CLI - because they are routinely different.

## Codebase

### T7. The Schema Contract is canonical HERE, and the client's copy is a downstream drop-in

`contracts/2_SCHEMA_CONTRACT.xml` is the producer-owned original; `BearFunds-client/2_SCHEMA_CONTRACT.xml` is refreshed from it. Searching the client's copy answers what the client was last given, not what the server promises.

**Alternative:** for a contract question, read the copy in this repo and say which one you read.

## Stop and measure

- A green RLS suite whose setup could fail silently (T3).
- "This column does not exist" derived from one migration (T4).
- Any CLI output about a database, before establishing which instance it describes (T6).
- A helper "in `_shared`" without saying which `_shared` (T1).

## Environment

- The sandbox CAN run Postgres 16 RLS suites via `pgserver`, one-shot per bash call. It CANNOT run Deno (deno.land is network-blocked) or `supabase functions serve`; those are operator-side.
- There is no `node_modules` in this repo and no build step, so none of the client's toolchain hazards apply here.
- Sandbox git is informational-only and always takes `--no-optional-locks`.

## Raw amendments

_Session buffer. An entry here is a SIGNAL, not a rule - one instance is a data point. The entries above were verified; entries here have not been, and must not be read with the same authority. Entry shape, session tags, stages and the cap are defined in the `session-wrap` skill's `references/skill-amendments.md`._

_(none yet)_
