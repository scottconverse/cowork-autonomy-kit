param([string]$InterruptRestoreRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
$kit=Split-Path $PSScriptRoot -Parent
Import-ConfigurationFunctions $kit
. (Join-Path $kit 'lib/AutonomySettings.ps1')
if ($InterruptRestoreRoot) {
    $savedManifestWriter=${function:Write-KitManifest}
    function Write-KitManifest {
        param([string]$ClaudeRoot,$Manifest)
        & $savedManifestWriter $ClaudeRoot $Manifest
        if ($Manifest.Operations[-1].Files[0].State -eq 'restored') { exit 77 }
    }
    Restore-KitSettingsOperation -ClaudeRoot $InterruptRestoreRoot
    exit 0
}
$passed=0
$sandbox=Join-Path $env:TEMP ('claude-recovery-'+[guid]::NewGuid().ToString('n'))
[void][IO.Directory]::CreateDirectory($sandbox)
try {
    $root=Join-Path $sandbox 'user'; $project=Join-Path $sandbox 'project'
    [void][IO.Directory]::CreateDirectory($root); [void][IO.Directory]::CreateDirectory((Join-Path $project '.claude'))
    $user=Join-Path $root 'settings.json'; $shared=Join-Path $project '.claude/settings.json'
    $original='{"permissions":{"deny":["Read(secret)"]},"custom":"original"}'
    [IO.File]::WriteAllText($user,$original); [IO.File]::WriteAllText($shared,$original)
    $plan=@(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project)
    if (Get-Command Invoke-KitSettingsOperation -ErrorAction SilentlyContinue) { Invoke-KitSettingsOperation -ClaudeRoot $root -Plan $plan | Out-Null }
    Assert-Kit ((Read-KitSettings $user).permissions.deny.Count -eq 0) 'operation commits planned user settings'
    $manifest=Read-KitManifest $root
    Assert-Kit ($manifest.Operations.Count -eq 1 -and $manifest.Operations[0].State -eq 'completed') 'completed operation recorded'
    foreach ($entry in $manifest.Operations[0].Files) {
        Assert-Kit ((Get-KitFileHash $entry.BackupPath) -eq $entry.OriginalHash -and (Get-Content $entry.BackupPath -Raw) -ceq $original) 'exact original bytes and hash recorded'
    }
    $count=@(Get-ChildItem $root -Recurse -File).Count; $hash=Get-KitFileHash $user
    Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project) | Out-Null
    Assert-Kit ((Get-KitFileHash $user) -eq $hash -and @(Get-ChildItem $root -Recurse -File).Count -eq $count -and (Read-KitManifest $root).Operations.Count -eq 1) 'repeat is byte and history no-op'
    $before=@(Get-ChildItem $sandbox -Recurse -File | ForEach-Object { $_.FullName+':'+(Get-KitFileHash $_.FullName) }) -join "`n"
    Restore-KitSettingsOperation -ClaudeRoot $root -WhatIf
    $after=@(Get-ChildItem $sandbox -Recurse -File | ForEach-Object { $_.FullName+':'+(Get-KitFileHash $_.FullName) }) -join "`n"
    Assert-Kit ($before -ceq $after) 'WhatIf makes zero file or manifest writes'
    [IO.File]::WriteAllText($user,'{"later":"edit"}')
    Restore-KitSettingsOperation -ClaudeRoot $root
    Assert-Kit ((Get-Content $user -Raw) -ceq $original -and (Get-Content $shared -Raw) -ceq $original) 'last restore returns exact pre-operation files'
    Assert-Kit (@(Get-ChildItem $root -Filter '*.before-restore-*.bak' | Where-Object { (Get-Content $_.FullName -Raw) -eq '{"later":"edit"}' }).Count -eq 1) 'later edit preserved before full-file restore'
    $count=@(Get-ChildItem $sandbox -Recurse -File).Count
    Restore-KitSettingsOperation -ClaudeRoot $root
    Assert-Kit (@(Get-ChildItem $sandbox -Recurse -File).Count -eq $count) 'repeat restore does not walk history'
    # Inject a replacement failure at the production file-writing seam.
    $saved=${function:Write-KitAtomicBytes}
    $script:replacements=0
    function Write-KitAtomicBytes {
        param([string]$Path,[byte[]]$Bytes,$ExpectedHash)
        if ($Path -eq $shared) { throw 'injected replacement failure' }
        & $saved @PSBoundParameters
    }
    $failed=$false
    try { Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project) } catch { $failed=$_.Exception.Message -like '*injected replacement failure*' }
    Set-Item function:Write-KitAtomicBytes $saved
    Assert-Kit ($failed -and (Get-Content $user -Raw) -ceq $original -and (Get-Content $shared -Raw) -ceq $original) 'mid-operation failure restores already replaced file'
    Assert-Kit ((Read-KitManifest $root).Operations[-1].State -eq 'recovered') 'recovery state recorded truthfully'
    $savedManifestWriter=${function:Write-KitManifest}
    function Write-KitManifest {
        param([string]$ClaudeRoot,$Manifest)
        if ($Manifest.Operations[-1].State -eq 'completed') { throw 'injected completion-manifest failure' }
        & $savedManifestWriter $ClaudeRoot $Manifest
    }
    $failed=$false
    try { Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project) } catch { $failed=$_.Exception.Message -like '*injected completion-manifest failure*' }
    Set-Item function:Write-KitManifest $savedManifestWriter
    Assert-Kit ($failed -and (Get-Content $user -Raw) -ceq $original -and (Read-KitManifest $root).Operations[-1].State -eq 'recovered') 'failed final manifest persistence really recovers live writes'

    function Write-KitAtomicBytes {
        param([string]$Path,[byte[]]$Bytes,$ExpectedHash)
        if ($Path -eq $shared) { [IO.File]::WriteAllText($user,'{"concurrent":"keep"}'); throw 'injected concurrent edit' }
        & $saved @PSBoundParameters
    }
    $failed=$false
    try { Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project) } catch { $failed=$_.Exception.Message -like '*Recovery incomplete*' }
    Set-Item function:Write-KitAtomicBytes $saved
    Assert-Kit ($failed -and (Get-Content $user -Raw) -eq '{"concurrent":"keep"}' -and (Read-KitManifest $root).Operations[-1].State -eq 'recovery-incomplete') 'automatic recovery never overwrites a concurrent edit'
    [IO.File]::WriteAllText($user,$original)
    try { Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @() } catch { Assert-Kit ($_.Exception.Message -like '*Previous operation recovered*') 'pending operation recovers from exact original hashes' }
    Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project)
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -InterruptRestoreRoot $root
    Assert-Kit ($LASTEXITCODE -eq 77 -and (Read-KitManifest $root).Operations[-1].State -eq 'restore-incomplete') 'abrupt exit during restore leaves durable pending state'
    $failed=$false
    try { Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @() } catch { $failed=$_.Exception.Message -like '*interrupted restore*' }
    Assert-Kit ($failed) 'even empty plans cannot bypass pending restore'
    Restore-KitSettingsOperation -ClaudeRoot $root
    Assert-Kit ((Get-Content $user -Raw) -ceq $original -and (Get-Content $shared -Raw) -ceq $original -and -not (Read-KitManifest $root).RestorePending) 'interrupted restore resumes to exact originals'

    # Two projects retain separate first-touch baselines across later operations.
    Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project)
    $project2=Join-Path $sandbox 'project2'; [void][IO.Directory]::CreateDirectory((Join-Path $project2 '.claude'))
    $shared2=Join-Path $project2 '.claude/settings.json'; [IO.File]::WriteAllText($shared2,'{"permissions":{"ask":["Bash"]}}')
    Invoke-KitSettingsOperation -ClaudeRoot $root -Plan @(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project2)
    Assert-Kit ((Read-KitManifest $root).Baselines.Count -eq 3) 'first-touch baselines retained across projects and reruns'
    Restore-KitSettingsOperation -ClaudeRoot $root
    Assert-Kit ((Read-KitSettings $shared2).permissions.ask.Count -eq 1 -and (Read-KitSettings $shared).permissions.deny.Count -eq 0) 'last restore affects only latest operation project'
    Restore-KitSettingsOperation -ClaudeRoot $root -Baseline
    Assert-Kit ((Get-Content $user -Raw) -ceq $original -and (Get-Content $shared -Raw) -ceq $original) 'baseline restore reaches first-touch state for earlier project'
    $held=Open-KitOperationLock $root
    try {
        $failed=$false
        try { Install-KitConfiguration -KitRoot $kit -ClaudeRoot $root } catch { $failed=$_.Exception.Message -like '*holds*lock*' }
        Assert-Kit ($failed -and (Get-Content $user -Raw) -ceq $original) 'overlapping Setup fails without replacing settings'
        $failed=$false
        try { Uninstall-KitConfiguration -ClaudeRoot $root } catch { $failed=$_.Exception.Message -like '*holds*lock*' }
        Assert-Kit ($failed -and (Test-Path (Join-Path $root 'autonomy-kit/settings-history.json'))) 'overlapping Uninstall cannot delete recovery state'
    } finally { $held.Dispose() }

    $upgrade=Join-Path $sandbox 'legacy-upgrade'; [void][IO.Directory]::CreateDirectory($upgrade)
    $upgradeUser=Join-Path $upgrade 'settings.json'
    [IO.File]::WriteAllText("$upgradeUser.pre-autonomy-kit",$original)
    [IO.File]::WriteAllText($upgradeUser,(ConvertTo-KitJson (Merge-KitSettings -Settings ([pscustomobject]@{}) -ClaudeRoot $upgrade)))
    Invoke-KitSettingsOperation -ClaudeRoot $upgrade -Plan @(New-KitSettingsPlan -ClaudeRoot $upgrade -ProjectRoot $project2)
    Uninstall-KitConfiguration -ClaudeRoot $upgrade
    Assert-Kit ((Get-Content $upgradeUser -Raw) -ceq $original) 'project-only manifest does not skip legacy user baseline on uninstall'

    $corrupt=Join-Path $sandbox 'corrupt'; [void][IO.Directory]::CreateDirectory($corrupt)
    $corruptUser=Join-Path $corrupt 'settings.json'; [IO.File]::WriteAllText($corruptUser,$original)
    Invoke-KitSettingsOperation -ClaudeRoot $corrupt -Plan @(New-KitSettingsPlan -ClaudeRoot $corrupt)
    $entry=(Read-KitManifest $corrupt).Operations[-1].Files[0]
    [IO.File]::WriteAllText($entry.BackupPath,'corrupt')
    $liveHash=Get-KitFileHash $corruptUser; $failed=$false
    try { Restore-KitSettingsOperation -ClaudeRoot $corrupt } catch { $failed=$_.Exception.Message -like '*Missing/corrupt backup*' }
    Assert-Kit ($failed -and (Get-KitFileHash $corruptUser) -eq $liveHash) 'corrupt exact backup cannot overwrite live settings'
    [IO.File]::Delete($entry.BackupPath); $failed=$false
    try { Restore-KitSettingsOperation -ClaudeRoot $corrupt } catch { $failed=$_.Exception.Message -like '*Missing/corrupt backup*' }
    Assert-Kit ($failed -and (Get-KitFileHash $corruptUser) -eq $liveHash) 'missing backup fails without writes'
    $movedRoot=Join-Path $sandbox 'missing-project-user'; [void][IO.Directory]::CreateDirectory($movedRoot)
    $movedProject=Join-Path $sandbox 'missing-project'; [void][IO.Directory]::CreateDirectory((Join-Path $movedProject '.claude'))
    [IO.File]::WriteAllText((Join-Path $movedProject '.claude/settings.json'),$original)
    Invoke-KitSettingsOperation -ClaudeRoot $movedRoot -Plan @(New-KitSettingsPlan -ClaudeRoot $movedRoot -ProjectRoot $movedProject)
    [IO.Directory]::Move($movedProject,($movedProject+'-moved'))
    $failed=$false
    try { Restore-KitSettingsOperation -ClaudeRoot $movedRoot -Baseline } catch { $failed=$_.Exception.Message -like '*Missing/moved parent directory*' }
    Assert-Kit ($failed -and -not (Test-Path $movedProject) -and (Read-KitManifest $movedRoot).RestorePending -eq 'baseline') 'missing project is not guessed or recreated and baseline recovery remains pending'
    $raceFile=Join-Path $sandbox 'late-edit.json'; [IO.File]::WriteAllText($raceFile,'{"new":"owner edit"}')
    $failed=$false
    try { Write-KitAtomicBytes -Path $raceFile -Bytes ([Text.Encoding]::UTF8.GetBytes('{}')) -ExpectedHash ('0'*64) } catch { $failed=$_.Exception.Message -like '*immediately before replacement*' }
    Assert-Kit ($failed -and (Get-Content $raceFile -Raw) -eq '{"new":"owner edit"}' -and @(Get-ChildItem $sandbox -Filter '*.tmp').Count -eq 0) 'atomic writer rechecks expected hash after preparing temp bytes and retains intervening edits'
    Write-Host "SUMMARY: $passed PASS / 0 FAIL"
} finally { Remove-TestRoot $sandbox }
