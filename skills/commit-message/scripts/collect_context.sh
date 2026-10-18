#!/bin/sh
# Collect everything needed to write a commit message, in one pass.
#
# Usage: sh collect_context.sh [max_lines_per_file]
#
# Per-file diffs are truncated at max_lines_per_file (default 400) so that one
# large file cannot bury the rest of the change. Truncation is announced, so a
# file worth reading in full can be opened directly.
set -u

MAX_LINES=${1:-400}

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	echo "not a git repository (or no git on PATH)"
	exit 1
fi

echo "=== BRANCH ==="
git rev-parse --abbrev-ref HEAD
git log -1 --format='HEAD %h %s' 2>/dev/null || echo "no commits yet"

echo
echo "=== RECENT SUBJECTS (the convention already in use) ==="
git log -20 --format='%s' 2>/dev/null

echo
echo "=== LAST FULL MESSAGE (body style, trailers) ==="
git log -1 --format='%B' 2>/dev/null

echo
echo "=== STATUS ==="
git status --porcelain=v1

echo
echo "=== STAGED DIFFSTAT ==="
git diff --cached --stat

echo
echo "=== UNSTAGED DIFFSTAT ==="
git diff --stat

echo
echo "=== UNTRACKED FILES (these do not appear in any diff below) ==="
git ls-files --others --exclude-standard

dump() {
	label=$1
	shift
	files=$(git diff --name-only "$@")
	if [ -z "$files" ]; then
		return
	fi
	echo
	echo "=== $label ==="
	printf '%s\n' "$files" | while IFS= read -r f; do
		[ -n "$f" ] || continue
		echo
		echo "--- $f ---"
		n=$(git diff "$@" -- "$f" | wc -l | tr -d ' ')
		if [ "$n" -gt "$MAX_LINES" ]; then
			git diff "$@" -- "$f" | head -n "$MAX_LINES"
			echo "... [truncated at $MAX_LINES of $n lines - open $f directly if this change matters]"
		else
			git diff "$@" -- "$f"
		fi
	done
}

dump "STAGED DIFF" --cached
dump "UNSTAGED DIFF"
