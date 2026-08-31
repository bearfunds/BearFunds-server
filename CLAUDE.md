# BearFunds Server — Operating Manual

**A routing file, not a manual.** Everything below points; nothing here restates a rule that lives somewhere else.

This is the **server** of BearFunds ("Sweet Savings For Families") — the backend that provides real authentication, multi-family tenancy, and server-side secrets. The **client repo** (React 19 + TS + Vite, offline-first) is the sibling directory `../client/` in this workspace. This repo is **DEPLOYED** (live since 2026-06-17): a Supabase project under `supabase/` (migrations 0001-0016 + RLS policies + the `api` data Edge Function and the `parse-receipt` AI Edge Function) plus `contracts/` (the canonical Schema Contract).

## Read these first (in order)

1. **`0_AI_INSTRUCTIONS.md`** — the engineering protocol. The canonical working discipline (Impact Analysis → Approval Lock → Test-first → Verify), adapted for server work (contract bumps, tenancy, RLS). Read it fully and follow it exactly. It is authoritative over this file if they ever disagree.
2. **`contracts/2_SCHEMA_CONTRACT.xml`** — the backend API + DB contract (v1.16). **This repo is its canonical home** (the producer owns the interface; decided 2026-06-01). It is a *shared* client↔server interface, so changes are deliberate version bumps that the operator drops into the client — never casual edits. The canonical copy carries a `Canonical: BearFunds-server · vX.Y` header line; the client keeps a downstream drop-in (currently v1.15, one bump behind).

## Start work with a skill

`impact-analysis` executes the protocol's Step 1 rather than recalling it, and loads this repo's extension first. `search-code` searches; `blast-radius` sweeps a rename, deletion or retirement; `contract-dropin` proposes a change to a contract; `commit-handoff` assembles the commit script. Each reads its own file in `.claude/skill-extensions/`.

## Never

- Write a secret into the repo or a commit, or overwrite `.env*`. If a new key is needed, say so in chat.
- Trust a client-supplied `family_id` or `user_id`. Tenancy is derived from the session, RLS on every tenant table is the backstop, and isolation is tested directly.
- Edit an applied migration. Migrations are forward-only - a correction is a new one.
- Change the wire shape implicitly, or edit `contracts/2_SCHEMA_CONTRACT.xml` by hand. Only operator hands touch a contract, and a bump rides the slice's own commit.
- Simulate an approval, or write code before one.

## Relationship to the brain (decisions live there, not here)

The design this repo implements is the brain's `Areas/BearFunds/Reference/BearFunds Server Architecture.md`, alongside the schema contract, data model and persistence docs, plus `Sources of Truth.md` for the governance. This repo owns the runtime and the canonical Schema Contract; the why lives in the brain. Registers are one file per entry, cited by prefixed code (`BF-Q`, `BF-C`, `BF-B`, `BF-H`).

**Environment and write-path rules are canonical in the brain's `CLAUDE.md` under "Tool reliability"** - the write-path matrix, the absolute rule against a scripted read-modify-write, strict ASCII, the stale-mount and git hazards, and the no-`npm install`-on-a-mount rule. Read it before writing here.

**Repo-specific lessons live in `.claude/skill-extensions/`**, one file per skill that loads it: `impact-analysis.md` (architecture orientation, and this repo's execution boundary - what the sandbox can and cannot run), `contract-dropin.md`, `blast-radius.md`, `commit-handoff.md`. **An extension is loaded by its skill, never restated here.** Nothing in `.claude/skills/` - a repo-local copy of a shared skill shadows the plugin's and goes stale.
