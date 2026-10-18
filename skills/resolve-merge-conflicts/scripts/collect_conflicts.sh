#!/bin/sh
# Collect everything needed to resolve a merge conflict, in one pass.
#
# Usage: sh collect_conflicts.sh [max_lines_per_diff]
#
# Per-file diffs are truncated at max_lines_per_diff (default 300) so one large
# file cannot bury the rest. Truncation is announced, so a file worth reading in
# full can be opened directly.
set -u

MAX=${1:-300}

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	echo "not a git repository (or no git on PATH)"
	exit 1
fi

if ! git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1; then
	echo "=== NOT IN A MERGE ==="
	echo "MERGE_HEAD does not exist, so no merge is in progress."
	for h in REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
		if git rev-parse -q --verify "$h" >/dev/null 2>&1; then
			echo "But $h exists - a different operation is in progress, and its"
			echo "ours/theirs are reversed relative to a merge. Say so rather"
			echo "than resolving it as if it were one."
		fi
	done
	echo
	echo "Unmerged paths, if any:"
	git ls-files -u | cut -f2 | sort -u
	echo
	echo "Status:"
	git status --short --branch
	exit 0
fi

OURS_REF=$(git rev-parse --abbrev-ref HEAD)
OURS=$(git rev-parse --short HEAD)
THEIRS=$(git rev-parse --short MERGE_HEAD)
BASE=$(git merge-base HEAD MERGE_HEAD 2>/dev/null) || BASE=""
if [ -n "$BASE" ]; then
	BASE_SHORT=$(git rev-parse --short "$BASE")
else
	BASE_SHORT="none"
fi
STYLE=$(git config merge.conflictStyle) || STYLE="merge (base is NOT shown in the markers)"

echo "=== THE MERGE ==="
echo "ours   (HEAD)       = $OURS_REF @ $OURS"
echo "theirs (MERGE_HEAD) = $THEIRS  $(git log -1 --format='%s' MERGE_HEAD)"
echo "base   (merge-base) = $BASE_SHORT"
echo "conflict style      = $STYLE"
echo
echo "--- git's own merge message (names what is being merged) ---"
cat "$(git rev-parse --git-path MERGE_MSG)" 2>/dev/null || echo "(none)"

if [ -z "$BASE" ]; then
	echo
	echo "!!! No merge base - these histories are unrelated. Nearly every file"
	echo "!!! will conflict and none of the intent-reading below can work."
	echo "!!! Stop and ask whether this merge was meant to happen at all."
	git status --porcelain=v1 | grep -E '^(DD|AU|UD|UA|DU|AA|UU) '
	exit 0
fi

echo
echo "=== WHAT EACH SIDE DID SINCE THE BASE ==="
echo "--- ours: $BASE_SHORT..HEAD ---"
git log --oneline "$BASE..HEAD" | head -n 40
echo "--- theirs: $BASE_SHORT..MERGE_HEAD ---"
git log --oneline "$BASE..MERGE_HEAD" | head -n 40

echo
echo "=== CONFLICTED PATHS ==="
echo "(DD both deleted, AU added by us, UD deleted by them, UA added by them,"
echo " DU deleted by us, AA both added, UU both modified)"
git status --porcelain=v1 | grep -E '^(DD|AU|UD|UA|DU|AA|UU) ' ||
	echo "(none - everything is staged; what remains is to verify and commit)"

CONFLICTED=$(git ls-files -u | cut -f2 | sort -u)
if [ -z "$CONFLICTED" ]; then
	exit 0
fi

trunc() {
	body=$(cat)
	if [ -z "$body" ]; then
		echo "(no change on this side)"
		return
	fi
	count=$(printf '%s\n' "$body" | wc -l | tr -d ' ')
	if [ "$count" -gt "$MAX" ]; then
		printf '%s\n' "$body" | head -n "$MAX"
		echo "... [truncated at $MAX of $count lines - open the file directly]"
	else
		printf '%s\n' "$body"
	fi
}

echo
echo "=== PER FILE: WHAT EACH SIDE CHANGED, AND WHERE THEY CLASH ==="
printf '%s\n' "$CONFLICTED" | while IFS= read -r f; do
	[ -n "$f" ] || continue
	echo
	echo "################ $f ################"
	echo "stages present (1=base 2=ours 3=theirs):"
	git ls-files -u -- "$f" | awk '{print "  stage " $3 "  " $1 " " $2}'

	echo
	echo "---- OUR change ($BASE_SHORT..HEAD) ----"
	git diff "$BASE" HEAD -- "$f" | trunc
	echo
	echo "---- THEIR change ($BASE_SHORT..MERGE_HEAD) ----"
	git diff "$BASE" MERGE_HEAD -- "$f" | trunc

	if [ -f "$f" ]; then
		markers=$(grep -c '^<<<<<<< ' "$f" 2>/dev/null) || markers=0
		echo
		echo "---- CONFLICT REGIONS in the working tree ($markers) ----"
		if [ "$markers" -eq 0 ]; then
			echo "(no markers - this is a stage-level conflict such as"
			echo " delete/modify or add/add, not a text clash. The file left in"
			echo " the tree is one whole side; decide between the sides above.)"
		else
			awk '
				/^<<<<<<< / { inblock = 1 }
				inblock     { printf "%6d| %s\n", NR, $0 }
				/^>>>>>>> / { inblock = 0; print "" }
			' "$f" 2>/dev/null | trunc
		fi
	else
		echo
		echo "---- no file in the working tree (delete/modify, or both deleted) ----"
	fi
done

echo
echo "=== MERGED WITHOUT COMPLAINT BUT TOUCHED BY BOTH SIDES ==="
echo "(git resolved these itself, on text alone. This is where a clean merge"
echo " still fails to build - check them once the markers are gone.)"
BOTH=$(
	{
		git diff --name-only "$BASE" HEAD
		git diff --name-only "$BASE" MERGE_HEAD
	} | sort | uniq -d
)
QUIET=$(
	printf '%s\n' "$BOTH" | while IFS= read -r f; do
		[ -n "$f" ] || continue
		printf '%s\n' "$CONFLICTED" | grep -qxF -- "$f" || echo "  $f"
	done
)
if [ -n "$QUIET" ]; then
	printf '%s\n' "$QUIET"
else
	echo "(none)"
fi
