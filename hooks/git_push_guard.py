"""PreToolUse guard for anything that sends work to GitHub.

Wired to the Bash and PowerShell tools in ~/.claude/settings.json. Reads the
hook payload on stdin and, for commands that publish something, answers:

  deny  - anything that lands code on main/master or publishes a release
          without a PR Josh reviewed: force pushes, --mirror/--all, a
          `git push` to main/master, `gh repo create --push` (even a brand-new
          repo starts from a GitHub-made README and gets its code through a
          PR), `gh repo sync`, tag pushes and `gh release create` (tags are
          releases, and Josh cuts them), and `gh api` writes to contents, refs,
          merges or releases.
  ask   - every other push, `gh pr merge`, other mutating `gh api` calls, and
          anything that makes a repo public. Josh approves each one.

It also polices the hook bypasses. Setting ALLOW_MAIN_PUSH, and writing,
unsetting or overriding core.hooksPath (`git -c`, `git config`, GIT_CONFIG_*
env that names it) are denied. Reads of them (`git config --get`, grep, git
log) and text a heredoc or here-string writes to a file pass. Any other mention
(an echo, a sed, a heredoc into a shell profile) gets a prompt, as do setting
SKIP_GITLEAKS and --no-verify.

Overrides that drop the global config without naming core.hooksPath are denied
too: GIT_CONFIG_GLOBAL, HOME, HOMEDRIVE, HOMEPATH or USERPROFILE set (or
unset) in front of git or for the session (export, $env:, Set-Item, setx), a
bare `env -i git`, and a config include pulled in from the command line
(`git -c include.path=`, GIT_CONFIG_KEY_n=include.path). The same prefix in
front of some other command gets a prompt. Each of these was checked to skip the
hooks with git 2.55 on Windows. GIT_CONFIG_NOSYSTEM, GIT_CONFIG_SYSTEM and
XDG_CONFIG_HOME don't (hooksPath lives in ~/.gitconfig, which outranks them),
so they pass.

Commands that publish nothing pass through untouched. Only Claude's tool calls
go through this; pushes Josh types in a terminal are unaffected.
"""
import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED = {"main", "master"}
FORCE_LONG = ("--force", "--force-with-lease", "--force-if-includes")
VALUE_OPTS = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}
RANK = {None: 0, "ask": 1, "deny": 2}


def tokens(segment):
    try:
        parts = shlex.split(segment, posix=False)
    except ValueError:
        parts = segment.split()
    return [p.strip("'\"") for p in parts]


def current_branch(cwd):
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
        return out.stdout.strip() if out.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


TAG_REASON = (
    "Pushing tags or creating releases is Josh's step: a tag makes code live for whatever "
    "depends on it. Josh cuts it from a terminal, on a reviewed commit on main."
)


def is_tag(name, cwd):
    try:
        out = subprocess.run(["git", "-C", cwd, "show-ref", "--verify", "--quiet", f"refs/tags/{name}"],
                             capture_output=True, timeout=5)
        return out.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def branch_name(ref):
    ref = ref.lstrip("+")
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def check_push(args, cwd):
    positionals, skip = [], False
    for a in args:
        if skip:
            skip = False
            continue
        if a in VALUE_OPTS:
            skip = True
        elif a.startswith(FORCE_LONG) or re.fullmatch(r"-[a-zA-Z]*f[a-zA-Z]*", a):
            return "deny", "Force-pushing is not allowed. Rewrite history locally and talk it through with Josh instead."
        elif a in ("--mirror", "--all"):
            return "deny", f"`git push {a}` would push main/master directly. Push the feature branch by name instead."
        elif a in ("--tags", "--follow-tags"):
            return "deny", TAG_REASON
        elif not a.startswith("-"):
            positionals.append(a)

    refspecs = positionals[1:]
    if any(r.startswith("+") for r in refspecs):
        return "deny", "A `+refspec` is a force push, which is not allowed."
    for r in refspecs:
        src, _, dst = r.partition(":")
        if src.startswith("refs/tags/") or dst.startswith("refs/tags/") or (src and is_tag(src, cwd)):
            return "deny", TAG_REASON

    if refspecs:
        branch = None
        targets = []
        for r in refspecs:
            dst = r.split(":", 1)[1] if ":" in r else r
            if dst == "HEAD":
                branch = branch or current_branch(cwd)
                dst = branch or "HEAD"
            targets.append(branch_name(dst))
    else:
        branch = current_branch(cwd)
        if branch is None:
            return "ask", "Push requested, but the guard could not work out which branch it would push. Check the branch before approving."
        targets = [branch]

    hit = PROTECTED.intersection(targets)
    if hit:
        return "deny", (
            f"Direct pushes to {', '.join(sorted(hit))} are not allowed. "
            "Push a feature branch and land it through a PR (/pr)."
        )
    return "ask", f"Push of {', '.join(targets)} to GitHub. Josh approves every push."


def check_gh(args):
    joined = " ".join(args)
    if args[:2] == ["pr", "merge"]:
        return "ask", "Merging a PR updates main on GitHub. Josh approves every merge."
    if args[:2] == ["repo", "create"]:
        if "--push" in args:
            return "deny", (
                "`gh repo create --push` puts unreviewed code straight onto main. Create the repo "
                "with --add-readme, clone it, and bring the code in on a feature branch and a PR."
            )
        if "--public" in args:
            return "ask", "This creates a PUBLIC repo. The convention is private by default."
    if args[:2] == ["repo", "sync"]:
        return "deny", "`gh repo sync` updates a branch on GitHub without a PR."
    if args[:2] == ["release", "create"]:
        return "deny", TAG_REASON
    if args[:2] == ["repo", "edit"] and re.search(r"--visibility[ =]public", joined):
        return "ask", "This makes the repo PUBLIC."
    if args[:1] == ["api"]:
        return check_gh_api(args[1:])
    return None, None


def check_gh_api(args):
    method = None
    for i, a in enumerate(args):
        if a in ("-X", "--method") and i + 1 < len(args):
            method = args[i + 1].upper()
        elif a.startswith("--method="):
            method = a.split("=", 1)[1].upper()
    has_fields = any(a in ("-f", "-F", "--field", "--raw-field", "--input") or
                     a.startswith(("--field=", "--raw-field=", "--input=")) for a in args)
    if (method or ("POST" if has_fields else "GET")) == "GET":
        return None, None
    endpoint = next((a for a in args if not a.startswith("-") and "/" in a), "")
    if re.search(r"/contents/|/git/(refs|tags|commits)|/merges\b|/pulls/\d+/merge|/releases\b", endpoint):
        return "deny", (
            f"`gh api` write to {endpoint} would change code, refs or releases without a PR. "
            "Go through a branch and a PR."
        )
    return "ask", f"`gh api` write ({method or 'POST'} {endpoint}) changes something on GitHub. Josh approves it."


# --- hook bypasses ----------------------------------------------------------
ALLOW_REASON = "ALLOW_MAIN_PUSH lifts the pre-push block on main. It's Josh's terminal-only escape hatch."
HOOKS_REASON = "Changing or overriding core.hooksPath would switch off the global gitleaks and main-protection hooks."
SKIP_REASON = "This skips the global git hooks (secret scan / main protection). Only with Josh's explicit yes."

SEP = re.compile(r"&&|\|\||[;|\n]")
PREFIX = re.compile(r"[A-Za-z_]\w*=")  # VAR=value in front of a command
BYPASS = re.compile(r"ALLOW_MAIN_PUSH|hookspath|SKIP_GITLEAKS", re.I)
SETS_ALLOW = re.compile(r"ALLOW_MAIN_PUSH['\"]?\s*=|\b(set-item|new-item|setx|export|SetEnvironmentVariable)\b"
                        r"[^;|&\n]*ALLOW_MAIN_PUSH", re.I)
SETS_HOOKS = re.compile(r"hookspath['\"]?\s*=|\b[A-Za-z_]\w*=\S*hookspath", re.I)
NO_VERIFY = re.compile(r"\bgit\b[^;&|\n]*\b(commit|push|merge|am)\b[^;&|\n]*--no-verify"
                       r"|\bgit\b[^;&|\n]*\bcommit\b[^;&|\n]*\s-n(\s|$)")
HEREDOC = re.compile(r"(?<!<)<<(-?)[ \t]*(['\"]?)([A-Za-z_][\w.-]*)\2")
HERESTRING = re.compile(r"@(['\"])[ \t]*\r?\n(.*?)\r?\n\1@", re.S)
PROFILE = re.compile(r"\.(bashrc|bash_profile|profile|zshrc|gitconfig)\b|profile\.ps1|\$profile\b"
                     r"|\.git[\\/]+config\b", re.I)
RUNS_CODE = re.compile(r"\b(iex|invoke-expression|invoke-command|start-process)\b", re.I)

# Vars that decide which global config git reads. Git for Windows takes HOME, else HOMEDRIVE+HOMEPATH if that
# directory exists, else USERPROFILE; PowerShell has no HOME, so all three matter.
HOME_VARS = "GIT_CONFIG_GLOBAL|HOME|HOMEDRIVE|HOMEPATH|USERPROFILE"
HOME_REASON = ("Overriding or clearing {} makes git read a different (or no) global config, which drops "
               "core.hooksPath and with it the global gitleaks and main-protection hooks.")
HOME_PREFIX = re.compile(rf"({HOME_VARS})=", re.I)       # a VAR=value token
HOME_VAR = re.compile(rf"({HOME_VARS})", re.I)
SETS_HOME = re.compile(                                   # for the rest of the session
    rf"\$\{{?env:({HOME_VARS})\}}?\s*=(?!=)"
    rf"|\b(set-item|si|new-item|ni|remove-item|ri|clear-item|cli|set-content|rm|del|erase)\b[^;|&\n]*"
    rf"(?<![$\{{])env:({HOME_VARS})\b"
    rf"|\bSetEnvironmentVariable\s*\(\s*['\"]({HOME_VARS})['\"]"
    rf"|\bsetx\s+['\"]?({HOME_VARS})\b|\bset\s+['\"]?({HOME_VARS})="
    rf"|\b(export|unset|declare|typeset|readonly|local)\b[^;|&\n]*?\s['\"]?({HOME_VARS})(=|\s|$)", re.I)
HOME_TEXT = re.compile(rf"(?<![\w$])({HOME_VARS})['\"]?\s*=|\benv\s+(-i|--ignore-environment|-)\s", re.I)
CLEARS_ENV = re.compile(r"-|--ignore-environment|-[a-zA-Z]*i[a-zA-Z]*")
ENV_VALUE_OPTS = {"-u", "--unset", "-C", "--chdir"}
INCLUDE_KEY = re.compile(r"(--config-env=)?include(if\.[^=]*)?\.path", re.I)
INCLUDE_ENV = re.compile(r"GIT_CONFIG_(KEY_\d+|PARAMETERS)['\"]?\s*=\s*\S*include(if\.\S*)?\.path", re.I)
INCLUDE_REASON = ("A config include pulled in from the command line can set core.hooksPath, which would switch "
                  "off the global gitleaks and main-protection hooks.")

READ_HEADS = {"grep", "egrep", "fgrep", "rg", "findstr", "select-string", "sls", "cat", "type", "gc",
              "get-content", "head", "tail", "less", "more", "wc", "ls", "dir", "gci", "get-childitem",
              "printenv", "which", "where", "get-command"}
GIT_READS = {"log", "show", "grep", "diff", "blame", "status", "shortlog", "ls-files", "rev-parse", "cat-file"}
PRINT_HEADS = {"echo", "printf", "write-output", "write-host"}
INTERPRETERS = {"sh", "bash", "zsh", "dash", "ksh", "python", "python3", "py", "node", "perl", "ruby",
                "pwsh", "powershell", "cmd", "wsl", "source", "eval", "xargs"}
CONFIG_VALUE_OPTS = {"-f", "--file", "--blob", "--type", "--default", "--comment"}
CONFIG_WRITES = {"--unset", "--unset-all", "--replace-all", "--add", "--rename-section", "--remove-section"}
CONFIG_READS = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--list", "-l"}


def split_heredocs(command):
    """Cut out heredoc and PowerShell here-string bodies: (command without them, [bodies])."""
    bodies = []

    def cut(m):
        bodies.append(m.group(2))
        return "''"
    command = HERESTRING.sub(cut, command)
    lines, out, i = command.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        out.append(line)
        i += 1
        for m in HEREDOC.finditer(line):
            delim, tabs = m.group(3), m.group(1) == "-"
            end = next((j for j in range(i, len(lines))
                        if (lines[j].lstrip("\t") if tabs else lines[j]).rstrip("\r") == delim), None)
            if end is None:  # never terminated: not a heredoc, so vet those lines as commands
                break
            bodies.append("\n".join(lines[i:end]))
            i = end + 1
    return "\n".join(out), bodies


def head_index(t):
    """Index of the command name, past VAR=value prefixes, `env` (and its options) and PowerShell's `&`."""
    i = 0
    while i < len(t):
        if t[i] == "env":
            i += 1
            while i < len(t) and t[i].startswith("-"):
                i += 2 if t[i] in ENV_VALUE_OPTS else 1
        elif PREFIX.match(t[i]) or t[i] in ("&", "command", "exec", "nohup", "time"):
            i += 1
        else:
            break
    return i


def head_of(t):
    """Skip VAR=value prefixes, `env` and PowerShell's `&`; return (command name, its args)."""
    i = head_index(t)
    if i == len(t):
        return "", []
    name = os.path.basename(t[i]).lower()
    return (name[:-4] if name.endswith(".exe") else name), t[i + 1:]


def check_config(args):
    """`git config` that writes, unsets or drops core.hooksPath (or the whole core section)."""
    pos, flags, skip = [], set(), False
    for a in args:
        if skip:
            skip = False
        elif a in CONFIG_VALUE_OPTS:
            skip = True
        elif a.startswith("-"):
            flags.add(a.split("=", 1)[0])
        else:
            pos.append(a)
    if pos and pos[0] in ("get", "list", "get-color", "get-colorbool"):
        return None, None
    if pos and pos[0] in ("set", "unset", "rename-section", "remove-section"):
        writes, pos = True, pos[1:]
    else:
        writes = bool(flags & CONFIG_WRITES) or (not flags & CONFIG_READS and len(pos) >= 2)
    if writes and pos and pos[0].lower() in ("core.hookspath", "core"):
        return "deny", HOOKS_REASON
    return None, None


def check_mention(seg, head, sub, runs_code):
    """A segment that names ALLOW_MAIN_PUSH, core.hooksPath or SKIP_GITLEAKS."""
    found = {w.lower() for w in BYPASS.findall(seg)}
    if sub == "config":
        found.discard("hookspath")  # check_config has already placed it
    if not found or head in READ_HEADS or (head == "git" and sub in GIT_READS):
        return None, None
    printing = head in PRINT_HEADS and not runs_code  # an echo whose output nothing runs
    if "allow_main_push" in found and not printing and SETS_ALLOW.search(seg):
        return "deny", ALLOW_REASON
    if "hookspath" in found and not printing and SETS_HOOKS.search(seg):
        return "deny", HOOKS_REASON
    if "skip_gitleaks" in found and re.search(r"SKIP_GITLEAKS['\"]?\s*=", seg):
        return "ask", SKIP_REASON
    names = ", ".join(sorted({w for w in BYPASS.findall(seg)}))
    return "ask", f"This mentions {names}, and the guard can't tell whether it switches a hook off. Check it."


def check_home(seg, t, head, runs_code):
    """Overrides that make git read another global config (or none), so core.hooksPath silently drops out."""
    if head in READ_HEADS:
        return None, None
    if INCLUDE_ENV.search(seg) and not (head in PRINT_HEADS and not runs_code):
        return "deny", INCLUDE_REASON
    pre = t[:head_index(t)]
    names = {a.split("=", 1)[0].upper() for a in pre if HOME_PREFIX.match(a)}
    names |= {b.upper() for a, b in zip(pre, pre[1:]) if a in ("-u", "--unset") and HOME_VAR.fullmatch(b)}
    names |= {a[8:].upper() for a in pre if a.startswith("--unset=") and HOME_VAR.fullmatch(a[8:])}
    if head and any(CLEARS_ENV.fullmatch(a) for a in pre):
        names.add("the whole environment (env -i)")
    if names:
        what = ", ".join(sorted(names))
        if head in ("git", ""):  # in front of git, or a bare assignment (HOME & co. are already exported)
            return "deny", HOME_REASON.format(what)
        if head not in PRINT_HEADS:
            return "ask", HOME_REASON.format(what) + f" Here it's in front of {head}, which might run git. Check it."
    if head in PRINT_HEADS and not runs_code:
        if PROFILE.search(seg) and HOME_TEXT.search(seg):
            return "ask", "This writes a HOME / GIT_CONFIG_GLOBAL override into a shell profile or git config. Check it."
        return None, None
    m = SETS_HOME.search(seg)
    if m:
        return "deny", HOME_REASON.format(next(g for g in m.groups() if g and HOME_VAR.fullmatch(g)).upper())
    if runs_code and HOME_TEXT.search(seg):  # e.g. bash -c "HOME=/x git commit", or echo '...' | sh
        return ("deny" if re.search(r"\bgit\b", seg) else "ask"), HOME_REASON.format("HOME / GIT_CONFIG_GLOBAL")
    return None, None


def assess(command, cwd):
    text, bodies = split_heredocs(command)
    heads = {head_of(tokens(s.strip()))[0] for s in SEP.split(text)}
    runs_code = bool(INTERPRETERS & heads or RUNS_CODE.search(text))
    verdict, reason = None, None
    if bodies and runs_code:
        text = command  # the bodies are fed to an interpreter, so vet them as commands too
    elif any(BYPASS.search(b) or HOME_TEXT.search(b) for b in bodies) and PROFILE.search(text):
        verdict, reason = "ask", ("This writes ALLOW_MAIN_PUSH / core.hooksPath / SKIP_GITLEAKS text, or a HOME / "
                                  "GIT_CONFIG_GLOBAL override, into a shell profile or git config, where it could "
                                  "switch a hook off. Check it.")
    if NO_VERIFY.search(text) and RANK[verdict] < RANK["ask"]:
        verdict, reason = "ask", SKIP_REASON
    for seg in SEP.split(text):
        seg = seg.strip()
        head, args = head_of(tokens(seg))
        if not seg:
            continue
        if head in ("cd", "set-location", "pushd", "sl") and args:
            cwd = os.path.join(cwd, args[0])
            continue
        v, r, sub = None, None, None
        if head == "git":
            i, gcwd = 0, cwd
            while i < len(args) and args[i].startswith("-"):
                if args[i] == "-C" and i + 1 < len(args):
                    gcwd = os.path.join(cwd, args[i + 1])
                    i += 2
                elif args[i] in ("-c", "--config-env") and i + 1 < len(args):
                    if re.search("hookspath", args[i + 1], re.I):
                        v, r = "deny", HOOKS_REASON
                    elif INCLUDE_KEY.match(args[i + 1]):
                        v, r = "deny", INCLUDE_REASON
                    i += 2
                else:
                    if re.search("hookspath", args[i], re.I):
                        v, r = "deny", HOOKS_REASON
                    elif INCLUDE_KEY.match(args[i]):
                        v, r = "deny", INCLUDE_REASON
                    i += 1
            sub = args[i] if i < len(args) else None
            if v is None and sub == "push":
                v, r = check_push(args[i + 1:], gcwd)
            elif v is None and sub == "config":
                v, r = check_config(args[i + 1:])
        elif head == "gh":
            v, r = check_gh(args)
        for v, r in ((v, r), check_mention(seg, head, sub, runs_code), check_home(seg, tokens(seg), head, runs_code)):
            if RANK[v] > RANK[verdict]:
                verdict, reason = v, r
    return verdict, reason


def emit(decision, reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": decision,
        "permissionDecisionReason": f"[push guard] {reason}",
    }}))


def main():
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw)
        command = payload.get("tool_input", {}).get("command", "") or ""
        if not re.search(r"\bpush\b|\bgh\b|\bcommit\b|\bconfig\b|ALLOW_MAIN_PUSH|SKIP_GITLEAKS|hooksPath|--no-verify"
                         rf"|{HOME_VARS}|GIT_CONFIG|include|\benv\b", command, re.I):
            return
        decision, reason = assess(command, payload.get("cwd") or os.getcwd())
        if decision:
            emit(decision, reason)
    except Exception as exc:  # fail towards a prompt, never towards a silent push
        if re.search(rf"\bpush\b|\bgh\b|\bconfig\b|ALLOW_MAIN_PUSH|hooksPath|{HOME_VARS}|GIT_CONFIG|include", raw, re.I):
            emit("ask", f"The push guard hit an error ({exc!r}), so it could not vet this command. Check it by hand.")


if __name__ == "__main__":
    main()
