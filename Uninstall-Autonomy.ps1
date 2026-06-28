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
      alone — those are general-purpose, not specific to the kit.

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

# 4. CLAUDE.md
$claudeMd = Join-Path $cl "CLAUDE.md"
if (Test-Path -LiteralPath $claudeMd) {
    if (-not (Restore-LatestBak $claudeMd)) {
        if ($PSCmdlet.ShouldProcess($claudeMd, "remove (no .bak to restore)")) {
            Remove-Item -LiteralPath $claudeMd -Force
            Write-Host "removed $claudeMd (no .bak to restore)"
        }
    }
}

# 5. Depth profile + notify hook (always written by Setup; safe to remove)
foreach ($p in @(
    (Join-Path $cl "CLAUDE-Cowork-Autonomous-Software-Development.md"),
    (Join-Path $cl "hooks\notify-turn-ended.ps1")
)) {
    if (Test-Path -LiteralPath $p) {
        if ($PSCmdlet.ShouldProcess($p, "remove")) {
            Remove-Item -LiteralPath $p -Force
            Write-Host "removed $p"
        }
    }
}

Write-Host "`nDONE. Toolchain (python/scoop/node/gh/rg/jq/sqlite/uv/playwright) left alone."
Write-Host "Restart Cowork/Claude Code for settings changes to take effect."
