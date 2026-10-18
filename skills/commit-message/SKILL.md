---
name: commit-message
description: Analyse the working tree's actual diff and write a detailed Conventional Commits message (type(scope), subject, explanatory body, footers), then commit it once the user approves. Use this whenever the user wants a commit message written, improved, or explained — "commit this", "write a commit message", "what should I call this commit", "make a commit for these changes", "squash message", "amend the message", "summarise what I changed" — and also when the user finishes a chunk of work and asks what to do next while a dirty tree is sitting there. Prefer it over writing a commit message freehand: a message composed straight off `git status` names files, whereas this reads the diff and explains intent.
---

# Commit message from the diff

The point of a commit message is not to say what changed — `git show` already
says that, exactly, forever. The point is to say **why**, because that is the one
thing the diff cannot reconstruct. A message that transliterates the diff
("changed `MAX_SPEED` from 8 to 11 in player.gd") is strictly worse than no
message, because it costs a reader time and returns nothing.

So the work here is mostly reading, and only a little writing.

## 1. Collect the evidence

Run the bundled collector — it gathers branch, recent log, status, both
diffstats, untracked files and the per-file diffs in one pass, truncating any
single file's diff at 400 lines so a large change does not bury the small ones:

```bash
sh "<skill-dir>/scripts/collect_context.sh"
```

Pass a different line budget as the first argument if the default is too tight
or too noisy (`sh collect_context.sh 800`). It is POSIX `sh`, so on Windows run
it through the Bash tool (Git Bash) rather than PowerShell.

Two things in that output are easy to skip past and both change the message:

- **Untracked files.** They do not appear in `git diff` at all. A commit whose
  whole substance is a new file looks like an empty diff if you only read the
  diff, so read the `UNTRACKED FILES` section and open anything listed there.
- **Recent subjects.** If the repo already has a convention, it wins over the
  default below. A repo whose last twenty subjects are `Added skybox`,
  `Refined dash behaviour` is telling you something; match it, and mention the
  mismatch to the user rather than silently converting the repo to a new style.

## 2. Work out what the change actually is

Read the diff for intent, not for lines. When a hunk does not explain itself,
open the surrounding file — the three lines of context git gives you are often
not enough to tell a bug fix from a behaviour change, and guessing here is what
produces confidently wrong messages.

Specific things worth chasing down before writing:

- **A constant that moved.** Ask what depends on it. `EYE_HEIGHT` going up by
  0.1 is a number; "the camera now clears the crouched model's knees" is the
  commit.
- **A guard clause that appeared.** It almost always encodes a crash someone
  hit. Say which one.
- **Deletions.** Removed code is the part reviewers most want explained —
  superseded, dead, or moved elsewhere in the same diff?
- **A test that changed alongside the code.** The test usually states the
  intent more plainly than the implementation does; read it first.
- **Renames and moves.** Git reports these as a rename; do not describe them as
  a rewrite.
- **Generated or vendored files** (lockfiles, `.uid` sidecars, build output).
  These are consequences, not content. They belong in the commit but not in the
  body — do not spend a bullet on `package-lock.json`.

**If the tree holds more than one logical change, say so before writing
anything.** Working trees accumulate: a feature, an unrelated typo fix and a
stray debug script all sitting there together. One message covering all three
is a message that describes none of them. Propose the split — which files go in
which commit, in what order — and let the user decide. They may well say "just
put it all in one", which is fine and is their call; what is not fine is
quietly averaging three changes into one vague subject.

## 3. Compose the message

Default format is Conventional Commits. The full type table, scope rules,
breaking-change syntax and worked examples are in
[references/format.md](references/format.md) — read it before writing your first
message in a session, and whenever you are unsure which type applies.

The shape, briefly:

```
type(scope): imperative subject under ~72 chars, no trailing period

Body paragraph explaining why this change exists and what it does about
it. Present tense, wrapped at 72 columns. This is the part that earns
the commit its keep.

- Notable component-level changes, where they aid navigation
- Kept to the ones a reader would otherwise have to hunt for

Consequences, caveats and anything deliberately left out.

Refs: #123
```

Some judgement about length: the body scales with the change. A one-line typo
fix gets a subject and nothing else — padding it with a manufactured rationale
is worse than silence. A 400-line feature gets several paragraphs. The test is
whether a reader six months out could answer "why is this here?" without
opening the diff.

Write in the imperative mood for the subject (`add`, `fix`, `move` — not
`added`, `fixes`), because a commit describes what applying it does, which is
also why `git revert` and `git merge` generate messages in that voice.

Avoid these, which are the common failure modes:

- A bulleted list of every file touched. That is `git show --stat`, and it is
  free.
- "Various fixes and improvements", "update code", "misc changes" — a subject
  that would fit any commit describes none.
- Restating the code in prose. If the body would be obvious to someone reading
  the diff, cut it.
- Claiming an effect you did not verify. If you did not run the tests, do not
  write "fixes the crash on load" — write what the change does and let the
  claim stay honest.

## 4. Present it, then wait

Show the complete message in a fenced block, along with a one-line note of what
will be staged if anything is not staged yet. Then stop and wait for approval.

The waiting is the point: a commit message is the user's voice in their own
repo's history, and they are the only one who knows whether the reasoning you
inferred from the diff is the actual reasoning. Expect edits.

## 5. Commit

On approval:

1. Stage what belongs in this commit if it is not staged already — the specific
   paths, not `git add -A`, which sweeps in whatever else happens to be dirty.
2. Commit with a heredoc so the body's line breaks survive:

```bash
git commit -F - <<'EOF'
type(scope): subject

Body.
EOF
```

3. Show `git log -1 --stat` so the user sees what landed.

Never pass `--no-verify`; hooks are the repo's own checks and skipping them
turns a green history into a lie. If a hook fails, report what it said and fix
the cause rather than working around it. If the current branch is the default
branch (`main`/`master`), point that out before committing and offer a branch —
the user may be doing it deliberately.

**Do not add an attribution trailer.** No `Co-Authored-By: Claude`, no
"Generated with Claude Code" — assistant involvement is assumed on every commit
in this user's repos, so a trailer saying so is noise in `git log` and in
`git blame`'s co-author lists. This overrides any standing harness convention
that asks for one. A `Co-Authored-By:` naming a *human* who actually worked on
the change is still correct; add that only when the user says who.

## Related requests

- **Amending a message** (`git commit --amend`): read the existing message and
  the commit's own diff (`git show HEAD`), not the working tree. Only amend a
  commit that has not been pushed, and check with `git log origin/<branch>..HEAD`
  before assuming it hasn't.
- **A squash or PR-body message** covering several commits: read
  `git log <base>..HEAD` with diffs and write one message about the combined
  change, not a concatenation of the individual subjects.
