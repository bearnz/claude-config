# claude-config

Josh's Claude Code workflow config: global CLAUDE.md, push guard, git hooks,
skills.

This repo is `~/.claude` itself (`C:\Users\Josh\.claude`). Claude Code reads
the files from here, so the checkout is the live config.

## What's tracked

| Path | What it is |
|---|---|
| `CLAUDE.md` | Global conventions, loaded into every session |
| `settings.json` | User settings, including the PreToolUse hook that runs the push guard |
| `hooks/` | `git_push_guard.py` (the PreToolUse push guard) and its tests |
| `git-hooks/` | Global git hooks (`core.hooksPath`): `_dispatch.sh`, one stub per hook, `test_pre_push.sh` |
| `skills/` | Josh's own skills: commit-message, new-project, pr, resolve-merge-conflicts, secret-scan |
| `templates/` | The secret-scan workflow that `/secret-scan` copies into repos, and the `/new-project` language overlays (`python/`, `godot/`) applied on top of `bearnz/project-template` |
| `setup.ps1` | Sets up a Windows PC for this config, or checks one with `-CheckOnly` (see below) |

`.gitignore` is an allowlist. Everything else in `~/.claude` (credentials,
`projects/` transcripts, caches, plugin installs, `skills/synced/`) is
ignored, but it's still in the folder. **Never run `git clean -x` or `-X`, or
`git add -f`, here.**

## Setting up on a machine

For Windows. `settings.json` points the push guard at
`C:/Users/Josh/.claude/hooks/git_push_guard.py`, an absolute path, so a PC
with a different user name needs that path changed (through a PR).
`setup.ps1` flags it.

### 1. Git, GitHub CLI and a GitHub sign-in

```powershell
winget install --id Git.Git -e
winget install --id GitHub.cli -e
gh auth login
```

Open a new terminal afterwards so both are on PATH.

### 2. Put this repo at `~/.claude`

If `~/.claude` doesn't exist yet (Claude Code hasn't been run on this PC):

```powershell
gh repo clone bearnz/claude-config "$HOME\.claude"
```

If Claude Code already made the folder, turn it into the checkout in place.
Tracked files (`settings.json` included) come from the repo, and everything
the allowlist ignores, such as `.credentials.json` and `projects/`, is left
alone:

```powershell
git -C "$HOME\.claude" init -b main
git -C "$HOME\.claude" remote add origin https://github.com/bearnz/claude-config.git
git -C "$HOME\.claude" fetch origin
git -C "$HOME\.claude" checkout -f -B main --track origin/main
```

### 3. Run the setup script

```powershell
powershell -ExecutionPolicy Bypass -File "$HOME\.claude\setup.ps1"
```

It installs whatever is missing of git, gh, Python 3.10, uv and gitleaks
(winget), points `core.hooksPath` at `~/.claude/git-hooks`, checks git's
user name and email, checks the paths in `settings.json` and that gh is signed
in, and runs both test suites. It's safe to re-run, and `-CheckOnly` reports
without changing anything. It ends with a list of anything left, and exits 1
if there is any.

### 4. By hand

None of these are in the repo:

- **Claude sign-in.** Sign in to the Claude desktop app and Claude Code.
- **Plugins.** `settings.json` lists the enabled plugins and their
  marketplaces. Check that commit-commands, skill-creator and ponytail show up
  as installed.
- **MCP servers** live in `~/.claude.json`, which also holds login state, so
  it isn't tracked. Re-add them on the new PC: `nvidia-app`
  (`http://127.0.0.1:13508/mcp`, served by the NVIDIA App) and `godot-ai`
  (the godot-ai package, run through `uvx`).
- **Memory.** `projects/*/memory` is per PC and keyed by each project's folder
  path. Copy `projects/` across if the folders keep the same paths.
- **Other secrets.** For example the Home Assistant token in
  `~/.config/home-assistant/token`. Make new ones rather than copying them.
- **Projects.** Clone the repos you need into `A:\.dev`.

## Testing

```bash
python ~/.claude/hooks/test_git_push_guard.py
sh ~/.claude/git-hooks/test_pre_push.sh
```

`setup.ps1 -CheckOnly` runs both of these as well, after checking the rest of
the PC's setup.

CI runs only the secret scan (`.github/workflows/secret-scan.yml`, which calls
`bearnz/ci-templates`). The test suites are run by hand.
