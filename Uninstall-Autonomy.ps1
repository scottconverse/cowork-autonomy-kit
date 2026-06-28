<#
.SYNOPSIS
    Reverses the config layer installed by Setup-Autonomy.ps1.

.DESCRIPTION
    - Stops and removes the ClaudeApproveWatcher scheduled task (always).
    - Stops and removes the ClaudeElevatedDevHelper scheduled task (only with -RemoveHelper).
    - Restores the most recent ~/.claude/settings.json.bak if present, else removes the
      bypassPermissions + notify-hook entries written by Setup.
    - Restores the most recent ~/.claude/CLAUDE.md.bak if present, else deletes CLAUDE.md.
    - Leaves the toolchain (python, scoop, node, gh, ripgrep, jq, sqlite, uv, playwright)
      alone -- those are general-purpose, not specific to the kit.

.PARAMETER RemoveHelper
    Also unregister the ClaudeElevatedDevHelper task. Files under
    C:\dev\ClaudeElevatedHelper are left in place.

.PARAMETER WhatIf
    Print what would happen without changing anything.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Autonomy.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$RemoveHelper
)

$ErrorActionPreference = "Stop"
$cl = "$env:USERPROFILE\.claude"

function Restore-LatestBak($path) {
    $dir  = Split-Path -Parent $path
    $name = Split-Path -Leaf   $path
    $bak  = Get-ChildItem -LiteralPath $dir -Filter "$name.bak-*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($bak) {
        if ($PSCmdlet.ShouldProcess($path, "restore from $($bak.Name)")) {
            Copy-Item -LiteralPath $bak.FullName -Destination $path -Force
            Write-Host "restored $path  <-  $($bak.Name)"
        }
        return $true
    }
    return $false
}

# 1. Approve watcher
$w = Get-ScheduledTask -TaskName "ClaudeApproveWatcher" -ErrorAction SilentlyContinue
if ($w) {
    if ($PSCmdlet.ShouldProcess("ClaudeApproveWatcher", "Unregister-ScheduledTask")) {
        Stop-ScheduledTask  -TaskName "ClaudeApproveWatcher" -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName "ClaudeApproveWatcher" -Confirm:$false
        Write-Host "removed scheduled task: ClaudeApproveWatcher"
    }
} else {
    Write-Host "ClaudeApproveWatcher not present - skip"
}

# 2. Elevated helper (only on request)
if ($RemoveHelper) {
    $h = Get-ScheduledTask -TaskName "ClaudeElevatedDevHelper" -ErrorAction SilentlyContinue
    if ($h) {
        if ($PSCmdlet.ShouldProcess("ClaudeElevatedDevHelper", "Unregister-ScheduledTask")) {
            Unregister-ScheduledTask -TaskName "ClaudeElevatedDevHelper" -Confirm:$false
            Write-Host "removed scheduled task: ClaudeElevatedDevHelper (files under C:\dev\ClaudeElevatedHelper left in place)"
        }
    }
}

# 3. settings.json
$sp = Join-Path $cl "settings.json"
if (Test-Path -LiteralPath $sp) {
    if (-not (Restore-LatestBak $sp)) {
        try {
            $s = Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json
            if ($s.permissions -and $s.permissions.defaultMode -eq 'bypassPermissions') {
                if ($PSCmdlet.ShouldProcess($sp, "drop defaultMode=bypassPermissions")) {
                    $s.permissions.PSObject.Properties.Remove('defaultMode')
                }
            }
            if ($s.hooks -and $s.hooks.PSObject.Properties.Name -contains 'Stop') {
                $kept = @()
                foreach ($e in @($s.hooks.Stop)) {
                    $isNotify = $false
                    foreach ($h in @($e.hooks)) {
                        if ("$($h.command)" -like "*notify-turn-ended*") { $isNotify = $true }
                    }
                    if (-not $isNotify) { $kept += $e }
                }
                if ($PSCmdlet.ShouldProcess($sp, "drop notify-turn-ended Stop hook")) {
                    $s.hooks | Add-Member Stop $kept -Force
                }
            }
            ($s | ConvertTo-Json -Depth 20) | Set-Content -LiteralPath $sp -Encoding UTF8
            Write-Host "stripped kit-added entries from settings.json (no .bak found to restore)"
        } catch {
            Write-Warning "could not parse $sp - left as-is"
        }
    }
}

# 4. CLAUDE.md: prefer restoring user's .bak; else remove only if it matches the staged kit copy.
$claudeMd = Join-Path $cl "CLAUDE.md"
$stage    = Join-Path $cl "autonomy-kit"
if (Test-Path -LiteralPath $claudeMd) {
    if (-not (Restore-LatestBak $claudeMd)) {
        $stageFile = Join-Path $stage 'CLAUDE-Cowork-Core.md'
        $matches = (Test-Path -LiteralPath $stageFile) -and `
            ((Get-FileHash $claudeMd -Algorithm SHA1).Hash -eq (Get-FileHash $stageFile -Algorithm SHA1).Hash)
        if ($matches) {
            if ($PSCmdlet.ShouldProcess($claudeMd, "remove (matches staged)")) {
                Remove-Item -LiteralPath $claudeMd -Force
                Write-Host "removed $claudeMd"
            }
        } else {
            Write-Host "kept $claudeMd (differs from staged; user-customized)"
        }
    }
}

# 5. Depth profile + notify hook (live copies; remove only if they match the staged kit copy
#    so we don't clobber user customizations made after install).
function Remove-IfMatchesStage($live, $stageName) {
    if (-not (Test-Path -LiteralPath $live)) { return }
    $stageFile = Join-Path $stage $stageName
    $matches = $false
    if (Test-Path -LiteralPath $stageFile) {
        $matches = ((Get-FileHash $live -Algorithm SHA1).Hash -eq (Get-FileHash $stageFile -Algorithm SHA1).Hash)
    }
    if ($matches) {
        if ($PSCmdlet.ShouldProcess($live, "remove (matches staged)")) {
            Remove-Item -LiteralPath $live -Force
            Write-Host "removed $live"
        }
    } else {
        Write-Host "kept $live (differs from staged or no staged copy; user-customized)"
    }
}
Remove-IfMatchesStage (Join-Path $cl "CLAUDE-Cowork-Autonomous-Software-Development.md") 'CLAUDE-Cowork-Autonomous-Software-Development.md'
Remove-IfMatchesStage (Join-Path $cl "hooks\notify-turn-ended.ps1")                       'notify-turn-ended.ps1'

# 6. Staging dir (kit-owned; always safe to remove)
if (Test-Path -LiteralPath $stage) {
    if ($PSCmdlet.ShouldProcess($stage, "remove staging dir")) {
        Remove-Item -LiteralPath $stage -Recurse -Force
        Write-Host "removed $stage"
    }
}

Write-Host "`nDONE. Toolchain (python/scoop/node/gh/rg/jq/sqlite/uv/playwright) left alone."
Write-Host "Restart Cowork/Claude Code for settings changes to take effect."
