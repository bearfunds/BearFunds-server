# BearFunds Server — Operating Manual

Entry point for any Claude Code session in this repo. This file is a **thin loader**: it points at the canonical sources of truth rather than restating them, so there is exactly one authoritative copy of each. Read the chain below before doing any work.

This is the **server** of BearFunds ("Sweet Savings For Families") — the backend that introduces real authentication, multi-family tenancy, and server-side secrets. The **client repo** (React 19 + TS + Vite, offline-first) and a **brain vault** holding the decisions and synthesis are sibling checkouts; their paths are machine-specific and recorded in the brain's `CLAUDE Environments.md`. This repo is **scaffolded and DEPLOYED** (live since 2026-06-17): a Supabase project under `supabase/` (migrations 0001-0017 and counting, RLS policies, the `api` data Edge Function and the `parse-receipt` AI Edge Function) plus `contracts/` (the canonical Schema Contract). The design it implements is the brain's [[BearFunds Server Architecture]] (Q6).

## Read these first (in order)

1. **`0_AI_INSTRUCTIONS.md`** — the engineering protocol. The canonical working discipline (Impact Analysis → Approval Lock → Test-first → Verify), adapted for server work (contract bumps, tenancy, RLS). Read it fully and follow it exactly. It is authoritative over this file if they ever disagree.
2. **`contracts/2_SCHEMA_CONTRACT.xml`** — the backend API + DB contract (v1.20 at last update; the file's `Canonical: BearFunds-server · vX.Y` header line is the live version). **This repo is its canonical home** (the producer owns the interface; decided in the brain's Sources of Truth, 2026-06-01). It is a *shared* client↔server interface, so changes are deliberate version bumps that the operator drops into the client — never casual edits.

## The working loop (summary — `0_AI_INSTRUCTIONS.md` is canonical)

- Output an `## Impact Analysis` **before any code**: files/migrations/policies to touch, contract compliance (or an explicit versioned bump), the tenancy & auth check (server-derived `family_id`, RLS coverage, brain QA Areas 008/019), risk, and a test plan including RLS-isolation tests.
- Then present the plan and **enter the Approval Lock** — end with exactly: `Awaiting approval. Please use an approval keyword to proceed.` Generate no code until an approval keyword arrives. **Never simulate a user approval.**
- On approval: write tests first (incl. isolation tests), then the implementation, then remove dead code. Verify against the contract and the tenancy invariants.

## Architecture orientation (DEPLOYED — see the brain for the full design)

- **Platform:** Supabase — managed **Postgres** (datastore), **Auth** (Google sign-in), and **Edge Functions** (the API seam).
- **API seam:** a single Edge Function that **honors the Schema Contract** — one POST endpoint, action-based (`read`/`batchCreate`/`batchUpdate`/`batchUpsert`/`wipe`/`version`), snake_case logical keys, `{ status, data }` envelope. This keeps the client's `core/api/` layer almost unchanged (it swaps the shared bundle key for a Supabase session JWT).
- **Datastore:** one table per client collection (`transactions`, `categories`, `subcategories`, `accounts`, `entities`, `members`, `staged_transactions`, `budgets`) + a `families` tenancy root, mapping the brain's `Syncable` model 1:1, with server-managed `updated_at`, soft-delete `deleted`, and `is_immutable`.
- **Tenancy/auth:** every tenant row carries a server-derived `family_id`, enforced by Postgres **RLS**; `FamilyMember.role` (`admin`/`member`) is server-enforced. Secrets (Gemini, JWT) live server-side, never in the client bundle.
- A RESTful **v2** contract is deferred future work; honor the current v1.x contract now.
- **BUDGETS** (since contract v1.16) is a tenant table like any other, with one property worth stating: its whole meaningful payload - name, amount, note AND the category/account membership - rides the `enc` envelope. The server therefore cannot enforce the one-category-per-Budget-per-period rule; the client owns it (`core/budgetPolicy.ts`, with a unit matrix). Utilization is computed on device from the ledger, never snapshotted.

## Critical guardrails

- **The operator has TWO machines (Windows/PowerShell and macOS/zsh) - detect before writing a hand-off command.** Key on the repo root path: `D:\` is Windows, `/Users/arts-mac/` is macOS, anything else means stop and ask. Dialects and paths are in the brain's `CLAUDE Environments.md`, referred to BY NAME because the path is itself machine-specific. The Linux-sandbox commands Claude runs itself stay bash on every machine.
- **Coverage ratchet.** A bug fix lands with the regression test that would have caught it (fails before, passes after); a feature or changed flow lands with new or extended scenarios; REMOVING a rule retires the tests pinning it in the same slice; and the coverage question is answered explicitly before the work is "done". (Ratchet obligations: brain `CLAUDE.md` "Coverage ratchet"; how-to in the brain Testing Methodology.) **How to REPORT a count or a green claim is the `write-a-guard` skill**, canonical since 2026-08-29 - a green claim names its run and what it covered or says "not run", a bare "green" is forbidden, and a figure is stated in its predicate's own terms.
- **Never** write secrets into the repo or commits; **never** overwrite `.env*`. New key needed → say so in chat.
- **Never** change the wire shape implicitly — `2_SCHEMA_CONTRACT.xml` changes are deliberate, versioned, and propagated to the client. When a slice includes an operator-applied contract bump, stage `2_SCHEMA_CONTRACT.xml` with the slice's code in the same commit - it is part of the slice, not a follow-up.
- **Never** trust a client-supplied `family_id`/`user_id`; derive tenancy from the session. RLS on every tenant table is the backstop, and isolation must be tested directly.
- **Migrations are forward-only** — add a new one, don't edit an applied migration.
- Warn when a file exceeds ~300 lines; reuse existing helpers before writing new ones; don't refactor working architecture unless asked.

## Relationship to the brain (decisions live there, not here)

The **BearFunds brain vault** (separate repo; path per machine in its `CLAUDE Environments.md`) owns the decisions, the maps, and the decision trail. This repo owns the runtime and the canonical Schema Contract. When a "why" is needed, it lives in the brain.

Brain Reference docs (under `Areas/BearFunds/`): `Reference/BearFunds Server Architecture.md` (the design this repo implements), `Reference/BearFunds Schema Contract.md`, `Reference/BearFunds Data Model.md`, `Reference/BearFunds Persistence and Sync.md`; plus `Sources of Truth.md` (governance + the Schema Contract re-home). The completed `Migration Playbook.md` is archived at `Archive/BearFunds/`.

**The decision registry is one file per entry** (2026-08-25): the entries live under `Areas/BearFunds/Questions/` with the index page inside that folder. Cite a question by its prefixed code (`BF-Q6`, never a bare `Q6`), because every area keeps its own register and a bare code no longer says which one is meant.

Initial setup is complete and kept only as history: the canonical contract re-home (2026-06-02) and the Supabase scaffold + deploy (2026-06-17) both went through the standard protocol; details in the brain.

## Environment & write-path rules (canonical: brain `CLAUDE.md`, "Tool reliability")

**THE WRITE-PATH RULES ARE IN THE BRAIN'S `CLAUDE.md`, UNDER "Tool reliability", AND THIS FILE NO LONGER RESTATES THEM.** Read that section before any session that writes to this repo: the write-path decision matrix, the absolute rule forbidding any edit that passes through a full read and a full write of an existing file, strict ASCII and the verify-every-write checks, the stale-mount hazards, the informational-only git boundary, and the no-`npm install`-on-a-mount rule. Every one of those governs this repo unchanged.

**WHAT DOES NOT LIVE IN THE BRAIN, AND THEREFORE STAYS HERE - THIS REPO'S EXECUTION BOUNDARY** (codified 2026-06-10). The sandbox is Linux, with no browser and an allowlisted network. Proven sandbox-safe here: Postgres 16 RLS-isolation suites via `pgserver` (the recipe itself is in the brain's Tool reliability) and pure-Node action/validation harnesses. **Operator-side: `supabase functions serve` and any live-function E2E, Deno-native test runs - `deno.land` is network-blocked - and anything that builds or drives the client app.** The Deno and Supabase-CLI halves are true of this repo and of nowhere else, so they are not a digest of anything.

_A four-point digest of the brain's write-path rules stood above this paragraph and was DELETED on 2026-08-27, verified point by point against the canonical section first. The execution boundary was NOT deleted with it: the check found that its Deno and `supabase functions serve` clauses appear nowhere in the brain, so it was never a copy, and deleting it would have destroyed the only record of them. That check is the reason the deletion was safe, and it is worth stating that it fired._

_A long-form "Tool reliability (file writes)" section used to sit here and was DELETED in the 2026-08-05 merge rather than merged, because it stated a policy this repo has since **reversed**: "default to writing through bash... use the Edit tool only for small ASCII-only changes." The brain's absolute rule is the opposite, and it is the opposite deliberately - the scripted read-modify-write path truncated three client files mid-JSX and broke a fourth time wearing a comment-only costume. Keeping both would have left this file recommending the exact path its own first rule forbade. The stale-mount and index-corruption hazards it also described survive in the brain's canonical section; the incident narratives live in the brain's `CLAUDE Lessons — Archive.md`, which is where a repo loader should point rather than restate._
