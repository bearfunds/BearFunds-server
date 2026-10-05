---
name: blast-radius
description: Sweep the full blast radius before changing what something is called or whether it exists - renaming, deleting, retiring, moving, redefining a value in place, or applying a mapping across many sites. Use when the operator says "rename X", "delete X", "remove X", "retire X", "move X", "get rid of X", "change X to Y", or asks what a change would break. Use it before a blanket replace, before changing user-visible copy, and when a change alters a prop, a key or an interface. Use it especially when the sweep's subject list is a folder or a file chosen because its name matches, and when a rename looks finished.
---

# Blast radius

**A rename, a deletion, a move and a redefinition all fail the same way: something somewhere still names the old thing, and nothing goes red.** A compiler catches a stale import. It cannot catch a guard that has stopped being able to find its subject, a document asserting a fact that stopped being true, a lookup keyed on a value that now means something else, or a relationship that every individual value survived and no pair did.

So the governing question, asked before the edit and again before calling it finished:

> **What else names this thing, and if one of them keeps naming it, would anything at all report that?**

Where the answer is no, the sweep is the only defence there is, and it has to be argued rather than run.

## Load the extension first

**Read `.claude/skill-extensions/blast-radius.md` before sweeping.** The rules here are general. Everything that varies by corpus lives in that file - whether an approval gates the edit, what happens to historical records, which verifier to run, and the local hazards that make a sweep read wrong.

**It is authoritative wherever it and this skill appear to disagree**, and its absence is not permission to guess: a corpus without one gets the general discipline and nothing more, and any question this skill defers to the extension stays open until a human answers it.

---

## 0. What this skill does not do

**THIS SKILL GATHERS. IT PRODUCES THE EVIDENCE A CHANGE NEEDS AND NEVER THE AUTHORISATION TO MAKE IT.** Everything below describes what to find and what must survive; the repairs it names are what the evidence implies, not permission to start typing. **What sits between the sweep and the edit - what analysis it feeds, who approves it, whether anything gates it at all - is not this skill's business.** It is stated in the extension, and the extension is authoritative over anything you might assume from the shape of the tree in front of you.

The tell that this has gone wrong is a session that swept well and started editing, which reads as momentum rather than as a bypass.

**AND THE SEARCHING ITSELF BELONGS TO `search-code`.** This skill says what the subject list IS and what must survive; it does not say how to search without fooling yourself. **Invoke `search-code` for the sweep** - it carries the controls, the inversion test and the hazards local to what you are searching, and it is what stops a zero being believed. Escalate to it whenever the sweep is about to produce a site list, a count, or a claim that nothing else names the thing.

---

## 1. The subject list is the CHANGE, not a container

**The subject is the behaviour, the value or the name - never a directory or a file chosen because its name matches.** A retirement scoped to the file named for the rule stops exactly where you would have guessed, and the consumer that breaks is somewhere else. The tell is a sweep whose subject list is a folder.

**Grep for everything that NAMES the thing, not only for the thing.** A value has log lines, selectors, headings, fixtures and waits that spell it out. Each of those is a site, and none of them is in the directory you are editing.

**Where two things must agree, the agreement gets a guard rather than a convention.** A value written in one place and waited for in another agrees today by coincidence, and nothing can see it stop. If the sweep reveals such a pair, the sweep's output is a check, not just an edit.

**Include the executable AND the prose.** A change's radius covers the source, the checks that assert it, the documentation that describes it, the registers that track it and the notes the current work is being steered by. The prose half has none of the machinery the executable half has, which is section 3.

## 2. Renaming an identifier

**Grep the suite first, and treat every hit as a check that must be re-proved rather than re-typed.** A guard that names a thing is coupled to that name, and a rename is precisely the moment that coupling stops being visible. Renaming through it leaves a check that runs, passes, and can no longer find its subject.

**Ask of every hit whether the check needs the spelling ABSENT or PRESENT.** Most need it absent and get swept. Some need it present on purpose - a fixture string, an assertion message, a contract-bearing fake id, a past-tense narrative in a comment. Sweeping those turns a diligent rename into a red suite. Each one is excluded with its reason recorded, exactly like any other exclusion.

**A blanket replace crosses boundaries the name does not.** One prop name can be three unrelated things in three components. Establish what the name means at each site before replacing, or let the compiler find the collateral and read every hit it reports.

**A blanket replace across a test file partitions nothing.** Split the subjects into what SURVIVES the change and what DIES in it, and rename only the survivors - the dying set gets deleted, not updated. The tell is a replace count larger than the number of subjects you intend to keep.

## 3. Prose has no compiler

**A document that quotes a fact is a hand-maintained copy of it.** A register entry, a reference page or a handoff naming a union's members, a file path or an identifier is asserting something the rename just made false, and nothing anywhere can go red.

**Triage every prose hit by TENSE, never by location.** A sentence describing what IS becomes false and is fixed in the same commit as the rename. A sentence describing what HAPPENED is true as written and must not be touched - rewriting it destroys the record. "The old spelling survived the rename" is a true sentence about the past.

**A document decays fastest on exactly the identifiers the current work is renaming.** Verify a named artefact against the tree rather than against the text that cites it.

## 4. Renaming a document that other documents cite

**Whether historical records are swept or left standing is a POLICY, and it is not this skill's to set.** Sweeping them costs a wide diff and buys one live spelling; leaving them costs permanent redirection debt and buys an untouched record. Both are defensible, the answer differs per corpus, and it is stated in the extension. Read it before you decide, and do not infer the answer from what the tree looks like.

The rest of this section is mechanism, and it holds whichever policy applies.

**Sweep only OUTSIDE code spans.** A backticked occurrence is a QUOTATION of the name rather than a reference to the thing - a rule citing a filename as a string, an entry recording that a file crossed a size. Those are kept, under either policy.

**A bare-name pattern needs a negative lookbehind for every prefixed sibling, and a control proving the siblings measure zero.** Where several documents share a base name under different prefixes, a bare pattern matches inside all of them and renames them by accident. The control is what catches it.

**Front matter is never in scope.** A sweep that reaches a document's own metadata turns a record of the old name into a self-referential one.

**A cross-reference can survive a rename and stop being TRUE.** A sibling saying "same format as X" is still resolvable after X is renamed and may be false because X has changed. Repointing the link is not the same as checking the claim.

**The verifier is whatever link checker the corpus has**, and it is only worth anything if it distinguishes a live link from a quoted one.

## 5. Redefining a value in place

**Keeping the name and changing what it MEANS is the quietest change in this document.** Every guard that names the thing still finds it. Every citation still resolves. Nothing is stale by any mechanical test, and the rendering is different everywhere.

**The DEFAULT moves with the redefinition.** Sites that relied on the old default by passing nothing are silently re-pointed at the new meaning, so the default is restated to follow the rendering rather than the word.

**A lookup keyed on the redefined value is re-pointed at the caller's own word in the same edit, or deleted.** Leaving it keyed on the word makes it answer a question nobody is asking.

**The tell is a diff whose message says rename and whose call sites did not change.**

## 6. Applying a value mapping

**A mechanical transform preserves every value and can destroy every relationship.** Each substitution is correct at its own site; what breaks is the pairs - rest against hover, live against disabled, fill against border, a token against the component that must agree with it.

**Enumerate the relationships BEFORE the phase plan, not inside it.** The enumeration is what sizes the work; discovering a relationship mid-slice because a guard went red means the work was costed as a rename and is not one.

**Assert each relationship still holds AFTER, by comparing the before and after SETS.** Reading the output cannot do this: a relationship that survives is invisible in a diff, and only its absence shows, and only if something asks.

**The tell is a change whose specification is a table.**

## 7. Removing

**Removing a rule retires the checks pinning it, in the SAME slice.** A scenario left asserting a rule the code is now forbidden to follow goes permanently red, and a suite carrying a permanent red has stopped being a signal.

**The sweep is scoped to the rule, not the file named for it** - grep the whole tree for the behaviour, its identifiers and its copy.

**A step is judged by what it SUPPLIES, never by what it is called.** Before deleting a step, ask what state the next line depends on it establishing. A step whose removal breaks something downstream is a step that thing depends on, whatever its name says.

**Deleting a named rule breaks every citation of it.** Grep for citations before proposing the deletion, and rewrite each one to state the reasoning without the dead reference. This cost is the guard that stops a contract rotting quietly and should not be weakened to make a sweep go faster.

**MOVING a rule is worse than deleting it, because nothing breaks.** A deletion leaves citations that name something absent, and a reader who follows one finds nothing and knows. A MOVE leaves every pointer AT the rule still resolving, still grammatical, and now naming the wrong file - so the reader follows it, reads whatever is there instead, and concludes.

**So the subject list for a move includes the pointers, not only the rule.** Grep for the DESTINATION FILE'S OLD NAME as well as the rule's, because the sentences that decay are the ones of the form "X is in Y" - and they were written by whoever last moved something, which is to say by the same discipline doing the moving now.

**The tell is a sentence naming a file plus a section.** That shape is mechanically checkable, unlike most prose, so it is worth a detector where the corpus has one.

**A RENAME'S BLAST RADIUS FOLLOWS THE INSTRUMENTS KEYED ON THE NAME, NOT THE REPOSITORY THE RENAME HAPPENED IN.** A checker, a linter or a build script that hardcodes the old name goes on running and stops matching - it reports the same clean result as yesterday, because an exclusion or a scope that matches nothing removes nothing and raises nothing. **A sweep whose corpus is "this repo" is blind to every tool that lives in another one**, and tooling is exactly what gets factored out into a plugin, a shared package or a sibling checkout.

**So enumerate the TOOLS that name the thing before the sweep is called finished**, wherever they live, and check each one's scopes and exclusions rather than only its prose. **The tell is a rename that fixed the same hazard twice inside one instrument** - a second instance in one file is evidence of a class, and a class has members outside the tree you are standing in.

**A CLOSED VOCABULARY IS A RENAME TARGET NO PAGE-NAME SWEEP WILL FIND.** When a register, a folder or a concept is renamed, values that named it - a `kind`, a `status`, a code prefix, a tag - carry the old word inside a controlled list, and a sweep scoped to page names passes straight over them. **So the subject list for a rename includes the VALUES, not only the pages and the prose.**

The tell is a rename whose sweep was thorough and whose subject was a name. Grep the old word inside frontmatter and inside any list the documentation calls closed, and check what a value renamed there would break: a value outside its declared vocabulary is worse than the stale word, so the DECLARATION changes first and the members follow.

**The same discipline governs comments.** A comment explains what the code does and why it is right, never what it used to do. A comment recording why a rule was reversed is the same baggage one layer down, and it dangles the moment the rule goes.

**When exactly one artefact disagrees with two, read that one first.** After a deliberate reversal, the dissenter is usually the stale check rather than the new behaviour.

## 8. Copy that something asserts

**Changing user-visible copy is a coverage event.** A scenario asserting a sentence verbatim goes red on a working feature, which is the most expensive kind of false signal - it costs a full investigation to discover nothing is wrong.

**The repair is not to update the string, which only re-arms the trap.** Give the element a stable test hook and assert that the thing is SHOWN. Wording is a design decision that will keep changing; presence is the behaviour the check actually claims.

## 9. Callers, not edits

**When a change adds, removes or retypes a prop, a key or an interface, the verification subject list is the CALLERS.** A check scoped to the files in the diff is blind to them by construction, and the thing that breaks is the thing you did not touch.

**Derive the caller set rather than recalling it**, and verify against that set rather than against the edit list.

## 10. Before calling the sweep finished

**State the count kept deliberately beside the count changed.** A sweep reporting only what it changed cannot be distinguished from one that missed a class of site.

**Every exclusion carries its reason in the diff.** An exclusion that is obvious to the person making it is invisible to the person reading it six weeks later, and it is the first thing a later sweep will undo.

**A sweep that "finished the job" is a warning sign.** The hits that must survive - quotations, fixtures, past-tense records, contract-bearing strings - are a real fraction of any mature tree, and a sweep with no exclusions probably did not look for them.

**If the check that verifies the sweep cannot fail, it has verified nothing.** Run a control through it first.

---

## Where the rest lives

**This skill is canonical for how to sweep a change, and it is deliberately not the archive.** Each rule was distilled from an incident, and the incidents are recorded in the log record that shipped the rule - not here, because a rule and its story have different lifetimes and the story is what makes a skill expensive to load.

**Anything true of only one corpus is not in here.** The hazards, the conventions, and the policy questions this skill names but declines to answer belong in that corpus's `.claude/skill-extensions/` file, which is loaded at run time and is authoritative wherever it and this skill appear to disagree.

## Governance

**This file states what IS.** No dated narrative, no record of what a rule used to say, no changelog section - that history belongs in the log record of the session that changed it, and the plugin's `version` is what makes the change reachable. **The tell is a past-tense sentence about the skill itself; the cheap test is whether deleting it would change what a reader DOES**, and if not it is history.

**And it states ONE BEHAVIOUR, never a different one per corpus.** A branch on which repo or vault you are standing in asks the reader to CLASSIFY the tree first, and that classification is the failure - each branch is individually correct, so a session working across two corpora in one sitting mixes them and nothing reports it. Whatever varies goes in that corpus's `.claude/skill-extensions/` file, which this skill loads first and which outranks it on disagreement.
