#!/bin/sh
# Machine-wide git hooks, enabled with `git config --global core.hooksPath`.
#
# Setting core.hooksPath makes git ignore each repo's own .git/hooks, which
# would silently disable hooks that tools like git-lfs install there. So every
# hook here runs the repo's own hook of the same name afterwards, if there is one.
#
# pre-commit also runs gitleaks on the staged changes, honouring the repo's
# .gitleaksignore / .gitleaks.toml. Skip once with SKIP_GITLEAKS=1 (or
# --no-verify, which also skips the repo's own pre-commit). CI scans again.
#
# pre-push refuses any push that would update or delete main/master on the
# remote, so main only ever changes through a merged PR. GitHub can't enforce
# that on free private repos, so this machine does. For a deliberate exception
# (e.g. the empty first commit of a local-first repo), Josh runs
# ALLOW_MAIN_PUSH=1 git push ... from a terminal. That still runs the repo's own
# pre-push (git-lfs uploads objects there), which --no-verify would skip.
name=$1
shift

if [ "$name" = pre-push ]; then
	input=$(cat)
	if [ -z "${ALLOW_MAIN_PUSH:-}" ]; then
		printf '%s\n' "$input" | while read -r lref lsha rref rsha; do
			case "$rref" in
			refs/heads/main | refs/heads/master)
				echo "pre-push: refusing to update ${rref#refs/heads/} on $1 - main changes only through a merged PR." >&2
				echo "  Push a feature branch and open a PR. Deliberate exception: ALLOW_MAIN_PUSH=1 git push ..." >&2
				exit 1
				;;
			esac
		done || exit 1
	fi
	local_hook="$(git rev-parse --git-common-dir 2>/dev/null)/hooks/$name"
	if [ -f "$local_hook" ] && [ -x "$local_hook" ]; then
		printf '%s\n' "$input" | "$local_hook" "$@"
		exit $?
	fi
	exit 0
fi

if [ "$name" = pre-commit ] && [ -z "${SKIP_GITLEAKS:-}" ]; then
	gl=$(command -v gitleaks 2>/dev/null)
	if [ -z "$gl" ] && [ -n "${LOCALAPPDATA:-}" ]; then
		gl="$(cygpath -u "$LOCALAPPDATA" 2>/dev/null || echo "$LOCALAPPDATA")/Microsoft/WinGet/Packages/Gitleaks.Gitleaks_Microsoft.Winget.Source_8wekyb3d8bbwe/gitleaks.exe"
	fi
	if [ -n "$gl" ] && [ -f "$gl" ]; then
		if ! "$gl" git --pre-commit --staged --redact --no-banner --verbose --log-level warn .; then
			echo >&2
			echo "gitleaks: staged changes contain a likely secret - commit blocked." >&2
			echo "  Remove it, or if it is a false positive add its Fingerprint to .gitleaksignore." >&2
			echo "  To skip this check once: SKIP_GITLEAKS=1 git commit ..." >&2
			exit 1
		fi
	else
		echo "warning: gitleaks not found - secret scan skipped for this commit (CI will still scan)." >&2
	fi
fi

local_hook="$(git rev-parse --git-common-dir 2>/dev/null)/hooks/$name"
if [ -f "$local_hook" ] && [ -x "$local_hook" ]; then
	exec "$local_hook" "$@"
fi
exit 0
