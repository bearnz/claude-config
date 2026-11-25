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
the skill. For each candidate, test it against every integration branch the repo
has — `origin/main`, `origin/master`, `origin/develop` — since a repo on the
develop flow merges feature work there rather than into the trunk:

```sh
git merge-base --is-ancestor "$branch" origin/main
```

Exit 0 means every commit on the branch is already in that branch and nothing is
at stake. A branch that fails against all of them has commits that exist nowhere
else: say how many (`git rev-list --count origin/main..$branch`) and what their
subjects are, and **ask Josh before touching it**. Never fold it in with the safe
ones.

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
git for-each-ref --format='%(worktreepath)' "refs/heads/$branch"
```

Empty output means the branch has no worktree. Resist the urge to parse
`git worktree list` instead: its plain output puts the path first, so a path
containing a space defeats field splitting, and the `--porcelain` form wants
awk's whole-line and field variables — the dollar-sign-number ones. Those must
never appear in a skill file. The loader substitutes them from the invoking
command's arguments, so what reaches the session is the argument text rather
than the variable, and the command is invalid by the time anyone runs it. The
file reviews clean and breaks only at the moment of use, which is the worst
place to find out.

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
