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
      4. settings.json: DEV_ROOT is set, and every path the hooks use
         ($HOME/..., $DEV_ROOT/... or absolute) exists on this PC.
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
function Get-NewestWingetId($prefix) {
    # Newest stable <prefix>N in winget, e.g. Python.Python.3. -> Python.Python.3.14.
    # Pre-releases have letters in the version and don't match.
    $re = '^.*\s(' + [regex]::Escape($prefix) + '(\d+))\s+\d+(\.\d+)+\s*$'
    winget search --id $prefix --source winget --disable-interactivity |
        ForEach-Object { if ($_ -match $re) { [pscustomobject]@{ id = $Matches[1]; n = [int]$Matches[2] } } } |
        Sort-Object n | Select-Object -Last 1 -ExpandProperty id
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
$tools = [ordered]@{
    git      = 'Git.Git'
    gh       = 'GitHub.cli'
    python   = 'Python.Python.3.'  # ends in '.': the newest stable 3.N
    uv       = 'astral-sh.uv'
    gitleaks = 'Gitleaks.Gitleaks'
}
$installed = $false
foreach ($name in $tools.Keys) {
    $id = $tools[$name]
    $found = Find-Tool $name
    if ($found) { Ok "$name ($($found.Source))"; continue }
    if ($id.EndsWith('.')) {
        $prefix = $id
        $id = Get-NewestWingetId $prefix
        if (-not $id) { Todo "$name is missing, and no winget package matches $($prefix)N"; continue }
    }
    if ($CheckOnly) { Todo "$name is missing: winget install --id $id -e"; continue }
    winget install --id $id -e
    if ($LASTEXITCODE -eq 0) { Did "installed $id"; $installed = $true }
    else { Todo "winget install --id $id -e failed (exit $LASTEXITCODE)" }
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
# Hook commands run through Git Bash, which expands $HOME and $DEV_ROOT, so
# settings.json writes paths as "$HOME/..." or "$DEV_ROOT/...", in double
# quotes. DEV_ROOT is the dev root, a user environment variable that
# bearnz/workstation's bootstrap.ps1 sets. setx only reaches new processes,
# so read the User scope too.
$devRoot = $env:DEV_ROOT
if (-not $devRoot) { $devRoot = [Environment]::GetEnvironmentVariable('DEV_ROOT', 'User') }
if ($devRoot) { Ok "DEV_ROOT is $devRoot" }
else { Todo 'DEV_ROOT is not set: setx DEV_ROOT <dev root> (D:\.dev on the laptop), then restart Claude Code' }
$settings = Get-Content (Join-Path $Claude 'settings.json') -Raw | ConvertFrom-Json
$paths = @()
foreach ($event in $settings.hooks.PSObject.Properties) {
    foreach ($group in $event.Value) {
        foreach ($hook in $group.hooks) {
            foreach ($s in @($hook.command) + @($hook.args) | Where-Object { $_ }) {
                # The whole string, or a double-quoted part of a shell command.
                $parts = @($s) + @([regex]::Matches($s, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
                $paths += $parts | Where-Object { $_ -match '^([A-Za-z]:[\\/]|\$HOME/|\$DEV_ROOT/)' }
            }
        }
    }
}
if (-not $paths) { Ok 'no paths in hooks' }
foreach ($p in $paths | Select-Object -Unique) {
    if ($p.StartsWith('$HOME/')) { $full = Join-Path $HOME $p.Substring(6) }
    elseif ($p.StartsWith('$DEV_ROOT/')) {
        if (-not $devRoot) { Todo "settings.json uses $p, which needs DEV_ROOT"; continue }
        $full = Join-Path $devRoot $p.Substring(10)
    }
    else { $full = $p }
    if (Test-Path $full) { Ok "$p exists ($full)" }
    else { Todo "settings.json uses $p, which does not exist on this PC ($full)" }
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
