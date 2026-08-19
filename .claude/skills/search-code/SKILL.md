---
name: search-code
description: Find things reliably in a codebase and its registers - a definition, every caller, whether something exists at all, whether a finding is already filed, what enforces a rule. Use when locating code or evidence ("where is X defined", "every caller of X", "does X exist anywhere in the tree", "is this already registered", "what changed in X"), before renaming or deleting anything, before reporting a count or a site list, and - especially - when a search returned nothing and you are about to conclude absence.
---

# Search a codebase

**A search is a claim.** Every incident behind this skill is a search that returned a confident, complete-looking, wrong result: nothing threw, nothing errored, and the only symptom was a plausible number. Treat a search as evidence you must earn.

> **This file is a DROP-IN COPY.** The canonical `search-code` lives in the `second-brain-skills` plugin (repo `01-skills-plugins`; its checkout path is machine-specific and recorded in the brain's `CLAUDE Environments.md`). It is copied into each repo so a session is self-contained on either machine. **Never edit this file** - a rule change is written to the canonical copy and every drop-in is refreshed from it. Repo-specific findings do NOT belong here: they go to `.claude/skill-extensions/search-code.md` in this repo.

## Load the repo's extension first

The rules here are repo-agnostic. **Every repo's own search hazards live in `.claude/skill-extensions/search-code.md` inside that repo** - the tooling that lies, the helpers with documented blind spots, the two spellings of the same hook. Read it before searching if it exists; a repo without one simply gets the general discipline.

That file is written and verified per repo, and it is where a repo-specific finding is filed. Nothing repo-specific belongs in this skill.

## Two paths

**Cheap check - most searches.** Name what you expect to find, run it **unbounded**, and read the result against that expectation. If the result surprises you - a zero, a number you cannot explain, or a hit you believe is wrong - **stop and run the full procedure.** The surprise is the trip-wire; do not explain it away and continue.

**Full procedure - mandatory when any of these is true:**

- a COUNT or a SITE LIST that anyone will act on
- an ABSENCE claim ("X does not exist", "nothing reads this")
- anything about to be deleted or renamed on the strength of the search
- filing a finding as NEW
- the result goes into a plan, a register, a commit message or a handoff

If you read step 3 and step 6 and nothing else, you have most of the value.

---

## 0. Gate: can a search answer this at all?

Ask what evidence could settle the question. Stop and MEASURE if the answer lives only:

- **at render time** - in the box model, the cascade, or the layout. The markup on disk can be entirely correct while the render contradicts it.
- **in a running process** - and if the app disagrees with the tree, suspect a stale cache or service worker FIRST, before reading source and before reverting. An experiment whose readout is the rendered app proves nothing until you prove the app is reading the tree.
- **in an outcome that cannot go red** - a discarded position class, a prop that resolves correctly and renders invisibly, a prop rendered in one variant only. The control still works; only the DOM can tell you where it is.
- **at a site that does not exist yet.** A change with known LANDING PLACES (a new table, a new synced collection, a new contract field) needs a checklist, not a pattern - search proves things only about places a reference already exists.

A fix that left an IDENTICAL failure signature is refuted. Measure; do not re-read.

## 1. Name the claim, then pick the corpus

Write the sentence the search must support before running anything - "X has N call sites", "X appears nowhere", "this is not already filed". The sentence fixes the corpus and the bounds, and it is what you will otherwise report without them.

These corpora are NOT interchangeable: the code tree, the vault's registers, the vault's prose, read-only contracts, the OTHER repo, a running process.

- **Filing anything as new greps the REGISTER first** - two or three distinctive words of the title you are about to write.
- **Establish what your tool is describing.** A sandbox git can invent a diff as readily as hide one; a staging path can serve pre-edit bytes with fresh metadata; a migration ledger describes the remote, not the local instance. A direct read of the file is authoritative over a cached view.
- **Read the guard's header before duplicating its search.** Well-maintained tooling documents its own limits, and the boundary you need is often already written down.

## 2. Derive the subject list

Never hand-type it. Derive from the filesystem, the closed union or the directory, then subtract an exclusion map in which **every exclusion carries a written reason** - then a new member joins by existing, and skipping it must be argued for in the diff.

- Name the sources the derivation walks, and prove it found something. "Derived" does not mean "complete".
- **Classify per INSTANCE, never per file.** If one member of a file opted out, would the others still be checked?
- This applies to PROSE as hard as to guards. A census inside a planning document has no compiler, so a silently dropped directory is wrong in every headline number and nothing can fail.

## 3. The inversion question

> **What would a WRONG instance look like, and can this search even contain it?**

The highest-yield check in this skill. If the answer is *"a wrong instance would look like a right one minus the thing I am searching for"*, the search is inverted - stop, and key on the shape the broken case cannot avoid having.

It fails at two altitudes for one reason, keying on ADOPTION rather than on SHAPE:

- **Subject list** - a teardown sweeping the marker that MIGRATED shells carry; a site list derived from a helper's callers, missing the surfaces broken because they never called it; a fixture minted from the same seed ids the code keys on.
- **Predicate** - a notice defined as "fill plus border" (six borderless ones invisible); a delete defined as "a trash glyph"; a selection defined as a variable named `selected`.

**Mechanical tell: a predicate you have widened more than once is keyed on the wrong axis**, and the next spelling will beat it too.

Where stragglers genuinely cannot be derived, the subject list is a UNION - derived members plus a registered list, pinned to a register that empties itself as they convert.

## 4. Write the pattern

**Enumerate the legal spellings first.** Both quote dialects; attribute versus prop versus object-property spelling; literal versus escaped (source versus built output); single-line versus multi-line; contiguous-ordered versus interleaved; one element versus split across two; a concept as a NAME versus as a COUNT or a synonym. Check the quantifier too - "at least one" cannot express "too many".

- **Anchor both ends.** A boundary you did not write is a case the pattern silently reclassifies. `\b` is wrong wherever the language treats `-`, `[` or `]` as ordinary - use `(?<![-\w])` / `(?![-\w])`. Substring equality is a missing boundary in disguise.
- **If you are parsing a language, use its parser.** A hand-rolled scanner will read an apostrophe in a comment as a string open, swallow a nested payload into an opening tag, end a tag at a generic's `>`, and return no parentage at all.
- **Prefer a scope to a window.** Three patches at a character-count lookahead that keep getting closer mean the tool's SHAPE is wrong, not its tuning.
- **Decide whether prose counts - both answers are load-bearing.** An absence check blanks comments; a check whose fixture is a quoted dead spelling must not.

## 5. Prove the predicate before trusting it

A check never observed to fail is a hypothesis wearing a lab coat. Two cheap controls:

1. **Found-some** - feed it something you know is there, require a hit.
2. **Catches-the-decorated-form** - feed it the prefixed, escaped, interleaved or object-property spelling and require it to be CAUGHT.

**And check the other side of the comparison.** Every value you expect must be producible by your own predicate; an expected value the predicate cannot match is an invented one, and it will agree with wrong code because both came from the same assumption.

## 6. Run unbounded, then read the result

**Never truncate.** No `head`, no `.slice`, no stopping at the first offender. A truncated set reads exactly like a complete one, and a cap re-creates the trap at a different size - remove it rather than raising it. Count first, then look.

**Reading a NEGATIVE result is where this goes wrong most quietly**, because a broken scan still returns results.

- Zero hits is not absence. A cached or sandboxed grep's silence is not proof.
- "No reader found" is WEAKER evidence for a DOM attribute or a string-keyed lookup than for a code symbol - a runtime handler or an external consumer reads it without appearing in the tree.
- The compiler is an exhaustive search **only where the type is CLOSED**. Confirm the union is pinned complete before treating "the typecheck would have caught it" as a result.
- **A failure you believe is wrong is evidence about the PREDICATE.** The instinct to override that belief and "fix" the accused subject is the failure.

## 7. Report with its bounds

- **An estimate says so.** A sizing probe has none of a guard's defences by definition; a scan whose bounds were chosen for speed is quoted WITH those bounds or not offered as a measurement.
- **A census is an UPPER BOUND until each member has been read.**
- **Measure the thing, not its generator's source.** If the subject BUILDS its content, execute it and count the output.
- **A cited count is a claim, not a search** - re-run before acting. Registers decay fastest on exactly the identifiers the current engagement is renaming, and **a number quoted out of a narrative describes the narrative**.
- **Prose you touch is triaged by TENSE**: a sentence describing what IS is now false and rides the same commit; a sentence describing what HAPPENED is correct and must not be edited.

## 8. If you act on the result

- **Assert how many times the anchor matched**, not merely that it did.
- **Do not corrupt the corpus you are reading.** Verify an append at the SEAM above the new content, never the tail. Emit-then-link, never link-then-emit.
- Renaming or deleting many sites is a different job - it is edit mechanics, and the vault's own absolute rule owns it.

---

## When to stop and ask

**Default: do not interrupt.** Collect questions and raise them in ONE batch at the end. A skill that stops often is a skill that gets bypassed.

**Three hard stops, mid-flight, and no others:**

1. **Two authoritative sources disagree.** Never silently resolve a contradiction - file it and stop.
2. **About to delete or rename on the strength of a search whose subject list could not be derived.** Deletion is the irreversible one.
3. **The inversion question (step 3) has no answer.** If you cannot say what a wrong instance looks like, you do not yet understand the subject well enough to search for it.

Everything else batches: register drift, claims you could not verify, a count that will size someone's slice.

## Environments

**An agent's own searches are machine-invariant** where the shell is a sandbox rather than the operator's machine - the same grep behaves identically regardless of which machine the operator is on. Do not dialect them.

What actually varies:

- **Commands handed TO the operator** take that machine's shell. Detect from the repo root path before writing one - and prefer not to hand one over at all.
- **Never hardcode an absolute path.** Repo-relative only; roots differ per machine.
- **Line endings.** A `$` anchor, a pattern spanning a line end, or byte arithmetic behaves differently under CRLF.
- **Case sensitivity.** A Linux sandbox is case-sensitive; macOS and Windows mounts are not. The agent's greps are consistent with each other; an operator-run one may not be.
- **Observed-versus-applies.** Where a hazard has only ever been seen on one machine, the rule still applies on all of them; the evidence does not.
- **A shared vault means amendments collide** - hence the machine tag below.

---

## Raw amendments

_Session buffer. An entry here is a SIGNAL, not a rule - one instance is a data point. `references/rules.md` has been distilled and verified; entries here have not, and must not be read with the same authority._

**This section implements the shared amendment protocol** - entry shape (six fields, `Evidence` mandatory), session tags, stages, and the 7-entry cap are defined once in the `session-wrap` skill's `references/skill-amendments.md`. Read it there rather than relying on a summary here.

**What is specific to this skill:**

- **Elevating** means adding or editing a rule in `references/rules.md`. A rule that turns out to be WRONG is deleted outright - this skill records what is true NOW, and a refuted rule kept "so the reversal is legible" biases the next reader against what is known in the moment.
- **A repo-specific finding does NOT belong here.** It goes to that repo's `.claude/skill-extensions/search-code.md`, which carries its own buffer. Routing test: would this still be true in a different repo?
- An amendment may CONTRADICT a rule and should say so plainly. It never silently replaces it - **the rule stands until elevated.**

_(no amendments yet)_

---

## Reference

`references/rules.md` - all 25 rules with the incidents that bought them, grouped by what fails: the predicate, the subject list, the tokenizer, the report, the corpus.

**When your search hardens into a guard:** a predicate worth copying is worth extracting, and an extracted one needs its own suite the day it gets a second caller. Controls at the CALL SITES cannot prove a shared tokenizer, because every consumer assumes the scan worked before its own predicate begins.
