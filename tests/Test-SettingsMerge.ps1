<#
.SYNOPSIS
    Regression guard for Setup's settings.json merge idempotency.

.DESCRIPTION
    Setup-Autonomy.ps1 merges three things into ~/.claude/settings.json:
    bypassPermissions, empty ask/deny, and a Stop hook entry pointing at
    notify-turn-ended.ps1. Each merge MUST be idempotent: running Setup twice
    must not produce a duplicate Stop hook entry, two defaultMode keys, etc.

    The Stop-hook dedupe in particular is a quiet correctness bug if it
    regresses: a second Setup run would append a duplicate Stop entry, and
    notify-turn-ended.ps1 would fire twice every turn.

    This test materializes a fake ~/.claude state, runs the merge logic
    twice, and asserts shape invariants.

    The merge snippet below MUST stay in sync with Setup-Autonomy.ps1's
    step 6 config block. If you change one, change the other.

    Exit 0 = pass. Exit 1 = regression.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-SettingsMerge.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sandbox = Join-Path $env:TEMP ("autonomy-kit-mergetest-" + [guid]::NewGuid().ToString('n'))
$cl      = Join-Path $sandbox '.claude'
New-Item -ItemType Directory -Force -Path $cl | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $cl 'hooks') | Out-Null

function Invoke-MergeOnce($settingsPath, $clRoot) {
    $settings = $null
    if (Test-Path -LiteralPath $settingsPath) {
        try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json } catch { $settings = $null }
    }
    if (-not $settings) { $settings = [pscustomobject]@{} }

    if (-not ($settings.PSObject.Properties.Name -contains 'permissions')) {
        $settings | Add-Member permissions ([pscustomobject]@{}) -Force
    }
    $settings.permissions | Add-Member defaultMode "bypassPermissions" -Force
    if (-not ($settings.permissions.PSObject.Properties.Name -contains 'ask'))  { $settings.permissions | Add-Member ask  @() -Force }
    if (-not ($settings.permissions.PSObject.Properties.Name -contains 'deny')) { $settings.permissions | Add-Member deny @() -Force }

    $hookCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$clRoot\hooks\notify-turn-ended.ps1`""
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

    $json = $settings | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($settingsPath, $json, [System.Text.UTF8Encoding]::new($false))
}

function Count-NotifyStopHooks($settingsPath) {
    $s = Get-Content $settingsPath -Raw | ConvertFrom-Json
    $count = 0
    foreach ($e in @($s.hooks.Stop)) {
        foreach ($h in @($e.hooks)) {
            if ("$($h.command)" -like "*notify-turn-ended*") { $count++ }
        }
    }
    return $count
}

try {
    $sp = Join-Path $cl 'settings.json'

    # Round 1: clean state.
    Invoke-MergeOnce $sp $cl
    $count1 = Count-NotifyStopHooks $sp
    $mode1  = (Get-Content $sp -Raw | ConvertFrom-Json).permissions.defaultMode

    if ($count1 -ne 1) {
        Write-Host "FAIL (round 1): expected 1 notify Stop hook, got $count1" -ForegroundColor Red
        exit 1
    }
    if ($mode1 -ne 'bypassPermissions') {
        Write-Host "FAIL (round 1): expected defaultMode=bypassPermissions, got '$mode1'" -ForegroundColor Red
        exit 1
    }

    # Round 2: re-run on the just-merged file. Idempotency.
    Invoke-MergeOnce $sp $cl
    $count2 = Count-NotifyStopHooks $sp
    if ($count2 -ne 1) {
        Write-Host "FAIL (round 2): re-run produced $count2 notify Stop hooks; idempotency broken." -ForegroundColor Red
        exit 1
    }

    # Round 3: pre-seed with foreign Stop hook (e.g. user's own), confirm we preserve it
    # AND don't duplicate the notify one.
    $s = Get-Content $sp -Raw | ConvertFrom-Json
    $foreign = [pscustomobject]@{ matcher = ""; hooks = @([pscustomobject]@{ type = "command"; command = "echo user-hook" }) }
    $s.hooks.Stop = @($s.hooks.Stop) + $foreign
    [System.IO.File]::WriteAllText($sp, ($s | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
    Invoke-MergeOnce $sp $cl
    $afterForeign = Get-Content $sp -Raw | ConvertFrom-Json
    $notifyCount = Count-NotifyStopHooks $sp
    $foreignKept = $false
    foreach ($e in @($afterForeign.hooks.Stop)) {
        foreach ($h in @($e.hooks)) {
            if ("$($h.command)" -eq 'echo user-hook') { $foreignKept = $true }
        }
    }
    if ($notifyCount -ne 1) {
        Write-Host "FAIL (round 3): expected 1 notify Stop hook, got $notifyCount" -ForegroundColor Red
        exit 1
    }
    if (-not $foreignKept) {
        Write-Host "FAIL (round 3): merge dropped a foreign Stop hook." -ForegroundColor Red
        exit 1
    }

    # BOM check on what we wrote.
    $b = [System.IO.File]::ReadAllBytes($sp)
    if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) {
        Write-Host "FAIL: merge produced a UTF-8 BOM in settings.json." -ForegroundColor Red
        exit 1
    }

    Write-Host "PASS: merge is idempotent across re-runs, preserves foreign hooks, no BOM." -ForegroundColor Green
    exit 0
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
