# Install-ApproveWatcherTask.ps1
# Registers a user-scope scheduled task that runs the watcher at every logon. No admin.

param(
    [string] $TaskName = 'ClaudeApproveWatcher',
    [switch] $Uninstall
)

if ($Uninstall) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Write-Host "Removed scheduled task '$TaskName'."
    return
}

$script = Join-Path $PSScriptRoot 'Watch-ComputerUseApprove.ps1'
if (-not (Test-Path $script)) { throw "Watcher script not found: $script" }

$action  = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero)
$prin    = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $set -Principal $prin -Force | Out-Null

Write-Host "Installed '$TaskName' -- runs $script at every logon."
Write-Host "Start now:    Start-ScheduledTask -TaskName $TaskName"
Write-Host "Uninstall:    powershell -File `"$PSCommandPath`" -Uninstall"
