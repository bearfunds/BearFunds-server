# impact-analysis extension: BearFunds server

_Repo-local extension of the `impact-analysis` skill (`code-skills` plugin). **`0_AI_INSTRUCTIONS.md` is the protocol and outranks both**; the skill is the discipline for executing it; this file carries what is true only of this repo._

---

## E1. Architecture orientation

Where the moving parts are. The design this implements is the brain's `BearFunds Server Architecture.md`, and the full rationale lives there - this is the orientation a change needs in hand.

- **Platform:** Supabase — managed **Postgres** (datastore), **Auth** (Google sign-in), and **Edge Functions** (the API seam).
- **API seam:** a single Edge Function that **honors the Schema Contract** — one POST endpoint, action-based (`read`/`batchCreate`/`batchUpdate`/`batchUpsert`/`wipe`/`version`), snake_case logical keys, `{ status, data }` envelope. This keeps the client's `core/api/` layer almost unchanged (it swaps the shared bundle key for a Supabase session JWT).
- **Datastore:** one table per client collection (`transactions`, `categories`, `subcategories`, `accounts`, `entities`, `members`, `staged_transactions`, `budgets`) + a `families` tenancy root, mapping the brain's `Syncable` model 1:1, with server-managed `updated_at`, soft-delete `deleted`, and `is_immutable`.
- **Tenancy/auth:** every tenant row carries a server-derived `family_id`, enforced by Postgres **RLS**; `FamilyMember.role` (`admin`/`member`) is server-enforced. Secrets (Gemini, JWT) live server-side, never in the client bundle.
- A RESTful **v2** contract is deferred future work; honor the current v1.x contract now.
- **BUDGETS** (since contract v1.16) is a tenant table like any other, with one property worth stating: its whole meaningful payload - name, amount, note AND the category/account membership - rides the `enc` envelope. The server therefore cannot enforce the one-category-per-Budget-per-period rule; the client owns it (`core/budgetPolicy.ts`, with a unit matrix). Utilization is computed on device from the ledger, never snapshotted.

## E2. The execution boundary - what the Test Plan may and may not claim

Proven sandbox-safe here: **Postgres 16 RLS-isolation suites via `pgserver`** (the recipe is in the brain's Tool reliability) and pure-Node action and validation harnesses.

**Operator-side: `supabase functions serve` and any live-function E2E, Deno-native test runs - `deno.land` is network-blocked - and anything that builds or drives the client app.** An Impact Analysis that promises a live-function check is promising something this session cannot run; say who runs it.

**And a migration ledger describes the LINKED REMOTE, not the local stack the app talks to.** Before believing any Supabase CLI output about what exists, establish which instance it is describing.

## E3. Running Postgres and reading the right database

_Moved from the brain's `CLAUDE.md` on 2026-08-31: these are server facts, and they were loading in every vault session that never touches this repo._

**Postgres 16 RLS and SQL suites run in-sandbox via `pgserver`.** `pip install pgserver --break-system-packages`. The server does not persist across bash calls, so it is ONE-SHOT per call: `initdb -D /tmp/pgd -U postgres -A trust`, then `pg_ctl -D /tmp/pgd -o "-k /tmp/pgsock -p 5433 -c listen_addresses=''" -w start`, then apply `auth_shim.sql` plus the migrations plus the suite via `psql -h /tmp/pgsock -p 5433 -U postgres`, then stop. **To reproduce Supabase's grant behaviour, create an `anon` role and `alter default privileges in schema public grant all on tables to anon, authenticated` BEFORE the migrations.**

**A ledger about one database says nothing about another.** `supabase migration list` compares the migration FILES ON DISK against the LINKED REMOTE project, so neither of its columns describes the local stack the app actually talks to. Three consequences: a claim about what a database CONTAINS is settled by querying THAT database, because a migration ledger records intent and intent is not schema; establish WHICH instance a CLI command describes before believing it - `VITE_SUPABASE_URL` for the app, `supabase/.temp/project-ref` for the CLI, and they are routinely different; and a local stack started before a migration was written does not have it, which `supabase migration up` fixes. The tell is a tool answering confidently about "remote" when nothing in the failing path is remote.
