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
| `templates/` | The secret-scan workflow that `/secret-scan` copies into repos |

`.gitignore` is an allowlist. Everything else in `~/.claude` (credentials,
`projects/` transcripts, caches, plugin installs, `skills/synced/`) is
ignored, but it's still in the folder. **Never run `git clean -x` or `-X`, or
`git add -f`, here.**

## Setting up on a machine

Not written yet. On this PC the global hooks are wired up with
`git config --global core.hooksPath C:/Users/Josh/.claude/git-hooks`, and
`settings.json` points the push guard at
`C:/Users/Josh/.claude/hooks/git_push_guard.py`. Both are absolute paths.

## Testing

```bash
python ~/.claude/hooks/test_git_push_guard.py
sh ~/.claude/git-hooks/test_pre_push.sh
```

CI runs only the secret scan (`.github/workflows/secret-scan.yml`, which calls
`bearnz/ci-templates`). The test suites are run by hand.
