# Working conventions (all projects)

## Provenance labels

Josh uses these sessions for side projects and does not want to take AI output
as gospel. So for any non-trivial factual claim — how an API or library
behaves, a version number, a config key, a performance claim, "this is fixed",
"this is the cause" — mark where it came from:

- **[verified]** — I checked it this session: ran it, read the source, saw the
  output. Say what I checked ("[verified: ran `pytest`, 14 passed]").
- **[docs]** — from documentation or a page I actually read this session. Give
  the link.
- **[unverified]** — from memory, training data, or inference. A lead, not a
  fact.

Rules that make the labels worth anything:

- Never upgrade a label without doing the work. If I haven't run it, it is not
  verified, however confident I feel.
- What I read in a CLAUDE.md, memory file, code comment or commit message is
  something someone wrote down, not a checked fact. Label it by what I
  actually checked.
- "I don't know" beats a plausible gap-filler. When an [unverified] claim is
  load-bearing for a decision, say so and offer the check that would settle it.
- Don't label trivia or things directly visible in the conversation. Keep labels
  inline and short. They are there to flag risk, not to decorate the reply.

## Git and GitHub

### The rules

- **Nothing reaches `main` except through a PR that Josh reviewed and
  merged.** That applies in every repo, including a brand-new repo's first
  commit and repos created during a session. The one exception: widmark's
  (`bearnz/widmark`, formerly boozer-calc) drink list PRs (`chore/data-*`,
  opened by the app's Publish button) are
  merged by its `automerge-data` workflow once secret-scan passes. Publish
  shows Josh the edits before it pushes, and that is their review. Nothing
  else auto-merges, other `chore/` branches included, and Claude never adds an
  auto-merge to another repo or branch without Josh asking.
- **Josh is the only approver.** Josh merging a PR is the OK for code going to
  "prod" (Josh's own devices), so no other reviewers are needed. Before asking
  to merge, show the PR's final diff and its CI state. Never merge a PR whose
  checks failed.
- **Approving a push is not a code review.** Before asking to push, show Josh
  what the push will publish (the diff, or the file list and contents). The
  review itself happens on the PR.
- **Never push without an explicit yes for that push.** Never force-push,
  never `git push` to `main`/`master`, and never create or push tags or
  releases. A tag makes code live for whatever depends on it, so Josh cuts tags
  from a terminal on a reviewed commit.
- Never commit secrets. Don't bypass the hooks below (`SKIP_GITLEAKS=1`,
  `--no-verify`) without Josh's yes.

### Workflow

- GitHub account: `bearnz`. New repos are **private** unless Josh says
  otherwise.
- Work on a `feature/<short-name>` (or `fix/…`, `chore/…`) branch cut from
  `origin/main`, and land it through a PR (the `/pr` skill). Repos that already
  use `develop` (e.g. devil-horn-panic) branch from and PR into `develop`, and
  `develop` reaches `main` through a PR.
- Commit freely on branches, with Conventional Commits messages (the
  `commit-message` skill).
- Josh often has uncommitted work in the main checkout. Don't stash it, reset
  it or switch branches under it. Use a throwaway worktree on a short path
  instead (see the `/secret-scan` skill).

### Enforcement (this PC)

GitHub can't enforce any of this on free private repos (branch protection
returns 403). There's one user on one machine, so local hooks are the accepted
enforcement. Don't suggest GitHub Pro. If another developer machine ever joins,
it needs the same `~/.claude/git-hooks` setup.

- **Global git hooks**, `~/.claude/git-hooks/` via `core.hooksPath`, cover
  every repo, Josh's terminal included. Each one also runs the repo's own
  `.git/hooks`.
  - pre-commit: gitleaks on the staged changes.
  - pre-push: refuses any update or deletion of `main`/`master`. Josh's
    deliberate, terminal-only escape hatch is `ALLOW_MAIN_PUSH=1 git push …`.
  - Tests: `sh ~/.claude/git-hooks/test_pre_push.sh`.
- **Claude's push guard**, `~/.claude/hooks/git_push_guard.py` (PreToolUse).
  - Denies: pushes to main, force pushes, tags and releases,
    `gh repo create --push`, and `gh api` writes to code or refs.
  - Denies hook bypasses: setting `ALLOW_MAIN_PUSH`, and writing, unsetting
    or overriding `core.hooksPath` (`git config`, `git -c`, `GIT_CONFIG_*`
    env that names it). Reads (`git config --get core.hooksPath`, grep, git
    log) pass, and so does text a heredoc or here-string writes to a file. Any
    other mention (an echo, a sed, a heredoc into a shell profile, a heredoc
    fed to an interpreter) gets a prompt, as do setting `SKIP_GITLEAKS` and
    `--no-verify`.
  - Also denies swapping the global config out, which drops hooksPath
    without naming it: `GIT_CONFIG_GLOBAL`, `HOME`, `HOMEDRIVE`, `HOMEPATH`
    or `USERPROFILE` set or unset in front of git or for the session
    (`export`, `$env:`, `Set-Item`, `setx`), `env -i git`, and a
    command-line config include (`git -c include.path=`,
    `GIT_CONFIG_KEY_n=include.path`). The same prefix on another command
    gets a prompt. Reads (`echo $HOME`, `printenv`) pass, and so do
    `GIT_CONFIG_NOSYSTEM`, `GIT_CONFIG_SYSTEM` and `XDG_CONFIG_HOME`, which
    don't skip the hooks because `~/.gitconfig` outranks them.
  - Asks before every other push, merge or GitHub write.
  - Tests: `python ~/.claude/hooks/test_git_push_guard.py`. It builds throwaway
    repos in Temp, so it doesn't depend on which branch a real checkout is on.
- **CI**: every repo carries a short `.github/workflows/secret-scan.yml` that
  calls the shared gitleaks job in `bearnz/ci-templates` at `@v1`. Add it with
  `/secret-scan`. gitleaks gets bumped only in ci-templates, and Josh moves the
  `v1` tag.
- The rules hold even where none of these can see the action, for example
  edits in GitHub's web UI.

## This config is a repo

`~/.claude` is the checkout of `bearnz/claude-config` (private), and the rules
above apply to it: changes to CLAUDE.md, hooks/, git-hooks/, skills/ and
settings.json go through a branch and a PR. The checkout is the live config,
so whatever it has checked out is what runs. Keep it on `main`, apart from the
branch of an open PR, and after a merge switch back to `main` and pull.

`.gitignore` is an allowlist: to track a new path, add a `!` line to it.
Credentials, transcripts and caches sit in the same folder as ignored files,
so never run `git clean -x`/`-X` or `git add -f` here.

Writing a skill: never put a shell positional variable (`$0`, `$1` and the
rest) in a `SKILL.md`, not even inside a fenced code block. The loader
substitutes them from the invoking command's arguments, so a snippet using one
reaches the session with the argument text where the variable should be — the
file reviews clean and the command is only invalid at the moment someone runs
it. Named variables like `$branch` come through untouched. Reach for git
plumbing instead of parsing output with awk fields: step 4 of
`skills/clean-gone/SKILL.md` uses `%(worktreepath)` for exactly this reason.

## New projects

New side projects live in `$DEV_ROOT\<kebab-case-name>`. `DEV_ROOT` is a user
environment variable naming the dev root on each PC (`D:\.dev` on the laptop,
`A:\.dev` on the desktop), set by `bearnz/workstation`'s `bootstrap.ps1`.
Never hardcode a drive in config or skills. Use the `/new-project`
skill: GitHub creates `main` from `bearnz/project-template` (the
language-neutral base), and the language overlay from `~/.claude/templates/`
(python by default, godot) arrives as a PR. Template changes reach existing
repos through a copy-files PR, as the skill describes.

## Machine

Windows (10 on the desktop, 11 on the laptop). Git Bash and PowerShell are
both available. Python 3 (`python`, `py`; setup installs the newest stable
3.x, so check `python --version` rather than assume one), `uv`, `gh` and
gitleaks 8.30.1 (winget) are installed. Node is not.
