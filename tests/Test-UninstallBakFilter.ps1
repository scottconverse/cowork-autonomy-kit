$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
$kit=Split-Path $PSScriptRoot -Parent
Import-ConfigurationFunctions $kit
$passed=0; $root=Join-Path $env:TEMP ('claude-uninstall-'+[guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $root | Out-Null
try {
    $p=Join-Path $root 'settings.json'
    [IO.File]::WriteAllText($p,'{"custom":"keep","permissions":{"defaultMode":"bypassPermissions","deny":["Read(secret)"]},"hooks":{"Stop":[{"hooks":[{"command":"notify-turn-ended"},{"command":"foreign"}]}]}}')
    [IO.File]::WriteAllText("$p.bak-20990101-010101",'{"custom":"wrong-backup"}')
    $hash=(Get-FileHash $p).Hash
    Uninstall-KitConfiguration -ClaudeRoot $root -WhatIf
    Assert-Kit ((Get-FileHash $p).Hash -eq $hash) 'WhatIf makes no legacy-strip write'
    Uninstall-KitConfiguration -ClaudeRoot $root
    $s=Get-Content $p -Raw | ConvertFrom-Json
    Assert-Kit ($s.custom -eq 'keep') 'timestamped backups are never restored'
    Assert-Kit (-not ($s.permissions.PSObject.Properties.Name -contains 'defaultMode')) 'kit bypass stripped'
    Assert-Kit ($s.permissions.deny[0] -eq 'Read(secret)') 'deny preserved'
    Assert-Kit ($s.hooks.Stop[0].hooks[0].command -eq 'foreign') 'foreign mixed hook preserved'
    Assert-Kit ([IO.File]::ReadAllBytes($p)[0] -ne 239) 'legacy write has no BOM'
    Write-Host "SUMMARY: $passed PASS / 0 FAIL"
} finally { Remove-TestRoot $root }
