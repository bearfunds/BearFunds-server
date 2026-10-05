---
name: contract-dropin
description: Propose a change to a read-only contract or protocol file that only the operator's hands may edit - a QA masterplan, a schema contract, a design contract, an engineering protocol. Use when the operator says "update the QA masterplan", "update the design contract", "the contract needs a rule for this", "change the schema contract", "add a gotcha", "write a drop-in", or when your own analysis concludes that a contract is wrong, incomplete or contradicted by the code. Use it before proposing any wording, and again before handing over a commit script that stages a contract file.
---

# Contract drop-in

**A contract is edited by the operator's hands and never by yours.** What you produce is a paste-ready snippet, and everything below exists because a snippet that reads perfectly can still land in the wrong place, delete a neighbour, contradict a sentence forty lines away, or be committed before it was applied.

The governing question, asked before the wording is written:

> **If the operator pastes this exactly as written, what else in the file changes?**

If you cannot answer from having read the file this session, you are not ready to propose.

## Load the extension first

**Read `.claude/skill-extensions/contract-dropin.md` before proposing anything.** The rules here are general. Which files in this corpus are operator-hands, which have a citation checker and which are silent, whether an approval gate stands between the proposal and the commit, and what the read-back is verified against - all of that varies and all of it lives in that file.

**It is authoritative wherever it and this skill appear to disagree**, and its absence is not permission to guess. A corpus with no extension gets the general discipline and nothing more; if you cannot establish that a file is operator-hands, ask rather than inferring it from the file's name or its tone.

---

## 1. Before you write a word: grep the whole document

**A claim important enough to state is important enough to have been stated somewhere else.** Grep the ENTIRE contract for the claim's distinctive phrases - not the rule you happen to have open, and not the section you were pointed at. A rule long enough to need a drop-in is long enough to state one thing twice, and two live sentences saying different things about one claim is worse than one stale sentence, because a reader resolves the pair by whichever they meet first.

**Grep for the CLAIM, not for the element.** The other statement will not share the rule's name; it will share its subject. Search the words the claim is about.

**A contradiction you find is a finding, not an obstacle.** Say which sentences disagree and let the operator settle it. Never resolve it silently inside a drop-in that was scoped to something else.

## 2. The anchor

**Anchors are session-verified. Never cite an element name from memory or from a prior proposal.** Read the file this session and copy the name out of it. A name that is nearly right produces a drop-in that cannot be applied, and the operator discovers that mid-paste.

**Never take an anchor from a probe's rendering of the file.** A name copied out of truncated output - a `cut`, a `head -c`, a column-bounded formatter - is a PREFIX of the real one, and a prefix silently matches the wrong thing.

**An ADD names the element BEFORE and the element AFTER the insertion point, states explicitly that both survive, and gives the expected element order afterwards** so the read-back has something to compare against. "Add after X" is executed as "replace X" often enough that naming one neighbour is not enough - and this is not a property of operator hands, because an editing tool anchored on a heading and not re-including it deletes that heading just as silently, reporting success.

**A REPLACE names its single target**, because there the deletion is the point. **Prefer a REPLACE wherever an extension would serve**: restating a whole element with one clause added is unambiguous, where an insert is an instruction someone has to interpret.

## 3. One operation, named

**The proposal is exactly one of ADD, REPLACE or REMOVE**, against exact element names. A drop-in that describes an intention in prose - "tighten this to also cover X" - is not a drop-in.

**Match the file's own element structure.** If it is XML with `<Behavior>` and `<Gotcha>` elements, the snippet is those elements, well-formed. The operator should be able to paste without editing.

## 4. What the drop-in may say

**Present tense, standalone, current state only.** The contract records what is true NOW.

- **No history.** No "what we had before", no narrative of a reversal, no rule kept so the reversal stays legible. Historic baggage biases a reader against what is known in the moment, and an idea needed again is re-derived better adjusted to the state it re-enters.
- **No work-slice labels**, no references to a plan, a session, a register or a vault. The contract must stand alone.
- **No forward references.** A rule may not cite a guard, a file or a rule that does not exist yet. If the drop-in needs one, that artefact ships FIRST - which sometimes means two drop-ins, one to state the rule and a second to cite the guard once it exists. Take the two; a single drop-in that forward-references turns a suite red on a change containing nothing wrong.
- **A citation is never line-wrapped.** Where citations are read as tokens, a name split across a line break becomes a fragment that resolves nowhere - and it looks perfectly correct to a human reader, because the sentence still reads. Reflow the line, even where that leaves it ragged.

## 5. Deleting a rule is a coverage event

**A rule that no longer holds is deleted outright** - not marked retired, not left standing with a corrective paragraph on top.

**But deleting a named rule breaks every citation of it.** Grep the whole tree for citations BEFORE proposing the deletion, and rewrite each one to state the reasoning without the dead reference. Where a citation checker exists this cost is loud and enforced; where none exists the same deletion is silent, and the extension is what tells you which case you are in. Do not weaken the sweep to make the deletion go faster - the citation cost is the guard that stops a contract rotting quietly.

**The same discipline governs comments in code.** A comment explains what the code does and why it is right, never what it used to do. A comment recording why a rule was reversed is the identical baggage one layer down, and it dangles the moment the rule goes.

**A deletion nobody proposed is the finding.** After any drop-in is applied, confirm the change is a pure ADDITION unless a deletion was the proposal. A diff showing zero deletions is the cheapest possible proof, and a removed line nobody asked for is exactly what the read-back exists to catch.

## 6. Delivery

**A drop-in is a full snippet in the session chat, never a file hand-off.** Paste it in the message that proposes it. It is a thing to READ before it is a thing to apply - the operator's last chance to disagree with the wording - and a file they must open in another window is one they will apply without reading.

**Length is not an exemption.** A long replacement is the one that most needs reading. Generating it by substitution rather than by retyping is right, because that is what stops a hand-copied rule drifting from the original; its OUTPUT still belongs in the message.

**For a small change, propose the anchored edit rather than reprinting an unchanged element**, and say which form you have chosen so the operator can ask for the other.

## 7. The read-back is a hard gate

**The operator applies; you then READ THE FILE BACK and confirm, from disk.** Not from the message you sent, not from what you intended.

**Read back every drop-in you proposed, individually.** When several go out together, some land and some do not, and the one that silently did not land is invisible in any summary. Confirm each anchor by name and say which are verbatim and which are not.

**Verify against the file, and against the repository's own view of what changed.** A file can read correctly and still be unstaged, and an "applied" that never reached disk looks exactly like an applied one in conversation.

## 8. The commit comes after the gate, never alongside

**Hand over the commit script only once the read-back has cleared.** A script handed over while a drop-in is still unapplied WILL be run first - the operator has no reason to wait - and the contract then arrives a commit late, with nothing in its own commit to explain it.

**The applied contract file rides the SAME commit as the work it belongs to**, staged explicitly and named in the message. Never a loose follow-up.

**Scope the script to what actually landed.** If one of several drop-ins is outstanding, either hold the script or scope it to the finished files and say which you did. A commit message describing a change the commit does not contain is worse than a missing commit.

**If a commit has already landed without its contract change**, say so plainly in the next message and name the commit it belongs to, rather than writing as though the pairing held.

---

## Where the rest lives

**This skill is canonical for how to propose a contract change, and it is deliberately not the archive.** Each rule was distilled from an incident, and the incidents are recorded in the log record that shipped the rule - a rule and its story have different lifetimes, and the story is what makes a skill expensive to load.

**Anything true of only one corpus is not in here.** Which files are operator-hands, which contracts have a citation checker, what gates the edit, and which verifier proves the read-back all belong in that corpus's `.claude/skill-extensions/contract-dropin.md`, which is loaded at run time and outranks this skill wherever they disagree.

**Renaming or deleting something a contract names is a different job.** `blast-radius` owns what such a change must sweep and which hits must survive it; `search-code` owns the searching. Escalate to them rather than doing the sweep by hand inside a drop-in.

## Governance

**This file states what IS.** No dated narrative, no record of what a rule used to say, no changelog section - that history belongs in the log record of the session that changed it, and the plugin's `version` is what makes the change reachable. **The tell is a past-tense sentence about the skill itself; the cheap test is whether deleting it would change what a reader DOES**, and if not it is history.

**And it states ONE BEHAVIOUR, never a different one per corpus.** A branch on which repo or vault you are standing in asks the reader to CLASSIFY the tree first, and that classification is the failure - each branch is individually correct, so a session working across two corpora in one sitting mixes them and nothing reports it. Whatever varies goes in that corpus's `.claude/skill-extensions/` file, which this skill loads first and which outranks it on disagreement.
