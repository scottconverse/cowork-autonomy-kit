<#
.SYNOPSIS
    One-command toolchain + config bootstrap for the Claude Cowork Autonomy Kit on a fresh
    Windows machine. Run NON-admin, from inside the kit folder, then restart Cowork.

.DESCRIPTION
    A clean Cowork/Windows box starts with no real Python (only the Microsoft Store stub),
    no `python3`, no Node, no user-scope package manager, and `winget` that needs admin for
    machine installs and is flaky inside non-interactive elevated tasks. This script fixes
    all of that with user-scope, no-admin installs, in the order that actually works:

      1. Python (winget user-scope) + a real `python3.exe` shim  (hooks call `python3`)
      2. uv            (astral.sh installer)
      3. scoop         (the no-admin package-manager keystone)
      4. node-lts, gh, ripgrep, jq, sqlite   (via scoop)
      5. Playwright + browsers                (via pip)
      6. Cowork config / staging:
         - Always refreshes a staging copy of the kit's files under ~/.claude/autonomy-kit/.
         - Live files (CLAUDE.md, depth profile, notify hook) are written ONLY on first
           install. If they already exist they are backed up and LEFT UNCHANGED -- re-run
           Setup safely without clobbering customizations.
         - settings.json: idempotent key-level merge (bypassPermissions + Stop hook +
           YOUR_USERNAME substitution). Skipped entirely with -SkipConfig.
      7. computer-use-approve-watcher: registers and starts a user-scope logon scheduled
         task that auto-clicks the computer-use / browser / webfetch Approve dialog.
      8. elevated-dev-helper: triggers the helper's UAC installer if the
         ClaudeElevatedDevHelper task is not already present. Skip with -SkipHelper.

    Idempotent: re-running skips anything already present and never duplicates settings
    entries. Everything is user-scope; the only admin step (the elevated dev helper) is left
    to its own UAC installer and printed at the end.

.PARAMETER SkipConfig
    Install the toolchain only; leave ~/.claude/CLAUDE.md and settings.json untouched.

.PARAMETER SkipBrowsers
    Install the Playwright package but skip the (large) browser download.

.PARAMETER SkipHelper
    Skip the elevated-dev-helper UAC installer (step 8).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-Autonomy.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipConfig,
    [switch]$SkipBrowsers,
    [switch]$SkipHelper
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$kit = $PSScriptRoot

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Prepend-UserPath($dir) {
    if (-not $dir -or -not (Test-Path -LiteralPath $dir)) { return }
    $up = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($up -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable('Path', "$dir;$up", 'User')
    }
    if (($env:Path -split ';') -notcontains $dir) { $env:Path = "$dir;$env:Path" }
}

# ---------------------------------------------------------------- 1. Python + python3 shim
Step "Python (user-scope) + python3 shim"
$pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $pyExe) {
    winget install -e --id Python.Python.3.12 --scope user `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    $pyExe = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1
}
if ($pyExe) {
    $pydir = $pyExe.Directory.FullName
    $py3 = Join-Path $pydir "python3.exe"
    if (-not (Test-Path -LiteralPath $py3)) { Copy-Item $pyExe.FullName $py3 -Force }  # hooks exec `python3`
    Prepend-UserPath $pydir
    Prepend-UserPath (Join-Path $pydir "Scripts")
    Write-Host "python: $(& $pyExe.FullName --version)"
} else {
    Write-Warning "Python not installed automatically; install it and re-run."
}

# ----------------------------------------------------------------------------------- 2. uv
Step "uv"
if (-not (Test-Path "$env:USERPROFILE\.local\bin\uv.exe")) {
    powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://astral.sh/uv/install.ps1 | iex"
}
Prepend-UserPath "$env:USERPROFILE\.local\bin"
Write-Host "uv: $(& "$env:USERPROFILE\.local\bin\uv.exe" --version 2>&1)"

# --------------------------------------------------------------------------------- 3. scoop
Step "scoop (no-admin package-manager keystone)"
if (-not (Test-Path "$env:USERPROFILE\scoop\shims\scoop.ps1")) {
    Invoke-Expression (Invoke-RestMethod -Uri "https://get.scoop.sh")
}
Prepend-UserPath "$env:USERPROFILE\scoop\shims"
$scoop = "$env:USERPROFILE\scoop\shims\scoop.ps1"
& $scoop bucket add main *> $null

# --------------------------------------------------------------- 4. core CLI tools via scoop
Step "core tools via scoop (nodejs-lts, gh, ripgrep, jq, sqlite)"
# Per-tool so we never duplicate something already installed another way (winget/zip).
$wanted = [ordered]@{ 'nodejs-lts' = 'node'; 'gh' = 'gh'; 'ripgrep' = 'rg'; 'jq' = 'jq'; 'sqlite' = 'sqlite3' }
foreach ($pkg in $wanted.Keys) {
    $cmd = $wanted[$pkg]
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host "$cmd already present - skip"
    } else {
        & $scoop install $pkg
    }
}

# ---------------------------------------------------------------------------- 5. Playwright
Step "Playwright + browsers"
$py3cmd = (Get-Command python3 -ErrorAction SilentlyContinue).Source
if (-not $py3cmd -and $pyExe) { $py3cmd = Join-Path $pyExe.Directory.FullName "python3.exe" }
if ($py3cmd) {
    # Idempotent: only install if absent; do NOT auto-upgrade on every Setup re-run.
    $pwInstalled = & $py3cmd -m pip show playwright 2>$null
    if (-not $pwInstalled) {
        & $py3cmd -m pip install --quiet playwright
        Write-Host "playwright: installed"
    } else {
        Write-Host "playwright already present - skip pip install"
    }
    if (-not $SkipBrowsers) { & $py3cmd -m playwright install }
    Write-Host "playwright: $(& $py3cmd -m playwright --version 2>&1)"
}

# ------------------------------------------------------------------------------- 6. config
if (-not $SkipConfig) {
    Step "Cowork config / profile staging (~/.claude)"
    $cl    = "$env:USERPROFILE\.claude"
    $stage = Join-Path $cl "autonomy-kit"
    New-Item -ItemType Directory -Force -Path $cl    | Out-Null
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $cl "hooks") | Out-Null

    # Stage the kit's reference copies -- always refreshed; never user-edited.
    Copy-Item "$kit\CLAUDE-Cowork-Core.md"                                 $stage -Force
    Copy-Item "$kit\CLAUDE-Cowork-Autonomous-Software-Development.md"      $stage -Force
    Copy-Item "$kit\settings.autonomy.example.json"                        $stage -Force
    Copy-Item "$kit\hooks\notify-turn-ended.ps1"                           $stage -Force
    Write-Host "staged kit files under $stage (refreshed)"

    # Live files: create only if absent. If present, back up and leave the user's copy alone.
    function Install-LiveOrLeave($src, $dst) {
        if (Test-Path -LiteralPath $dst) {
            Copy-Item $dst "$dst.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))" -Force
            Write-Host ("kept existing {0} (backup made; merge from staging if you want kit updates)" -f (Split-Path -Leaf $dst))
        } else {
            Copy-Item $src $dst -Force
            Write-Host "created $dst"
        }
    }
    Install-LiveOrLeave "$kit\CLAUDE-Cowork-Core.md"                            (Join-Path $cl "CLAUDE.md")
    Install-LiveOrLeave "$kit\CLAUDE-Cowork-Autonomous-Software-Development.md" (Join-Path $cl "CLAUDE-Cowork-Autonomous-Software-Development.md")
    Install-LiveOrLeave "$kit\hooks\notify-turn-ended.ps1"                      (Join-Path $cl "hooks\notify-turn-ended.ps1")

    $sp = Join-Path $cl "settings.json"
    $settings = $null
    if (Test-Path -LiteralPath $sp) {
        Copy-Item $sp "$sp.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss'))" -Force
        try { $settings = Get-Content $sp -Raw | ConvertFrom-Json } catch { $settings = $null }
    }
    if (-not $settings) { $settings = [pscustomobject]@{} }

    # permissions: bypassPermissions, empty ask/deny (preserve any existing allow)
    if (-not ($settings.PSObject.Properties.Name -contains 'permissions')) {
        $settings | Add-Member permissions ([pscustomobject]@{}) -Force
    }
    $settings.permissions | Add-Member defaultMode "bypassPermissions" -Force
    if (-not ($settings.permissions.PSObject.Properties.Name -contains 'ask'))  { $settings.permissions | Add-Member ask  @() -Force }
    if (-not ($settings.permissions.PSObject.Properties.Name -contains 'deny')) { $settings.permissions | Add-Member deny @() -Force }

    # hooks.Stop -> notify (idempotent: only add if not already wired)
    $hookCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$cl\hooks\notify-turn-ended.ps1`""
    if (-not ($settings.PSObject.Properties.Name -contains 'hooks')) {
        $settings | Add-Member hooks ([pscustomobject]@{}) -Force
    }
    $stop = @()
    if ($settings.hooks.PSObject.Properties.Name -contains 'Stop') { $stop = @($settings.hooks.Stop) }
    $already = $false
    foreach ($e in $stop) { foreach ($h in @($e.hooks)) { if ("$($h.command)" -like "*notify-turn-ended*") { $already = $true } } }
    if (-not $already) {
        $stop += [pscustomobject]@{ matcher = ""; hooks = @([pscustomobject]@{ type = "command"; command = $hookCmd }) }
    }
    $settings.hooks | Add-Member Stop $stop -Force

    # additionalDirectories: if any entry contains the literal "YOUR_USERNAME" placeholder
    # (from a manual merge of settings.autonomy.example.json), substitute the real user name.
    if ($settings.permissions.PSObject.Properties.Name -contains 'additionalDirectories') {
        $subbed = $false
        $newDirs = @()
        foreach ($d in @($settings.permissions.additionalDirectories)) {
            $orig = "$d"
            $fixed = $orig -replace 'YOUR_USERNAME', $env:USERNAME
            if ($fixed -ne $orig) { $subbed = $true }
            $newDirs += $fixed
        }
        if ($subbed) {
            $settings.permissions | Add-Member additionalDirectories $newDirs -Force
            Write-Host "substituted YOUR_USERNAME -> $env:USERNAME in additionalDirectories"
        }
    }

    # Write UTF-8 WITHOUT BOM. PS 5.1's `Set-Content -Encoding UTF8` prepends a BOM,
    # which breaks naive JSON consumers (python json.loads, etc.). See user memory
    # feedback-powershell-utf8-bom-trap.md.
    $json = $settings | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($sp, $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "merged settings.json (bypassPermissions + notify Stop hook; UTF-8 no BOM)"
}

# ----------------------------------------------------------- 7. computer-use approve watcher
Step "computer-use approve watcher"
$watcherInstaller = Join-Path $kit "computer-use-approve-watcher\Install-ApproveWatcherTask.ps1"
if (Test-Path -LiteralPath $watcherInstaller) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $watcherInstaller
    $w = Get-ScheduledTask -TaskName ClaudeApproveWatcher -ErrorAction SilentlyContinue
    if ($w) {
        Start-ScheduledTask -TaskName ClaudeApproveWatcher -ErrorAction SilentlyContinue
        Write-Host "approve watcher: installed + started (task ClaudeApproveWatcher)"
    } else {
        Write-Warning "approve watcher install FAILED (task not registered). Inspect errors above; re-run computer-use-approve-watcher\Install-ApproveWatcherTask.ps1 manually."
    }
} else {
    Write-Warning "approve watcher installer not found: $watcherInstaller"
}

# ------------------------------------------------------------------- 8. elevated-dev-helper
if (-not $SkipHelper) {
    Step "elevated dev helper (UAC prompt if not already installed)"
    $helperTask    = Get-ScheduledTask -TaskName "ClaudeElevatedDevHelper" -ErrorAction SilentlyContinue
    $helperInstall = Join-Path $kit "elevated-dev-helper\Install-ClaudeElevatedDevHelper-AsAdmin.cmd"
    if ($helperTask) {
        Write-Host "ClaudeElevatedDevHelper already installed - skip"
    } elseif (Test-Path -LiteralPath $helperInstall) {
        Write-Host "launching helper installer (Windows UAC prompt expected)..."
        Start-Process -FilePath $helperInstall -Verb RunAs -Wait
        $helperTask = Get-ScheduledTask -TaskName "ClaudeElevatedDevHelper" -ErrorAction SilentlyContinue
        Write-Host ("helper: {0}" -f $(if ($helperTask) { 'installed' } else { 'NOT installed (UAC declined or installer error)' }))
    } else {
        Write-Warning "helper installer not found: $helperInstall"
    }
}

# -------------------------------------------------------------------------------- summary
Step "Summary"
$report = [ordered]@{}
foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3') {
    $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
    $report[$t] = if ($src) { 'OK' } else { 'missing (open a new shell)' }
}
$report.GetEnumerator() | ForEach-Object { "{0,-10} {1}" -f $_.Key, $_.Value } | Write-Host

Write-Host "`nNEXT:" -ForegroundColor Green
Write-Host "  1. RESTART Cowork/Claude Code so the new PATH, CLAUDE.md, and hooks load."
Write-Host "  2. Inventory check anytime, from the kit dir:"
Write-Host "       powershell -NoProfile -ExecutionPolicy Bypass -File `"$kit\Doctor-Autonomy.ps1`""
Write-Host "  3. Install any other tool on demand, no admin, via: scoop install <x> | uv tool install <x> | pip install <x> | npm i -g <x>."
