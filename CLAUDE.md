# BearFunds Server — Operating Manual

Entry point for any Claude Code session in this repo. This file is a **thin loader**: it points at the canonical sources of truth rather than restating them, so there is exactly one authoritative copy of each. Read the chain below before doing any work.

This is the **server** of BearFunds ("Sweet Savings For Families") — the backend that introduces real authentication, multi-family tenancy, and server-side secrets. The **client repo** (React 19 + TS + Vite, offline-first) and a **brain vault** holding the decisions and synthesis are sibling checkouts; their paths are machine-specific and recorded in the brain's `CLAUDE Environments.md`. This repo is **scaffolded and DEPLOYED** (live since 2026-06-17): a Supabase project under `supabase/` (migrations 0001-0012 + RLS policies + the `api` data Edge Function and the `parse-receipt` AI Edge Function) plus `contracts/` (the canonical Schema Contract). The design it implements is the brain's [[BearFunds Server Architecture]] (Q6).

## Read these first (in order)

1. **`0_AI_INSTRUCTIONS.md`** — the engineering protocol. The canonical working discipline (Impact Analysis → Approval Lock → Test-first → Verify), adapted for server work (contract bumps, tenancy, RLS). Read it fully and follow it exactly. It is authoritative over this file if they ever disagree.
2. **`2_SCHEMA_CONTRACT.xml`** — the backend API + DB contract (v1.16). **This repo is its canonical home** (the producer owns the interface; decided in the brain's Sources of Truth, 2026-06-01). It is a *shared* client↔server interface, so changes are deliberate version bumps that the operator drops into the client — never casual edits. The canonical copy carries a `Canonical: BearFunds-server · vX.Y` header line; the client keeps a downstream drop-in.

## The working loop (summary — `0_AI_INSTRUCTIONS.md` is canonical)

- Output an `## Impact Analysis` **before any code**: files/migrations/policies to touch, contract compliance (or an explicit versioned bump), the tenancy & auth check (server-derived `family_id`, RLS coverage, brain QA Areas 008/019), risk, and a test plan including RLS-isolation tests.
- Then present the plan and **enter the Approval Lock** — end with exactly: `Awaiting approval. Please use an approval keyword to proceed.` Generate no code until an approval keyword arrives. **Never simulate a user approval.**
- On approval: write tests first (incl. isolation tests), then the implementation, then remove dead code. Verify against the contract and the tenancy invariants.

## Architecture orientation (DEPLOYED — see the brain for the full design)

- **Platform:** Supabase — managed **Postgres** (datastore), **Auth** (Google sign-in), and **Edge Functions** (the API seam).
- **API seam:** a single Edge Function that **honors the v1.16 Schema Contract** — one POST endpoint, action-based (`read`/`batchCreate`/`batchUpdate`/`batchUpsert`/`wipe`/`version`), snake_case logical keys, `{ status, data }` envelope. This keeps the client's `core/api/` layer almost unchanged (it swaps the shared bundle key for a Supabase session JWT).
- **Datastore:** one table per client collection (`transactions`, `categories`, `subcategories`, `wallets`, `entities`, `members`, `staged_transactions`, `budgets`) + a `families` tenancy root, mapping the brain's `Syncable` model 1:1, with server-managed `updated_at`, soft-delete `deleted`, and `is_immutable`.
- **Tenancy/auth:** every tenant row carries a server-derived `family_id`, enforced by Postgres **RLS**; `FamilyMember.role` (`admin`/`member`) is server-enforced. Secrets (Gemini, JWT) live server-side, never in the client bundle.
- A RESTful **v2** contract is deferred future work; honor v1.16 now.
- **BUDGETS (v1.16)** is a tenant table like any other, with one property worth stating: its whole meaningful payload - name, amount, note AND the category/account membership - rides the `enc` envelope. The server therefore cannot enforce the one-category-per-Budget-per-period rule; the client owns it (`core/budgetPolicy.ts`, with a unit matrix). Utilization is computed on device from the ledger, never snapshotted.

## Critical guardrails

- **The operator has TWO machines (Windows/PowerShell and macOS/zsh) - detect before writing a hand-off command.** Key on the repo root path: `D:\` is Windows, `/Users/arts-mac/` is macOS, anything else means stop and ask. Dialects and paths are in the brain's `CLAUDE Environments.md`. The Linux-sandbox commands Claude runs itself stay bash on every machine. (Brain CLAUDE.md convention, v1.48; was PowerShell-only v1.6 to v1.47.)
- **Coverage ratchet.** Every bug, feature, or contract/tenancy change is a test opportunity: a bug fix lands with the regression test that would have caught it (fails before, passes after); a feature or changed flow lands with new or extended tests (incl. an RLS-isolation test for any tenant-table change); and the coverage question is answered explicitly (tests added, or a one-line reason none were warranted) before the work is "done". (Brain CLAUDE.md convention, v1.8; how-to in the brain Testing Methodology.)
- **Never** write secrets into the repo or commits; **never** overwrite `.env*`. New key needed → say so in chat.
- **Never** change the wire shape implicitly — `2_SCHEMA_CONTRACT.xml` changes are deliberate, versioned, and propagated to the client. When a slice includes an operator-applied contract bump, stage `2_SCHEMA_CONTRACT.xml` with the slice's code in the same commit - it is part of the slice, not a follow-up.
- **Never** trust a client-supplied `family_id`/`user_id`; derive tenancy from the session. RLS on every tenant table is the backstop, and isolation must be tested directly.
- **Migrations are forward-only** — add a new one, don't edit an applied migration.
- Warn when a file exceeds ~300 lines; reuse existing helpers before writing new ones; don't refactor working architecture unless asked.

## Relationship to the brain (decisions live there, not here)

The **BearFunds brain vault** (separate repo; path per machine in its `CLAUDE Environments.md`) owns the decisions, the maps, and the decision trail. This repo owns the runtime and (now) the canonical Schema Contract. When a "why" is needed, it lives in the brain.

Brain Reference docs (under `Areas/BearFunds/`):
- `Reference/BearFunds Server Architecture.md` — the design this repo implements (datastore, auth, tenancy, contract handling, migration path).
- `Reference/BearFunds Schema Contract.md`, `Reference/BearFunds Data Model.md`, `Reference/BearFunds Persistence and Sync.md` — the contract map, the `Syncable` model, and the client's sync layer this server must interoperate with.
- `Sources of Truth.md` (governance + the Schema Contract re-home), `Open Questions.md` (the decision registry). The completed `Migration Playbook.md` (esp. L2 auth, L4 server-authoritative sync) is archived at `Archive/BearFunds/` (vault reorg 2026-07-05).

## Setup (done - kept for history)

Both initial-setup steps are complete: (1) the canonical `2_SCHEMA_CONTRACT.xml` is re-homed here with the `Canonical: BearFunds-server` header (now v1.13) and the client holds a downstream drop-in; (2) the Supabase layout is scaffolded and deployed - `supabase/` (migrations 0001-0012 + RLS + the `api` and `parse-receipt` Edge Functions) and `contracts/`, with action-handler + RLS-isolation tests. New work goes through the `0_AI_INSTRUCTIONS.md` protocol (Impact Analysis -> Approval) as usual.


## Tool reliability (file writes)

The Edit/Write tools can silently truncate a file mid-write while reporting success. Two known triggers, often combined: (1) multi-byte / non-ASCII characters in the content (em dashes, smart quotes, arrows, emoji), where the write is cut at the offending character; and (2) large files, very long lines, or content near the end. The Edit tool rewrites the whole file, so a stray non-ASCII character anywhere in it - not only in the change - can trip this.

Policy (prevention-first; mirrors the brain vault CLAUDE.md):
- Default to writing through bash (a heredoc, or a Python literal-replace) for anything beyond a tiny, ASCII-only, surgical edit. Use the Edit tool only for small ASCII-only changes.
- Keep all authored content strict ASCII - no em dashes, smart quotes, arrows, or emoji in code or comments.
- Verify every write immediately (wc -l plus tail, or grep for the expected closing section). A "success" tool result is not proof; the file on disk is.
- If a write did truncate, recover from git (tracked files) or rewrite via heredoc (new files), then re-verify.

Additional hazard (learned 2026-06-04): git commands run from the Cowork sandbox against this Windows-mounted repo can corrupt the git index (garbage entries, orphaned `index.lock` the sandbox cannot delete) - in one case from plain `git status`. From the sandbox, git is informational-only (`git --no-optional-locks status`, `diff`, `show`, `log`, `ls-files`); index-writing commands (`add`, `reset`, `checkout`, `restore`, `commit`) are operator-side. Recovery: working tree is unaffected; run `del .git\index.lock` (if present) then `git reset`.
Stale-mount caveat: the sandbox's view of files freshly edited on the Windows side can show phantom truncation/NUL-padding (stale size cache); verify through the desktop-side Read tool before declaring corruption.



Execution-environment boundary (codified 2026-06-10): the Cowork sandbox is Linux with no browser and an allowlisted network. Proven sandbox-safe here: Postgres 16 RLS-isolation suites and pure-Node action/validation harnesses. Operator-side: `supabase functions serve` / live-function E2E, Deno-native test runs (deno.land is network-blocked), and anything that builds or drives the client app (its `node_modules` is built for the operator's platform and cannot execute on Linux either way - see the client CLAUDE.md). Never `npm install` onto a mounted repo from the sandbox.
