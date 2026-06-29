<#
.SYNOPSIS
    Regression guard for the Uninstall bak-format filter (v1.3.3 fix).

.DESCRIPTION
    Uninstall-Autonomy.ps1's Restore-LatestBak picks the newest backup that
    matches the kit's own format: `<name>.bak-YYYYMMDD-HHmmss`. Backups created
    by other tools (e.g. `<name>.bak-pre-ponytail`, `<name>.bak-cowork-foo`) must
    be skipped, otherwise Uninstall greedily restores unrelated state.

    This test materializes a temp dir with one kit-format backup and three
    non-kit backups, applies the regex, and asserts the right one wins.

    The regex below MUST stay in sync with Uninstall-Autonomy.ps1's
    Restore-LatestBak. If you change one, change the other.

    Exit 0 = pass. Exit 1 = regression.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-UninstallBakFilter.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sandbox = Join-Path $env:TEMP ("autonomy-kit-bakfilter-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Force -Path $sandbox | Out-Null

try {
    # Create one kit-format bak and three non-kit baks alongside a "live" file.
    'live' | Set-Content -LiteralPath (Join-Path $sandbox 'settings.json')
    'kit-format'    | Set-Content -LiteralPath (Join-Path $sandbox 'settings.json.bak-20260628-151845')
    'pre-ponytail'  | Set-Content -LiteralPath (Join-Path $sandbox 'settings.json.bak-pre-ponytail')
    'cowork-tagged' | Set-Content -LiteralPath (Join-Path $sandbox 'settings.json.bak-cowork-20260620-083430')
    'restore-tag'   | Set-Content -LiteralPath (Join-Path $sandbox 'settings.json.bak-pre-ponytail-restore-20260628-145442')

    # Set LastWriteTimes so the non-kit pre-ponytail is the MOST RECENT (would beat
    # the kit-format file in a naive Sort-Object -Descending). The kit-format file
    # is intentionally older to prove the regex (not the timestamp) is the gate.
    (Get-Item (Join-Path $sandbox 'settings.json.bak-20260628-151845')).LastWriteTime           = (Get-Date).AddHours(-2)
    (Get-Item (Join-Path $sandbox 'settings.json.bak-pre-ponytail')).LastWriteTime              = (Get-Date)
    (Get-Item (Join-Path $sandbox 'settings.json.bak-cowork-20260620-083430')).LastWriteTime    = (Get-Date).AddHours(-1)
    (Get-Item (Join-Path $sandbox 'settings.json.bak-pre-ponytail-restore-20260628-145442')).LastWriteTime = (Get-Date).AddMinutes(-30)

    $name = 'settings.json'
    $rx   = "^" + [regex]::Escape($name) + "\.bak-\d{8}-\d{6}$"
    $picked = Get-ChildItem -LiteralPath $sandbox -Filter "$name.bak-*" |
        Where-Object { $_.Name -match $rx } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    if (-not $picked) {
        Write-Host "FAIL: regex matched zero files; expected the kit-format bak to win." -ForegroundColor Red
        exit 1
    }
    if ($picked.Name -ne 'settings.json.bak-20260628-151845') {
        Write-Host ("FAIL: picked '{0}', expected 'settings.json.bak-20260628-151845'" -f $picked.Name) -ForegroundColor Red
        exit 1
    }

    # Also assert the non-kit baks would have won under a naive (no-regex) policy --
    # i.e. confirm the test is meaningful (would catch a regression to the v1.3.2 behavior).
    $naive = Get-ChildItem -LiteralPath $sandbox -Filter "$name.bak-*" |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($naive.Name -eq 'settings.json.bak-20260628-151845') {
        Write-Host "WARN: test fixture failed to make a non-kit bak the most-recent; the regression check is weaker than intended." -ForegroundColor Yellow
    }

    Write-Host "PASS: bak-format regex correctly skipped non-kit backups." -ForegroundColor Green
    exit 0
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
