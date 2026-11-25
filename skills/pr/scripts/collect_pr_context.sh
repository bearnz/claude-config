#!/bin/sh
# Collect everything needed to write a pull request description, in one pass.
#
# Usage: sh collect_pr_context.sh [--base <branch>] [max_lines_per_file]
#
# Works out the target branch (feature -> main by default; in repos with a
# develop branch, develop -> main and anything else -> develop), then dumps the commits, the diff against the merge
# base, and a set of signals worth a reviewer's attention.
#
# --base <branch> overrides the target, for a PR stacked on another PR's
# branch: the commits and diff are then scoped to what this branch adds on top
# of its parent, and the STACK section reports the parent's PR.
set -u

MAX_LINES=300
BASE_OVERRIDE=""
while [ $# -gt 0 ]; do
	case "$1" in
	--base)
		if [ $# -lt 2 ] || [ -z "$2" ]; then
			echo "--base needs a branch name"
			exit 1
		fi
		BASE_OVERRIDE=$2
		shift 2
		;;
	--base=*)
		BASE_OVERRIDE=${1#--base=}
		shift
		;;
	*)
		MAX_LINES=$1
		shift
		;;
	esac
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
	echo "not a git repository (or no git on PATH)"
	exit 1
fi

echo "=== FETCH ==="
if git fetch --quiet origin 2>/dev/null; then
	echo "fetched origin - remote refs are current"
else
	echo "WARNING: could not fetch origin (offline, or no remote)."
	echo "Remote refs below may be stale; the commit list could be wrong."
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Resolve the trunk - the branch develop merges into. Prefer a real main or
# master over origin/HEAD: that symref is frequently absent, and when it is
# present it records whatever branch happened to be checked out at clone time,
# which is not the same question. origin/HEAD is the last resort, not the first.
TRUNK=""
TRUNK_GUESSED=0
for candidate in main master; do
	if git rev-parse --verify --quiet "refs/remotes/origin/$candidate" >/dev/null; then
		TRUNK=$candidate
		break
	fi
done
if [ -z "$TRUNK" ]; then
	TRUNK=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's#^refs/remotes/origin/##')
	TRUNK_GUESSED=1
	[ -n "$TRUNK" ] && echo "NOTE: no origin/main or origin/master; guessing trunk from origin/HEAD -> $TRUNK"
fi
[ -n "$TRUNK" ] || TRUNK=main

echo
echo "=== BRANCH AND TARGET ==="
echo "current branch:  $BRANCH"
echo "trunk:           $TRUNK"

if [ "$BRANCH" = "HEAD" ]; then
	echo "target:          NONE - detached HEAD, check out a branch first"
	exit 1
fi

if [ "$BRANCH" = "$TRUNK" ]; then
	if [ "$TRUNK_GUESSED" = "1" ]; then
		echo "target:          NONE - this remote has no main, master or develop branch,"
		echo "                 so there is no trunk to target. Not a branching problem on"
		echo "                 your side: check the remote is the one you expect."
	else
		echo "target:          NONE - already on the trunk ($TRUNK); branch first, then raise the PR"
	fi
	exit 1
fi

if [ -n "$BASE_OVERRIDE" ]; then
	if [ "$BASE_OVERRIDE" = "$BRANCH" ]; then
		echo "target:          NONE - --base names the current branch"
		exit 1
	fi
	BASE=$BASE_OVERRIDE
	echo "rule:            explicit --base $BASE"
else
case "$BRANCH" in
develop)
	BASE=$TRUNK
	echo "rule:            on develop -> target $TRUNK"
	;;
*)
	# Default convention is feature -> trunk. Repos that opted into a develop
	# branch (it exists on origin) keep feature -> develop.
	if git rev-parse --verify --quiet "refs/remotes/origin/develop" >/dev/null; then
		BASE=develop
		echo "rule:            feature branch, repo uses develop -> target develop"
	else
		BASE=$TRUNK
		echo "rule:            feature branch -> target $TRUNK"
	fi
	;;
esac
fi

if ! git rev-parse --verify --quiet "refs/remotes/origin/$BASE" >/dev/null; then
	echo "target:          NONE - origin/$BASE does not exist"
	exit 1
fi

BASE_REF="origin/$BASE"
echo "target:          $BASE  (via $BASE_REF)"

MERGE_BASE=$(git merge-base "$BASE_REF" HEAD 2>/dev/null)
if [ -z "$MERGE_BASE" ]; then
	echo "ERROR: no common ancestor between HEAD and $BASE_REF"
	exit 1
fi
echo "merge base:      $(git rev-parse --short "$MERGE_BASE")"

echo
echo "=== PUSH STATE ==="
UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
if [ -z "$UPSTREAM" ]; then
	echo "no upstream set - branch has never been pushed."
	echo "needs: git push -u origin $BRANCH"
else
	echo "upstream: $UPSTREAM"
	ahead=$(git rev-list --count "$UPSTREAM..HEAD" 2>/dev/null || echo 0)
	behind=$(git rev-list --count "HEAD..$UPSTREAM" 2>/dev/null || echo 0)
	echo "ahead of upstream by $ahead, behind by $behind"
	[ "$ahead" -gt 0 ] && echo "NOTE: unpushed commits - push before opening the PR or they will not be in it"
	[ "$behind" -gt 0 ] && echo "NOTE: upstream has commits you do not - someone else pushed, or you amended after pushing"
fi

behind_base=$(git rev-list --count "HEAD..$BASE_REF" 2>/dev/null || echo 0)
if [ "$behind_base" -gt 0 ]; then
	echo "NOTE: $BASE_REF has moved on by $behind_base commit(s) since the merge base."
	echo "      The PR will still be scoped correctly, but expect conflicts if they overlap."
fi

echo
echo "=== COMMITS IN THIS PR ($(git rev-list --count "$MERGE_BASE..HEAD") total, oldest first) ==="
git log --reverse --format='--- %h  (%an, %ad)%n%B' --date=short "$MERGE_BASE..HEAD"

echo
echo "=== DIFFSTAT vs MERGE BASE ==="
git diff --stat "$MERGE_BASE...HEAD"

echo
echo "=== CHURN: files touched by the most commits (instability hotspots) ==="
git log --format='' --name-only "$MERGE_BASE..HEAD" | sed '/^$/d' | sort | uniq -c | sort -rn | head -15

echo
echo "=== SIGNALS FOR REVIEWER ATTENTION ==="
echo "(mechanical hints only - they are a starting point, not the list)"

changed=$(git diff --name-only "$MERGE_BASE...HEAD")

flag() {
	label=$1
	pattern=$2
	hits=$(printf '%s\n' "$changed" | grep -iE "$pattern" || true)
	if [ -n "$hits" ]; then
		echo
		echo "* $label:"
		printf '%s\n' "$hits" | sed 's/^/    /'
	fi
}

flag "Dependency / lockfile changes (supply chain, version drift)" \
	'(package(-lock)?\.json|yarn\.lock|pnpm-lock|requirements.*\.txt|Pipfile|poetry\.lock|go\.(mod|sum)|Cargo\.(toml|lock)|Gemfile|\.csproj|gradle)'
flag "CI / workflow / build config (runs with credentials)" \
	'(\.github/workflows/|\.gitlab-ci|Jenkinsfile|azure-pipelines|Dockerfile|docker-compose|Makefile)'
flag "Project / runtime config" \
	'(\.env|config\.|settings\.|\.ini$|\.toml$|\.yaml$|\.yml$|project\.godot)'
flag "Database / migrations (hard to reverse)" \
	'(migrations?/|schema\.|\.sql$)'
deleted=$(git diff --diff-filter=D --name-only "$MERGE_BASE...HEAD")
if [ -n "$deleted" ]; then
	echo
	echo "* Files deleted outright:"
	printf '%s\n' "$deleted" | sed 's/^/    /'
fi

added_files=$(git diff --diff-filter=A --name-only "$MERGE_BASE...HEAD")
if [ -n "$added_files" ]; then
	echo
	echo "* Files added:"
	printf '%s\n' "$added_files" | sed 's/^/    /'
fi

added_lines=$(git diff "$MERGE_BASE...HEAD" -U0 | grep '^+' | grep -v '^+++' || true)

grep_added() {
	label=$1
	pattern=$2
	hits=$(printf '%s\n' "$added_lines" | grep -inE "$pattern" | head -20 || true)
	if [ -n "$hits" ]; then
		echo
		echo "* $label:"
		printf '%s\n' "$hits" | cut -c1-160 | sed 's/^/    /'
	fi
}

grep_added "New TODO / FIXME / HACK markers (deferred work entering the branch)" \
	'(TODO|FIXME|HACK|XXX|WIP)[: ]'
grep_added "Possible secrets or credentials - verify before this is public" \
	'(api[_-]?key|secret|passwd|password|token|private[_-]?key|BEGIN [A-Z ]*PRIVATE KEY)[[:space:]]*[:=]'
grep_added "Debug / temporary output left in" \
	'(console\.log|print_debug|breakpoint\(|debugger;|binding\.pry)'
grep_added "Error handling that swallows (a caught error going nowhere)" \
	'(except[a-z ]*:[[:space:]]*pass|catch[[:space:]]*\([^)]*\)[[:space:]]*\{[[:space:]]*\}|rescue[[:space:]]+nil)'

echo
echo "=== PR TEMPLATE (if the repo has one, follow it over the default layout) ==="
for t in .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md \
	.github/PULL_REQUEST_TEMPLATE/*.md docs/pull_request_template.md \
	PULL_REQUEST_TEMPLATE.md; do
	if [ -f "$t" ]; then
		echo "--- $t ---"
		cat "$t"
	fi
done

echo
echo "=== TOOLING ==="
# Resolve gh even when it is installed but not yet on this shell's PATH. On
# Windows a fresh install updates the machine PATH, which existing shells do
# not inherit until they are restarted - so "command -v gh" says missing while
# the binary sits right there. Checking the standard locations avoids sending
# someone down the compare-URL path for a tool they already have.
GH=""
if command -v gh >/dev/null 2>&1; then
	GH=gh
else
	for p in "/c/Program Files/GitHub CLI/gh.exe" \
		"/c/Program Files (x86)/GitHub CLI/gh.exe" \
		"${LOCALAPPDATA:-}/GitHubCLI/gh.exe"; do
		if [ -x "$p" ]; then
			GH=$p
			echo "gh: found at $p but NOT on this shell's PATH"
			echo "    (installed after this shell started - restart to pick it up)"
			break
		fi
	done
fi

if [ -n "$GH" ]; then
	echo "gh: $("$GH" --version 2>&1 | head -1)"
	GH_OK=""
	if "$GH" auth status >/dev/null 2>&1; then
		echo "gh auth: ok"
		GH_OK=1
		# Whether a PR is already open for this branch decides create-vs-update,
		# so report it as a fact rather than as a table to be eyeballed. --jq is
		# gh's own embedded engine; it does not need jq installed.
		EXISTING=$("$GH" pr list --head "$BRANCH" --state open \
			--json number,isDraft,url,title \
			--jq '.[] | "PR #\(.number)  draft=\(.isDraft)  \(.url)\n      title: \(.title)"' 2>/dev/null)
		if [ -n "$EXISTING" ]; then
			echo "existing PR: OPEN - update it, do not open a second one"
			printf '%s\n' "$EXISTING" | sed 's/^/    /'
		else
			echo "existing PR: none open for $BRANCH - this will be a new one"
		fi
	else
		echo "gh auth: NOT authenticated."
		echo "    'gh auth login' is interactive (browser / device code), so the user must"
		echo "    run it themselves - do not attempt it. Use the compare URL below instead,"
		echo "    or ask them to authenticate first."
	fi
else
	echo "gh: NOT INSTALLED - use the compare URL fallback (see SKILL.md step 5)"
fi

# Stacking. With --base on a non-trunk branch, report the parent's PR: it has
# to merge first, with a merge commit, or this PR lands in the parent's branch
# instead of the trunk. Without --base, look for the opposite mistake: an open
# PR's branch already inside this one, whose commits would then be described
# here as if they were this branch's own work.
echo
echo "=== STACK ==="
if [ -z "${GH_OK:-}" ]; then
	echo "unknown - needs an authenticated gh"
elif [ -n "$BASE_OVERRIDE" ] && [ "$BASE" != "$TRUNK" ] && [ "$BASE" != "develop" ]; then
	PARENT=$("$GH" pr list --head "$BASE" --state open --json number,url \
		--jq '.[] | "#\(.number)  \(.url)"' 2>/dev/null)
	if [ -n "$PARENT" ]; then
		echo "stacked on:      $PARENT  ($BASE)"
		echo "merge order:     that PR first, with 'Create a merge commit'. Merging this one"
		echo "                 first lands it in $BASE, not in $TRUNK."
	else
		echo "WARNING: no open PR has $BASE as its head. A PR based on it would merge"
		echo "         into a branch that is not on its way to $TRUNK."
	fi
else
	FOUND=""
	for line in $("$GH" pr list --state open --json number,headRefName \
		--jq '.[] | "\(.number):\(.headRefName)"' 2>/dev/null); do
		n=${line%%:*}
		head=${line#*:}
		[ "$head" = "$BRANCH" ] && continue
		git rev-parse --verify --quiet "refs/remotes/origin/$head" >/dev/null || continue
		if git merge-base --is-ancestor "origin/$head" HEAD &&
			! git merge-base --is-ancestor "origin/$head" "$BASE_REF"; then
			echo "NOTE: this branch contains open PR #$n ($head), which is not in $BASE yet."
			echo "      Its commits will be described here as this PR's own. To stack"
			echo "      on it instead, re-run with: --base $head"
			FOUND=1
		fi
	done
	[ -n "$FOUND" ] || echo "not stacked - no open PR's branch is inside this one"
fi

REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
SLUG=$(printf '%s' "$REMOTE_URL" | sed -e 's#^git@github\.com:##' -e 's#^https://github\.com/##' -e 's#\.git$##')
if [ -n "$SLUG" ]; then
	echo
	echo "compare URL:  https://github.com/$SLUG/compare/$BASE...$BRANCH?expand=1"
fi

# The per-file diff goes last on purpose: it is by far the largest section and
# the one most likely to be cut off by an output limit. Everything above it is
# needed to decide what to do; this is the detail you read selectively.
echo
echo "=== PER-FILE DIFF vs MERGE BASE ==="
echo "(largest section, deliberately last - read the files that matter, not all of it)"
printf '%s\n' "$changed" | while IFS= read -r f; do
	[ -n "$f" ] || continue
	echo
	echo "--- $f ---"
	n=$(git diff "$MERGE_BASE...HEAD" -- "$f" | wc -l | tr -d ' ')
	if [ "$n" -gt "$MAX_LINES" ]; then
		git diff "$MERGE_BASE...HEAD" -- "$f" | head -n "$MAX_LINES"
		echo "... [truncated at $MAX_LINES of $n lines - open $f directly if this change matters]"
	else
		git diff "$MERGE_BASE...HEAD" -- "$f"
	fi
done
