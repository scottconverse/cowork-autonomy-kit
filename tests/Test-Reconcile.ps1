$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Import-ProductionFunctions.ps1')
$kit=Split-Path $PSScriptRoot -Parent
Import-ConfigurationFunctions $kit
. (Join-Path $kit 'lib/AutonomySettings.ps1')
$passed=0
$sandbox=Join-Path $env:TEMP ('claude-reconcile-'+[guid]::NewGuid().ToString('n'))
[void][IO.Directory]::CreateDirectory($sandbox)
try {
    $root=Join-Path $sandbox 'user'; $project=Join-Path $sandbox 'Project with spaces'
    [void][IO.Directory]::CreateDirectory($root)
    [void][IO.Directory]::CreateDirectory((Join-Path $project '.claude'))
    $raw='{"permissions":{"defaultMode":"default","ask":["Bash"],"deny":["Read(secret)"],"allow":["Read"]},"env":{"KEEP":"unchanged"},"custom":{"nested":{"list":[1,true,null,{"x":"y"}]}}}'
    $user=Join-Path $root 'settings.json'; $shared=Join-Path $project '.claude/settings.json'
    [IO.File]::WriteAllText($user,$raw); [IO.File]::WriteAllText($shared,$raw)
    $plan=@()
    if (Get-Command New-KitSettingsPlan -ErrorAction SilentlyContinue) { $plan=@(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project) }
    Assert-Kit ($plan.Count -eq 2) 'plan selects user and existing project only'
    Assert-Kit ($plan[0].After.permissions.deny.Count -eq 0 -and $plan[0].After.permissions.ask.Count -eq 0) 'default clears user rules'
    Assert-Kit ($plan[0].After.permissions.defaultMode -eq 'bypassPermissions') 'user bypass selected'
    Assert-Kit ($plan[1].After.permissions.PSObject.Properties.Name -notcontains 'defaultMode' -and -not $plan[1].After.hooks) 'project inherits mode without user hook'
    Assert-Kit ($plan[1].After.custom.nested.list[3].x -eq 'y' -and $plan[1].After.env.KEEP -eq 'unchanged' -and $plan[1].After.permissions.allow[0] -eq 'Read') 'nested unrelated data retained'
    foreach ($skipRules in @($false,$true)) {
        foreach ($skipMode in @($false,$true)) {
            $p=@(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project -SkipBypass:$skipMode -SkipClearBlockingRules:$skipRules)
            $u=if ($p.Count) { $p | Where-Object Scope -eq 'user' } else { $null }
            Assert-Kit ($u.After.permissions.deny.Count -eq [int]$skipRules) 'rule switch independent of mode switch'
            Assert-Kit ($u.After.permissions.defaultMode -eq $(if ($skipMode) { 'default' } else { 'bypassPermissions' })) 'mode switch independent of rule switch'
        }
    }
    Assert-Kit ((Get-Content $user -Raw) -ceq $raw -and -not (Test-Path (Join-Path $root 'autonomy-kit'))) 'planner performs no writes'
    [IO.File]::WriteAllText((Join-Path $project '.claude/settings.local.json'),'{bad')
    $failed=$false
    try { New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project | Out-Null } catch { $failed=$_.Exception.Message -like '*settings.local.json*' }
    Assert-Kit ($failed -and (Get-Content $user -Raw) -ceq $raw) 'malformed later target aborts before writes'
    $savedRoot=$env:CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR=$root
        Assert-Kit ((Resolve-KitConfigRoot) -eq $root) 'configuration root override is resolved consistently'
        $env:CLAUDE_CONFIG_DIR=$user; $failed=$false
        try { Resolve-KitConfigRoot | Out-Null } catch { $failed=$true }
        Assert-Kit ($failed) 'file-valued config root is rejected without fallback'
    } finally { $env:CLAUDE_CONFIG_DIR=$savedRoot }
    $untouched=Join-Path $sandbox 'skip-config'
    Install-KitConfiguration -KitRoot $kit -ClaudeRoot $untouched -ProjectRoot $project -SkipConfig
    Assert-Kit (-not (Test-Path $untouched)) 'SkipConfig creates no config root, stage, profile, snapshot or manifest'
    $sources=@(Get-KitSettingsSources -ClaudeRoot $root)
    Assert-Kit (@($sources | Where-Object { $_.Scope -eq 'project' -and $_.Kind -eq 'uninspected' }).Count -eq 1) 'no project argument gives explicit uninspected coverage'
    $plan=@(New-KitSettingsPlan -ClaudeRoot $root)
    Assert-Kit ($plan.Count -eq 1 -and $plan[0].Scope -eq 'user') 'no project argument limits edits to user'
    $local=Join-Path $project '.claude/settings.local.json'
    [IO.File]::WriteAllText($local,$raw)
    $plan=@(New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $project)
    Assert-Kit ($plan.Count -eq 3 -and $plan[2].After.permissions.ask.Count -eq 0 -and $plan[2].After.permissions.PSObject.Properties.Name -notcontains 'defaultMode') 'local project settings also clear rules and inherit user mode'
    $aliasProject=Join-Path $sandbox 'alias'
    [void][IO.Directory]::CreateDirectory($aliasProject)
    New-Item -ItemType Junction -Path (Join-Path $aliasProject '.claude') -Target $root | Out-Null
    $failed=$false
    try { New-KitSettingsPlan -ClaudeRoot $root -ProjectRoot $aliasProject | Out-Null } catch { $failed=$_.Exception.Message -like '*Ambiguous linked target*' }
    # Remove the junction itself before the normal recursive temporary-root cleanup.
    [IO.Directory]::Delete((Join-Path $aliasProject '.claude'))
    Assert-Kit ($failed) 'linked project target cannot alias user/managed settings during writes'
    Write-Host "SUMMARY: $passed PASS / 0 FAIL"
} finally { Remove-TestRoot $sandbox }
