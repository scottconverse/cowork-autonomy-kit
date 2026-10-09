<#
.SYNOPSIS
    Read-only status dashboard for the Claude Code Windows Autonomy Kit installation.

.DESCRIPTION
    Inventory of what's installed and configured on this box. Distinct from
    tests/Test-AutonomyKit.ps1 (which proves capability via sandboxed actions) --
    Doctor reports state without changing anything.

    Sections: toolchain, config, watcher, helper.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Doctor-Autonomy.ps1
#>
[CmdletBinding()]
param()

$cl = "$env:USERPROFILE\.claude"
function Hdr($title) { Write-Host "`n=== $title ===" -ForegroundColor Cyan }
function L($k,$v) { "{0,-32} {1}" -f $k, $v | Write-Host }

Hdr "Toolchain"
foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3','playwright') {
    $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
    L $t  $(if ($src) { $src } else { '(missing)' })
}
# Playwright browsers live outside PATH. Setup installs chromium only.
$pwBrowsers = Join-Path $env:LOCALAPPDATA "ms-playwright"
$chromium = Get-ChildItem -Path $pwBrowsers -Directory -Filter 'chromium-*' -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending | Select-Object -First 1
L 'playwright chromium' $(if ($chromium) { $chromium.FullName } else { '(missing; run: python3 -m playwright install chromium)' })

Hdr "Config (~/.claude)"
Write-Host "In Claude: Settings, Claude Code, turn on 'Allow bypass permissions mode'. Without it the Code tab cannot use Bypass permissions."
Write-Host 'Doctor cannot read the app toggle; verify it in Claude Settings.'
$claudeMd = Join-Path $cl "CLAUDE.md"
$sp       = Join-Path $cl "settings.json"
$profile  = Join-Path $cl "CLAUDE-Cowork-Autonomous-Software-Development.md"
$notify   = Join-Path $cl "hooks\notify-turn-ended.ps1"
$stage    = Join-Path $cl "autonomy-kit"

function Compare-WithStage($live, $stageName) {
    $stageFile = Join-Path $stage $stageName
    if (-not (Test-Path $live))      { return '(missing)' }
    if (-not (Test-Path $stageFile)) { return "present ($((Get-Item $live).Length)b; no staged copy to compare)" }
    $lh = (Get-FileHash -LiteralPath $live      -Algorithm SHA1).Hash
    $sh = (Get-FileHash -LiteralPath $stageFile -Algorithm SHA1).Hash
    if ($lh -eq $sh) { return "present, matches staged ($((Get-Item $live).Length)b)" }
    else             { return "present, customized ($((Get-Item $live).Length)b; staged copy: $((Get-Item $stageFile).Length)b) -- diff ~/.claude/autonomy-kit if you want to compare" }
}
L "staging dir"      $(if (Test-Path $stage) { "$stage ($((Get-ChildItem $stage -File -ErrorAction SilentlyContinue).Count) files)" } else { '(missing -- run Setup-Autonomy.ps1)' })
L "CLAUDE.md"        (Compare-WithStage $claudeMd 'CLAUDE-Cowork-Core.md')
L "depth profile"    (Compare-WithStage $profile  'CLAUDE-Cowork-Autonomous-Software-Development.md')
L "notify hook file" (Compare-WithStage $notify   'notify-turn-ended.ps1')

$hasImport = (Test-Path -LiteralPath $claudeMd) -and (@(Get-Content -LiteralPath $claudeMd) -ccontains '@CLAUDE-Cowork-Autonomous-Software-Development.md')
L 'depth profile import' $(if ($hasImport) { 'present' } else { 'missing' })

if (Test-Path $sp) {
    try {
        $s = Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json
        L "settings.json" $sp
        L "  defaultMode"   $(if ($s.permissions) { "$($s.permissions.defaultMode)" } else { '(no permissions block)' })
        L "  ask entries"   ("{0}" -f @($s.permissions.ask | Where-Object { $null -ne $_ }).Count)
        L "  deny entries"  ("{0}" -f @($s.permissions.deny | Where-Object { $null -ne $_ }).Count)
        L "  allow entries" ("{0}" -f @($s.permissions.allow | Where-Object { $null -ne $_ }).Count)
        $ad = @($s.permissions.additionalDirectories | Where-Object { $null -ne $_ })
        L "  additionalDirs" ("{0} entries" -f $ad.Count)
        foreach ($d in $ad) {
            $marker = if ("$d" -match 'YOUR_USERNAME') { ' <-- UNRESOLVED PLACEHOLDER' } else { '' }
            L "    -" "$d$marker"
        }
        $notifyWired = $false
        foreach ($e in @($s.hooks.Stop)) {
            foreach ($h in @($e.hooks)) {
                if ("$($h.command)" -like "*notify-turn-ended*") { $notifyWired = $true }
            }
        }
        L "  Stop hook (notify)" $(if ($notifyWired) { 'wired' } else { 'NOT wired' })
        $bakCount = (Get-ChildItem -LiteralPath $cl -Filter "settings.json.bak-*" -ErrorAction SilentlyContinue).Count
        L "  backups present" $bakCount
    } catch {
        L "settings.json" "PARSE ERROR: $($_.Exception.Message)"
    }
} else {
    L "settings.json" '(missing)'
}

Hdr "Legacy watcher"
try {
    $legacy = Get-ScheduledTask -TaskName 'ClaudeApproveWatcher' -ErrorAction Stop
    L 'legacy task' 'legacy approve watcher still installed; run Uninstall-Autonomy.ps1 to remove it'
} catch { L 'legacy task' ('absent or inaccessible: ' + $_.Exception.Message) }

Hdr "Elevated dev helper"
$statePath = Join-Path $env:ProgramData 'ClaudeElevatedHelper\install-state.json'
if (Test-Path -LiteralPath $statePath) {
    try {
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        L 'worker root' $state.install_root
        L 'data root' $state.data_root
        L 'invoker' $state.invoker_script
        L 'verified installation' $state.installed
        $task = Get-ScheduledTask -TaskName $state.task_name -ErrorAction Stop
        L 'task' $task.TaskName
        L 'state' $task.State
    } catch { L 'helper status' ('invalid or inaccessible: ' + $_.Exception.Message) }
} else { L 'helper state' 'missing; install or migrate helper using its installer' }
