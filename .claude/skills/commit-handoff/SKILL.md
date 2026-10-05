---
name: commit-handoff
description: Assemble a ready-to-paste commit script for the operator to run, in any repo. Use when the operator says "commit this", "give me the commit", "commit script", "hand me the commits", "what do I commit", "stage this", "can you wrap this up into a commit", or asks how to get the work into git. Use it at the end of any slice, ingest or write pass that produced committable changes, and before handing over ANY block of shell the operator is expected to paste. Use it especially when new files were created, when a file was emptied or moved, when more than one repo changed, and when a decision about the commit's shape is still open.
---

# Commit hand-off

**You do not commit. You hand the operator shell they will paste, in order - one block, or two where something must be read before the commit (section 6).** Every rule here exists because a script that read perfectly did something else: staged work its message did not describe, staged nothing at all and reported success, wrote a junk file into the repo root, or executed a hole its author had left deliberately.

The governing question, asked before the block is written and again before it is sent:

> **If the operator pastes this whole thing right now without reading it, what lands in history - and is that the change I just described?**

**A script is run even when it is visibly incomplete.** The operator has no reason to wait, and a question attached to a script is not a brake. Treat every line as one that WILL execute.

## 1. Load the extension first

**Read `.claude/skill-extensions/commit-handoff.md` in the repo you are committing before writing a line.** The rules here are invariant. Whether an approval gate stands between the work and the commit, which message convention the repo uses, which files must ride the same commit as the code, which paths are always staged and which are always excluded, and which verifier proves the tree is sound all vary per repo and all live in that file.

**It is authoritative wherever it and this skill appear to disagree, except on attribution, which section 7 forbids outright and no extension can permit.** Its absence is not permission to guess: a corpus with no extension gets the invariant discipline and nothing more, and if you cannot establish the repo's message convention, ask rather than inferring one from the log.

## 2. Hand it over only when work on its files has stopped

**A hand-off is valid only while the files it stages stay untouched.** A script written when the work looked done, then followed by more edits to the same files, stages work its message does not describe - and can stage a file whose new import has no definition yet, producing a commit that does not build.

So: send the script when editing has stopped, or scope it to the files that are finished and say which you did. **If more edits follow, REISSUE it** rather than assuming it still holds.

**AND A REISSUE DOES NOT RETRACT WHAT IT REPLACES.** The superseded block is still sitting in the conversation, still valid shell, still stages real paths - and it is one scroll closer to hand than the new one. So a reissue **says plainly that the earlier block for that repo is dead**, and never assumes the newest script is the one that runs.

**The sharpest form of this is a REUSED MESSAGE.** Two scripts for one repo carrying the same `-m` text produce two commits nobody can tell apart in a log, and if the wrong one runs, the message describes work the commit does not contain - which no verification catches, because the tree is correct and only the record is wrong. **Give every script for a repo its own message**, even when the second is a small follow-up to the first, and especially then.

**Where a gate stands between the work and the commit, the script comes after the gate clears, never alongside it.** A runnable script sitting beside an unmet precondition is run first, and whatever was supposed to ride that commit then arrives a commit late with nothing in its own commit to explain it.

**Where the tree is frozen - a live run driving the app, a suite mid-flight - no script is handed over at all until it reports.** Running one rewrites files underneath it.

## 3. Inspect before you stage

`git status` and `git diff --stat` first, always.

**If a whole tree looks modified, suspect line endings before content:** `git diff --ignore-all-space --stat` coming back empty means zero content difference. Never `git add -A` in that state. The durable fix is a repo-local `.gitattributes` (`* text=auto eol=lf`) plus `git add --renormalize .`, because that is the one config layer every git reads; a checkout-conversion phantom cannot be cleared by restoring the file.

**A status line produced somewhere other than the operator's own git is not evidence about the operator's tree, in either direction.** Confirm before filing one as work or staging it as a change.

**On a synced or cloud-mounted repo, the operator's own view can lag the writer's by a few seconds.** A hand-off issued right after a sandboxed agent's edits land can be run before the operator's local filesystem has caught up - `git add`/`git commit` then stage the PRE-EDIT content, and the commit looks clean while the edits it was meant to capture are still sitting uncommitted underneath it. The tell is a tree that goes dirty again minutes later with no further edits in between. Where the hand-off follows edits by seconds rather than minutes, say so, and suggest the operator glance at `git diff --cached` (or reopen one touched file) before the `git commit` line runs.

**If unrelated uncommitted changes are already sitting in the repo, say so and scope the proposed commit to this slice's own files.**

**A `git add -u` or `git add -A` stages the tree as it is WHEN THE OPERATOR PASTES, not as it was when the script was written.** The status you inspected is a snapshot, and the script outlives it. Where another session may be writing to the same tree, or the same block could be pasted twice, a broad add sweeps in whatever became dirty in between and commits it under a message describing different work - and a second paste of an already-run script commits ONLY that stray edit, under a message that is entirely false. **So where the tree is shared, stage by explicit path and never by `-u` or `-A`.** The tell is a commit whose diff contains a file its message never mentions.

**A SWEEP'S PATH LIST IS THE SWEEP'S OWN OUTPUT, never a list of folders typed afterwards.** A sweep reaches wherever its subject is, and a folder list written from memory is a recalled subject list - it misses a tree the sweep touched and the commit lands half the change, with nothing to report it until a link checker runs against HEAD. **Have the sweep write every path it changed to a file** - both the old and the new path of every rename, so the deletion is staged too - **and stage exactly that file with `git --literal-pathspecs add --pathspec-from-file=<list>`**, which is exact at any size, still stages by path, and reads a bracket in a filename as a character rather than a glob. The tell is a sweep's commit script whose `git add` line names directories.

## 4. Every line in the block is shell input, including the parts that are not commands

**Scrub `>` `<` `|` `$` and backticks from `-m` prose.** Write "to" for an arrow and "greater than" for a comparison, and the hazard cannot fire however the quoting survives the paste. A `>` read as redirection writes the command's output into a file named after half the message, and leaves it sitting untracked one `git add -A` away from being committed. Prefer double quotes so apostrophes need no escaping.

**A `#` comment is shell input too, and an interactive shell need not honour it.** Where it does not, the comment's words become further pathspecs, and `git add` refuses the WHOLE invocation when any pathspec matches nothing - so the annotated lines stage nothing while the unannotated ones succeed, and the commit lands looking correct with the slice's own new file missing. **Annotations go in the prose around the block, never inside it.**

**If a message file is used at all, name it per slice and never end the script by deleting it.** One reused filename plus a trailing removal means running an earlier slice's tail deletes the next slice's message before it is committed.

## 5. The script ends at the last `git commit`

**A hand-off script never contains `git push`.** Pushing is the operator's call and its timing is theirs; a script ending in a push makes that decision for them by being convenient. If a push is genuinely a precondition for the next step, say so in prose and let them run it.

This is doubled for any branch that publishes to real users: never propose, script, or bundle a push to it. Check the ahead-count before even discussing a release, because a branch that looks provisional may be the published one.

## 6. What git will silently not stage

Three ways a file the work was ABOUT misses its own commit, each producing a message that is true about everything except the thing that mattered:

- **New files.** `git commit -am` and `git add -u` skip them. **Stage each new path explicitly and call it out as NEW in the prose.**
- **A `git mv` of a file with unstaged edits** carries the edits along unstaged. `git add` the destination path explicitly after the move, and say why.
- **An emptied file.** Plain `git rm` declines a file with local modifications, and emptying it is one, so the file survives as a committed stub. Use `git rm -f`, say why the `-f` is there, and never `git add` an emptied file.

**Whatever must be READ before the commit ends a block of its own, and the commit is a SECOND block.** A pasted block runs top to bottom, so a line placed between the adds and the commit is read only after the commit has already run - and prose saying "stop if this goes red" names a moment the operator never gets. **Block one stages and ends with what must be read**: a bare `git status --short` whenever it stages a new file, so an add that matched nothing is seen before it is committed, and the corpus's verifier wherever it has one. **Block two is the commit, pasted only after reading.** The tell is prose beside a single snippet saying what to do if a line in the middle of it fails.

## 7. One change per commit, one script per repo

**One logical change per commit** where practical.

**Separate repositories are separate commits.** One step often produces a commit in each - provide every one, and never fold a change to one repo into another's message.

**Whatever the repo's convention says must ride the same commit as the work - a contract file, a generated artefact, a version bump - is staged in that commit and named in its message**, never left as a follow-up. If a commit has already landed without it, say so plainly in the next message and name the commit it belongs to, rather than writing as though the pairing held.

**Match the repo's own message style.**

**NOTHING IN A HAND-OFF CREDITS OR NAMES THE ASSISTANT, MODEL, VENDOR OR HARNESS THAT WROTE IT, and no extension, repo convention, prior commit or harness default lifts this.** No `Co-Authored-By` or other trailer, no "Generated with" line, no model name, no vendor email or link - in a `-m` message, a tag, a branch name, a pull request, issue or release body, or an author or committer identity. A repo's log that already carries such a trailer is not a convention to match; it is the mistake this rule exists to stop repeating. Only the operator, in the session, in their own words, can lift it, and only for the commit they name.

## 8. Write it in the machine's dialect

**Detect the machine from the repo root path before writing a single operator-facing command.** A script in the wrong shell dialect looks correct and cannot run. If the path does not identify the machine, STOP and ask rather than guessing a shell.

This governs only commands handed TO the operator. Commands you run yourself are unaffected.

## 9. No holes

**A hand-off contains no placeholder and no open question.** If the shape of a commit is genuinely undecided - one commit or two, which files belong together - **ask in prose with NO script in the message, and write the script after the answer.**

A script with a hole in it is a script whose hole gets executed. An empty commit left as a deliberate no-op is still run, and history then carries a message describing work the commit does not contain, with the real files sitting uncommitted behind it. Undoing that is index-writing, so it costs the operator another round trip on top of the one the question was trying to save.

**The tell is a `-m` message you could not defend if the commit landed exactly as written.**

## 10. Before you send it

Read the block back once as the operator will run it, top to bottom:

1. Does every path in it exist, spelled as the repo spells it?
2. Is every NEW file staged by an explicit `add`, and is there a `status --short` to catch one that matched nothing?
3. Does the message describe what is actually staged, and nothing that is not?
4. Is there a `#`, a placeholder, an open question, a `push`, or any line crediting or naming an assistant, model, vendor or harness anywhere in it?
5. Have the files it stages been touched since it was written?

**State what the script does NOT cover** - unrelated changes left uncommitted, a second repo whose script is still coming, a verifier that was not run - in the prose beside it. A hand-off that reads as complete when it is partial is the failure this whole skill is about.

## Governance

**This file states what IS.** No dated narrative, no record of what a rule used to say, no changelog section - that history belongs in the log record of the session that changed it, and the plugin's `version` is what makes the change reachable. **The tell is a past-tense sentence about the skill itself; the cheap test is whether deleting it would change what a reader DOES**, and if not it is history.

**And it states ONE BEHAVIOUR, never a different one per corpus.** A branch on which repo or vault you are standing in asks the reader to CLASSIFY the tree first, and that classification is the failure - each branch is individually correct, so a session working across two corpora in one sitting mixes them and nothing reports it. Whatever varies goes in that corpus's `.claude/skill-extensions/` file, which this skill loads first and which outranks it on disagreement.
