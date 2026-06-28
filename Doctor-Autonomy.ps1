<#
.SYNOPSIS
    Read-only status dashboard for the Claude Cowork Autonomy Kit installation.

.DESCRIPTION
    Inventory of what's installed and configured on this box. Distinct from
    tests/Test-AutonomyKit.ps1 (which proves capability via sandboxed actions) —
    Doctor reports state without changing anything.

    Sections: toolchain, config, watcher, helper.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Doctor-Autonomy.ps1
#>
[CmdletBinding()]
param()

$cl = "$env:USERPROFILE\.claude"
function H($title) { Write-Host "`n=== $title ===" -ForegroundColor Cyan }
function L($k,$v) { "{0,-32} {1}" -f $k, $v | Write-Host }

H "Toolchain"
foreach ($t in 'python3','pip','uv','scoop','node','npm','npx','gh','rg','jq','sqlite3','playwright') {
    $src = (Get-Command $t -ErrorAction SilentlyContinue).Source
    L $t  $(if ($src) { $src } else { '(missing)' })
}

H "Config (~/.claude)"
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
    else             { return "present, DIFFERS from staged ($((Get-Item $live).Length)b vs $((Get-Item $stageFile).Length)b) — merge ~/.claude/autonomy-kit if you want kit updates" }
}
L "staging dir"      $(if (Test-Path $stage) { "$stage ($((Get-ChildItem $stage -File -ErrorAction SilentlyContinue).Count) files)" } else { '(missing — run Setup-Autonomy.ps1)' })
L "CLAUDE.md"        (Compare-WithStage $claudeMd 'CLAUDE-Cowork-Core.md')
L "depth profile"    (Compare-WithStage $profile  'CLAUDE-Cowork-Autonomous-Software-Development.md')
L "notify hook file" (Compare-WithStage $notify   'notify-turn-ended.ps1')

if (Test-Path $sp) {
    try {
        $s = Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json
        L "settings.json" $sp
        L "  defaultMode"   $(if ($s.permissions) { "$($s.permissions.defaultMode)" } else { '(no permissions block)' })
        L "  ask entries"   ("{0}" -f @($s.permissions.ask).Count)
        L "  deny entries"  ("{0}" -f @($s.permissions.deny).Count)
        L "  allow entries" ("{0}" -f @($s.permissions.allow).Count)
        $ad = @($s.permissions.additionalDirectories)
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

H "Approve watcher"
$w = Get-ScheduledTask -TaskName "ClaudeApproveWatcher" -ErrorAction SilentlyContinue
if ($w) {
    L "task"        "ClaudeApproveWatcher"
    L "  state"     $w.State
    $info = Get-ScheduledTaskInfo -TaskName "ClaudeApproveWatcher"
    L "  last run"  $info.LastRunTime
    L "  last result code" $info.LastTaskResult
    $proc = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'Watch-ComputerUseApprove' }
    if ($proc) { L "  process"   ("alive (PID {0})" -f (($proc.ProcessId) -join ',')) }
    else       { L "  process"   "not running" }
} else {
    L "task" '(not registered — run Setup-Autonomy.ps1 or computer-use-approve-watcher\Install-ApproveWatcherTask.ps1)'
}

H "Elevated dev helper"
$h = Get-ScheduledTask -TaskName "ClaudeElevatedDevHelper" -ErrorAction SilentlyContinue
if ($h) {
    L "task"     "ClaudeElevatedDevHelper"
    L "  state"  $h.State
    $hinfo = Get-ScheduledTaskInfo -TaskName "ClaudeElevatedDevHelper"
    L "  last run" $hinfo.LastRunTime
    L "  last result code" $hinfo.LastTaskResult
    L "  install root" 'C:\dev\ClaudeElevatedHelper'
} else {
    L "task" '(not registered — run elevated-dev-helper\Install-ClaudeElevatedDevHelper-AsAdmin.cmd)'
}

Write-Host ""
