# BearFunds Server — Operating Manual

**A routing file, not a manual.** Everything below points; nothing here restates a rule that lives somewhere else.

The **server** of BearFunds - a deployed Supabase backend (Postgres, RLS, Auth, Edge Functions) under `supabase/`, plus `contracts/`. The **client** (React 19 + TypeScript, offline-first) and the **brain vault** (decisions, maps, the trail) are sibling checkouts; their paths are per machine, in the brain's `CLAUDE Environments.md`.

## Read these first (in order)

1. **`0_AI_INSTRUCTIONS.md`** - the engineering protocol, adapted for server work, and authoritative over this file.
2. **`contracts/2_SCHEMA_CONTRACT.xml`** - the API and DB contract, and **canonical here**: the producer owns the interface. The file's `Canonical:` header line is the live version. A change is a deliberate versioned bump the operator drops into the client, never a casual edit.

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
