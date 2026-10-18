---
name: resolve-merge-conflicts
description: Resolve conflicts from a `git merge` by reading what each side was actually trying to do, resolving the mechanical clashes directly and stopping to ask about the ones that need a judgement call. Use this whenever a merge is or is about to be conflicted — "fix the merge conflicts", "resolve the conflicts", "merge main into my branch", "git pull left me with conflicts", "this PR has conflicts", "CONFLICT (content)", "help me finish this merge" — and also whenever a `git merge` or `git pull` you ran yourself reports CONFLICT and leaves unmerged paths behind. Prefer it over resolving markers by hand: the markers show two final states with no history, and picking between them without reading the two branches is how one side's work gets silently deleted.
---

# Resolving a merge conflict

A conflict marker is a poor description of the problem. It shows two *final
states* and nothing about how either got there:

```
<<<<<<< HEAD
    speed = clamp(speed, 0.0, MAX_SPEED)
=======
    speed = speed * drag
>>>>>>> feature/drag
```

Which is right? The markers cannot tell you, because the answer is a question
about intent: one side clamped a runaway value, the other added drag, and quite
possibly the merge wants both, in a particular order. Choosing between two lines
by eye is how a merge quietly discards a bug fix.

So the work here is mostly reading, and the reading material is the two branches
— not the file in front of you.

## 1. Establish what is being merged

```bash
sh "<skill-dir>/scripts/collect_conflicts.sh"
```

POSIX `sh`, so on Windows run it through the Bash tool (Git Bash) rather than
PowerShell. Pass a line budget as the first argument if the per-file diffs are
too tight or too noisy (`sh collect_conflicts.sh 600`).

It prints, in one pass: which branch is being merged into which, the merge base,
the commits each side landed since that base, every conflicted path with its
status code, and per file **what our side changed and what their side changed
relative to the base** — which is the evidence the markers are missing. It ends
with the files git merged silently that both sides touched; keep that list, it
matters in step 5.

Two things to fix in your head before reading further, because inverting either
one produces a resolution that looks plausible and is backwards:

- **In a merge, "ours" is the branch you are standing on** (`HEAD`) and
  "theirs" is the branch named in the merge command (`MERGE_HEAD`). When you
  merge `main` into your feature branch, *ours* is your feature work and
  *theirs* is main. This reverses under rebase and cherry-pick, so if the script
  reports one of those in progress, say so rather than proceeding on merge
  assumptions.
- **The three stages are available as files.** `git show :1:path` is the base,
  `:2:path` is ours, `:3:path` is theirs. When a conflict region is long or the
  markers have been mangled, read the stages instead of squinting at the
  working copy.

If `merge.conflictStyle` is unset, the markers hide the base. Suggest
`git config --global merge.conflictStyle zdiff3` once — seeing what the line
*used to be* turns most conflicts from a guess into an observation — but do not
change the user's git config as a side effect of a task they asked for.

## 2. Work out what each side was doing

For each conflicted file, before touching it:

- Read our diff and their diff from the script's output. Most conflicts explain
  themselves at that point — one side renamed something, the other added a
  caller.
- When a hunk still does not explain itself, read the commits that produced it:
  `git log --merge -p -- <path>` shows only the commits from either side that
  touched this file. The commit message usually states the intent more plainly
  than the code does.
- Open the surrounding file when the conflict is about how a change fits, not
  about the lines themselves. Three lines of context is often not enough to tell
  a refactor from a behaviour change, and guessing here is what produces
  confidently wrong merges.

## 3. Sort each conflict into mechanical or judgement

This split is the whole point of the skill. Resolve the first kind and get on
with it; stop and ask about the second. The line between them is not how big the
conflict is — it is **whether the resolution can be wrong in a way the diff would
not show**.

**Mechanical — resolve these yourself, and note what you did:**

- *Both sides added to an unordered list.* Imports, exports, dependencies, test
  cases, enum members, a switch of independent branches. Take the union, drop
  duplicates, and keep whatever ordering the file already has (alphabetical,
  grouped by origin) rather than concatenating the two blocks.
- *One side moved or reformatted code the other side edited.* The edit is the
  content and the move is the container: apply the edit inside the new location.
- *Adjacent but unrelated edits.* Git conflicts on touching hunks even when the
  changes are independent. If our change and their change are to different lines
  that happen to sit together, keep both.
- *Generated or derived files.* Lockfiles, build output, `.import`/`.uid`
  sidecars, compiled assets, snapshots. Never hand-merge these — take either
  side, regenerate from the merged source, and keep the regenerated result. See
  [references/patterns.md](references/patterns.md) for the recurring file
  classes and the command that regenerates each.
- *One side changed nothing.* The script says "(no change on this side)" — the
  conflict is an artefact of a delete/re-add or a whitespace pass; take the side
  that has the work.

**Judgement — stop and ask, with a recommendation:**

- *Both sides changed the same expression, condition, or constant.* Two people
  fixed the same thing differently and only one fix survives. There is no
  combination of the two lines that is safe by construction.
- *One side deleted what the other side edited* (`DU`/`UD` status). The deletion
  may be a removal the edit hasn't heard about, or the edit may be exactly why
  the file should stay. Both readings are common and they have opposite
  resolutions.
- *Both sides created the same file independently* (`AA`). Two implementations
  of one thing; merging their text usually produces neither.
- *The combination is coherent but changes behaviour.* Both sides' code fits
  together and the result does something neither branch does. That is a design
  decision, not a merge.
- *A resolution that would drop something.* Any time the answer is "delete one
  side's work", say so out loud before doing it.

**When you are not sure which kind it is, treat it as judgement.** The costs are
not symmetric: asking about a mechanical conflict wastes a few seconds, and
silently guessing at a semantic one buries a deleted bug fix in a merge commit
that nobody reviews line by line.

## 4. Resolve

Edit the file so that no marker remains — including the `=======` and the
`>>>>>>>`, which are easy to leave behind in a long region. Write the merged
result as code you would have written if both changes had been made in sequence,
not as one side's block followed by the other's.

Avoid these:

- **`git checkout --ours` / `--theirs` on a file with real conflicts.** They
  take that side's *entire file*, throwing away every unrelated change the other
  side made to it, with no diff to show for it. They are right for a lockfile
  you are about to regenerate and wrong almost everywhere else.
- **Keeping both versions "to be safe"** — a duplicated function or a
  double-applied change compiles and is wrong.
- **Resolving by deleting the conflicting code entirely.** It makes the markers
  go away and is the one outcome neither branch asked for.
- **Reformatting while you are in there.** A merge commit that also reflows a
  file is unreviewable; keep the resolution to the conflict.

Then stage the file — in git, `git add <path>` *is* the act of marking it
resolved:

```bash
git add <path>
```

If you mangle a file mid-resolution, `git checkout -m -- <path>` restores the
conflict markers and lets you start that file again. If the whole merge turns
out to be a mistake, `git merge --abort` returns the tree to where it was.

## 5. Check the conflicts git did not report

The dangerous outcome of a merge is not a conflict — it is the file git merged
without complaint that no longer works. Git merges text; it does not know that
one branch renamed `apply_damage` while the other added three calls to it. Both
diffs applied cleanly and the result does not run.

So, before committing:

- Read the "merged without complaint but touched by both sides" list from the
  script. For each file, ask whether one side's change assumes something the
  other side altered — a renamed symbol, a changed signature, a moved file, a
  new required argument.
- **Build it, or run the tests, or both.** This is not optional politeness; it
  is the only check that covers the semantic case. If the repo has a smoke test
  or a headless run, that is the one to use. If you cannot run anything, say
  clearly that the resolution is unverified rather than implying it works.
- Sweep for leftovers, since a stray marker inside a string or a comment gets
  past the compiler:

```bash
git diff --cached --check
git grep -nE '^(<<<<<<< |=======$|>>>>>>> )' -- . || echo "no markers left"
```

## 6. Report, then commit

Before committing, show the user a short account of what you decided — this is
the only moment the reasoning exists anywhere. Something like:

```
Resolved 6 conflicts in 4 files, merging origin/main into feature/drag.

Mechanical (resolved):
  scripts/player.gd:12   both added imports - took the union
  package-lock.json      regenerated from the merged package.json
  scripts/hud.gd:88      their rename applied to our new label

Needs your call (not resolved):
  scripts/player.gd:140  both changed the speed clamp. Ours limits to
                         MAX_SPEED after drag; theirs applies drag to an
                         already-clamped value. Different results at high
                         speed - I'd take ours, but it's your fix.

Verified: godot --headless smoke_test.tscn passes (14/14).
```

Then commit. A merge commit's default message is generated by git and already
names the branches, so keep it and **add a line for anything you resolved
non-obviously** — the resolution is invisible in the merge commit's diff against
either parent, so this note is the only record that a decision was made:

```bash
git commit --no-edit          # nothing worth recording
```

or, when there is:

```bash
git commit -F - <<'EOF'
Merge branch 'main' into feature/drag

Resolved the speed clamp in player.gd in favour of main's ordering:
drag is applied before the clamp, so a large delta cannot exceed
MAX_SPEED for one frame.
EOF
```

Never pass `--no-verify`; hooks are the repo's own checks, and a merge is
exactly when you want them to run. If a hook fails, report what it said and fix
the cause.

## Notes on the awkward cases

- **A conflicted binary or opaque file** (image, `.blend`, an editor scene file
  that is really a serialised graph). There is no meaningful text merge: present
  both sides — sizes, what each commit says it changed — and let the user pick
  one, or ask them to redo the change on top of the merged version.
- **Very many conflicted files.** Group them by cause rather than walking the
  list. Twenty files conflicting on the same rename is one decision applied
  twenty times, and reporting it as twenty questions wastes everyone's time.
- **Conflicts that keep coming back** on repeated merges of the same branches:
  mention `git rerere`, which records a resolution and replays it. Suggest it;
  do not enable it silently, since it changes how future merges behave.
- **The merge is not the fix.** If the two branches have genuinely diverged in
  design, sometimes the right answer is to abort, and rebase or redo the work
  rather than to negotiate every hunk. Say so if you see it.
