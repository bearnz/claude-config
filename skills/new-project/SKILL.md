---
name: new-project
description: Scaffold a new side project in $DEV_ROOT\<name> (the dev root). A private GitHub repo under bearnz is created from the reviewed bearnz/project-template (README, common .gitignore, a lean CLAUDE.md, the secret-scan workflow), cloned locally, and a language overlay (python by default, godot, or base only) arrives on feature/scaffold as a PR for Josh to review and merge. Also covers syncing later base-template changes into existing repos. Use whenever Josh wants to start, spin up, bootstrap or scaffold a new project, repo or side project — "new project", "start a project for X", "set up a repo for this", "/new-project" — when throwaway work in a scratch folder should become a real project, and when an existing repo should pick up changes to the project template.
---

# New side project

Josh's conventions live in `~/.claude/CLAUDE.md`. This skill applies them to a
project that doesn't exist yet: one predictable shape for every side project.

Projects are built in two layers:

- **Base**: the private template repo `bearnz/project-template`. It is
  language-neutral and holds what every repo gets: `README.md` and `CLAUDE.md`
  with `PROJECT_NAME` / `PROJECT_DESCRIPTION` placeholders and Running/Testing
  "Not written yet", a common `.gitignore` (secrets, local overrides, OS
  clutter), and `.github/workflows/secret-scan.yml`. Josh reviewed it, and it
  changes only through PRs on that repo.
- **Overlay**: `~/.claude/templates/<stack>/`, applied on the project's first
  feature branch. Each overlay has a `gitignore` with lines to append, and may
  have an `apply.sh` that generates the rest with the language's own tooling.

**The rule this skill keeps:** the only commit that reaches `main` without a PR
is the one GitHub makes from the reviewed template when it creates the repo.
Everything after that (the filled-in placeholders and the overlay included)
comes in on `feature/scaffold` through a PR. The push guard denies
`gh repo create --push` for this reason.

## 1. Pin down the inputs

You need four things. Take them from the request, and ask (one AskUserQuestion
call) only for the ones you can't infer:

- **name**: kebab-case. It is both the folder and the GitHub repo name.
- **one-line description**: used in the README, CLAUDE.md, the GitHub repo and
  (for Python) pyproject.toml.
- **stack**: `python` (the default), `godot`, or `other` (say what). It picks
  the overlay.
- **visibility**: private unless Josh says otherwise. Don't ask.

## 2. Check nothing is already there

Projects go in the dev root, the `DEV_ROOT` user environment variable
(`bearnz/workstation`'s `bootstrap.ps1` sets it; in PowerShell it's
`$env:DEV_ROOT`). The commands below are Git Bash. If `DEV_ROOT` is empty,
stop and ask Josh where projects live on this PC rather than guessing a drive.

```bash
echo "DEV_ROOT=$DEV_ROOT"
ls "$DEV_ROOT/<name>" 2>/dev/null && echo EXISTS
gh repo view "bearnz/<name>" --json name 2>/dev/null && echo REPO_EXISTS
```

If either one exists, stop and ask. Never scaffold over an existing folder or
repo.

## 3. Create the repo from the template, only after a yes

Show Josh the name, description and visibility, then ask. Creating a repo is
outward-facing. On a yes:

```bash
gh repo create "bearnz/<name>" --private --template bearnz/project-template --description "<description>"
gh repo edit "bearnz/<name>" --delete-branch-on-merge
git clone "https://github.com/bearnz/<name>.git" "$DEV_ROOT/<name>"
git -C "$DEV_ROOT/<name>" log --oneline
git -C "$DEV_ROOT/<name>" switch -c feature/scaffold
```

Every bearnz repo deletes a PR's head branch once it's merged.
`gh repo create` has no flag for that, hence the `gh repo edit`.

`main` now holds one commit, GitHub's copy of the template. If `git log` shows
no commits, GitHub hadn't finished generating the repo yet: delete the empty
local clone, wait a few seconds, and clone again.

**If Josh wants it local-only for now:** clone the template instead
(`git clone https://github.com/bearnz/project-template.git "$DEV_ROOT/<name>"`),
then `git -C "$DEV_ROOT/<name>" remote remove origin` and
`git switch -c feature/scaffold`. When it goes to GitHub later, create an empty
repo (no `--add-readme`, `--template` or `--push`), then run the same
`gh repo edit --delete-branch-on-merge`. Josh pushes `main` from a
terminal with `ALLOW_MAIN_PUSH=1 git push -u origin main` (the pre-push hook and
the guard both block Claude from doing it), and the scaffold branch then
follows as a normal PR. The template's own history comes along in that case;
say so when offering it.

## 4. Fill in the base and apply the overlay (on `feature/scaffold`)

**Placeholders:** replace `PROJECT_NAME` and `PROJECT_DESCRIPTION` in
`README.md` and `CLAUDE.md` (use Edit; a description can hold characters that
break a sed). Leave Running and Testing as "Not written yet" unless a command
for them has actually been run.

**Overlay:** from the repo root,

```bash
cat ~/.claude/templates/<stack>/gitignore >> .gitignore
```

then, if the overlay has an `apply.sh`, run it. Report what each step created
rather than assuming.

- **python** (default):

  ```bash
  sh ~/.claude/templates/python/apply.sh "<description>"
  ```

  This runs `uv init --package --app --vcs none --author-from none
  --description "<description>" .`, which keeps the base README and adds
  `pyproject.toml` (requires-python `>=3.N`, a `[project.scripts]` entry named
  after the project, the `uv_build` backend), `.python-version` (`3.N`) and
  `src/<package>/__init__.py`. `3.N` is the minor version of the Python uv
  finds on this PC, so report which one it picked. It then adds pytest as a
  dev dependency (`uv.lock` appears; commit it), writes `tests/test_smoke.py`
  and runs `uv run pytest`. It refuses to run where a `pyproject.toml` already exists.
  Afterwards run `uv run <name>` too. Once both have passed, fill CLAUDE.md and
  the README in: Running is `uv run <name>`, Testing is `uv run pytest`.
- **godot**: the gitignore lines only. Godot writes `project.godot` itself when
  Josh first opens the folder in the editor, so don't hand-write one.
- **other**: base only, no overlay. Add the stack's ignore lines by hand. If
  the same language comes up a second time, propose a new
  `~/.claude/templates/<lang>/` overlay (a `gitignore`, plus an `apply.sh` if
  the language has an init tool) as a claude-config PR.

## 5. Commit, then review before anything leaves the PC

```bash
git -C "$DEV_ROOT/<name>" add -A
git -C "$DEV_ROOT/<name>" commit -m "chore: scaffold <name>"
```

The global pre-commit hook runs gitleaks on this commit. Then show Josh the
complete diff of what the PR will contain (`git diff origin/main...HEAD`, or
the file list plus contents for a small scaffold; `uv.lock` can be summarised),
and ask before pushing.

## 6. Push the branch and raise the PR

```bash
git -C "$DEV_ROOT/<name>" push -u origin feature/scaffold
```

Then use `/pr` against `main`. The secret-scan workflow runs on that PR. Report
the CI result. Josh reviews and merges. Never merge it yourself.

## 7. Hand over

- If this session is running somewhere else (a scratch folder, another
  project), offer to move it into the new folder.
- Report what exists: local path, GitHub URL, the scaffold PR and its CI state,
  and the current branch. Say what wasn't done, such as run or test commands
  that are still "Not written yet".
- Further work starts on a new `feature/` branch from `origin/main` once the
  scaffold PR is merged.

## Syncing base changes into an existing repo

GitHub templates copy files once, at creation. A later change to
`bearnz/project-template` (say, a new `.gitignore` line) never reaches repos
made earlier, nor repos that predate the template. Bring it over as a normal PR:

1. Get the current base:
   `git clone --depth 1 https://github.com/bearnz/project-template.git <short temp path>`.
2. In the target repo, cut `chore/sync-template` from `origin/main`. If Josh
   has uncommitted work in the main checkout, use a throwaway worktree on a
   short path instead of switching under it.
3. Copy over only the base files that changed, file by file:
   - `.github/workflows/secret-scan.yml`: copy as is (it's the same file as
     `~/.claude/templates/secret-scan/`; `/secret-scan` is the other way in).
   - `.gitignore`: add the new base lines; keep the repo's own (overlay and
     project) lines.
   - `README.md`, `CLAUDE.md`: these belong to the project now. Never copy the
     placeholder versions over them. Carry a new base convention across by
     hand, in the project's own words.
4. Commit (`chore: sync base files from project-template`), show Josh the diff,
   push on a yes, and `/pr`.

Don't `git merge --allow-unrelated-histories` the template in. It would pull
the template's whole history and its placeholder README and CLAUDE.md into the
repo, and conflict on every file the project has since made its own.
