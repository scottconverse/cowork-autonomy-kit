<#
.SYNOPSIS
    Portability guard — fails if any shipped file contains a hardcoded per-user or
    machine-specific path (e.g. C:\Users\<account>). This protects the v1.2.1
    portability fix from silent regression on future commits.

.DESCRIPTION
    Scans all tracked-style source files (.ps1/.psm1/.json/.cmd/.md) under the kit
    for literal `C:\Users\<name>` paths. Placeholders (YOUR_USERNAME, <YOUR-HOME>)
    are allowed — they are obviously-edit-me templates, not machine data. CHANGELOG.md
    is exempt because it intentionally documents the OLD hardcoded path it removed.

    Exit 0 = clean (portable). Exit 1 = a hardcoded path leaked back in.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-NoHardcodedPaths.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$kit = Split-Path $PSScriptRoot -Parent

$files = Get-ChildItem $kit -Recurse -File -Include *.ps1, *.psm1, *.json, *.cmd, *.md |
    Where-Object { $_.FullName -notlike '*\.git\*' }

# Allowed placeholders (templates the user is told to replace) and history exemption.
$placeholders = @('YOUR_USERNAME', 'YOUR-HOME', '<YOUR')

$hits = foreach ($f in $files) {
    # `\\+` matches one-or-more backslashes so this catches BOTH .ps1 single-backslash
    # paths (C:\Users\name) AND JSON double-backslash-escaped paths (C:\\Users\\name).
    foreach ($ms in (Select-String -LiteralPath $f.FullName -Pattern 'C:\\+Users\\+[A-Za-z0-9._-]+' -AllMatches)) {
        foreach ($m in $ms.Matches) {
            $val = $m.Value
            $isPlaceholder = $false
            foreach ($p in $placeholders) { if ($val -like "*$p*") { $isPlaceholder = $true } }
            # Exempt: CHANGELOG (documents the removed path on purpose) and THIS guard
            # script (its docs/regex legitimately contain example C:\Users\ paths).
            $isExempt = ($f.Name -eq 'CHANGELOG.md' -or $f.Name -eq 'Test-NoHardcodedPaths.ps1')
            if (-not $isPlaceholder -and -not $isExempt) {
                [pscustomobject]@{
                    File  = $f.FullName.Substring($kit.Length + 1)
                    Line  = $ms.LineNumber
                    Match = $val
                }
            }
        }
    }
}

if ($hits) {
    Write-Host "FAIL: hardcoded user/machine path(s) found - portability regression:" -ForegroundColor Red
    $hits | ForEach-Object { Write-Host ("  {0}:{1}  ->  {2}" -f $_.File, $_.Line, $_.Match) -ForegroundColor Red }
    Write-Host 'Use $env:USERPROFILE (scripts) or a YOUR_USERNAME/<YOUR-HOME> placeholder (examples).' -ForegroundColor Yellow
    exit 1
}

Write-Host "PASS: no hardcoded user/machine paths in shipped files (placeholders + CHANGELOG history excluded)." -ForegroundColor Green
exit 0
