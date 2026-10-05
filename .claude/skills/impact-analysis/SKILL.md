---
name: impact-analysis
description: Runs the mandatory Impact Analysis before any code change in the BearFunds client or server repos - Step 1 of 0_AI_INSTRUCTIONS.md, executed rather than recalled. Use this whenever you are about to write, edit, fix, refactor, extend or delete code in these repos; whenever the operator asks for an impact analysis or a plan; and whenever they say "implement X", "change X", "fix X", "add X" or point at a surface and describe what is wrong with it. Use it especially when the change looks small or looks like state, data or persistence work rather than UI - a one-control change is exactly where the primitive lookup gets skipped. Do not write code before running it.
---

# Impact Analysis

## What this skill is, and what it deliberately is not

`0_AI_INSTRUCTIONS.md` Step 1 defines the Impact Analysis. **This skill carries none of those rules and must never restate them.** It reads them at run time and executes them.

That separation is not tidiness. This codebase has repeatedly paid for the same defect - a second list that agrees with the first today and drifts on whatever somebody adds next, with both surfaces looking deliberate. `shared/fieldGlyphs.ts` says so in its own header, and a session then hand-picked a glyph list anyway. A skill holding its own copy of the protocol would be that failure one layer up, and it would be worse, because nothing compiles either file.

**The protocol is also operator-owned and off-limits to edit.** If following it reveals a gap, propose a drop-in in chat and let the operator apply it.

## Load the repo extension first

**Read `.claude/skill-extensions/impact-analysis.md` in the repo you are working in, before the analysis begins.** It carries what is true only of that repo - the traps a change of this kind has actually hit there, the harness's blind spots, the gates known to fail silently - and an analysis is written with those in hand rather than discovering them from a run afterwards. A trap you have read is a risk you can name in Step 1; the same trap met later is a rework round.

**It is authoritative wherever it and this skill appear to disagree**, and its absence is not permission to guess: a repo with no extension gets the protocol and this skill's discipline and nothing more. It does not displace `0_AI_INSTRUCTIONS.md`, which is the protocol and outranks both.

## Why proximity, not prominence

A session once skipped Step 1's UI Inventory **four times out of four** and hand-rolled a footer, a glyph list, a set of field labels and a native select that a shared picker already covered.

The rule was not missing. It was loaded at session start, tagged `CRITICAL`, and stated that an analysis without named rejects is invalid. It was skipped anyway, while the analyses **looked** thorough - they carried invented headings like "Files", "Guards" and "Risks", which read as diligence and quietly omitted the one numbered item that mattered.

So the two things worth fixing are not "say it louder":

1. **Proximity.** The checklist belongs at the moment the analysis is written, not an hour upstream of it.
2. **Evidence.** "No primitive fits" is a claim about a **search**. Without the search it is a claim about what you happen to remember - and it will be honest and wrong, because an agent that does not know `OverlayFooter` exists will report that nothing fits with complete sincerity. Run the lookups as tool calls so the operator can see them in the transcript.

## Step 1: read the protocol

Read `0_AI_INSTRUCTIONS.md` Step 1 in the repo you are working in. It is the source of truth for what the analysis must contain, what the Primitive Ladder rungs mean, and what makes a reject valid. Everything below is mechanism for satisfying it.

Also read the QA Area for the feature (`1_QA_MASTERPLAN.xml`), and `3_DESIGN_CONTRACT.xml` if look and feel changes.

## Step 2: run the lookups, before forming an opinion

Run these against the repo root. They are cheap, and their output is the evidence the analysis rests on. Adjust paths per repo; the client is the one with primitives.

**The edited file's own comments come first.** A file routinely names the primitive it should be using, or a sibling surface that already uses it. That is a lookup result already sitting in front of you, and skipping it is how a session hand-rolls a footer directly beneath a comment naming the primitive and the sibling that takes it.

```bash
# 1. What does the file I am about to change already say about itself?
sed -n '1,60p' <file>                      # header comment
grep -n 'primitive\|hand-roll\|instead of\|see also\|same surface' <file>

# 2. Does a primitive already do this? Primitives live across SEVERAL directories.
grep -rln '<concept>' components/ui components/form components/layout components/modals

# 3. Does a sibling surface solve the same problem? Often the fastest answer.
grep -rln '<the thing this screen is a variant of>' features/

# 4. Is the VALUE I am about to choose already decided somewhere?
#    Glyphs, field names, labels, sizes, colours are shared assets too.
grep -rn '<field or concept>' shared/fieldGlyphs.ts features/import/stagedColumns.ts components/ui/tokens.ts

# 5. What do the guards say about my subject? An analysis that ignores them
#    plans work the suite already forbids.
grep -rln '<ComponentName>' tests/

# 6. What drives this surface today? Renaming or removing it is a coverage event.
grep -rn '<testid or copy>' tests/scenarios/
```

These are a **first pass**, and they have a specific weakness: each keys on a concept word you guessed. Guess "Footer" when the primitive is called something else and you get zero hits and conclude nothing exists - honestly, and wrongly. Which is the next step.

## Step 2b: escalate to `search-code` before claiming anything is absent

Invoke the **`search-code`** skill. Do not re-derive its discipline here or hand-roll a deeper sweep - it carries controls, an inversion test and repo-specific hazards this skill has no business restating, and the BearFunds client ships its own `.claude/skill-extensions/search-code.md` that it loads automatically.

**This is not optional for the claim the analysis turns on.** `search-code` mandates its full procedure for an **absence claim**, and again for any result that **goes into a plan**. "No suitable shared asset exists" is both at once - it is an absence claim, and an Impact Analysis is a plan. A named-rejects list resting on one quick grep is exactly the shape it exists to stop.

Escalate whenever the analysis is about to:

- claim nothing suitable exists, or that nothing reads a thing you intend to remove
- state a **count** or a **site list** anyone will act on - risk sections are full of these
- report a figure into the plan, a register, a commit message or the handoff

**A rename, a deletion or a retirement takes `blast-radius` FIRST, and it calls `search-code` itself.** That skill owns what the subject list of such a change is - that it is the rule or the value and never the directory named for it, that prose and the suite are in scope as well as the source, that some hits must SURVIVE the sweep, and that the verification subject is the callers rather than the files in the diff. Its output is evidence for this analysis, not a licence to start editing: the Approval Lock still applies, and nothing in that skill overrides it.

Its highest-yield question is worth carrying into every lookup above: **what would a WRONG instance look like, and can this search even contain it?** If a wrong instance would look like a right one minus the thing you searched for, the search is inverted and its zero means nothing.

A search that came back empty is evidence only once it has earned that; a search you did not run is not evidence at all.

## Step 3: write the analysis with its headings intact

Emit `## Impact Analysis` with a heading for **every** numbered item in the protocol's Step 1, in its order, including any that turn out to be short. A section that genuinely does not apply says so in one line and says why.

Do not invent your own section names. Invented headings are the specific failure mode this skill exists to prevent: they read as thorough while omitting the item that would have caught the defect, and because an analysis is chat output rather than a file, **no guard can ever detect the omission**. Visible shape is the only enforcement available, which is why the shape is not optional.

Label each load-bearing claim as a **verified fact** (and how - file read, command output) or an **assumption**. Assumptions may move faster; unlabelled ones may not.

**NAME THE GUARDS THAT CONSTRAIN THE SUBJECT, or the analysis plans work the suite already forbids.** Listing files, behaviours and risk says nothing about what the tests ASSERT about the thing being changed, and a plan is a claim about what is possible. Before proposing a change to a component's or a module's API, grep the test tree for its NAME, then **open each file the grep returns and QUOTE the assertion** - or say which guard the plan proposes to change, and why.

**Naming a guard is not reading one, and the grep is the half that gets performed.** The tell is a risk section listing guards by filename with nothing quoted from any of them; citing a rule by name does none of its work. Where a guard forbids where a thing LIVES rather than that it exists, the answer is usually a module boundary rather than an argument.

Two habits worth carrying in, both learned expensively:

- **Re-derive numbers rather than quoting them.** A figure in a planning doc was true when written and nothing makes it stay true. Ask the guard that measures it, then state it in that guard's own terms - a number is often honest at the point of measurement and false in the sentence that repeats it.
- **A blocker recorded in prose expires.** Before repeating "this is blocked on X", check X against its live register. A resolved question and an open one read identically in prose.

## Step 4: stop

End with the Approval Lock exactly as the protocol words it, and generate no code until an approval keyword arrives. Never simulate approval.

If the change would contradict `1_QA_MASTERPLAN.xml` or `2_SCHEMA_CONTRACT.xml`, stop and say so plainly instead - that is a conversation, not a plan.

## The failure this is aimed at

Every one of these produced working code and a confident analysis, and every one was caught by the operator looking at the screen rather than by any check:

| What happened | What the lookup would have returned |
|---|---|
| Two stacked buttons hand-rolled into a footer | `OverlayFooter`, named in the edited file's own comment, and `DateRangeOverlay` using it three files away |
| A glyph list hand-picked, twice | `shared/fieldGlyphs.ts`, whose header predicts this exact drift |
| Field labels invented (`Description` for a field the app calls `Notes`) | `features/import/stagedColumns.ts` |
| A native select of member names | `components/form/MemberPicker.tsx` - extracted precisely so a second member-picking idiom would not appear |

Most of those sit **outside** `components/ui/`. A sweep of one directory would have missed them, which is why step 2 searches every primitive directory and the vocabulary sources as well.

## Governance

**This file states what IS.** No dated narrative, no record of what a rule used to say, no changelog section - that history belongs in the log record of the session that changed it, and the plugin's `version` is what makes the change reachable. **The tell is a past-tense sentence about the skill itself; the cheap test is whether deleting it would change what a reader DOES**, and if not it is history.

**And it states ONE BEHAVIOUR, never a different one per corpus.** A branch on which repo or vault you are standing in asks the reader to CLASSIFY the tree first, and that classification is the failure - each branch is individually correct, so a session working across two corpora in one sitting mixes them and nothing reports it. Whatever varies goes in that corpus's `.claude/skill-extensions/` file, which this skill loads first and which outranks it on disagreement.
