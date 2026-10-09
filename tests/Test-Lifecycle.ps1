$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
$kit=Split-Path $PSScriptRoot -Parent
Import-ConfigurationFunctions $kit
$passed=0; $sandbox=Join-Path $env:TEMP ('claude-lifecycle-'+[guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
try {
    $root=Join-Path $sandbox 'existing'; New-Item -ItemType Directory -Path $root | Out-Null
    $sp=Join-Path $root 'settings.json'; $md=Join-Path $root 'CLAUDE.md'
    [IO.File]::WriteAllText($sp,'{"permissions":{"defaultMode":"default"},"custom":"unchanged"}')
    [IO.File]::WriteAllText($md,'User instructions')
    $settingsHash=(Get-FileHash $sp).Hash; $mdHash=(Get-FileHash $md).Hash
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root
    Assert-Kit ((Get-FileHash "$sp.pre-autonomy-kit").Hash -eq $settingsHash) 'first snapshot not overwritten by rerun'
    Assert-Kit ((Get-FileHash $md).Hash -eq $mdHash) 'customized live instructions not overwritten'
    $before=(Get-FileHash $sp).Hash
    Uninstall-KitConfiguration -ClaudeRoot $root -WhatIf
    Assert-Kit ((Get-FileHash $sp).Hash -eq $before) 'snapshot restore WhatIf makes no writes'
    Assert-Kit (Test-Path (Join-Path $root 'autonomy-kit')) 'WhatIf keeps staging'
    Uninstall-KitConfiguration -ClaudeRoot $root
    $restored=Get-Content $sp -Raw | ConvertFrom-Json
    Assert-Kit ($restored.permissions.defaultMode -eq 'default' -and $restored.custom -eq 'unchanged') 'original settings restored'
    Assert-Kit (-not $restored.hooks) 'no kit hook remains'
    Assert-Kit ((Get-FileHash $sp).Hash -eq $settingsHash -and (Get-FileHash $md).Hash -eq $mdHash) 'exact user settings and instructions restored'
    Assert-Kit ([IO.File]::ReadAllBytes($sp)[0] -ne 239) 'restored settings have no BOM'
    $root=Join-Path $sandbox 'absent'
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root
    Assert-Kit (@(Get-Content (Join-Path $root 'CLAUDE.md')) -ccontains '@CLAUDE-Cowork-Autonomous-Software-Development.md') 'fresh Core has a real depth import'
    Uninstall-KitConfiguration -ClaudeRoot $root
    Assert-Kit (-not (Test-Path (Join-Path $root 'settings.json')) -and -not (Test-Path (Join-Path $root 'CLAUDE.md'))) 'originally absent kit-created files gone'
    $root=Join-Path $sandbox 'broken'; New-Item -ItemType Directory -Path $root | Out-Null
    $sp=Join-Path $root 'settings.json'; [IO.File]::WriteAllText($sp,'{broken-json')
    $hash=(Get-FileHash $sp).Hash; $failure=$null
    try { Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root } catch { $failure=$_.Exception.Message }
    Assert-Kit ($failure -like '*Invalid settings file*' -and $failure.Contains($sp)) 'bad settings clearly throw naming path'
    Assert-Kit ((Get-FileHash $sp).Hash -eq $hash -and @(Get-ChildItem $root).Count -eq 1) 'bad settings cause no file writes'
    $root=Join-Path $sandbox 'modified'
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root
    Add-Content (Join-Path $root 'CLAUDE.md') 'User change'
    $sp=Join-Path $root 'settings.json'; $s=Get-Content $sp -Raw | ConvertFrom-Json; $s | Add-Member custom 'later'; [IO.File]::WriteAllText($sp,($s | ConvertTo-Json -Depth 20))
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root
    Uninstall-KitConfiguration -ClaudeRoot $root
    Assert-Kit ((Test-Path $sp) -and (Test-Path (Join-Path $root 'CLAUDE.md'))) 'customized originally-absent files retained'
    Write-Host "SUMMARY: $passed PASS / 0 FAIL"
} finally { Remove-TestRoot $sandbox }
