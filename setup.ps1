<#
.SYNOPSIS
    Sets up a Windows PC for this Claude Code config, from a checkout of
    bearnz/claude-config at ~/.claude. The README's "Setting up on a machine"
    section covers getting the checkout there first.

.DESCRIPTION
    Safe to re-run. Each step checks first and only changes what is missing:
      1. The checkout: origin is bearnz/claude-config and main is checked out.
      2. Tools: git, gh, python, uv and gitleaks, installed with winget.
      3. Global git hooks: core.hooksPath points at ~/.claude/git-hooks, and
         git has a user name and email.
      4. settings.json: every absolute path it uses exists on this PC.
      5. GitHub CLI: signed in.
      6. Tests: the push guard and pre-push hook suites pass.
    It ends with a list of anything still to do by hand, and exits 1 if
    there is any.

.PARAMETER CheckOnly
    Report what is missing without installing or changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$HOME\.claude\setup.ps1" -CheckOnly
#>
param([switch]$CheckOnly)

# Native commands report failure through $LASTEXITCODE, which is checked
# explicitly. 'Stop' would also turn their stderr into terminating errors on
# Windows PowerShell 5.1.
$ErrorActionPreference = 'Continue'

$Claude = Join-Path $HOME '.claude'
$todo = New-Object System.Collections.Generic.List[string]

function Step($m) { Write-Host ""; Write-Host "== $m" }
function Ok($m)   { Write-Host "  ok    $m" -ForegroundColor Green }
function Did($m)  { Write-Host "  done  $m" -ForegroundColor Cyan }
function Todo($m) { Write-Host "  todo  $m" -ForegroundColor Yellow; $script:todo.Add($m) }

function Find-Tool($name) {
    # The Microsoft Store "python" alias in WindowsApps only opens the Store.
    Get-Command $name -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -notlike '*\WindowsApps\*' } |
        Select-Object -First 1
}

if ($CheckOnly) { Write-Host "Check only: nothing will be installed or changed." }

Step 'Checkout'
if (-not (Test-Path (Join-Path $Claude '.git'))) {
    Write-Host "  $Claude is not a git checkout. Follow the README's 'Setting up on a machine' first." -ForegroundColor Red
    exit 1
}
$origin = git -C $Claude remote get-url origin
if ($origin -match 'bearnz/claude-config') { Ok "origin is $origin" } else { Todo "origin is '$origin', expected bearnz/claude-config" }
$branch = git -C $Claude branch --show-current
if ($branch -eq 'main') { Ok 'main is checked out' } else { Todo "the checkout is on '$branch'. The live config should be on main, apart from the branch of an open PR" }

Step 'Tools'
# Each key is the command looked for on PATH; the value is the winget package to
# install when it is not there. Either an exact id, or idPrefix to take the
# newest stable <idPrefix>.N. bearnz/workstation's packages.json names these
# same tools the same way, so keep the two agreeing.
$tools = [ordered]@{
    git      = @{ id = 'Git.Git' }
    gh       = @{ id = 'GitHub.cli' }
    python   = @{ idPrefix = 'Python.Python.3'; scope = 'user'; custom = 'PrependPath=1' }
    uv       = @{ id = 'astral-sh.uv'; scope = 'user' }
    gitleaks = @{ id = 'Gitleaks.Gitleaks' }
}

# Newest stable <prefix>.N in winget, e.g. Python.Python.3 -> Python.Python.3.15.
# Pre-releases have letters in the version and so don't match. Only ever called
# for a tool that is actually missing: the search is the slow part, and its
# answer is irrelevant once the tool is on PATH.
function Resolve-NewestWingetId($prefix) {
    $re = '^.*\s(' + [regex]::Escape($prefix) + '\.(\d+))\s+\d+(\.\d+)+\s*$'
    $newest = winget search --id "$prefix." --source winget --disable-interactivity |
        ForEach-Object { if ($_ -match $re) { [pscustomobject]@{ id = $Matches[1]; n = [int]$Matches[2] } } } |
        Sort-Object n | Select-Object -Last 1
    if ($newest) { return $newest.id }
    return $null
}

$installed = $false
foreach ($name in $tools.Keys) {
    $t = $tools[$name]
    $found = Find-Tool $name
    if ($found) { Ok "$name ($($found.Source))"; continue }
    $id = $t.id
    if (-not $id) {
        # Resolving needs a winget search, so -CheckOnly does reach the network
        # here. It reads only, and it is what makes the Todo name a real package.
        $id = Resolve-NewestWingetId $t.idPrefix
        if (-not $id) { Todo "$name is missing and no winget package matches $($t.idPrefix).N"; continue }
    }
    $a = @('install', '--id', $id, '-e')
    if ($t.scope)  { $a += @('--scope', $t.scope) }
    if ($t.custom) { $a += @('--custom', $t.custom) }
    if ($CheckOnly) { Todo "$name is missing: winget $($a -join ' ')"; continue }
    winget @a
    if ($LASTEXITCODE -eq 0) { Did "installed $id"; $installed = $true }
    else { Todo "winget $($a -join ' ') failed (exit $LASTEXITCODE)" }
}
if ($installed) {
    # Pick up the new tools in this process without a new terminal.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

Step 'Global git hooks'
if (-not (Find-Tool git)) {
    Todo 'git is not installed, so the hooks cannot be wired up yet. Re-run after installing it'
} else {
    $want = ($Claude -replace '\\', '/') + '/git-hooks'
    $have = git config --global --get core.hooksPath
    if ($have -eq $want) {
        Ok "core.hooksPath is $want"
    } elseif ($CheckOnly) {
        Todo "core.hooksPath is '$have', should be '$want'"
    } else {
        git config --global core.hooksPath $want
        if ($LASTEXITCODE -eq 0) { Did "set core.hooksPath to $want" } else { Todo "could not set core.hooksPath (exit $LASTEXITCODE)" }
    }
    foreach ($key in 'user.name', 'user.email') {
        if (git config --global --get $key) { Ok "$key is set" }
        else { Todo "git $key is not set: git config --global $key <value>" }
    }
}

Step 'settings.json paths'
$settings = Get-Content (Join-Path $Claude 'settings.json') -Raw | ConvertFrom-Json
$paths = @()
foreach ($event in $settings.hooks.PSObject.Properties) {
    foreach ($group in $event.Value) {
        foreach ($hook in $group.hooks) {
            $paths += @($hook.command) + @($hook.args) | Where-Object { $_ -match '^[A-Za-z]:[\\/]' }
        }
    }
}
if (-not $paths) { Ok 'no absolute paths in hooks' }
foreach ($p in $paths) {
    if (Test-Path $p) { Ok "$p exists" }
    else { Todo "settings.json uses $p, which does not exist on this PC. Fix the path through a PR" }
}

Step 'GitHub CLI'
if (Find-Tool gh) {
    gh auth status *> $null
    if ($LASTEXITCODE -eq 0) { Ok 'gh is signed in' } else { Todo 'gh is not signed in: gh auth login' }
} else {
    Todo 'gh is not installed, so sign-in was not checked'
}

Step 'Tests'
$python = Find-Tool python
$git = Find-Tool git
if ($python) {
    & $python.Source (Join-Path $Claude 'hooks/test_git_push_guard.py') | Select-Object -Last 1
    if ($LASTEXITCODE -eq 0) { Ok 'push guard tests passed' } else { Todo 'push guard tests failed: python ~/.claude/hooks/test_git_push_guard.py' }
} else {
    Todo 'python is not installed, so the push guard tests did not run'
}
if ($git) {
    # Git for Windows' own sh. Another sh can come first on PATH (WinAVR has one).
    $sh = Join-Path (Split-Path (Split-Path $git.Source)) 'bin\sh.exe'
    & $sh (Join-Path $Claude 'git-hooks/test_pre_push.sh') | Select-Object -Last 1
    if ($LASTEXITCODE -eq 0) { Ok 'pre-push hook tests passed' } else { Todo 'pre-push hook tests failed: sh ~/.claude/git-hooks/test_pre_push.sh' }
} else {
    Todo 'git is not installed, so the pre-push hook tests did not run'
}

Step 'Result'
if ($todo.Count -eq 0) {
    Write-Host '  Everything checked is in place. The README lists what still needs doing by hand (sign-ins, MCP servers, memory).' -ForegroundColor Green
    exit 0
}
Write-Host "  $($todo.Count) thing(s) to do:" -ForegroundColor Yellow
foreach ($t in $todo) { Write-Host "   - $t" }
exit 1
