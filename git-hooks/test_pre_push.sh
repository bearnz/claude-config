#!/bin/sh
# Exercises the global pre-push hook against a throwaway LOCAL bare repo in
# Temp: nothing goes to GitHub. Run: sh ~/.claude/git-hooks/test_pre_push.sh
set -u
T="${TMPDIR:-/tmp}/prepush-test.$$"
mkdir -p "$T" && cd "$T" || exit 1
git init -q --bare remote.git
git init -q -b main work && cd work
git remote add origin ../remote.git
git commit -q --allow-empty -m init
# a repo-local pre-push (like git-lfs) that must still run and still get stdin
printf '#!/bin/sh\ncat > .git/local-prepush-stdin\n' > .git/hooks/pre-push && chmod +x .git/hooks/pre-push

pass=0; fail=0
check() { # name, expected exit (0/1), command...
	n=$1; want=$2; shift 2
	"$@" >/dev/null 2>&1; got=$?; [ "$got" -ne 0 ] && got=1
	if [ "$got" = "$want" ]; then pass=$((pass+1)); echo "ok   $n"; else fail=$((fail+1)); echo "FAIL $n (exit $got, want $want)"; fi
}
check "push main refused"                   1 git push origin main
check "push HEAD:main refused"              1 git push origin HEAD:refs/heads/main
check "push feature allowed"                0 git push origin HEAD:refs/heads/feature/x
[ -s .git/local-prepush-stdin ] && { pass=$((pass+1)); echo "ok   repo-local pre-push ran with stdin"; } || { fail=$((fail+1)); echo "FAIL repo-local pre-push stdin"; }
check "tag push allowed"                    0 sh -c 'git tag v1 && git push origin refs/tags/v1'
check "ALLOW_MAIN_PUSH=1 lets main through" 0 env ALLOW_MAIN_PUSH=1 git push origin main
check "delete main refused"                 1 git push origin :refs/heads/main

cd / && rm -rf "$T"
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
