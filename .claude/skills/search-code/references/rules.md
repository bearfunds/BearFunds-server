# search-code: the rules

**Scope: repo-agnostic.** These rules are about predicates, subject lists, tokenizers, report bounds and choice of corpus - they hold in any codebase. The incidents illustrating them come from BearFunds, which is evidence rather than scope. Per-repo hazards live in that repo's `traps.md`.

_25 rules distilled from 103 recorded incidents. Grouped by WHAT FAILED, which is not the same as where it hurt - a search goes wrong at the predicate, the subject list, the tokenizer beneath them, the report, or the choice of corpus. SKILL.md carries the procedure; this file carries the reasoning and the incidents that bought each rule._

---

## A. The predicate

_Two symptoms, one cause. The QUIET form reports absence and the sweep looks finished. The LOUD form accuses innocent code, which is more dangerous, because the cheapest repair is always to "fix" the innocent subject._

### A-R1. Enumerate the legal spellings BEFORE writing the pattern

The thing you are looking for almost always has more than one lawful form, and you will write the one you happened to see. Dimensions that have actually bitten here:

- **Quote dialect.** A scenario-id scan matched `id: 'T-...'` only; the tree also uses double quotes. It reported a maximum of 205 against a real 212, and a new scenario collided with a live T-206.
- **Attribute versus prop versus object-property.** `data-testid="x"`, `testId={x}`, `id: X,`. A guard written for the attribute form reported a correctly-wired file as broken.
- **Literal versus escaped.** A verification grep for `CELL_WIDTH[cellWidth]` returned 0 against a compiled artifact holding the escaped regex form, and read as a missing edit.
- **Single-line versus multi-line.** A dead-variant grep required two props on the SAME LINE - blind to multi-line JSX and to the `axes: { tone, weight }` object form. It reported six dead variants of which FOUR had real callers, and was run twice the same day.
- **Contiguous-ordered versus interleaved.** A micro-label detector matched a fixed-order run of utility classes; real call sites interleave a colour class where a human would write it, and one interleaved class defeated the whole match. The fix that held was to match an unordered SET - and the fix's own first version failed its control, because it was tested against the token's SOURCE DEFINITION rather than the form call sites write.
- **One element versus two.** A ghost asserted `div:contains("3 Items")` and timed out, because the component renders the label and the count as separate stacked elements. No single element's text could ever contain that literal - impossible by construction, not stale.
- **A name versus a count versus a synonym.** A "Step 6" scheme was retired by grepping the literal string and survived where the same retired concept was expressed as a COUNT in prose ("the 6-step wizard").
- **The quantifier.** "At least one" cannot express "too many" - a guard asserting at-least-one infographic per header passes a header carrying two.

### A-R2. Anchor both ends

A boundary you did not write is a case the pattern silently reclassifies.

- **No left boundary:** a backdrop regex matched `md:bg-den-900/60` starting AFTER the variant prefix, so two surfaces painting no scrim below `md` validated as compliant. Separately, `/<Tabs/` also matches `<TabsSample` - a census returned 7 where the answer was 6.
- **No right boundary:** the hex literal `#D97706` was read as a reference to section `D97`.
- **Wrong character class:** `Behavior name="[A-Za-z ]*"` silently dropped every name containing a hyphen or a parenthesis, reported 5 of 7, and supported a conclusion about what a QA Area does not contain.
- **`\b` is the wrong tool wherever the language treats `-`, `[` or `]` as ordinary characters.** Tailwind breaks it at both ends: `text-\[10px\]\b` can never match (the token ends in `]`, followed by a space - no boundary transition exists there), and `font-black\b` matches happily inside `font-black-x`. Use `(?<![-\w])` / `(?![-\w])`.
- **Substring equality is a missing boundary in disguise.** An exclusion key matched with `.includes()` turned out to be a PREFIX of an unrelated class (`ring-brand-500` inside `ring-brand-500/30`), so the exclusion covered the wrong element and a real regression came up green.

**Corollary.** A short generic needle in an unscoped haystack proves almost nothing - a member check searching a whole concatenated text is satisfied by an unrelated occurrence of `square`, `sm` or `md` anywhere in any file. Scope the region, or pick a distinctive needle.

### A-R3. Key on the DEFINING property, never a correlated one

A notice is not "a fill and a border" - six borderless copies of an error recipe were invisible for a guard's entire life. A delete control is not "a `Trash2` glyph" - a delete with a text label is invisible. A selection is not a variable called `selected` - four spellings were found one at a time (`selected`, `selectedId`, `memberId === m.id`, `isSel`) and there is no reason the fifth will be caught. Compliance is not "calls one of these helper names" - two helpers added 25 commits earlier were invisible to a hand-typed alternation, and the two files whose compliance rode on them passed anyway, by accident, because they also called a known one.

**Mechanical tell: a predicate you have widened more than once is keyed on the wrong axis.** Key on what the thing IS, or on what it PAINTS.

### A-R4. The expected value comes from the code, never from memory

An allow-list token (`'bg-den-900/60 md:backdrop-blur-sm'`) existed in NO FILE - it was written from what the sites were assumed to say, so the allow-list and the code were wrong in the same direction and agreed. A guard pinning the literal `44px` asserted parity with a page that had rendered `40px` for a while; the assert checked the literal, never read the page, and stayed green through the whole divergence.

**Assert that every value you expect is itself producible by your own predicate.**

---

## B. The subject list

_The predicate can be perfect and the sweep still blind, because it was never pointed at the thing._

### B-R1. Derive the list; never hand-type it

A hand-typed list is blind precisely to the new thing most likely to be wrong - permanently, silently. Two guards written immediately AFTER an incident both hand-typed their subjects and inherited the incident's shape; deriving them took 31 to 93 and 91 to 153 assertions, and found a primitive catalogued for its whole life on its import string with no gallery entry, one listed in a single array so never once checked for stamping, and five primitives with no `data-part` at all.

Every exclusion carries a written reason - then a new member joins by existing, and skipping it must be argued for in the diff.

**This applies to prose as hard as to guards.** A worklist census silently excluded two directories with no reason recorded, so every headline number in the planning document was about 40 short - and nothing could fail, because prose does not compile.

### B-R2. A derivation is a claim about COVERAGE

"Derived" does not mean "complete". One derivation covered two of three real sources - picker groups and seeded data, but not literal names written directly in JSX call sites - and a broken icon name shipped. A walker using `readdirSync(dir, { withFileTypes: true })` cannot see a symlinked directory at all, because `dirent.isDirectory()` reports false where `statSync()` (which follows it) reports true; 27 of 163 suites walked that way, and the ones with no found-some control passed vacuously while agreeing with their authors.

Two independent vault-wide sweeps for the same defect caught different, partially-overlapping sets, because each subject list had a gap the other lacked. **A sweep is only as wide as its subject list, and a found-some control is what tells you it had one.**

### B-R3. Never key the subject list on a property the BROKEN case is defined by not having

The single highest-yield question in this skill: **what would a wrong instance look like, and can my subject list even contain it?**

- A ghost teardown swept `[data-part="overlay-backdrop"]` - and not carrying that part is the DEFINITION of an un-migrated shell. It covered every modal that no longer needed remembering and none of the five that did; eleven scenarios died, each passing its own assertions and then failing its closing navigate, which read as eleven unrelated feature bugs.
- An `Avatar` site list derived from a helper's CALLERS missed the two surfaces broken precisely because they never called it.
- An adoption guard matched only sites that had already converted, reporting zero raw instances while two dozen sat in the tree at slightly different sizes. Measuring adoption by asking the adopted.
- A guard whose subjects are "files that import X" is blind to the places that SHOULD use X and do not.
- A fixture minted from the same seed ids the code keys on returned 13 green assertions over a feature that produced nothing for any real family.
- An enumeration built to PREVENT a recurrence inherits the shape of the cases that caused it: a pass-detector grep for the known dialects stayed blind to the one that puts its label first.

**Fix shape:** derived subjects UNION a registered straggler list, pinned to a register that empties itself as they convert.

### B-R4. Classify per INSTANCE, never per file

One element opting out excused every other element in its file, and the cheapest way back to green was to raise the ceiling, which would have locked the hole in permanently. The same coarseness in the other direction flagged nine files where a per-instance ancestor walk found three sites.

### B-R5. A derived worklist SIZES and ORDERS a job; only reading certifies a member

A 35-site census was accurate per site, and six members could not convert for reasons it had no way to represent - a `ref` the primitive does not forward, a badge CHILD, a matched PAIR whose partner carries a text label, a bespoke radius, a six-state domain machine against five generic ones. The numbers were never wrong; the CATEGORIES were incomplete, which reads identically.

State the census figure as an UPPER BOUND and label it. **Citing this rule is not obeying it** - the immediate repeat quoted it by name in its opening line, predicted eight convertible sites from the census, and reading certified one.

---

## C. The tokenizer

### C-R0. The shared signature

**A broken scan still returns RESULTS.** Nothing throws, nothing errors, and the only symptom is a plausible number - which is why every instance below was found by eye, by the operator, or by accident, and never by a run.

### C-R1. If you are parsing a language, use its parser

A hand-rolled scanner over JSX/TS will:

- read an apostrophe inside a comment (`the sidebar's`) as a string opening, hunt a closing quote to end of file, and DROP the tag along with everything the runaway swallowed - wrong in both directions at once, hiding 7 real elements while inventing 5 where it resumed mid-source. Net -2, so the total never looked wrong.
- swallow a component's whole prop payload as part of its opening tag, so markup passed into a prop is never scanned. One shell swallowed 170 lines and the scanner returned nine tags for the file.
- end a tag at a generic's `>`, because depth counts braces and a type argument sits at depth zero. 18 call sites of three primitives came back carrying nothing.
- return no PARENTAGE, so it cannot see that two copy-pasted siblings share a surface.

### C-R2. Prefer a scope to a window

A window is a guess about how long the answer is; a scope is the answer. A fixed 900-character read from an attribute string was blind in a way that CORRELATED WITH DIFFICULTY - simple cases are written inline, elaborate ones get lifted to a `const` above the return - so the tool systematically missed the harder cases. **Three patches at the window each got closer and stayed wrong, which is the tell that the SHAPE of the tool is wrong rather than its tuning.** A 120-character lookahead spanned into the next arm of a ternary and fired on correct code.

Extract the branch, the object literal, the call - the thing itself.

### C-R3. Decide whether PROSE counts, and note that both answers are load-bearing

- **Strip it:** an absence check that reads the raw file goes red against a file that correctly explains the thing it forbids. One such guard was red long enough to be filed as standing debt and read past on every run. Another read a comment illustrating a naming convention as the thing being named.
- **Do not strip it:** a guard may quote a dead spelling ON PURPOSE as its own fixture, and a primitive's header comment may quote the very class its guard searches for - so deleting the enforcing code and leaving the paragraph stays green.

Ask of every hit inside a comment whether the check needs that spelling ABSENT or PRESENT.

### C-R4. A predicate worth copying is worth extracting - and an extracted one needs its own suite at its second caller

Two byte-identical private copies diverged for two days when a fix landed in one and not its twin, so one guard could see prop-nested markup while the other reported confident, wrong numbers. Extraction fixes that and CONCENTRATES the blast radius instead: controls at the call sites cannot prove the tokenizer, because every consumer assumes the scan worked before its own predicate begins.

---

## D. The report

### D-R1. Never truncate a discovery result

`head -8` on a selector sweep showed 4 of 9 stale selectors; a guard's `.slice(0, 15)` hid six files from anyone planning a batch off it; a `throw` that stops at the first offender produced an incident report saying "one file, three sites" where a full non-throwing sweep of the same predicate found "two files, seven".

A truncated set reads exactly like a complete one, and **any cap re-creates the trap at a different size - remove it rather than raising it.** Count first, then look.

### D-R2. Quote the bounds with the number, or do not call it a measurement

A sizing probe has none of a guard's defences by definition; it exists to decide whether work is worth doing, not to report how much there is. One reported "40 files / 83 sites" where the real guard measured 24 / 42, and the figure had already reached a plan, an Impact Analysis and a commit message. A damage report whose scan bounds were chosen for speed was read as exhaustive, omitted a package, and cost two further test cycles.

Method bounds count too: counting one match per LINE hides the second hook on a line, and grepping one of two legal spellings reported 5 against a true 14.

### D-R3. Measure the thing, not its generator's source

A grep over a fixture's source correctly found the largest literal date offset and concluded something false about the data it produces - running the module gave 89 transactions across three months. **A number derived by reading a file that PRODUCES something is a property of the source only**, and the arithmetic is right, which is why it is invisible in review.

### D-R4. A cited count is a claim, not a search

A deferral citing one broken assert had an identical second one nearby. Six open register entries had all drifted worse since filing, one by more than 2x. A stamping figure was quoted in two documents with nobody re-running the census. A rename's "touches N guards" missed a guard that had cited the old path since before the rename was proposed.

**A register decays fastest on exactly the identifiers the current engagement is renaming** - and **a number quoted out of a narrative describes the narrative**, not the thing the narrative was about.

---

## E. The corpus

### E-R1. Name the corpus before you search

The corpora here: the code tree, the brain's registers, the vault's prose, the read-only contracts, the OTHER repo, a running process. **Filing anything as NEW greps the register first** - a finding was filed as a new high-importance item while already sitting in the register at medium, because the session grepped the tree thoroughly and the register not at all. Cheap tell: grep the register for two or three distinctive words of the title you are about to write.

### E-R2. Prose does not compile

Every comment and register entry is a hand-maintained claim. Three comments asserted things no longer true - a removed CSS value, surfaces described as unconverted after they converted, a retired token name given as the reason for an exemption. One named a consumer that a full-tree grep showed does not exist. Two cited a `file:line` that moved after a rename - **cite the SYMBOL**. One cited a guard file that has NEVER existed, in three places, each reading as "this is checked" and thereby suppressing the search that would have found the gap.

**A rule that NAMES a guard is not enforced by it.** One rule was false for as long as its guard asserted the opposite, and the `guard=` attribute is precisely what stopped anyone re-reading the text.

Triage prose hits by TENSE: what IS gets fixed, what HAPPENED gets left alone.

### E-R3. "Grep found no reader" is weaker for a DOM attribute than for a code symbol

A scroll handler, a QA habit or a browser extension reads a data attribute without ever appearing in the source tree. Deferring the deletion is the correct call.

### E-R4. Establish WHAT the tool is describing before believing its answer

Sandbox git can invent a diff as readily as hide one - two files showed modified for six weeks and never were, because the sandbox reads only `.git/config` while the operator's git reads layers it cannot see. That invented diff was then re-filed as a new finding by a session that had not checked the register. A staging path can serve bytes from before an edit made the same session, with fresh metadata. `supabase migration list` compares files against the LINKED REMOTE, so neither column describes the local stack the ghosts drive - a correct diagnosis was WITHDRAWN because that ledger disagreed with it, and one `select count(*)` settled it.

The desktop Read is authoritative over the sandbox view, and a sandbox grep's SILENCE is not proof of absence.

### E-R5. The compiler is an exhaustive search only where the type is CLOSED

"The compiler walks you to the rest" held for the `satisfies`-pinned unions and not for the plain array literal beside them, which accepted a hole in silence. Confirm the containing structure is pinned before treating "the typecheck would have caught it" as a result.

---

## G. Acting on the result

### G-R1. Assert how many times the anchor matched

`assert old in s` passes just as happily against the WRONG occurrence of a repeated block - a real edit patched ghost T-08 instead of T-09, caught only by a follow-up grep.

### G-R2. Do not corrupt the corpus you are reading

An append through a stale mount splices at the STALE end-of-file offset and can cut committed content mid-word, while the write reports success and a stale `tail` shows the new text - verify at the SEAM above the new content, never the tail. And emit-then-link, never link-then-emit: a compiled scratch copy of a search tool wrote 20 untracked `.js` files into the source tree through a symlinked `outDir`, including a same-named sibling of a real `.ts` file the bundler would silently have preferred.

**Renaming or deleting many sites is a different job.** A scripted edit's blast radius is the SPAN, not the anchors; a blanket `replace_all` crosses component boundaries and repaints scenarios the same slice is about to delete. That is edit mechanics, and the constitution's absolute rule owns it.
