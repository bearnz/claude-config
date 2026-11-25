---
name: clean-gone
description: Delete the local branches whose upstream is gone — what a merged PR leaves behind once GitHub deletes the remote branch — along with any worktree holding one, after checking each branch is already in an integration branch and each worktree is clean. Use whenever Josh wants stale, merged or orphaned branches tidied — "clean the gone branches", "delete the merged branches", "tidy up my branches", "which branches can I delete", "/clean-gone" — and prefer it over the commit-commands plugin's `/clean_gone`, which force-deletes whatever it finds without checking whether the work is merged first.
---

# Clean up branches whose upstream is gone

A merged PR leaves a local branch behind. GitHub deletes the remote branch, the
local one stays pointing at a ref that no longer exists, and git marks its
upstream `gone`. They accumulate at a rate of one per PR, and because they are
almost always merged work, deleting them is routine — which is exactly why it
wants doing by something that checks rather than something that assumes.

## Why not the plugin

`commit-commands:clean_gone` from the official marketplace finds the right
branches. What it then does with them is the problem: it deletes with
`git branch -D` and removes worktrees with `git worktree remove --force`.

Run against a repo holding one merged and one unmerged stale branch, it deletes
both without a word — the unmerged commit is left unreachable from any branch,
recoverable only from the reflog by someone who knows to look. It also attempts
every branch whose upstream is gone, `main` and `master` included; git refuses
only while that branch is checked out somewhere. And it does not prune first, so
on a repo whose remote-tracking refs are stale it reports nothing to do.

It lives under `~/.claude/plugins/`, which claude-config's allowlist ignores, so
it cannot be fixed here and a plugin update would overwrite a patch anyway.
Hence this skill, which does the same job and checks before destroying.

## The procedure

**1. Prune, or there may be nothing to find.**

```sh
git fetch --prune
```

An upstream is only marked `gone` once its remote-tracking ref is removed.

**2. List the candidates.**

```sh
git branch -vv | grep ': gone\]'
```

`-v` prints a bare `[gone]` and `-vv` the upstream's name
(`[origin/feature/thing: gone]`) — either detects them; `-vv` is worth it for
saying which upstream went in the report. A `+` prefix means the branch is
checked out in a worktree and `*` means it is the current branch; strip either
with `sed 's/^[+* ]//'`.

**3. Check each one is already somewhere safe.** This is the step that earns
the skill. For each candidate, ask of every integration branch the repo has —
`origin/main`, `origin/master`, `origin/develop`, since a repo on the develop
flow merges feature work there rather than into the trunk — whether merging the
branch into it would change anything:

```sh
git merge-tree --write-tree origin/main "$branch" | head -n1 | xargs git diff --quiet origin/main
```

Exit 0 means merging would leave that integration branch exactly as it is, so
every change on the branch is already there, however it got there. A conflict
also lands as non-zero, because the merged tree then holds conflict markers.
It is written as a pipe rather than capturing the tree in a variable so the file
contains no shell substitution beyond a named variable — the only kind seen to
come through the skill loader intact.

If it fails against all of them, try patch equivalence before concluding
anything:

```sh
git cherry origin/main "$branch"
```

No `+` line (empty output, or only `-` lines) also means nothing is at stake.
Only when both checks fail against every integration branch does the branch
hold work that exists nowhere else: say how many `+` lines there are and what
their subjects are, and **ask Josh before touching it**. Never fold it in with
the safe ones.

Why two checks, and why not `git merge-base --is-ancestor`: ancestry only
recognises a merge commit, and GitHub offers squash and rebase merging on these
repos too. Both rewrite the commits, so a branch whose content landed stops
being an ancestor of the trunk, and a check that cries wolf on every squash is
one you learn to click past. The two checks here each have a blind spot the
other covers. `git cherry` compares patch ids commit by commit, so a squash of
several commits into one matches none of them; the merge-tree check fails when
the trunk has edited the same lines again since the branch landed. Each passes
only when the branch's changes are already upstream, so either one passing is
enough. When both fail on work that did land, it gets held for Josh, which is
the direction to err in.

Skip `main`, `master` and `develop` themselves even when their upstream is gone
— that means the remote branch was renamed or removed, which is a different
problem and not one to solve by deleting the local copy.

**4. Check each worktree is clean.**

```sh
git -C "$worktree" status --porcelain --untracked-files=all
```

Any output is uncommitted or untracked work that `--force` would bin. Ask.

Find the worktree by ref, not by directory name — worktree folders are usually
named after the session that made them and bear no relation to the branch:

```sh
git worktree list --porcelain |
  awk -v b="refs/heads/$branch" '/^worktree /{p=substr($0,10)} /^branch /{if (substr($0,8)==b) print p}'
```

**5. Delete, without force.**

```sh
git worktree remove "$worktree"   # only if the branch has one
git branch -d "$branch"
```

Lowercase `-d` refuses anything unmerged, which after step 3 should never
trigger. If it does, the checking was wrong — stop and look rather than reaching
for `-D`.

The current branch cannot be deleted, and `git branch -d` refuses it. If HEAD's
own upstream is gone (normal right after a PR merges), switch to the trunk and
pull first; the branch is then deletable with the rest.

## What to report

Name every branch deleted with the SHA it was at, so a mistake is recoverable
from the reflog for the next 90 days, and say which worktrees went. List
separately, and untouched, anything held back for Josh to decide.

If step 2 found nothing, say the repo is already clean rather than narrating the
steps that found nothing.
