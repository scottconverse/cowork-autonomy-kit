<#
.SYNOPSIS
    Restore the first pre-kit Claude Code configuration; remove legacy watcher task.
.DESCRIPTION
    Leaves general-purpose tools installed. No newest-backup guessing. WhatIf makes no writes.
    RemoveHelper unregisters the helper task; Program Files and ProgramData files remain.
#>
[CmdletBinding(SupportsShouldProcess)]
param([switch]$RemoveHelper)
$ErrorActionPreference = 'Stop'
function Remove-IfMatchesStage {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Live, [string]$Staged)
    if (-not (Test-Path -LiteralPath $Live)) { return }
    if ((Test-Path -LiteralPath $Staged) -and (Get-FileHash -LiteralPath $Live).Hash -eq (Get-FileHash -LiteralPath $Staged).Hash) {
        if ($PSCmdlet.ShouldProcess($Live,'Remove unchanged kit-created file')) { [IO.File]::Delete($Live) }
    } else { Write-Host "Kept modified live file: $Live" }
}

function Restore-PreKitFile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path, [string]$Staged)
    if (Test-Path -LiteralPath "$Path.pre-autonomy-kit") {
        if ($PSCmdlet.ShouldProcess($Path,'Back up current file and restore first pre-kit snapshot')) {
            if (Test-Path -LiteralPath $Path) {
                Copy-Item -LiteralPath $Path -Destination "$Path.before-uninstall-$([guid]::NewGuid().ToString('n')).bak"
            }
            Copy-Item -LiteralPath "$Path.pre-autonomy-kit" -Destination $Path -Force
        }
        return $true
    }
    if (Test-Path -LiteralPath "$Path.pre-autonomy-kit.absent") {
        Remove-IfMatchesStage -Live $Path -Staged $Staged -WhatIf:$WhatIfPreference
        return $true
    }
    return $false
}

function Remove-KitSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $settings = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($settings.permissions.defaultMode -eq 'bypassPermissions') { $settings.permissions.PSObject.Properties.Remove('defaultMode') }
    if ($settings.hooks -and $settings.hooks.PSObject.Properties.Name -contains 'Stop') {
        $stop = @()
        foreach ($entry in @($settings.hooks.Stop)) {
            $kept = @($entry.hooks | Where-Object { [string]$_.command -notlike '*notify-turn-ended*' })
            if ($kept.Count) { $entry | Add-Member hooks $kept -Force; $stop += $entry }
        }
        $settings.hooks | Add-Member Stop $stop -Force
    }
    if ($PSCmdlet.ShouldProcess($Path,'Strip only kit defaultMode and notify Stop hook; ignore timestamped backups')) {
        [IO.File]::WriteAllText($Path,($settings | ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
    }
}

function Uninstall-KitConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ClaudeRoot)
    $stage = Join-Path $ClaudeRoot 'autonomy-kit'
    $settings = Join-Path $ClaudeRoot 'settings.json'
    if (-not (Restore-PreKitFile -Path $settings -Staged (Join-Path $stage 'settings.created-by-kit.json') -WhatIf:$WhatIfPreference)) {
        Remove-KitSettings -Path $settings -WhatIf:$WhatIfPreference
    }
    foreach ($pair in @(@('CLAUDE.md','CLAUDE-Cowork-Core.md'),@('CLAUDE-Cowork-Autonomous-Software-Development.md','CLAUDE-Cowork-Autonomous-Software-Development.md'),@('hooks\notify-turn-ended.ps1','notify-turn-ended.ps1'))) {
        $live = Join-Path $ClaudeRoot $pair[0]; $staged = Join-Path $stage $pair[1]
        if (-not (Restore-PreKitFile -Path $live -Staged $staged -WhatIf:$WhatIfPreference)) {
            Remove-IfMatchesStage -Live $live -Staged $staged -WhatIf:$WhatIfPreference
        }
    }
    if ((Test-Path -LiteralPath $stage) -and $PSCmdlet.ShouldProcess($stage,'Remove kit staging directory')) {
        $expected = [IO.Path]::GetFullPath((Join-Path $ClaudeRoot 'autonomy-kit'))
        if ([IO.Path]::GetFullPath($stage) -ne $expected) { throw 'Unexpected cleanup target' }
        [IO.Directory]::Delete($expected,$true)
    }
}

function Get-KitRemovalTaskNames {
    param([string]$StatePath, [switch]$RemoveHelper)
    'ClaudeApproveWatcher'
    if ($RemoveHelper) {
        $name = 'ClaudeElevatedDevHelper'
        if (Test-Path -LiteralPath $StatePath) {
            $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($state.task_name) { $name = [string]$state.task_name }
        }
        $name
    }
}

foreach ($taskName in @(Get-KitRemovalTaskNames -StatePath (Join-Path $env:ProgramData 'ClaudeElevatedHelper\install-state.json') -RemoveHelper:$RemoveHelper)) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task -and $PSCmdlet.ShouldProcess($taskName,'Stop and unregister scheduled task')) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
}
Uninstall-KitConfiguration -ClaudeRoot (Join-Path $env:USERPROFILE '.claude') -WhatIf:$WhatIfPreference
Write-Host 'Toolchain left installed. Fully quit Claude from the system tray and reopen for settings changes.'
