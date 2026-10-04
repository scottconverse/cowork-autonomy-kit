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
    Write-Host "SUMMARY: $passed PASS / 0 FAIL"
} finally {
    Remove-Variable -Name helperInstallTestTriggeredTask -Scope Global -ErrorAction SilentlyContinue
    $resolved = [System.IO.Path]::GetFullPath($sandbox)
    if (-not $resolved.StartsWith([System.IO.Path]::GetFullPath($env:TEMP) + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
