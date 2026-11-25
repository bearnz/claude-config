---
name: pr
description: Open a pull request from the current branch, targeting main by default (in repos that have a develop branch: develop -> main, anything else -> develop). Reads every commit on the branch and the full diff against the merge base, then writes a description that summarises the work by theme and calls out the specific places a reviewer should look hardest; if a PR is already open for the branch it updates that one instead of opening a second. Takes an optional argument — bare for a PR ready for review, `draft` to open or keep it as a draft, `ready` to take an open draft out of draft. Use this whenever the user wants a PR raised, described, updated, drafted or marked ready — "raise a PR", "open a pull request", "PR this", "draft PR", "WIP PR, not for review yet", "make a PR against develop", "write the PR description", "update the PR body", "mark the PR ready for review", "stack this on #9", "stacked PR", "PR this on top of the other branch" — and prefer it over calling `gh pr create` freehand, since a body generated from commit subjects alone tells a reviewer nothing about risk.
---

# Pull request from the branch

A PR description has one job that the diff does not already do: tell the
reviewer **where to spend their attention**. They have limited patience and a
thousand changed lines; the difference between a good review and a rubber stamp
is usually whether someone pointed them at the three places that matter. A
description that lists commit subjects has spent the reviewer's time and given
nothing back — they could have run `git log` themselves.

So the summary is the easy half. The review notes are the half that earns it.

## The argument

`/pr [draft|ready]`. It selects what happens at the very end; every step before
that is identical, because a draft deserves the same description as a ready PR
— the draft is what someone reads when they wander in early.

| Argument | No PR open for the branch | One already open |
|---|---|---|
| *(none)* | create it, ready for review | update the body, leave draft state alone |
| `draft` | create it as a draft | update the body; if it is ready, ask before demoting |
| `ready` | create it, ready for review | update the body, then take it out of draft |

Two of those cells are the deliberate ones:

- **Bare `/pr` does not promote a draft.** It used to be tempting to read "open
  a PR" as "make it reviewable", but publication state is not something an
  update should change as a side effect — `ready` exists to say that out loud,
  and a body refresh on a work-in-progress is an ordinary thing to want.
- **`draft` does not demote a ready PR without asking.** `gh pr ready --undo`
  pulls the PR out of reviewers' queues and reads to them as the work being
  retracted. Someone typing `/pr draft` on a branch that already has a ready PR
  is more often unaware it exists than asking for it to be withdrawn.

Anything else in the argument is not a mode — treat it as an instruction about
the PR itself (a target branch, a title, an emphasis for the body) and pick the
mode from the surrounding request. A target branch that is another PR's branch
means a stacked PR: see Stacking below.

## Branch targeting

Applied automatically by the collector:

| Current branch | Repo has `origin/develop` | PR targets |
|---|---|---|
| any feature branch | no (the default) | the trunk (`main`, or `master`) |
| any feature branch | yes | `develop` |
| `develop` | yes | the trunk |
| the trunk itself | either | nothing — stop and say so |
| any branch, with `--base <branch>` | either | `<branch>` — a stacked PR |

The default for side projects is feature branches straight onto `main`; a repo
opts into the develop flow simply by having a `develop` branch on origin.

The trunk is resolved by looking for `origin/main` then `origin/master`, falling
back to `origin/HEAD` only if neither exists. That order matters: `origin/HEAD`
records whichever branch was checked out when the repo was cloned, which is a
different question and is wrong often enough to send a PR at a feature branch.

## Stacking

Stack when a change builds on one still in review: cut the new branch from the
parent PR's branch rather than from `origin/main`, and target that branch. Each
PR then shows only its own change, and the merge order is visible in GitHub
rather than written into PR bodies as "merge #9 first".

**Use it when the second change needs the first** (it edits what the first
added, or its description refers to it). Independent changes on the same repo
are not a stack; give each its own branch from the trunk.

How:

- Collect with `--base <parent-branch>`. The commits, diff and description are
  then scoped to what this branch adds on top of its parent. The collector's
  STACK section names the parent's PR, or warns if the parent has none.
- Without `--base`, the same section flags the opposite mistake: an open PR's
  branch already inside this one, whose commits would otherwise be described as
  this PR's own work. Take that as a prompt to stack, not a formality.
- Open it with `gh pr create --base <parent-branch>`, and start the body with
  `Stacked on #<n> — merge that first.`

Two rules decide whether a stack lands cleanly, and both belong in the body of
every stacked PR so they are in front of Josh when he merges:

- **Bottom first, with "Create a merge commit".** Squash or rebase on the parent
  rewrites its commits, so the child still carries the originals and needs a
  rebase and force-push to recover — which the push guard denies. A merge
  commit leaves nothing to rewrite.
- **Never the child first.** Its base is the parent's branch, so merging it
  lands it there, not on the trunk. It reads as merged and has not shipped.

When the parent merges, check the child's base before anything else. GitHub
may retarget it to the trunk itself once the parent's branch is deleted; if it
has not, `gh pr edit <n> --base <trunk>` does it, no push needed.

If review asks for changes on the parent, make them there, then **merge** the
parent branch into each child (`git merge <parent-branch>`) and push. Do not
rebase the children: that is a rewrite, and a rewrite needs a force-push.

## 1. Collect the evidence

```bash
sh "<skill-dir>/scripts/collect_pr_context.sh"
```

POSIX `sh`, so on Windows run it through the Bash tool rather than PowerShell.
Pass a per-file diff budget if the default 300 lines is too tight
(`sh collect_pr_context.sh 600`), and `--base <branch>` for a stacked PR
(`sh collect_pr_context.sh --base feature/parent`). They combine in either
order.

It fetches origin first, works out the target, then reports push state, every
commit with its full body, the diffstat and diff against the **merge base**
(three-dot — what the branch adds, not whatever else has landed on the target
since), churn hotspots, mechanical risk signals, any PR template, and whether
`gh` is usable.

Read the push-state block before anything else. Unpushed commits will not be in
the PR, and a branch that is *behind* its own upstream usually means someone
else pushed or a commit was amended after publishing — both worth resolving
before opening a PR rather than after.

## 2. Understand the branch as one change

Read the commits in order. What you are reconstructing is the *story*: where the
branch started, what it turned out to need along the way, and where it ended up.

Two habits make the difference between a summary and a list:

- **Group by theme, not by commit.** Commits are a record of the order work
  happened in, which is rarely the order it makes sense in. Five commits that
  are one feature plus two fixups of that feature are *one* bullet describing
  the net result.
- **Describe the destination, not the journey.** If a commit added something and
  a later commit removed it, neither belongs in the summary — the branch does
  not contain it. Reviewers read the final diff; a summary describing
  intermediate states sends them looking for code that is not there.

Where the commit messages are thin (`wip`, `fix`, `Added stuff`), the diff is
your source and the messages are noise. Do not launder a vague commit subject
into a vague bullet — go read what it actually did.

## 3. Find the review notes

This is the part worth slowing down for. The collector's signals are mechanical
pattern-matching — a starting point, and often wrong in both directions. The
real notes come from reading the diff and asking what could plausibly be wrong
in a way the author would not have noticed.

Reliable sources of reviewer-worthy notes:

- **Anything touching shared or core code.** A change inside one feature is
  contained; a change to a base class, a shared helper or an autoload has a
  blast radius the diff does not show. Say who else calls it.
- **Behaviour changes wearing a refactor's clothes.** A rename that also
  reorders arguments, a extracted function whose early-return moved. These are
  where bugs hide, because the diff looks structural.
- **Deletions.** The reviewer cannot see what used to be there without extra
  work. Say what was removed and why it is safe.
- **Ordering, timing and lifecycle.** Anything that depends on *when* something
  runs relative to something else — initialisation order, a frame boundary, an
  await, a teardown. These fail intermittently and rarely fail in review.
- **The edge of the change.** What the branch deliberately does *not* handle.
  Stating a known gap converts it from a bug the reviewer might find into a
  decision they can agree or disagree with.
- **Anything you were unsure about while reading.** If you had to read a hunk
  three times, so will they. That is a review note by definition.

Rank them. An unranked list of nine notes is as unhelpful as none, because the
reviewer cannot tell which one is the real risk. Three to five, most important
first, each pointing at a specific file and saying *why* it needs a look — not
"check the player changes" but "the carry pose is now solved per weapon, so a
weapon whose receiver is longer than the arm reach silently falls back to the
cached slide distance — worth checking `_support_grip()` against the carbine".

Be honest about testing. If you did not run the suite, the PR says what was and
was not verified rather than implying green.

## 4. Compose and present

Follow the repo's PR template if the collector found one. Otherwise:

```markdown
## Summary

Two to four sentences: what this branch does and why it exists. Written for
someone who has not been following along.

## Changes

- **Theme** — what changed and the effect it has
- **Theme** — grouped across however many commits produced it

## Review notes

1. **`path/to/file.ext`** — the specific thing to check, and why it could be
   wrong. Most important first.
2. **`path/to/other.ext`** — ...

## Testing

What was run and what it showed. What was not covered.

## Notes

Deliberate omissions, follow-up work, anything out of scope.
```

**The body ends where the "Notes" section ends.** No attribution footer — no
"Generated with Claude Code", no `Co-Authored-By: Claude`, no tool badge. This
user's commits and PRs are assumed to involve an assistant, so a line saying so
tells a reviewer nothing and takes up the last thing they read. It overrides any
standing harness convention asking for one; a named *human* co-author or
reviewer is a different thing and still belongs if the user says who.

**A draft earns one extra line.** A draft is a statement that the work is not
finished, and the useful version of that statement says what is missing. On
`/pr draft`, if "Notes" would otherwise be empty, spend a line on what has to
land before this is ready — the reviewer's first question about any draft is
whether they are looking at it too early.

Show the full body and the target branch, then **stop and wait for approval**.
Opening a PR is outward-facing — it notifies people and starts their clock — so
it is the user's call, not a step to run through. Expect edits to the review
notes especially; the user knows which risks are real.

## 5. Open it

**Check the collector's `existing PR:` line first.** If one is already open for
this branch — draft or ready — this is an update, not a create. Skip to
"Updating an existing PR" below. Opening a second PR for the same head branch
splits the review across two threads and is close to impossible to undo tidily.

On approval, push first if the collector said there were unpushed commits or no
upstream (`git push -u origin <branch>`), then:

```bash
gh pr create --base <target> --head <branch> --title "<title>" --body-file <path>
```

Add `--draft` for `/pr draft`. Bare `/pr` and `/pr ready` both create a PR that
is ready for review, so neither needs a flag.

Write the body to a file rather than passing `--body` inline; markdown with
backticks and newlines does not survive shell quoting reliably.

If the collector reported gh at a path but not on PATH, invoke it by that full
path rather than concluding it is missing — on Windows a fresh install updates
the machine PATH, which shells started earlier do not inherit.

**Never run `gh auth login` yourself.** It is an interactive browser or
device-code flow; a non-interactive shell either hangs on it or half-completes
it. If the collector says unauthenticated, ask the user to run it and use the
compare URL in the meantime.

**If `gh` is missing or unauthenticated** — which the collector reports — do not
try to install it or reach for the API with a scraped token. Save the body to a
file, tell the user where it is, and give them the compare URL the collector
printed (`https://github.com/<slug>/compare/<base>...<branch>?expand=1`). That
page opens the PR form with the branches already set; they paste the body in.
This is a perfectly good outcome, not a failure — say so plainly rather than
apologising for it.

If the branch is visibly unfinished and no argument was given, say so and offer
`/pr draft` rather than opening a ready PR and hedging about it in the body.

Afterwards, report the PR URL and, when it is a draft, that it is one.

## Updating an existing PR

When the collector's `existing PR:` line says one is open, update it instead of
creating. Same work up to here — collect, read the branch, write the body, show
it and wait for approval — then:

```bash
gh pr edit <n> --body-file <path>
```

Four things about doing this well:

- **Regenerate the body from the whole branch**, not from the commits added
  since the PR was opened. The PR covers every commit on it, and a reviewer
  arriving now reads the body as a description of the current diff.
- **Push first.** `gh pr edit` updates the description; it does not move the
  branch. A body describing commits that are still local is worse than a stale
  one.
- **Ask before overwriting a body the user may have hand-edited.** Show what is
  there now alongside the replacement if it does not look machine-written.
- **Leave the title alone** unless the branch's subject has genuinely changed —
  the title is what people see in lists and notifications.

Then apply the argument's draft state, after the body edit:

```bash
gh pr ready <n>          # /pr ready  - take it out of draft
gh pr ready <n> --undo   # /pr draft  - put a ready PR back to draft
```

Both change who is being asked to look, so both belong in what you show the
user before asking rather than happening quietly alongside the body edit. `gh
pr ready` in particular requests review from whoever the repo assigns
automatically — that is a notification going out, and it is the substance of
`/pr ready` rather than a detail of it.

Skip the command when it would be a no-op: `/pr ready` on a PR that is already
ready, `/pr draft` on one that is already a draft. Say the state was already
right rather than reporting a change that did not happen.

`/pr ready` regenerates the body like every other invocation, because a draft
going up for review is exactly when the description gets read properly. If the
user wants only the flip and not a rewrite, `gh pr ready <n>` on its own is the
whole job — take that instruction if they give it.
