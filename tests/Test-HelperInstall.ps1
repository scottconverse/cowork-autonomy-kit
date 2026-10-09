$ErrorActionPreference = 'Stop'
$kit = Split-Path $PSScriptRoot -Parent
$installer = Join-Path $kit 'elevated-dev-helper\Install-ClaudeElevatedDevHelper.ps1'
$tokens = $null; $errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($installer, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($name in @('Install-HelperFiles','Wait-HelperJobResult')) {
    $function = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name }.GetNewClosure(), $true)
    if (-not $function) { throw "FAIL: installer lacks tested behavior $name" }
    . ([scriptblock]::Create($function.Extent.Text))
}
$sandbox = Join-Path $env:TEMP ('claude-helper-install-test-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $sandbox | Out-Null
$passed = 0
function Assert($condition, $message) {
    if (-not $condition) { throw "FAIL: $message" }
    $script:passed++
}
function Expect-Failure($action, $pattern) {
    $failure = $null
    try { & $action } catch { $failure = $_.Exception.Message }
    Assert ($failure -and $failure -match $pattern) "expected failure matching $pattern; got $failure"
}
try {
    $root = Join-Path $sandbox 'Custom Helper Root'
    New-Item -ItemType Directory -Path $root | Out-Null
    $files = Install-HelperFiles -SourceRoot (Join-Path $kit 'elevated-dev-helper') -InstallRoot $root
    Assert (Test-Path -LiteralPath $files.invoker_script) 'invoker installed'
    Assert ((Get-FileHash $files.invoker_script).Hash -eq (Get-FileHash (Join-Path $kit 'elevated-dev-helper\Invoke-ClaudeElevatedDevHelper.ps1')).Hash) 'installed invoker matches source'
    # Execute the installed invoker, stubbing only the external task trigger.
    function Start-ScheduledTask { param($TaskName) $global:helperInstallTestTriggeredTask = $TaskName }
    $windowsPath = 'C:\dev\Path With Spaces\test.ps1'
    $queued = (& $files.invoker_script -Action RunTrustedPowerShellScript -Root $root -TaskName 'CustomHelperTask' -ScriptPath $windowsPath | Out-String) | ConvertFrom-Json
    $job = Get-Content -LiteralPath $queued.job_path -Raw | ConvertFrom-Json
    Assert ($job.scriptPath -ceq $windowsPath) 'Windows path round-trips through installed invoker'
    Assert ($global:helperInstallTestTriggeredTask -eq 'CustomHelperTask') 'custom task forwarded'
    foreach ($dir in @('done','failed')) { New-Item -ItemType Directory -Path (Join-Path $root $dir) | Out-Null }
    $ok = @{status='ok';result=@{exit_code=0;stdout='marker'}} | ConvertTo-Json -Depth 4
    $ok | Set-Content -LiteralPath (Join-Path $root 'done\success.result.json')
    $result = Wait-HelperJobResult -Root $root -JobId 'success' -TimeoutSeconds 1 -RequireExitCode
    Assert ($result.result.stdout -eq 'marker') 'valid result accepted'
    @{status='ok';result=@{exit_code=7}} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'done\nonzero.result.json')
    Expect-Failure { Wait-HelperJobResult -Root $root -JobId 'nonzero' -TimeoutSeconds 1 -RequireExitCode } 'exit code'
    @{status='ok';result=@{}} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'done\missing.result.json')
    Expect-Failure { Wait-HelperJobResult -Root $root -JobId 'missing' -TimeoutSeconds 1 -RequireExitCode } 'exit code'
    @{status='failed';error='deliberate failure'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $root 'failed\failure.error.json')
    Expect-Failure { Wait-HelperJobResult -Root $root -JobId 'failure' -TimeoutSeconds 1 } 'deliberate failure'
    Expect-Failure { Wait-HelperJobResult -Root $root -JobId 'absent' -TimeoutSeconds 0 } 'timed out'
    @{status='ok';result=@{is_admin=$false}} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $root 'done\not-admin.result.json')
    Expect-Failure { Wait-HelperJobResult -Root $root -JobId 'not-admin' -TimeoutSeconds 1 -RequireAdmin } 'administrator'
    $emptySource = Join-Path $sandbox 'incomplete-source'
    New-Item -ItemType Directory -Path $emptySource | Out-Null
    Copy-Item (Join-Path $kit 'elevated-dev-helper\ClaudeElevatedDevHelper.ps1') $emptySource
    Expect-Failure { Install-HelperFiles -SourceRoot $emptySource -InstallRoot $root } 'Missing'
    # Execute the production verification catch body with a deliberate failure.
    $verificationTry = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.TryStatementAst] -and $node.Body.Extent.Text -match '\$adminJob\s*=' }, $true)
    $body = $verificationTry.CatchClauses[0].Body.Extent.Text
    $failureHandler = [scriptblock]::Create("try { throw 'deliberate verification failure' } catch " + $body)
    $TaskName = 'CustomHelperTask'; $InstallRoot = $root
    $installLog = Join-Path $root 'install-log.txt'
    $warnings = New-Object System.Collections.Generic.List[string]
    $caught = $null
    try {
        & $failureHandler 3>&1 | ForEach-Object { $warnings.Add([string]$_) }
    } catch { $caught = $_.Exception.Message }
    Assert ($caught -eq 'deliberate verification failure') 'failure handler preserves original failure'
    $disclosure = $warnings -join "`n"
    Assert ($disclosure.Contains($TaskName) -and $disclosure.Contains('remains registered')) 'retained task explicitly disclosed'
    Assert ($disclosure.Contains($InstallRoot) -and $disclosure.Contains($installLog)) 'retained files and log location disclosed'

    . (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
    Import-ProductionFunctions $installer @('New-HelperAcl','Set-VerifiedHelperAcl','Initialize-DevelopmentRoot')
    $testSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $queueAcl=New-HelperAcl -UserSid $testSid -Kind Queue
    $readAcl=New-HelperAcl -UserSid $testSid -Kind ReadFile
    $codeAcl=New-HelperAcl -UserSid $testSid -Kind Code
    Assert $queueAcl.AreAccessRulesProtected 'queue inheritance disabled'
    $userQueue=@($queueAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $testSid })
    Assert (($userQueue[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::Modify) -eq [Security.AccessControl.FileSystemRights]::Modify) 'queue user Modify'
    $userRead=@($readAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq $testSid })
    Assert (($userRead[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write) -eq 0) 'state user cannot write'
    $ordinary=@($codeAcl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544') })
    Assert (@($ordinary | Where-Object { $_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write }).Count -eq 0) 'program directory has no ordinary-user write grant'
    function Set-Acl { param($LiteralPath,$AclObject,$ErrorAction) $script:writtenAcl=$AclObject }
    function Get-Acl { param($LiteralPath,$ErrorAction) $script:writtenAcl }
    Set-VerifiedHelperAcl -Path 'test' -UserSid $testSid -Kind Queue
    Assert ($null -ne $script:writtenAcl) 'production ACL write/readback succeeds for matching ACL'
    function Get-Acl { param($LiteralPath,$ErrorAction) New-HelperAcl -UserSid $testSid -Kind ReadDirectory }
    Expect-Failure { Set-VerifiedHelperAcl -Path 'test' -UserSid $testSid -Kind Queue } 'ACL verification failed'
    function Get-Acl { param($LiteralPath,$ErrorAction) New-HelperAcl -UserSid $testSid -Kind Code }
    $readOnlyWarnings = @(Initialize-DevelopmentRoot -Path $sandbox -UserSid $testSid 3>&1 | Where-Object { $_ -is [Management.Automation.WarningRecord] })
    Assert ($readOnlyWarnings.Count -eq 0) 'read-only Users grant is not mistaken for write access'
    function Get-Acl { param($LiteralPath,$ErrorAction) New-HelperAcl -UserSid 'S-1-5-11' -Kind Queue }
    $broadWarnings = @(Initialize-DevelopmentRoot -Path $sandbox -UserSid $testSid 3>&1 | Where-Object { $_ -is [Management.Automation.WarningRecord] })
    Assert ($broadWarnings.Count -eq 1 -and $broadWarnings[0].Message.Contains('S-1-5-11')) 'broad development-root writer is warned about without changing ACL'
    Import-ProductionFunctions (Join-Path $kit 'elevated-dev-helper\ClaudeElevatedDevHelper.ps1') @('Write-JsonLog','Complete-QueueFile','Invoke-HelperQueue','Assert-TrustedPath')
    $drain=Join-Path $sandbox 'drain'
    foreach ($dir in @('queue','done','failed','logs')) { New-Item -ItemType Directory -Path (Join-Path $drain $dir) -Force | Out-Null }
    [IO.File]::WriteAllText((Join-Path $drain 'queue\first.json'),'{{"action":"CheckAdmin"}}'.Replace('{{','{').Replace('}}','}'))
    $script:queueCalls=0
    function Invoke-HelperAction {
        param($Job)
        $script:queueCalls++
        if ($script:queueCalls -eq 1) { [IO.File]::WriteAllText((Join-Path $drain 'queue\second.json'),'{"action":"CheckAdmin"}') }
        return @{ok=$true}
    }
    Invoke-HelperQueue -Root $drain
    Assert ($script:queueCalls -eq 2 -and @(Get-ChildItem (Join-Path $drain 'queue') -Filter *.json).Count -eq 0) 'real worker drains arrivals during an active job'
    Assert ((Get-Content (Join-Path $drain 'done\second.result.json') -Raw | ConvertFrom-Json).status -eq 'ok') 'second arrival completed serially'
    Expect-Failure { Assert-TrustedPath (Join-Path $env:USERPROFILE '.claude\unsafe.ps1') } 'not under a trusted'
    Expect-Failure { Assert-TrustedPath (Join-Path $env:TEMP 'unsafe.ps1') } 'not under a trusted'
    Assert ((Assert-TrustedPath 'C:\dev\Example\x.ps1') -eq 'C:\dev\Example\x.ps1') 'development root retained'
    Write-Host "SUMMARY: $passed PASS / 0 FAIL"
} finally {
    Remove-Variable -Name helperInstallTestTriggeredTask -Scope Global -ErrorAction SilentlyContinue
    $resolved = [System.IO.Path]::GetFullPath($sandbox)
    if (-not $resolved.StartsWith([System.IO.Path]::GetFullPath($env:TEMP) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
