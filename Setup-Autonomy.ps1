<#
.SYNOPSIS
    Full-permission setup for Claude Code on Windows: the desktop app's Code tab and the CLI.
.DESCRIPTION
    Shows changes and asks for confirmation unless -Yes. Installs missing user-scope tools,
    merges settings, snapshots original files once, preserves existing live instructions,
    and optionally launches a visible UAC helper installer. The Cowork tab is out of scope.
.PARAMETER SkipBypass
    Leave defaultMode unchanged while applying other selected setup changes.
.PARAMETER Yes
    Skip the Continue? question for scripted runs.
.PARAMETER SkipConfig
    Skip all configuration files and snapshots.
.PARAMETER SkipHelper
    Skip administrator-helper installation.
.PARAMETER SkipBrowsers
    Skip the Chromium browser download.
#>
[CmdletBinding()]
param(
    [switch]$SkipConfig,
    [switch]$SkipBrowsers,
    [switch]$Yes,
    [switch]$SkipBypass,
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

# Pick the newest user-scope Python by version number. A text sort of folder names
# puts Python39 before Python313. Only plain PythonNNN folders count (no -32, no t builds).
function Find-UserPython {
    Get-ChildItem "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe" -ErrorAction SilentlyContinue |
        Where-Object { $_.Directory.Name -match '^Python3\d+$' } |
        Sort-Object { [int]($_.Directory.Name.Substring(7)) } -Descending |
        Select-Object -First 1
}

function Read-KitSettings {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{} }
    try {
        $value = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $value -or $value -isnot [pscustomobject]) { throw 'Expected a JSON object' }
        foreach ($key in @('permissions','hooks')) {
            if ($value.PSObject.Properties.Name -contains $key -and $value.$key -isnot [pscustomobject]) { throw "$key must be an object" }
        }
        return $value
    } catch { throw "Invalid settings file '$Path': $($_.Exception.Message). Nothing was written." }
}

function New-PreKitSnapshot {
    param([string]$Path)
    $snapshot = "$Path.pre-autonomy-kit"
    $absent = "$snapshot.absent"
    if ((Test-Path -LiteralPath $snapshot) -or (Test-Path -LiteralPath $absent)) { return }
    if (Test-Path -LiteralPath $Path) { Copy-Item -LiteralPath $Path -Destination $snapshot }
    else { [IO.File]::WriteAllText($absent, '', [Text.UTF8Encoding]::new($false)) }
}

function Install-LiveOrLeave {
    param([string]$Source, [string]$Destination)
    if (Test-Path -LiteralPath $Destination) {
        Copy-Item -LiteralPath $Destination -Destination "$Destination.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss-fffffff'))"
        Write-Host "Kept customized or existing live file: $Destination"
    } else { Copy-Item -LiteralPath $Source -Destination $Destination }
}

function Merge-KitSettings {
    param([pscustomobject]$Settings, [string]$ClaudeRoot, [switch]$SkipBypass)
    if (-not ($Settings.PSObject.Properties.Name -contains 'permissions')) { $Settings | Add-Member permissions ([pscustomobject]@{}) }
    if (-not $SkipBypass) {
        if ($Settings.permissions.PSObject.Properties.Name -contains 'defaultMode') { $Settings.permissions.defaultMode = 'bypassPermissions' }
        else { $Settings.permissions | Add-Member defaultMode 'bypassPermissions' }
    }
    foreach ($key in @('ask','deny')) {
        if (-not ($Settings.permissions.PSObject.Properties.Name -contains $key)) { $Settings.permissions | Add-Member $key @() }
    }
    if (-not ($Settings.PSObject.Properties.Name -contains 'hooks')) { $Settings | Add-Member hooks ([pscustomobject]@{}) }
    $hookCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $ClaudeRoot 'hooks\notify-turn-ended.ps1') + '"'
    $notify = [pscustomobject]@{type='command';shell='powershell';command=$hookCmd}
    $stop = @(); $wired = $false
    foreach ($entry in @($Settings.hooks.Stop)) {
        if ($null -eq $entry) { continue }
        $kept = @(); $touched = $false
        foreach ($hook in @($entry.hooks)) {
            if ([string]$hook.command -like '*notify-turn-ended*') {
                $touched = $true
                if (-not $wired) { $kept += $notify; $wired = $true }
            } else { $kept += $hook }
        }
        if ($touched) {
            $entry.PSObject.Properties.Remove('matcher')
            $entry | Add-Member hooks $kept -Force
        }
        if ($kept.Count -gt 0 -or -not $touched) { $stop += $entry }
    }
    if (-not $wired) { $stop += [pscustomobject]@{hooks=@($notify)} }
    $Settings.hooks | Add-Member Stop $stop -Force
    if ($Settings.permissions.PSObject.Properties.Name -contains 'additionalDirectories') {
        $dirs = @($Settings.permissions.additionalDirectories | ForEach-Object { [string]$_ -replace 'YOUR_USERNAME', $env:USERNAME })
        $Settings.permissions | Add-Member additionalDirectories $dirs -Force
    }
    return $Settings
}

function Install-KitConfiguration {
    param([string]$KitRoot, [string]$ClaudeRoot, [switch]$SkipBypass)
    $settingsPath = Join-Path $ClaudeRoot 'settings.json'
    # Validate before directories, backups, snapshots or live files are changed.
    $settings = Read-KitSettings -Path $settingsPath
    $stage = Join-Path $ClaudeRoot 'autonomy-kit'
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $ClaudeRoot 'hooks') | Out-Null
    foreach ($name in @('settings.json','CLAUDE.md','CLAUDE-Cowork-Autonomous-Software-Development.md','hooks\notify-turn-ended.ps1')) {
        New-PreKitSnapshot -Path (Join-Path $ClaudeRoot $name)
    }
    $pairs = @(
        @('CLAUDE-Cowork-Core.md','CLAUDE.md'),
        @('CLAUDE-Cowork-Autonomous-Software-Development.md','CLAUDE-Cowork-Autonomous-Software-Development.md'),
        @('hooks\notify-turn-ended.ps1','hooks\notify-turn-ended.ps1')
    )
    foreach ($pair in $pairs) {
        $source = Join-Path $KitRoot $pair[0]
        Copy-Item -LiteralPath $source -Destination (Join-Path $stage (Split-Path -Leaf $source)) -Force
        Install-LiveOrLeave -Source $source -Destination (Join-Path $ClaudeRoot $pair[1])
    }
    Copy-Item -LiteralPath (Join-Path $KitRoot 'settings.autonomy.example.json') -Destination $stage -Force
    if (Test-Path -LiteralPath $settingsPath) { Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak-$((Get-Date).ToString('yyyyMMdd-HHmmss-fffffff'))" }
    $merged = Merge-KitSettings -Settings $settings -ClaudeRoot $ClaudeRoot -SkipBypass:$SkipBypass
    [IO.File]::WriteAllText($settingsPath, ($merged | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
    $createdSettings = Join-Path $stage 'settings.created-by-kit.json'
    if ((Test-Path -LiteralPath "$settingsPath.pre-autonomy-kit.absent") -and -not (Test-Path -LiteralPath $createdSettings)) {
        Copy-Item -LiteralPath $settingsPath -Destination $createdSettings
    }
    Write-Host "Merged Claude Code settings and staged profiles at $stage"
}

Write-Host 'Setup will install missing developer tools, merge Claude Code settings, preserve live CLAUDE.md, and wire the notification hook.'
Write-Host ('Bypass mode: ' + $(if ($SkipBypass) { 'unchanged (-SkipBypass)' } else { 'defaultMode=bypassPermissions; existing ask/deny retained' }))
Write-Host ('Elevated helper: ' + $(if ($SkipHelper) { 'skipped' } else { 'optional administrator helper; Windows UAC if installation is needed' }))
if (-not $Yes -and (Read-Host 'Continue? [y/N]') -notmatch '^(?i)y(es)?$') { Write-Host 'Cancelled; no changes made.'; return }

# ---------------------------------------------------------------- 1. Python + python3 shim
Step "Python (user-scope) + python3 shim"
$pyExe = Find-UserPython
if (-not $pyExe) {
    winget install -e --id Python.Python.3.12 --scope user `
        --accept-package-agreements --accept-source-agreements --disable-interactivity
    $pyExe = Find-UserPython
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
# If scoop is already on PATH (anywhere -- standard $env:USERPROFILE\scoop OR a less-common
# location), the get.scoop.sh installer aborts with "Scoop is already installed". Under
# $ErrorActionPreference=Stop that kills Setup, even though scoop is fine. Try the install,
# but tolerate that abort; verify by Get-Command afterwards.
if (-not (Get-Command scoop -ErrorAction SilentlyContinue) -and
    -not (Test-Path "$env:USERPROFILE\scoop\shims\scoop.ps1")) {
    try {
        Invoke-Expression (Invoke-RestMethod -Uri "https://get.scoop.sh")
    } catch {
        Write-Warning "scoop installer raised: $($_.Exception.Message). Will verify via Get-Command."
    }
}
Prepend-UserPath "$env:USERPROFILE\scoop\shims"
$scoopCmd = Get-Command scoop -ErrorAction SilentlyContinue
$scoop = if ($scoopCmd) { $scoopCmd.Source } else { "$env:USERPROFILE\scoop\shims\scoop.ps1" }
if (-not (Test-Path $scoop)) {
    Write-Warning "scoop not found after install attempt -- skipping scoop-based tool installs in step 4."
    $scoop = $null
} else {
    & $scoop bucket add main *> $null
}

# --------------------------------------------------------------- 4. core CLI tools via scoop
Step "core tools via scoop (nodejs-lts, gh, ripgrep, jq, sqlite)"
# Per-tool so we never duplicate something already installed another way (winget/zip).
$wanted = [ordered]@{ 'nodejs-lts' = 'node'; 'gh' = 'gh'; 'ripgrep' = 'rg'; 'jq' = 'jq'; 'sqlite' = 'sqlite3' }
foreach ($pkg in $wanted.Keys) {
    $cmd = $wanted[$pkg]
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Write-Host "$cmd already present - skip"
    } elseif ($scoop) {
        & $scoop install $pkg
    } else {
        Write-Warning "$cmd not present and scoop unavailable -- install manually"
    }
}

# ---------------------------------------------------------------------------- 5. Playwright
Step "Playwright + chromium browser"
$py3cmd = (Get-Command python3 -ErrorAction SilentlyContinue).Source
if (-not $py3cmd -and $pyExe) { $py3cmd = Join-Path $pyExe.Directory.FullName "python3.exe" }
if ($py3cmd) {
    # Idempotent: only install if absent; do NOT auto-upgrade on every Setup re-run.
    #
    # Do NOT redirect stderr of a native command here (2>$null, 2>&1, *>$null). In Windows
    # PowerShell 5.1 (what Install.cmd runs), a stderr redirect turns each stderr line into an
    # error record, and $ErrorActionPreference=Stop then aborts Setup. The old check,
    # `pip show playwright 2>$null`, wrote "Package(s) not found" to stderr on a clean box,
    # so Setup died before it installed Playwright. find_spec writes nothing to stderr;
    # we read only the exit code.
    $pwProbe = "import importlib.util, sys; sys.exit(0 if importlib.util.find_spec('playwright') else 1)"
    & $py3cmd -c $pwProbe
    if ($LASTEXITCODE -ne 0) {
        & $py3cmd -m pip install --quiet playwright
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "pip install playwright FAILED (exit $LASTEXITCODE). Re-run Setup or run: python3 -m pip install playwright"
        } else {
            Write-Host "playwright: installed"
        }
    } else {
        Write-Host "playwright already present - skip pip install"
    }
    & $py3cmd -c $pwProbe
    if ($LASTEXITCODE -eq 0) {
        if (-not $SkipBrowsers) {
            & $py3cmd -m playwright install chromium
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "playwright install chromium FAILED (exit $LASTEXITCODE). Re-run: python3 -m playwright install chromium"
            } else {
                Write-Host "playwright: chromium installed"
            }
        }
        $pwVer = & $py3cmd -m playwright --version
        Write-Host "playwright: $pwVer"
    }
} else {
    Write-Warning "python3 not found - Playwright step skipped. Install Python and re-run Setup."
}

# 6. Claude Code configuration
if (-not $SkipConfig) {
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot (Join-Path $env:USERPROFILE '.claude') -SkipBypass:$SkipBypass
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
        $helperProcess = Start-Process -FilePath $helperInstall -Verb RunAs -WindowStyle Normal -Wait -PassThru
        if ($helperProcess.ExitCode -ne 0) { throw "Helper installer failed with exit code $($helperProcess.ExitCode)." }
        $helperTask = Get-ScheduledTask -TaskName "ClaudeElevatedDevHelper" -ErrorAction SilentlyContinue
        Write-Host ("helper: {0}" -f $(if ($helperTask) { 'installed' } else { 'NOT installed (UAC declined or installer error)' }))
    } else {
        Write-Warning "helper installer not found: $helperInstall"
    }
}

# -------------------------------------------------------------------------------- summary
Step "Summary"
$report = [ordered]@{}
foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3','playwright') {
    $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
    $report[$t] = if ($src) { 'OK' } else { 'missing (open a new shell)' }
}
$report.GetEnumerator() | ForEach-Object { "{0,-10} {1}" -f $_.Key, $_.Value } | Write-Host

Write-Host "`nNEXT:" -ForegroundColor Green
Write-Host "  1. In Claude: Settings, Claude Code, turn on 'Allow bypass permissions mode'. Without it the Code tab cannot use Bypass permissions."
Write-Host "  2. Fully quit Claude (right-click the Claude icon in the system tray, Quit), then open it again. A new session alone does not load new PATH entries; the desktop app does not read PowerShell profiles."
Write-Host "  3. Run Doctor-Autonomy.ps1. If depth profile import is missing, add @CLAUDE-Cowork-Autonomous-Software-Development.md on its own line to your live CLAUDE.md."
Write-Host "  4. If a folder still prompts, select Bypass permissions once for that folder in the Code tab."
