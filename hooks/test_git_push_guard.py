"""Regression cases for git_push_guard.py. Run: python ~/.claude/hooks/test_git_push_guard.py

Builds throwaway repos in Temp (on main, on develop, and on main with a v1 tag)
so the results don't depend on which branch Josh's real checkouts are on.
Nothing is pushed anywhere: the guard only reads the command text.
"""
import json, os, shutil, stat, subprocess, sys, tempfile

GUARD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "git_push_guard.py")
ROOT = tempfile.mkdtemp(prefix="push-guard-test-")


def repo(name, branch, tag=None):
    path = os.path.join(ROOT, name)
    git = lambda *a: subprocess.run(["git", "-C", path, *a], check=True, capture_output=True)
    os.makedirs(path)
    git("init", "-q", "-b", branch)
    git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--no-verify", "--allow-empty", "-m", "init")
    if tag:
        git("tag", tag)
    return path.replace("\\", "/")


MP = repo("on-main", "main")          # a checkout sitting on main
DH = repo("on-develop", "develop")    # a develop-flow repo on develop
CT = repo("tagged", "main", tag="v1")  # has a local v1 tag
WIN_MP = MP.replace("/", "\\")

# (cwd, command, expected)
CASES = [
    (MP, "ls -la", "pass"),
    (MP, "git status", "pass"),
    (MP, "git commit -m 'push the button'", "pass"),
    (MP, "git push", "deny"),
    (DH, "git push", "ask"),
    (MP, "git push origin feature/x", "ask"),
    (MP, "git push -u origin feature/x", "ask"),
    (MP, "git push origin feature/x:main", "deny"),
    (MP, "git push --force origin feature/x", "deny"),
    (MP, "git push -uf origin feature/x", "deny"),
    (MP, "git push --force-with-lease", "deny"),
    (MP, "git push origin +feature/x", "deny"),
    (MP, "git push --all", "deny"),
    (MP, "git push origin --delete main", "deny"),
    (DH, "git push origin HEAD", "ask"),
    (ROOT, f"cd {MP} && git push", "deny"),
    (ROOT, f'git -C "{WIN_MP}" push', "deny"),
    (MP, "GIT_TRACE=1 git push origin main", "deny"),
    (MP, "& git.exe push origin main", "deny"),
    (MP, "gh pr merge 3 --squash", "ask"),
    (MP, "gh repo create foo --public", "ask"),
    (MP, "gh repo edit --visibility public", "ask"),
    (MP, "gh pr list", "pass"),
    # bootstrap pushes, tags, releases, API writes
    (MP, "gh repo create foo --private --source . --push", "deny"),
    (MP, "gh repo create foo --private --add-readme", "pass"),
    (CT, "git push origin v1", "deny"),
    (CT, "git push origin refs/tags/v1", "deny"),
    (CT, "git push origin feature/x --follow-tags", "deny"),
    (CT, "git push --tags", "deny"),
    (CT, "gh release create v2", "deny"),
    (MP, "gh repo sync", "deny"),
    (MP, "gh api -X PUT repos/bearnz/x/contents/a.txt -f message=m -f content=Zg==", "deny"),
    (MP, "gh api repos/bearnz/x/git/refs -f ref=refs/heads/main -f sha=abc", "deny"),
    (MP, "gh api -X PUT repos/bearnz/x/pulls/2/merge", "deny"),
    (MP, "gh api -X PUT repos/bearnz/x/actions/permissions/access -f access_level=user", "ask"),
    (MP, "gh api repos/bearnz/x/actions/permissions/access", "pass"),
    (MP, "gh api repos/bearnz/x/pulls/2/merge", "pass"),
    # hook bypasses: the real thing is still denied
    (MP, "ALLOW_MAIN_PUSH=1 git push origin feature/x", "deny"),
    (MP, "export ALLOW_MAIN_PUSH=1", "deny"),
    (MP, "$env:ALLOW_MAIN_PUSH = '1'; git push origin feature/x", "deny"),
    (MP, "git -c core.hooksPath=/dev/null commit -m x", "deny"),
    (MP, "git --config-env=core.hooksPath=EMPTY commit -m x", "deny"),
    (MP, "git config --global --unset core.hooksPath", "deny"),
    (MP, "git config --global core.hooksPath /dev/null", "deny"),
    (MP, "git config set --global core.hooksPath /dev/null", "deny"),
    (MP, "git config unset --global core.hooksPath", "deny"),
    (MP, "git config --global --remove-section core", "deny"),
    (MP, "GIT_CONFIG_PARAMETERS=\"'core.hooksPath'='/dev/null'\" git commit -m x", "deny"),
    (MP, "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=x git commit -m x", "deny"),
    (MP, "bash <<'EOF'\nALLOW_MAIN_PUSH=1 git push origin main\nEOF", "deny"),
    (MP, "cat <<'EOF' | sh\nALLOW_MAIN_PUSH=1 git push origin feature/x\nEOF", "deny"),
    (MP, "echo 'ALLOW_MAIN_PUSH=1 git push origin feature/x' | sh", "deny"),
    (MP, "SKIP_GITLEAKS=1 git commit -m x", "ask"),
    (MP, "$env:SKIP_GITLEAKS='1'; git commit -m x", "ask"),
    (MP, "git commit --no-verify -m x", "ask"),
    (MP, "git commit -n -m x", "ask"),
    (MP, "git push --no-verify origin feature/x", "ask"),
    (MP, "git log -n 5", "pass"),
    (MP, "head -n 5 README.md", "pass"),
    # hook bypasses: reads and docs are no longer refused
    (MP, "git config --global core.hooksPath", "pass"),
    (MP, "git config --get core.hooksPath", "pass"),
    (MP, "git config --show-origin --get core.hooksPath", "pass"),
    (MP, "git config get --global core.hooksPath", "pass"),
    (MP, "git config --global --list", "pass"),
    (MP, "git config --global user.name", "pass"),
    (MP, "grep -rn 'ALLOW_MAIN_PUSH=1' ~/.claude", "pass"),
    (MP, "Select-String -Path CLAUDE.md -Pattern hooksPath", "pass"),
    (MP, "git log --oneline --grep hooksPath", "pass"),
    (MP, "grep -n SKIP_GITLEAKS ~/.claude/git-hooks/_dispatch.sh", "pass"),
    (MP, "cat > README.md <<'EOF'\nJosh runs ALLOW_MAIN_PUSH=1 git push from a terminal.\n"
         "Set core.hooksPath=~/.claude/git-hooks once. SKIP_GITLEAKS=1 skips the scan.\nEOF", "pass"),
    (MP, "cat <<EOF > notes.md\ngit push origin main\nEOF", "pass"),
    (MP, "git commit -F - <<'EOF'\ndocs: explain ALLOW_MAIN_PUSH and core.hooksPath\nEOF", "pass"),
    (MP, "Set-Content -Path README.md -Encoding utf8 -Value @'\nALLOW_MAIN_PUSH=1 git push origin main\n'@", "pass"),
    # hook bypasses: mentions the guard can't place get a prompt
    (MP, "echo 'Josh runs ALLOW_MAIN_PUSH=1 git push from a terminal'", "ask"),
    (MP, "sed -n '/hooksPath/p' ~/.gitconfig", "ask"),
    (MP, "python - <<'EOF'\nprint('ALLOW_MAIN_PUSH')\nEOF", "ask"),
    (MP, "cat >> ~/.bashrc <<'EOF'\nexport ALLOW_MAIN_PUSH=1\nEOF", "ask"),
    (MP, "cat > x.sh <<'EOF'\ngit push\n", "deny"),  # unterminated heredoc: lines vetted as commands
    # global-config swaps that drop core.hooksPath without naming it (each one checked to skip the hooks)
    (MP, "GIT_CONFIG_GLOBAL=/dev/null git commit -m x", "deny"),
    (MP, "GIT_CONFIG_GLOBAL= git commit -m x", "deny"),
    (MP, "HOME=/tmp/fake git commit -m x", "deny"),
    (MP, "HOME= git push origin feature/x", "deny"),
    (MP, "USERPROFILE=C:/x HOMEDRIVE=Z: git commit -m x", "deny"),
    (MP, "env HOME=/tmp/fake git commit -m x", "deny"),
    (MP, "env -u HOME -u HOMEDRIVE -u HOMEPATH -u USERPROFILE git commit -m x", "deny"),
    (MP, "env --unset=HOMEPATH git commit -m x", "deny"),
    (MP, "env -i PATH=/usr/bin git commit -m x", "deny"),
    (MP, "env -i git push origin main", "deny"),  # env options no longer hide the push from the main check
    (MP, "env -u FOO git push origin main", "deny"),
    (MP, "export HOME=/tmp/fake && git commit -m x", "deny"),
    (MP, "export GIT_CONFIG_GLOBAL=/dev/null", "deny"),
    (MP, "HOME=/tmp/fake; git commit -m x", "deny"),
    (MP, "unset HOME HOMEDRIVE HOMEPATH USERPROFILE; git commit -m x", "deny"),
    (MP, "$env:HOME = 'C:\\x'; git commit -m x", "deny"),
    (MP, "$env:HOMEPATH='\\x'; git commit -m x", "deny"),
    (MP, "${env:GIT_CONFIG_GLOBAL} = 'NUL'; git commit -m x", "deny"),
    (MP, "Set-Item -Path env:USERPROFILE -Value C:\\x; git commit -m x", "deny"),
    (MP, "Remove-Item Env:HOMEDRIVE; git commit -m x", "deny"),
    (MP, "[Environment]::SetEnvironmentVariable('HOME', 'C:\\x', 'User')", "deny"),
    (MP, "setx HOME C:\\x", "deny"),
    (MP, "cmd /c \"set HOME=C:\\x&& git commit -m x\"", "deny"),
    (MP, "bash -c 'HOME=/tmp/fake git commit -m x'", "deny"),
    (MP, "echo 'HOME=/tmp/fake git commit -m x' | sh", "deny"),
    (MP, "bash <<'EOF'\nGIT_CONFIG_GLOBAL=/dev/null git push origin main\nEOF", "deny"),
    (MP, "git -c include.path=/tmp/x.cfg commit -m x", "deny"),
    (MP, "git -c includeIf.gitdir:~/.path=/tmp/x.cfg commit -m x", "deny"),
    (MP, "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=include.path GIT_CONFIG_VALUE_0=/tmp/x git commit -m x", "deny"),
    (MP, "HOME=/tmp/fake python run_tests.py", "ask"),  # some other command: might run git
    (MP, "cat >> ~/.bashrc <<'EOF'\nexport HOME=/tmp/fake\nEOF", "ask"),
    # ...but reads, and overrides that keep the global config, still pass
    (MP, "echo $HOME", "pass"),
    (MP, "echo \"HOME=$HOME\"", "pass"),
    (MP, "printenv GIT_CONFIG_GLOBAL", "pass"),
    (MP, "printenv HOME USERPROFILE", "pass"),
    (MP, "$env:USERPROFILE", "pass"),
    (MP, "Get-ChildItem env:HOME*", "pass"),
    (MP, "ls $env:USERPROFILE\\.claude", "pass"),
    (MP, "cat $HOME/.gitconfig", "pass"),
    (MP, "cd $HOME && git status", "pass"),
    (MP, "rm -rf $HOME/tmp/build", "pass"),
    (MP, "export PATH=$HOME/bin:$PATH && git commit -m x", "pass"),
    (MP, "grep -n 'export HOME' ~/.bashrc", "pass"),
    (MP, "[Environment]::GetEnvironmentVariable('HOME')", "pass"),
    (MP, "env | grep HOME", "pass"),
    (MP, "env -i", "pass"),
    (MP, "GIT_CONFIG_NOSYSTEM=1 git commit -m x", "pass"),
    (MP, "GIT_CONFIG_SYSTEM=/dev/null git commit -m x", "pass"),
    (MP, "XDG_CONFIG_HOME=/tmp/xdg git commit -m x", "pass"),
    (MP, "git config --global --get include.path", "pass"),
    (MP, "git commit -F - <<'EOF'\nfix(guard): deny export HOME=/x and GIT_CONFIG_GLOBAL= before git\nEOF", "pass"),
    (MP, "git commit -m 'deny HOME= overrides'", "pass"),
    (MP, "ALLOW_MAIN_PUSH=1; git push origin feature/x", "deny"),  # bare assignments are vetted now
]

fails = 0
try:
    for cwd, cmd, want in CASES:
        payload = json.dumps({"tool_name": "Bash", "cwd": cwd, "tool_input": {"command": cmd}})
        out = subprocess.run([sys.executable, GUARD], input=payload, capture_output=True, text=True).stdout.strip()
        got = json.loads(out)["hookSpecificOutput"]["permissionDecision"] if out else "pass"
        mark = "ok  " if got == want else "FAIL"
        fails += got != want
        print(f"{mark} {got:5} {cmd!r}  [{os.path.basename(cwd)}]")
finally:
    shutil.rmtree(ROOT, onerror=lambda f, p, _: (os.chmod(p, stat.S_IWRITE), f(p)))
print(f"\n{len(CASES) - fails}/{len(CASES)} as expected")
sys.exit(1 if fails else 0)
