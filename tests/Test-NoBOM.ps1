<#
.SYNOPSIS
    BOM guard -- fails if any shipped .json file (or the live ~/.claude/settings.json
    that Setup writes) starts with a UTF-8 BOM. Protects the v1.4.0 BOM-free fix from
    silent regression on future commits.

.DESCRIPTION
    Windows PowerShell 5.1's `Set-Content -Encoding UTF8` prepends a UTF-8 BOM
    (EF BB BF). Naive JSON consumers (python json.loads, many CI tools) reject
    BOM-prefixed input. Setup writes settings.json without BOM via
    [IO.File]::WriteAllText + UTF8Encoding($false); this test catches accidental
    reintroductions.

    Scans:
      - all .json files tracked under the kit
      - ~/.claude/settings.json if present (the install's output)

    Exit 0 = clean. Exit 1 = BOM found.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-NoBOM.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$kit = Split-Path $PSScriptRoot -Parent

function Has-Utf8Bom([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $fs = [System.IO.File]::Open($path, 'Open', 'Read')
    try {
        if ($fs.Length -lt 3) { return $false }
        $b = New-Object byte[] 3
        $null = $fs.Read($b, 0, 3)
        return ($b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
    } finally { $fs.Close() }
}

$jsonFiles = Get-ChildItem $kit -Recurse -File -Include *.json |
    Where-Object { $_.FullName -notlike '*\.git\*' }

$liveSettings = Join-Path $env:USERPROFILE ".claude\settings.json"

$candidates = @($jsonFiles | ForEach-Object { $_.FullName })
if (Test-Path -LiteralPath $liveSettings) { $candidates += $liveSettings }

$hits = foreach ($p in $candidates) {
    if (Has-Utf8Bom $p) { $p }
}

if ($hits) {
    Write-Host "FAIL: UTF-8 BOM found in JSON file(s):" -ForegroundColor Red
    $hits | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host 'Write JSON with [IO.File]::WriteAllText + [System.Text.UTF8Encoding]::new($false).' -ForegroundColor Yellow
    exit 1
}

Write-Host "PASS: no UTF-8 BOM in shipped JSON or live settings.json." -ForegroundColor Green
exit 0
