$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
$kit = Split-Path $PSScriptRoot -Parent
Import-ConfigurationFunctions $kit
Import-ProductionFunctions (Join-Path $kit 'Setup-Autonomy.ps1') @('Get-RegisteredKitHelper','Test-InstalledHelperCurrent','Assert-KitSetupSucceeded')
Import-ProductionFunctions (Join-Path $kit 'Uninstall-Autonomy.ps1') @('Get-KitRemovalTaskNames')
Import-ProductionFunctions (Join-Path $kit 'elevated-dev-helper\Install-ClaudeElevatedDevHelper.ps1') @('Resolve-HelperInstallConfiguration')
Import-ProductionFunctions (Join-Path $kit 'elevated-dev-helper\ClaudeElevatedDevHelper.ps1') @('ConvertTo-WindowsArgument','Invoke-LoggedProcess','Write-HelperResult')
$sandbox = Join-Path $env:TEMP ('claude-audit-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$failures = @(); $passed = 0
function Check($condition, $message) {
    if ($condition) { $script:passed++; Write-Host "PASS: $message" }
    else { $script:failures += $message; Write-Host "FAIL: $message" }
}
try {
    foreach ($case in @(@{report=@{python3='missing (open a new shell)'};failed=@()},@{report=@{python3='OK'};failed=@('Chromium browser installation')})) {
        $failure = $null
        try { Assert-KitSetupSucceeded -Report $case.report -FailedSteps $case.failed } catch { $failure = $_.Exception.Message }
        Check ($failure -like 'Setup incomplete*') 'Setup refuses success when required tools or browser installation failed'
    }
    Assert-KitSetupSucceeded -Report @{python3='OK'} -FailedSteps @()
    Check $true 'successful toolchain report remains successful'
    # A real Windows child receives the actual ProcessStartInfo command line.
    $echo = Join-Path $sandbox 'Argument Echo.exe'
    Add-Type -TypeDefinition 'using System; using System.Text; public class ArgumentEcho { public static void Main(string[] args) { foreach (string arg in args) Console.WriteLine(Convert.ToBase64String(Encoding.UTF8.GetBytes(arg))); } }' -OutputAssembly $echo -OutputType ConsoleApplication
    $expected = @('two words','embedded"quote','','C:\space path\','C:\plain\')
    $result = Invoke-LoggedProcess -FilePath $echo -Arguments $expected -TimeoutSeconds 10
    $lines = @($result.stdout -split '\r?\n')
    $roundtrip = @($lines | Select-Object -First $expected.Count | ForEach-Object { [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($_)) })
    Check ($result.exit_code -eq 0 -and ($roundtrip -join '|') -ceq ($expected -join '|')) 'quoted, empty and trailing-backslash arguments reach the child unchanged'
    Import-ProductionFunctions (Join-Path $kit 'elevated-dev-helper\ClaudeElevatedDevHelper.ps1') @('Invoke-HelperAction')
    # Only trust-root policy is stubbed; execute the production action and real powershell.exe.
    function Assert-TrustedPath { param($Path) return $Path }
    $scriptProbe = Join-Path $sandbox 'PowerShell Argument Probe.ps1'
    [IO.File]::WriteAllText($scriptProbe, 'param([string]$One,[string]$Two,[string]$Three,[string]$Four,[string]$Five)' + "`r`n" + '@($One,$Two,$Three,$Four,$Five) | ConvertTo-Json -Compress')
    $scriptResult = Invoke-HelperAction -Job ([pscustomobject]@{action='RunTrustedPowerShellScript';scriptPath=$scriptProbe;arguments=$expected})
    $scriptRoundtrip = $scriptResult.stdout | ConvertFrom-Json
    Check ($scriptResult.exit_code -eq 0 -and ($scriptRoundtrip -join '|') -ceq ($expected -join '|')) 'real PowerShell script receives quoted, empty and trailing-backslash arguments unchanged'
    $published = Join-Path $sandbox 'atomic.result.json'
    Write-HelperResult -Path $published -Value @{status='ok';result=@{stdout=('large result ' * 50000)}}
    Check ((Get-Content -LiteralPath $published -Raw | ConvertFrom-Json).result.stdout.Length -eq 650000) 'large result JSON published completely'
    Check (@(Get-ChildItem -LiteralPath $sandbox -Filter '*.tmp').Count -eq 0 -and [IO.File]::ReadAllBytes($published)[0] -ne 239) 'atomic publication leaves no temp files or BOM'
    $originalHash = (Get-FileHash -LiteralPath $published).Hash; $collision = $false
    try { Write-HelperResult -Path $published -Value @{status='replacement'} } catch { $collision = $true }
    Check ($collision -and (Get-FileHash -LiteralPath $published).Hash -eq $originalHash -and @(Get-ChildItem -LiteralPath $sandbox -Filter '*.tmp').Count -eq 0) 'result collision preserves existing history and cleans temporary file'
    function Start-ScheduledTask { param($TaskName) }
    $invoker = Join-Path $kit 'elevated-dev-helper\Invoke-ClaudeElevatedDevHelper.ps1'
    $queued = (& $invoker -Root $sandbox -TaskName 'IsolatedTest' -Action RunTrustedPowerShellScript -ScriptPath 'C:\dev\test.ps1' -Arguments @('') | Out-String) | ConvertFrom-Json
    $emptyJob = Get-Content -LiteralPath $queued.job_path -Raw | ConvertFrom-Json
    Check ($emptyJob.arguments.Count -eq 1 -and $emptyJob.arguments[0] -ceq '') 'invoker preserves an explicitly supplied empty argument'
    Remove-Item function:Start-ScheduledTask

    $helperSource = Join-Path $kit 'elevated-dev-helper'
    $statePath = Join-Path $sandbox 'install-state.json'
    $worker = Join-Path $helperSource 'ClaudeElevatedDevHelper.ps1'
    $state = @{installed=$true;task_name='IsolatedTest';install_root=$helperSource;data_root=$sandbox;helper_script=$worker;invoker_script=$invoker}
    $state | ConvertTo-Json | Set-Content -LiteralPath $statePath
    function Get-ScheduledTask { param($TaskName,$ErrorAction) return $TaskName }
    Check ((Get-RegisteredKitHelper -StatePath $statePath) -eq 'IsolatedTest') 'Setup discovers the recorded custom task name'
    Check ((Get-KitRemovalTaskNames -StatePath $statePath -RemoveHelper) -contains 'IsolatedTest') 'helper removal targets the recorded custom task name'
    Check (@(Get-KitRemovalTaskNames -StatePath $statePath).Count -eq 1) 'ordinary rollback retains the custom helper task'
    Remove-Item function:Get-ScheduledTask
    $task = [pscustomobject]@{TaskName='IsolatedTest';Principal=[pscustomobject]@{RunLevel='Highest'};Settings=[pscustomobject]@{MultipleInstances='IgnoreNew'};Actions=@([pscustomobject]@{Execute='powershell.exe';Arguments=('-NoProfile -ExecutionPolicy Bypass -File "'+$worker+'" -Root "'+$sandbox+'"')})}
    Check (Test-InstalledHelperCurrent -Task $task -StatePath $statePath -SourceRoot $helperSource) 'matching verified helper can be skipped'
    $state.installed=$false; $state | ConvertTo-Json | Set-Content -LiteralPath $statePath
    Check (-not (Test-InstalledHelperCurrent -Task $task -StatePath $statePath -SourceRoot $helperSource)) 'failed helper self-test forces repair'
    $state.installed=$true; $state | ConvertTo-Json | Set-Content -LiteralPath $statePath
    $task.Actions[0].Arguments='-File "C:\dev\old-helper.ps1"'
    Check (-not (Test-InstalledHelperCurrent -Task $task -StatePath $statePath -SourceRoot $helperSource)) 'legacy helper task forces migration'
    Check (-not (Test-InstalledHelperCurrent -Task $task -StatePath (Join-Path $sandbox 'missing-state') -SourceRoot $helperSource)) 'registration without state never counts as installed'

    $oldKit = Join-Path $sandbox 'old-kit'; New-Item -ItemType Directory -Path (Join-Path $oldKit 'hooks') -Force | Out-Null
    foreach ($name in @('CLAUDE-Cowork-Core.md','CLAUDE-Cowork-Autonomous-Software-Development.md','settings.autonomy.example.json','hooks\notify-turn-ended.ps1')) {
        Copy-Item -LiteralPath (Join-Path $kit $name) -Destination (Join-Path $oldKit $name)
    }
    [IO.File]::WriteAllText((Join-Path $oldKit 'CLAUDE-Cowork-Core.md'),'Old kit core')
    $profile = Join-Path $sandbox 'profile'
    Install-KitConfiguration -KitRoot $oldKit -ClaudeRoot $profile
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $profile
    Check ((Get-FileHash (Join-Path $profile 'CLAUDE.md')).Hash -eq (Get-FileHash (Join-Path $kit 'CLAUDE-Cowork-Core.md')).Hash) 'unchanged kit-owned live profile upgrades to current source'
    Add-Content -LiteralPath (Join-Path $profile 'CLAUDE.md') -Value 'Owner customization'
    $customHash = (Get-FileHash (Join-Path $profile 'CLAUDE.md')).Hash
    Install-KitConfiguration -KitRoot $oldKit -ClaudeRoot $profile
    Check ((Get-FileHash (Join-Path $profile 'CLAUDE.md')).Hash -eq $customHash) 'customized profile survives an upgrade'
    $original = Join-Path $sandbox 'rollback'; New-Item -ItemType Directory -Path $original | Out-Null
    $originalSettings = Join-Path $original 'settings.json'
    [IO.File]::WriteAllText($originalSettings,'{"theme":"original"}')
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $original
    [IO.File]::WriteAllText($originalSettings,'{"theme":"later-owner-change"}')
    $laterHash = (Get-FileHash -LiteralPath $originalSettings).Hash
    Uninstall-KitConfiguration -ClaudeRoot $original -WhatIf
    Check (@(Get-ChildItem -LiteralPath $original -Filter '*.before-uninstall-*.bak').Count -eq 0) 'rollback WhatIf creates no recovery backups'
    Uninstall-KitConfiguration -ClaudeRoot $original
    $recovery = @(Get-ChildItem -LiteralPath $original -Filter 'settings.json.before-uninstall-*.bak')
    Check ($recovery.Count -eq 1 -and (Get-FileHash -LiteralPath $recovery[0].FullName).Hash -eq $laterHash) 'rollback retains later owner edits in an exact recovery backup'

    foreach ($json in @('{"hooks":{"Stop":"invalid"}}','{"hooks":{"Stop":[{"hooks":"invalid"}]}}','{"permissions":{"deny":"Read(secret)"}}')) {
        $broken = Join-Path $sandbox ([guid]::NewGuid().ToString('n')); New-Item -ItemType Directory -Path $broken | Out-Null
        $settings = Join-Path $broken 'settings.json'; [IO.File]::WriteAllText($settings,$json)
        $caught = $null
        try { Install-KitConfiguration -KitRoot $kit -ClaudeRoot $broken } catch { $caught = $_.Exception.Message }
        Check ($caught -like '*Invalid settings file*' -and @(Get-ChildItem -LiteralPath $broken).Count -eq 1) "invalid nested settings rejected before writes: $json"
    }

    $savedProfile = $env:USERPROFILE; $savedData = $env:ProgramData
    try {
        $env:USERPROFILE = Join-Path $sandbox 'doctor'; $env:ProgramData = Join-Path $sandbox 'doctor-data'
        $paths = Resolve-HelperInstallConfiguration -InstallRoot 'C:\Custom Code' -DataRoot 'C:\Custom Data' -TaskName 'CustomClaude' -ExplicitParameters @('InstallRoot','DataRoot','TaskName')
        Check ($paths.StatePath -eq (Join-Path $env:ProgramData 'ClaudeElevatedHelper\install-state.json') -and $paths.DataRoot -eq 'C:\Custom Data') 'custom data root keeps the canonical invoker/Doctor discovery record'
        New-Item -ItemType Directory -Path (Split-Path -Parent $paths.StatePath) -Force | Out-Null
        @{install_root='C:\Custom Code';data_root='C:\Custom Data';task_name='CustomClaude'} | ConvertTo-Json | Set-Content -LiteralPath $paths.StatePath
        $paths = Resolve-HelperInstallConfiguration -InstallRoot 'C:\Default Code' -DataRoot 'C:\Default Data' -TaskName 'DefaultClaude' -ExplicitParameters @()
        Check ($paths.InstallRoot -eq 'C:\Custom Code' -and $paths.DataRoot -eq 'C:\Custom Data' -and $paths.TaskName -eq 'CustomClaude') 'repair preserves recorded custom roots and task name'
        $paths = Resolve-HelperInstallConfiguration -InstallRoot 'C:\Replacement Code' -DataRoot 'C:\Default Data' -TaskName 'DefaultClaude' -ExplicitParameters @('InstallRoot')
        Check ($paths.InstallRoot -eq 'C:\Replacement Code' -and $paths.DataRoot -eq 'C:\Custom Data') 'explicit path override changes only its requested field'
        New-Item -ItemType Directory -Path (Join-Path $env:USERPROFILE '.claude') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $env:USERPROFILE '.claude\settings.json'),'{}')
        function Get-ScheduledTask { param($TaskName,$ErrorAction) throw 'test: no task' }
        $doctor = & (Join-Path $kit 'Doctor-Autonomy.ps1') *>&1 | Out-String
        foreach ($label in @('ask entries','deny entries','allow entries','additionalDirs')) {
            Check ($doctor -match ([regex]::Escape($label)+'\s+0\b')) "Doctor reports zero for missing $label"
        }
    } finally { $env:USERPROFILE = $savedProfile; $env:ProgramData = $savedData; Remove-Item function:Get-ScheduledTask }
    Write-Host "SUMMARY: $passed PASS / $($failures.Count) FAIL"
    if ($failures.Count) { throw ($failures -join '; ') }
} finally { Remove-TestRoot $sandbox }
