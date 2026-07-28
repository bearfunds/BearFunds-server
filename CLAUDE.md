# BearFunds Server — Operating Manual

Entry point for any Claude Code session in this repo. This file is a **thin loader**: it points at the canonical sources of truth rather than restating them, so there is exactly one authoritative copy of each. Read the chain below before doing any work.

This is the **server** of BearFunds ("Sweet Savings For Families") — the backend that provides real authentication, multi-family tenancy, and server-side secrets. The **client repo** (React 19 + TS + Vite, offline-first) is the sibling directory `../client/` in this workspace. This repo is **DEPLOYED** (live since 2026-06-17): a Supabase project under `supabase/` (migrations 0001-0016 + RLS policies + the `api` data Edge Function and the `parse-receipt` AI Edge Function) plus `contracts/` (the canonical Schema Contract).

## Read these first (in order)

1. **`0_AI_INSTRUCTIONS.md`** — the engineering protocol. The canonical working discipline (Impact Analysis → Approval Lock → Test-first → Verify), adapted for server work (contract bumps, tenancy, RLS). Read it fully and follow it exactly. It is authoritative over this file if they ever disagree.
2. **`contracts/2_SCHEMA_CONTRACT.xml`** — the backend API + DB contract (v1.16). **This repo is its canonical home** (the producer owns the interface; decided 2026-06-01). It is a *shared* client↔server interface, so changes are deliberate version bumps that the operator drops into the client — never casual edits. The canonical copy carries a `Canonical: BearFunds-server · vX.Y` header line; the client keeps a downstream drop-in (currently v1.15, one bump behind).

## The working loop (summary — `0_AI_INSTRUCTIONS.md` is canonical)

- Output an `## Impact Analysis` **before any code**: files/migrations/policies to touch, contract compliance (or an explicit versioned bump), the tenancy & auth check (server-derived `family_id`, RLS coverage), risk, and a test plan including RLS-isolation tests.
- Then present the plan and **enter the Approval Lock** — end with exactly: `Awaiting approval. Please use an approval keyword to proceed.` Generate no code until an approval keyword arrives. **Never simulate a user approval.**
- On approval: write tests first (incl. isolation tests), then the implementation, then remove dead code. Verify against the contract and the tenancy invariants.

## Architecture orientation (DEPLOYED)

- **Platform:** Supabase — managed **Postgres** (datastore), **Auth** (Google sign-in), and **Edge Functions** (the API seam).
- **API seam:** a single Edge Function that **honors the v1.16 Schema Contract** — one POST endpoint, action-based (`read`/`batchCreate`/`batchUpdate`/`batchUpsert`/`wipe`/`version`), snake_case logical keys, `{ status, data }` envelope. This keeps the client's `core/api/` layer almost unchanged (it swaps the shared bundle key for a Supabase session JWT).
- **Datastore:** one table per client collection (`transactions`, `categories`, `subcategories`, `wallets`, `entities`, `members`, `staged_transactions`, `budgets`) + a `families` tenancy root, mapping the client's `Syncable` model 1:1, with server-managed `updated_at`, soft-delete `deleted`, and `is_immutable`.
- **Tenancy/auth:** every tenant row carries a server-derived `family_id`, enforced by Postgres **RLS**; `FamilyMember.role` (`admin`/`member`) is server-enforced. Secrets (Gemini, JWT) live server-side, never in the client bundle.
- A RESTful **v2** contract is deferred future work; honor v1.16 now.
- **BUDGETS (v1.16)** is a tenant table like any other, with one property worth stating: its whole meaningful payload - name, amount, note AND the category/account membership - rides the `enc` envelope. The server therefore cannot enforce the one-category-per-Budget-per-period rule; the client owns it (`core/budgetPolicy.ts`, with a unit matrix). Utilization is computed on device from the ledger, never snapshotted.

## Edge-function webhooks (SQL-managed, not dashboard)

- **Canonical definition: `supabase/ops/webhook_triggers.sql`** - a manual ops script (NOT a migration; the trigger args carry WEBHOOK_SECRET and secrets never enter migrations). It contains the `supabase_functions` schema bootstrap (PART 1) and both trigger definitions (PART 2). Run it when bootstrapping a new environment; re-run PART 2 after rotating WEBHOOK_SECRET.
- Both webhooks are raw SQL triggers on `supabase_functions.http_request()` - they do NOT appear under Database > Webhooks in the dashboard:
  - `feedback` on `public.feedback` INSERT -> `send-feedback-notification`
  - `send_welcome_email` on `auth.users` INSERT -> `send-welcome-email`
- Both carry `Authorization: Bearer <WEBHOOK_SECRET>`; rotating that secret (function secrets) REQUIRES recreating both triggers (PART 2) or they 401.
- The `supabase_functions` schema was missing on this project (platform never provisioned it) and was bootstrapped manually per PART 1.
- Verify delivery via `net._http_response` (status_code + content); 200 with `sent:false` means the function ran but Resend rejected (check function logs).

## Critical guardrails

- **Operator runs commands in PowerShell (Windows), not bash.** Write every operator-facing hand-off command (git, npm, builds, tests, curl, file ops) in PowerShell syntax (`Copy-Item`/`copy` not `cp`, `$env:VAR=...` not `export`, backtick line-continuation, `;`/newlines not `&&`, `Invoke-RestMethod`/`curl.exe` not bare `curl`). The commands Claude runs itself stay bash. `supabase/tests/` ships a `.ps1` twin of every `.sh` runner for this reason.
- **Coverage ratchet.** Every bug, feature, or contract/tenancy change is a test opportunity: a bug fix lands with the regression test that would have caught it (fails before, passes after); a feature or changed flow lands with new or extended tests (incl. an RLS-isolation test for any tenant-table change); and the coverage question is answered explicitly (tests added, or a one-line reason none were warranted) before the work is "done".
- **Never** write secrets into the repo or commits; **never** overwrite `.env*`. New key needed → say so in chat.
- **Never** change the wire shape implicitly — `contracts/2_SCHEMA_CONTRACT.xml` changes are deliberate, versioned, and propagated to the client. When a slice includes an operator-applied contract bump, stage the contract file with the slice's code in the same commit - it is part of the slice, not a follow-up.
- **Never** trust a client-supplied `family_id`/`user_id`; derive tenancy from the session. RLS on every tenant table is the backstop, and isolation must be tested directly.
- **Migrations are forward-only** — add a new one, don't edit an applied migration.
- Warn when a file exceeds ~300 lines; reuse existing helpers before writing new ones; don't refactor working architecture unless asked.

## Tool reliability (file writes)

The Edit/Write tools can silently truncate a file mid-write while reporting success. Two known triggers, often combined: (1) multi-byte / non-ASCII characters in the content (em dashes, smart quotes, arrows, emoji), where the write is cut at the offending character; and (2) large files, very long lines, or content near the end. The Edit tool rewrites the whole file, so a stray non-ASCII character anywhere in it - not only in the change - can trip this.

Policy (prevention-first):
- Default to writing through bash (a heredoc, or a Python literal-replace) for anything beyond a tiny, ASCII-only, surgical edit. Use the Edit tool only for small ASCII-only changes.
- Keep all authored content strict ASCII - no em dashes, smart quotes, arrows, or emoji in code or comments.
- Verify every write immediately (wc -l plus tail, or grep for the expected closing section). A "success" tool result is not proof; the file on disk is.
- If a write did truncate, recover from git (tracked files) or rewrite via heredoc (new files), then re-verify.

Additional hazard (learned 2026-06-04): git commands run from a sandbox against a Windows-mounted checkout of this repo can corrupt the git index (garbage entries, orphaned `index.lock` the sandbox cannot delete) - in one case from plain `git status`. Under that setup git is informational-only (`git --no-optional-locks status`, `diff`, `show`, `log`, `ls-files`); index-writing commands (`add`, `reset`, `checkout`, `restore`, `commit`) are operator-side. Recovery: working tree is unaffected; run `del .git\index.lock` (if present) then `git reset`.
Stale-mount caveat: a sandbox view of files freshly edited on the Windows side can show phantom truncation/NUL-padding (stale size cache); verify through the desktop-side Read tool before declaring corruption.

Execution-environment boundary (codified 2026-06-10): a Linux sandbox with no browser and an allowlisted network can run the Postgres 16 RLS-isolation suites and the pure-Node action/validation harnesses. Operator-side: `supabase functions serve` / live-function E2E, Deno-native test runs (deno.land is network-blocked), and anything that builds or drives the client app (a Windows `node_modules` cannot execute on Linux - see the client CLAUDE.md). Never `npm install` onto a Windows-mounted repo from a sandbox.
