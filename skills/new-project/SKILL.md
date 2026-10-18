---
name: new-project
description: Scaffold a new side project in A:\.dev\<name>. A private GitHub repo under bearnz starts from a GitHub-made README, gets cloned locally, and its scaffold (README, .gitignore for the stack, a lean CLAUDE.md, the secret-scan workflow) arrives on a feature branch as a PR for Josh to review and merge. Nothing lands on main unreviewed. Use whenever Josh wants to start, spin up, bootstrap or scaffold a new project, repo or side project — "new project", "start a project for X", "set up a repo for this", "/new-project" — and also when throwaway work in a scratch folder should become a real project.
---

# New side project

Josh's conventions live in `~/.claude/CLAUDE.md`. This skill applies them to a
project that doesn't exist yet: one predictable shape for every side project.

**The rule this skill exists to keep:** no code reaches `main` without a PR
that Josh reviewed and merged, and that includes a brand-new repo. GitHub
creates `main` with nothing on it but its own README, and everything Claude
writes comes in through the first PR. The push guard denies
`gh repo create --push` for exactly this reason.

## 1. Pin down the inputs

You need four things. Take them from the request, and ask (one AskUserQuestion
call) only for the ones you can't infer:

- **name** — kebab-case. It is both the folder and the GitHub repo name.
- **one-line description** — used in the README, CLAUDE.md and the GitHub repo.
- **stack** — `python`, `godot`, or `other` (say what). This picks the .gitignore.
- **visibility** — private unless Josh says otherwise. Don't ask.

## 2. Check nothing is already there

```bash
ls "A:/.dev/<name>" 2>/dev/null && echo EXISTS
gh repo view "bearnz/<name>" --json name 2>/dev/null && echo REPO_EXISTS
```

If either one exists, stop and ask. Never scaffold over an existing folder or
repo.

## 3. Create the repo on GitHub — only after a yes

Show Josh the name, description and visibility, then ask. Creating a repo is
outward-facing. On a yes:

```bash
gh repo create "bearnz/<name>" --private --add-readme --description "<description>"
git clone "https://github.com/bearnz/<name>.git" "A:/.dev/<name>"
git -C "A:/.dev/<name>" switch -c feature/scaffold
```

`main` now holds only GitHub's one-line README, which needs no review.

**If Josh wants it local-only for now:** `git init -b main`, make one empty
commit (`git commit --allow-empty -m "chore: initialize repository"`), then
`git switch -c feature/scaffold`. When it goes to GitHub later, create the repo
*without* `--add-readme` or `--push`. Josh pushes the empty `main` from a
terminal with `ALLOW_MAIN_PUSH=1 git push -u origin main` (the pre-push hook and
the guard both block Claude from doing it), and the scaffold branch then
follows as a normal PR.

## 4. Write the scaffold (on `feature/scaffold`)

**README.md** (replaces GitHub's): the name as the heading, the description,
then "## Running" and "## Testing" sections that say plainly they haven't been
written yet. Don't invent run instructions for code that doesn't exist yet.

**.gitignore**: always include `.env`, `.env.*`, `*.local.json`,
`.claude/settings.local.json`, `.DS_Store` and `Thumbs.db`. Then add the stack's
entries:
- python: `__pycache__/`, `*.py[cod]`, `.venv/`, `.pytest_cache/`, `dist/`,
  `build/`, `*.egg-info/`
- godot: `.godot/`, `*.translation`, `export_presets.cfg`, `/android/`

For a Python project, also run `uv init --app --vcs none` in the folder. That
adds `pyproject.toml`, `.python-version` and a `main.py`. Report what it created
rather than assuming.

**CLAUDE.md**: keep it short. It gets read every session, so everything in it
should be true and current:

```markdown
# <name>

<one-line description>

## Running

Not written yet.

## Testing

Not written yet.

## Notes

Conventions are in ~/.claude/CLAUDE.md (feature branches -> PR -> main,
push only on approval, provenance labels).
```

Fill in Running and Testing as soon as they are real, and only with commands
that have actually been run.

**Secret scanning**: the standard caller from the template. Don't edit the copy:

```bash
mkdir -p "A:/.dev/<name>/.github/workflows"
cp ~/.claude/templates/secret-scan/.github/workflows/secret-scan.yml "A:/.dev/<name>/.github/workflows/"
```

## 5. Commit, then review before anything leaves the PC

```bash
git -C "A:/.dev/<name>" add -A
git -C "A:/.dev/<name>" commit -m "chore: scaffold <name>"
```

The global pre-commit hook runs gitleaks on this commit. Then show Josh the
complete diff of what the PR will contain (`git diff origin/main...HEAD`, or the
file list plus contents for a small scaffold), and ask before pushing.

## 6. Push the branch and raise the PR

```bash
git -C "A:/.dev/<name>" push -u origin feature/scaffold
```

Then use `/pr` against `main`. The secret-scan workflow runs on that PR, which
is its first real test in the new repo. Report the CI result. Josh reviews and
merges. Never merge it yourself.

## 7. Hand over

- If this session is running somewhere else (a scratch folder, another
  project), offer to move it into the new folder.
- Report what exists: local path, GitHub URL, the scaffold PR and its CI state,
  and the current branch. Say what wasn't done, such as no run or test commands
  yet.
- Further work starts on a new `feature/` branch from `origin/main` once the
  scaffold PR is merged.
