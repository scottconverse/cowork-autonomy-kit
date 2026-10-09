$ErrorActionPreference='Stop'
$kit=Split-Path $PSScriptRoot -Parent
function Find-HardcodedUserPath {
    param([string]$Text)
    foreach ($match in [regex]::Matches($Text,'(?i)C:[\\/]+Users[\\/]+([^\\/\s"''<>]+)')) {
        if ($match.Groups[1].Value -notmatch '^(YOUR_USERNAME|YOUR-HOME)$') { $match.Value }
    }
}
$forward='C:'+'/Users/'+'sample-user/private.txt'
if (@(Find-HardcodedUserPath $forward).Count -ne 1) { throw 'FAIL: forward-slash sample not detected' }
$hits=@()
$names=@(& git -C $kit ls-files)
if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed' }
foreach ($name in $names) {
    if ($name -in @('CHANGELOG.md','tests/Test-NoHardcodedPaths.ps1')) { continue }
    $file=Join-Path $kit $name
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
    $bytes=[IO.File]::ReadAllBytes($file)
    if ($bytes -contains 0) { continue }
    $text=[Text.Encoding]::UTF8.GetString($bytes)
    foreach ($hit in @(Find-HardcodedUserPath $text)) { $hits += "$name : $hit" }
}
if ($hits.Count) { throw ('FAIL: hardcoded paths: '+($hits -join '; ')) }
Write-Host 'PASS: all tracked text files scanned, including forward-slash sample proof'
