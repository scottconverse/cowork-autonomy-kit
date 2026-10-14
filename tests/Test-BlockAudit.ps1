$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
$kit = Split-Path $PSScriptRoot -Parent
$library = Join-Path $kit 'lib/AutonomySettings.ps1'
if (Test-Path $library) { . $library }
$passed = 0
$sandbox = Join-Path $env:TEMP ('claude-audit-' + [guid]::NewGuid().ToString('n'))
[void][IO.Directory]::CreateDirectory($sandbox)
try {
    $path = Join-Path $sandbox 'settings.json'
    [IO.File]::WriteAllText($path,'{"permissions":{"deny":["Read(secret)"],"ask":["Bash(git push *)"],"disableBypassPermissionsMode":"disable"},"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"check-command"}]}]}}')
    $hash = (Get-FileHash $path).Hash
    $audit = $null
    if (Get-Command Get-KitBlockAudit -ErrorAction SilentlyContinue) {
        $audit = Get-KitBlockAudit -Sources @([pscustomobject]@{Scope='user'; Location=$path; Kind='file'; Editable=$true})
    }
    Assert-Kit (@($audit.Findings | Where-Object { $_.Field -eq 'permissions.deny' -and $_.Rule -eq 'Read(secret)' -and $_.Effect -eq 'blocks when matched' -and $_.Source -eq $path }).Count -eq 1) 'deny finding carries source, rule and configured effect'
    Assert-Kit (@($audit.Findings | Where-Object Effect -eq 'requires approval when matched').Count -eq 1) 'ask finding retains distinct effect'
    Assert-Kit (@($audit.Findings | Where-Object { $_.Field -like 'hooks.PreToolUse*' -and $_.Effect -eq 'potential restriction' }).Count -eq 1) 'hook is potential, never an observed denial'
    Assert-Kit (@($audit.Findings | Where-Object Field -eq 'permissions.disableBypassPermissionsMode').Count -eq 1) 'bypass disable survives empty-rule reasoning'
    Assert-Kit ((Get-FileHash $path).Hash -eq $hash -and @(Get-ChildItem $sandbox).Count -eq 1) 'audit is read only'
    $sources = @(
        [pscustomobject]@{Scope='project'; Location=(Join-Path $sandbox 'absent.json'); Kind='file'; Editable=$true},
        [pscustomobject]@{Scope='managed'; Location='fixture registry'; Kind='inline'; Raw='{bad'; Editable=$false},
        [pscustomobject]@{Scope='managed'; Location='inaccessible source'; Kind='error'; Error='Access denied'; Editable=$false},
        [pscustomobject]@{Scope='managed'; Location='policy'; Kind='inline'; Raw='{"allowManagedPermissionRulesOnly":true,"permissions":{"deny":["Bash"]}}'; Editable=$false},
        [pscustomobject]@{Scope='runtime'; Location='remote policy'; Kind='uninspected'; Editable=$false}
    )
    $audit = Get-KitBlockAudit -Sources $sources
    Assert-Kit ($audit.ErrorCount -eq 2) 'malformed and unreadable sources fail static audit'
    Assert-Kit (@($audit.Coverage | Where-Object State -eq 'absent').Count -eq 1) 'absent distinguished from error'
    Assert-Kit (@($audit.Coverage | Where-Object State -eq 'not inspected').Count -eq 1) 'runtime unknown is explicit without failing static audit'
    Assert-Kit (@($audit.Findings | Where-Object { $_.Source -eq 'policy' -and $_.Activation -like 'unknown*' -and -not $_.EditEligible }).Count -ge 2) 'managed findings have uncertain activation and are report only'
    $audit=Get-KitBlockAudit -Sources @(
        [pscustomobject]@{Scope='user';Location='user';Kind='inline';Raw='{"permissions":{"defaultMode":"default","deny":["Read(secret)"]}}';Editable=$true},
        [pscustomobject]@{Scope='project';Location='project';Kind='inline';Raw='{"permissions":{"defaultMode":"plan","ask":["Bash"]}}';Editable=$true},
        [pscustomobject]@{Scope='local';Location='local';Kind='inline';Raw='{"permissions":{"defaultMode":"acceptEdits"}}';Editable=$true}
    )
    Assert-Kit (@($audit.Findings | Where-Object { $_.Field -eq 'permissions.defaultMode' -and $_.Activation -like 'shadowed*' }).Count -eq 2 -and @($audit.Findings | Where-Object { $_.Source -eq 'local' -and $_.Activation -like 'highest inspected*' }).Count -eq 1) 'local scalar precedence distinguishes effective local candidate from shadowed modes'
    Assert-Kit (@($audit.Findings | Where-Object Activation -like 'additive*').Count -eq 2) 'ordinary rule lists are additive, subject to managed and runtime uncertainty'
    $audit=Get-KitBlockAudit -Sources @([pscustomobject]@{Scope='user';Location='array.json';Kind='inline';Raw='[{}]';Editable=$true})
    Assert-Kit ($audit.ErrorCount -eq 1 -and $audit.Coverage[0].State -eq 'malformed') 'singleton JSON array cannot masquerade as an object'
    Write-Host "SUMMARY: $passed PASS / 0 FAIL"
} finally { Remove-TestRoot $sandbox }
