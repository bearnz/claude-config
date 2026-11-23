---
name: secret-scan
description: Add (or update) the standard gitleaks secret-scanning GitHub Actions workflow in a repo, on its own branch with a PR, after first scanning the repo's existing history so the first CI run holds no surprises. Use whenever Josh wants secret scanning, gitleaks, leak detection or "the CI template" added to a project, rolled out across existing repos, or bumped to a newer gitleaks — "add secret scanning", "bundle the secret scan", "check this repo for leaked keys", "/secret-scan".
---

# Secret scanning for a repo

Secret scanning has three layers. This skill installs the per-repo one:

1. **Local, every repo on this PC:** a global pre-commit hook
   (`core.hooksPath` → `~/.claude/git-hooks/`) runs gitleaks on staged changes.
   Nothing to install per repo.
2. **Shared CI job:** `bearnz/ci-templates/.github/workflows/secret-scan.yml`,
   a reusable workflow that pins gitleaks by version and checksum. Callers
   follow its `v1` tag.
3. **Per-repo caller:** `~/.claude/templates/secret-scan/.github/workflows/secret-scan.yml`,
   a short file that calls layer 2. GitHub only runs workflows that are in the
   repo itself, so every repo needs this file. It's what this skill adds.

**Bumping gitleaks** happens in `$DEV_ROOT\ci-templates` (the dev root), not
in any repo. Branch, change the version and checksum, open a PR there (its `self-scan` workflow runs
the change against ci-templates itself), and after Josh merges it, Josh moves
the `v1` tag from a terminal (commands in that repo's README). Claude doesn't
move the tag, because that's a force push. Callers pick up the change on their
next run, with no per-repo PRs. Only a breaking change gets a `v2` tag, and
then callers do need per-repo PRs.

The reusable workflow only works for **private** callers (ci-templates is
private). For a public repo, copy the job inline instead of using `uses:`.

GitHub can't make this check *required* on Josh's private repos (free plan:
branch protection and rulesets return 403). The CI run reports, and the
convention does the enforcing: **never merge a PR whose secret-scan run failed.**

## 1. Get the repo ready

From the repo root:

```bash
git status --porcelain
git fetch origin
```

Work out the base branch the same way `/pr` does: `develop` if
`origin/develop` exists, otherwise `main` (or `master`). Branch from the fresh
remote base, not from whatever is checked out, and pass `--no-track` so the new
branch doesn't treat `origin/<base>` as its upstream.

- **Clean tree:** `git switch --no-track -c chore/secret-scan "origin/<base>"`
- **Dirty tree** (Josh's work in progress, which is common): don't stash or
  touch it. Use a throwaway worktree instead, and keep its path **short**,
  because Windows git fails with "Filename too long" under the deep scratchpad
  path:

  ```bash
  git worktree add --no-track -b chore/secret-scan "$LOCALAPPDATA/Temp/<repo>-ss" "origin/<base>"
  ```

  Do steps 2–5 inside it, and `git worktree remove` it once the PR is merged.

Also check `git rev-list --count origin/<base>..<base>`. Local commits that
were never pushed won't be in the PR. Tell Josh they need their own branch and
PR. The local scan includes them (it walks every local ref), which is why its
commit count can be higher than CI's.

If `gitleaks` isn't on PATH in this shell (a winget install only reaches *new*
shells), it's at
`$LOCALAPPDATA/Microsoft/WinGet/Packages/Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe/gitleaks.exe`.

If `chore/secret-scan` already exists, it's an earlier run. Look at it before
reusing or replacing it.

## 2. Scan the history before adding CI

A repo that already has a secret in its history goes red on its first CI run.
Find out now:

```bash
gitleaks git --redact --no-banner --verbose .
```

If gitleaks isn't installed at all, say so, and say that CI's first run will be
the first scan. Don't install it unasked.

For each finding, show Josh the rule, file, commit and fingerprint. The output
is redacted, so never print the secret itself. Then:

- **A real secret, still live:** it's in the history (and on GitHub, if that
  commit was ever pushed), so deleting it in a new commit doesn't help. Josh must **rotate it** (revoke it at
  the provider). Rewriting history is optional, Josh's call, and comes after
  rotation, never instead of it.
- **Rotated, or a false positive:** after Josh confirms which it is, add its
  `Fingerprint` line to `.gitleaksignore` at the repo root, with a `#` comment
  above it saying why.

Never add a fingerprint to `.gitleaksignore` on your own judgement. Accepting a
finding is Josh's decision.

## 3. Add the workflow

```bash
mkdir -p .github/workflows
cp ~/.claude/templates/secret-scan/.github/workflows/secret-scan.yml .github/workflows/
```

If the repo already has a `secret-scan.yml` that differs from the template, show
the diff and ask before overwriting. It may have been tuned on purpose.

Commit with Conventional Commits:

```bash
git add .github/workflows/secret-scan.yml .gitleaksignore 2>/dev/null
git commit -m "ci: add gitleaks secret scanning"
```

(If the repo had the older inline workflow, the commit is `ci: call the shared secret-scan workflow from bearnz/ci-templates`.)

## 4. Push and raise the PR

Show Josh exactly what the push publishes (`git diff origin/<base>...HEAD`, with
any key values masked), then ask. Approving a push isn't a code review: the
review happens on the PR. After a yes (the push guard prompts as well):

```bash
git push -u origin chore/secret-scan
```

Then use `/pr` to raise the PR against the base.

## 5. Report the CI result

```bash
gh run list --workflow secret-scan.yml --branch chore/secret-scan --limit 1
gh run watch <run-id> --exit-status
```

Report the real outcome. If the run failed, read `gh run view <run-id> --log-failed`
and say which findings caused it. The PR is ready to merge only once the run is
green, and merging is still Josh's call.
