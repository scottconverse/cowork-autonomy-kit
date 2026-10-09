param(
    [string]$InstallRoot = (Join-Path $env:ProgramFiles "ClaudeElevatedHelper"),
    [string]$DataRoot = (Join-Path $env:ProgramData "ClaudeElevatedHelper"),
    [string]$TaskName = "ClaudeElevatedDevHelper"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Install-HelperFiles {
    param([string]$SourceRoot, [string]$InstallRoot)
    $names = @('ClaudeElevatedDevHelper.ps1', 'Invoke-ClaudeElevatedDevHelper.ps1', 'Test-InstalledHelperPath.ps1')
    foreach ($name in $names) {
        $sourceFile = Join-Path $SourceRoot $name
        if (-not (Test-Path -LiteralPath $sourceFile -PathType Leaf)) { throw "Missing helper installation file: $sourceFile" }
    }
    New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
    foreach ($name in $names) {
        Copy-Item -LiteralPath (Join-Path $SourceRoot $name) -Destination (Join-Path $InstallRoot $name) -Force
    }
    return @{
        helper_script = Join-Path $InstallRoot $names[0]
        invoker_script = Join-Path $InstallRoot $names[1]
        path_test_source = Join-Path $InstallRoot $names[2]
    }
}

function Wait-HelperJobResult {
    param([string]$Root, [string]$JobId, [int]$TimeoutSeconds = 30, [switch]$RequireAdmin, [switch]$RequireExitCode)
    $resultPath = Join-Path $Root "done\$JobId.result.json"
    $errorPath = Join-Path $Root "failed\$JobId.error.json"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-Path -LiteralPath $errorPath) {
            $failure = Get-Content -LiteralPath $errorPath -Raw | ConvertFrom-Json
            throw "Helper self-test failed: $($failure.error)"
        }
        if (Test-Path -LiteralPath $resultPath) {
            $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
            if ($result.status -ne 'ok') { throw "Helper self-test failed: status $($result.status)" }
            if ($RequireAdmin -and $result.result.is_admin -ne $true) { throw 'Helper self-test did not confirm administrator execution.' }
            if ($RequireExitCode -and ($null -eq $result.result.exit_code -or $result.result.exit_code -ne 0)) {
                throw "Helper self-test failed: child exit code $($result.result.exit_code); $($result.result.stderr)"
            }
            return $result
        }
        if ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 200 }
    } while ((Get-Date) -lt $deadline)
    throw "Helper self-test timed out after $TimeoutSeconds seconds: $JobId"
}

function Assert-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        throw "This installer must be run from an elevated PowerShell session."
    }
}

function New-HelperAcl {
    param([string]$UserSid, [ValidateSet('Code','ReadDirectory','Queue','ReadFile')][string]$Kind)
    $isFile = $Kind -eq 'ReadFile'
    $acl = if ($isFile) { New-Object Security.AccessControl.FileSecurity } else { New-Object Security.AccessControl.DirectorySecurity }
    $acl.SetAccessRuleProtection($true,$false)
    $acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
    $inherit = if ($isFile) { [Security.AccessControl.InheritanceFlags]::None } else { [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit' }
    foreach ($sid in @('S-1-5-32-544','S-1-5-18')) {
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($sid),'FullControl',$inherit,'None','Allow'))
    }
    $reader = if ($Kind -eq 'Code') { 'S-1-5-32-545' } else { $UserSid }
    $rights = if ($Kind -eq 'Queue') { 'Modify' } elseif ($isFile) { 'Read' } else { 'ReadAndExecute' }
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($reader),$rights,$inherit,'None','Allow'))
    return $acl
}

function Set-VerifiedHelperAcl {
    param([string]$Path, [string]$UserSid, [string]$Kind)
    $expected = New-HelperAcl -UserSid $UserSid -Kind $Kind
    Set-Acl -LiteralPath $Path -AclObject $expected -ErrorAction Stop
    $actual = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $sections = [Security.AccessControl.AccessControlSections]'Access,Owner'
    if ($actual.GetSecurityDescriptorSddlForm($sections) -ne $expected.GetSecurityDescriptorSddlForm($sections)) {
        throw "Helper ACL verification failed for $Path"
    }
}

function Initialize-HelperStorage {
    param([string]$InstallRoot,[string]$DataRoot,[string]$UserSid)
    if ([IO.Path]::GetFullPath($InstallRoot).TrimEnd('\') -eq [IO.Path]::GetFullPath($DataRoot).TrimEnd('\')) { throw 'Code and data roots must be separate' }
    foreach ($path in @($InstallRoot,$DataRoot)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
    # Protect parent directories before deploying executable code or registration.
    Set-VerifiedHelperAcl -Path $InstallRoot -UserSid $UserSid -Kind Code
    Set-VerifiedHelperAcl -Path $DataRoot -UserSid $UserSid -Kind ReadDirectory
    foreach ($name in @('queue','done','failed','logs')) {
        $path = Join-Path $DataRoot $name
        New-Item -ItemType Directory -Force -Path $path | Out-Null
        $kind = if ($name -eq 'queue') { 'Queue' } else { 'ReadDirectory' }
        Set-VerifiedHelperAcl -Path $path -UserSid $UserSid -Kind $kind
    }
}

function Initialize-DevelopmentRoot {
    param([string]$Path='C:\dev',[string]$UserSid)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
        $acl = New-HelperAcl -UserSid $UserSid -Kind Queue
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
        $actual = Get-Acl -LiteralPath $Path
        $sections = [Security.AccessControl.AccessControlSections]'Access,Owner'
        if ($actual.GetSecurityDescriptorSddlForm($sections) -ne $acl.GetSecurityDescriptorSddlForm($sections)) { throw "Development root ACL mismatch: $Path" }
        Write-Host "Created ${Path}: write access limited to Administrators, SYSTEM and installing user"
    } else {
        $allowed = @('S-1-5-32-544','S-1-5-18',$UserSid)
        $writeMask = [Security.AccessControl.FileSystemRights]'Write,Modify,FullControl,Delete,ChangePermissions,TakeOwnership'
        foreach ($rule in (Get-Acl -LiteralPath $Path).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -eq 'Allow' -and ($rule.FileSystemRights -band $writeMask) -and $allowed -notcontains $rule.IdentityReference.Value) {
                Write-Warning "Existing $Path permits writes by $($rule.IdentityReference.Value): $($rule.FileSystemRights). ACL left unchanged."
            }
        }
    }
}

Assert-Admin

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$userId = $identity.Name

$userSid = $identity.User.Value
Initialize-HelperStorage -InstallRoot $InstallRoot -DataRoot $DataRoot -UserSid $userSid
Initialize-DevelopmentRoot -UserSid $userSid
if (Test-Path -LiteralPath 'C:\dev\ClaudeElevatedHelper') {
    Write-Host 'Migrating task to Program Files and ProgramData. Check pending jobs before deleting old C:\dev\ClaudeElevatedHelper; this installer does not delete it.'
}
$files = Install-HelperFiles -SourceRoot $PSScriptRoot -InstallRoot $InstallRoot

foreach ($installed in @($files.helper_script,$files.invoker_script,$files.path_test_source)) {
    Set-VerifiedHelperAcl -Path $installed -UserSid $userSid -Kind ReadFile
}
$installLog = Join-Path $DataRoot 'install-log.txt'
"Installer running as $userId; elevated=True" | Add-Content -LiteralPath $installLog -Encoding UTF8
Set-VerifiedHelperAcl -Path $installLog -UserSid $userSid -Kind ReadFile

$target = $files.helper_script
$invokerTarget = $files.invoker_script

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$target`" -Root `"$DataRoot`""
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)

Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null

$state = @{
    installed = $false
    task_name = $TaskName
    install_root = $InstallRoot
    data_root = $DataRoot
    helper_script = $target
    invoker_script = $invokerTarget
    user_id = $userId
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
}
$statePath = Join-Path $DataRoot 'install-state.json'
$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
Set-VerifiedHelperAcl -Path $statePath -UserSid $userSid -Kind ReadFile

try {
    $adminJob = (& $invokerTarget -Root $DataRoot -TaskName $TaskName -Action CheckAdmin | Out-String) | ConvertFrom-Json
    $adminResult = Wait-HelperJobResult -Root $DataRoot -JobId $adminJob.job_id -RequireAdmin
    # IgnoreNew tasks may still be finishing after publishing a result. Wait before the next trigger.
    $idleDeadline = (Get-Date).AddSeconds(30)
    while ((Get-ScheduledTask -TaskName $TaskName).State -eq 'Running') {
        if ((Get-Date) -ge $idleDeadline) { throw 'Helper task did not become idle after administrator self-test.' }
        Start-Sleep -Milliseconds 200
    }
    $testDir = Join-Path $InstallRoot 'Self Test Path'
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    $testScript = Join-Path $testDir 'Windows Path Test.ps1'
    Copy-Item -LiteralPath $files.path_test_source -Destination $testScript -Force
    Set-VerifiedHelperAcl -Path $testDir -UserSid $userSid -Kind Code
    Set-VerifiedHelperAcl -Path $testScript -UserSid $userSid -Kind ReadFile
    $pathJob = (& $invokerTarget -Root $DataRoot -TaskName $TaskName -Action RunTrustedPowerShellScript -ScriptPath $testScript | Out-String) | ConvertFrom-Json
    $pathResult = Wait-HelperJobResult -Root $DataRoot -JobId $pathJob.job_id -RequireExitCode
    $pathOutput = $pathResult.result.stdout | ConvertFrom-Json
    if ($pathOutput.is_admin -ne $true -or $pathOutput.script_path -cne $testScript) { throw 'Installed invoker Windows-path self-test returned unexpected output.' }
    $state.installed = $true
    $state.admin_test_job = $adminJob.job_id
    $state.path_test_job = $pathJob.job_id
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
Set-VerifiedHelperAcl -Path $statePath -UserSid $userSid -Kind ReadFile
    "[$((Get-Date).ToUniversalTime().ToString('o'))] Administrator and Windows-path self-tests passed." | Add-Content -LiteralPath $installLog -Encoding UTF8
} catch {
    Write-Warning "Verification failed. Scheduled task '$TaskName' remains registered, and helper files remain at '$InstallRoot'. Review '$installLog' before using the helper."
    "[$((Get-Date).ToUniversalTime().ToString('o'))] Installation verification failed: $($_.Exception.Message)" | Add-Content -LiteralPath $installLog -Encoding UTF8
    throw
}

Write-Host "Installed $TaskName at $InstallRoot for $userId"
Write-Host "Install log: $installLog"
Write-Host 'Self-tests passed: administrator execution and installed invoker Windows-path execution (exit code 0).'
