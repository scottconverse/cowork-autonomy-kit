# Shared definitions only: loading this file performs no I/O.
function Resolve-KitConfigRoot {
    param([string]$ClaudeRoot)
    if (-not $ClaudeRoot) {
        $ClaudeRoot = if (-not [string]::IsNullOrEmpty($env:CLAUDE_CONFIG_DIR)) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
    }
    if ([string]::IsNullOrWhiteSpace($ClaudeRoot)) { throw 'Configuration root cannot be whitespace.' }
    $resolved = [IO.Path]::GetFullPath($ClaudeRoot)
    if ((Test-Path -LiteralPath $resolved) -and -not (Test-Path -LiteralPath $resolved -PathType Container)) { throw "Configuration root is not a directory: $resolved" }
    return $resolved
}

function Resolve-KitProjectRoot {
    param([string]$ProjectRoot)
    if (-not $ProjectRoot) { return $null }
    $resolved = [IO.Path]::GetFullPath($ProjectRoot)
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { throw "Project root must be an existing directory: $resolved" }
    return $resolved
}

function Get-KitManagedRoot {
    $programRoot = if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }
    return Join-Path $programRoot 'ClaudeCode'
}

function Get-KitSettingsSources {
    param([string]$ClaudeRoot, [string]$ProjectRoot)
    $root = Resolve-KitConfigRoot $ClaudeRoot
    [pscustomobject]@{ Scope='user'; Location=(Join-Path $root 'settings.json'); Kind='file'; Editable=$true }
    $project = Resolve-KitProjectRoot $ProjectRoot
    if ($project) {
        foreach ($name in @('settings.json','settings.local.json')) {
            [pscustomobject]@{ Scope=$(if ($name -eq 'settings.json') { 'project' } else { 'local' }); Location=(Join-Path $project ".claude\$name"); Kind='file'; Editable=$true }
        }
    } else { [pscustomobject]@{ Scope='project'; Location='ProjectRoot not requested'; Kind='uninspected'; Editable=$false } }
    $managed = Get-KitManagedRoot
    [pscustomobject]@{ Scope='managed'; Location=(Join-Path $managed 'managed-settings.json'); Kind='file'; Editable=$false }
    $dropins = Join-Path $managed 'managed-settings.d'
    try {
        if (Test-Path -LiteralPath $dropins -ErrorAction Stop) {
            $files = @(Get-ChildItem -LiteralPath $dropins -File -Filter '*.json' -ErrorAction Stop | Sort-Object Name)
            foreach ($file in $files) { [pscustomobject]@{ Scope='managed'; Location=$file.FullName; Kind='file'; Editable=$false } }
            if (-not $files.Count) { [pscustomobject]@{ Scope='managed'; Location=$dropins; Kind='empty'; Editable=$false } }
        } else { [pscustomobject]@{ Scope='managed'; Location=$dropins; Kind='absent'; Editable=$false } }
    } catch { [pscustomobject]@{ Scope='managed'; Location=$dropins; Kind='error'; Error=$_.Exception.Message; Editable=$false } }
    # Inspect both views explicitly. Runtime selection is reported as unknown;
    # a 32-bit PowerShell process must not silently hide the native policy view.
    $views = @([Microsoft.Win32.RegistryView]::Registry32)
    if ([Environment]::Is64BitOperatingSystem) { $views += [Microsoft.Win32.RegistryView]::Registry64 }
    foreach ($hive in @('LocalMachine','CurrentUser')) {
        foreach ($view in $views) {
            $label = "$hive\SOFTWARE\Policies\ClaudeCode\Settings ($view)"
            $base = $null; $key = $null
            try {
                $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hive,$view)
                $key = $base.OpenSubKey('SOFTWARE\Policies\ClaudeCode',$false)
                $raw = if ($key) { $key.GetValue('Settings',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) } else { $null }
                if ($null -eq $raw) { [pscustomobject]@{ Scope='managed'; Location=$label; Kind='absent'; Editable=$false } }
                else { [pscustomobject]@{ Scope='managed'; Location=$label; Kind='inline'; Raw=$raw; Editable=$false } }
            } catch { [pscustomobject]@{ Scope='managed'; Location=$label; Kind='error'; Error=$_.Exception.Message; Editable=$false } }
            finally { if ($key) { $key.Dispose() }; if ($base) { $base.Dispose() } }
        }
    }
    foreach ($source in @('Remote/host policy and policyHelper output','Launch flags and alternative settings sources','Live session mode and permissions','Desktop bypass toggle and remembered folder mode','Plugin/skill/agent hooks and dynamically loaded settings','WSL, cloud, other operating systems and Cowork tab','Built-in tool restrictions and mandatory interaction')) {
        [pscustomobject]@{ Scope='runtime'; Location=$source; Kind='uninspected'; Editable=$false }
    }
}

function ConvertFrom-KitSettingsJson {
    param([string]$Raw, [string]$Path)
    try {
        if ($Raw -notmatch '^\s*\{') { throw 'Expected a JSON object' }
        $value = ConvertFrom-Json -InputObject $Raw -ErrorAction Stop
        if ($null -eq $value -or $value -isnot [pscustomobject]) { throw 'Expected a JSON object' }
        foreach ($key in @('permissions','hooks')) {
            if ($value.PSObject.Properties.Name -contains $key -and $value.$key -isnot [pscustomobject]) { throw "$key must be an object" }
        }
        foreach ($key in @('allow','ask','deny','additionalDirectories')) {
            if ($value.permissions -and $value.permissions.PSObject.Properties.Name -contains $key) {
                if ($value.permissions.$key -isnot [array] -or @($value.permissions.$key | Where-Object { $_ -isnot [string] }).Count) { throw "permissions.$key must be an array of strings" }
            }
        }
        if ($value.permissions -and $value.permissions.PSObject.Properties.Name -contains 'defaultMode' -and $value.permissions.defaultMode -isnot [string]) { throw 'permissions.defaultMode must be a string' }
        if ($value.hooks) {
            foreach ($event in $value.hooks.PSObject.Properties) {
                if ($event.Value -isnot [array]) { throw "hooks.$($event.Name) must be an array" }
                foreach ($entry in $event.Value) {
                    if ($entry -isnot [pscustomobject] -or $entry.hooks -isnot [array]) { throw "hooks.$($event.Name) entries must contain a hooks array" }
                    foreach ($hook in $entry.hooks) { if ($hook -isnot [pscustomobject]) { throw "hooks.$($event.Name) handlers must be objects" } }
                }
            }
        }
        return $value
    } catch { throw "Invalid settings file '$Path': $($_.Exception.Message). Nothing was written." }
}

function Get-KitField {
    param($Value,[string]$Field)
    foreach ($part in $Field.Split('.')) {
        if ($null -eq $Value -or $Value.PSObject.Properties.Name -notcontains $part) { return $null }
        $Value = $Value.$part
    }
    return ,$Value
}

function Get-KitBlockAudit {
    param([string]$ClaudeRoot, [string]$ProjectRoot, [object[]]$Sources)
    if (-not $PSBoundParameters.ContainsKey('Sources')) { $Sources = @(Get-KitSettingsSources -ClaudeRoot $ClaudeRoot -ProjectRoot $ProjectRoot) }
    $coverage = @(); $findings = @(); $errors = 0
    foreach ($source in $Sources) {
        $state = 'inspected'; $value = $null; $detail = ''
        try {
            switch ($source.Kind) {
                'uninspected' { $state = 'not inspected' }
                'absent' { $state = 'absent' }
                'empty' { $detail = 'No JSON drop-ins found' }
                'error' { throw $source.Error }
                'inline' { $value = ConvertFrom-KitSettingsJson -Raw $source.Raw -Path $source.Location }
                'file' {
                    if (Test-Path -LiteralPath $source.Location -ErrorAction Stop) {
                        $raw = [IO.File]::ReadAllText($source.Location)
                        $value = ConvertFrom-KitSettingsJson -Raw $raw -Path $source.Location
                    } else { $state = 'absent' }
                }
                default { throw "Unknown source kind: $($source.Kind)" }
            }
        } catch {
            $state = if ($_.Exception.Message -like 'Invalid settings file*') { 'malformed' } else { 'unreadable' }
            $detail = $_.Exception.Message; $errors++
        }
        $activation = if ($source.Scope -eq 'managed') { 'unknown: policy selection, registry view and remote/host policy not established' } else { 'configured locally; runtime activation unverified' }
        $coverage += [pscustomobject]@{ Scope=$source.Scope; Source=$source.Location; State=$state; Detail=$detail; Activation=$activation; Value=$value }
        $start = $findings.Count
        $add = {
            param($field,$rule,$effect,$remedy,$editable)
            [pscustomobject]@{ Source=$source.Location; Scope=$source.Scope; Field=$field; Rule=$rule; Effect=$effect; Activation=$activation; Remediation=$remedy; EditEligible=[bool]$editable }
        }
        if ($state -in @('malformed','unreadable','not inspected')) {
            $findings += & $add '' $detail 'unknown/error' $(if ($state -eq 'not inspected') { 'Verify in the actual session; this audit does not inspect this source.' } else { 'Correct this source or its read access, then rerun Doctor.' }) $false
        }
        if ($value) {
            foreach ($key in @('ask','deny')) {
                foreach ($rule in @($value.permissions.$key)) {
                    if ($null -eq $rule) { continue }
                    $effect = if ($key -eq 'deny') { 'blocks when matched' } else { 'requires approval when matched' }
                    $remedy = if ($source.Editable) { 'Default Setup clears this selected array; -SkipClearBlockingRules retains it.' } else { 'Review with the policy owner; Setup leaves managed policy unchanged.' }
                    $findings += & $add "permissions.$key" $rule $effect $remedy $source.Editable
                }
            }
            if ($value.permissions -and $value.permissions.PSObject.Properties.Name -contains 'defaultMode') {
                $mode = $value.permissions.defaultMode
                if ($source.Scope -in @('project','local') -or $mode -ne 'bypassPermissions') {
                    $findings += & $add 'permissions.defaultMode' $mode 'mode override' 'Setup sets user bypass and removes selected project mode overrides unless -SkipBypass; verify session mode separately.' $source.Editable
                }
            }
            foreach ($event in @($value.hooks.PSObject.Properties)) {
                if ($null -eq $event) { continue }
                $index = 0
                foreach ($entry in $event.Value) {
                    foreach ($hook in $entry.hooks) {
                        $target = if ($hook.command) { $hook.command } elseif ($hook.prompt) { $hook.prompt } else { '(dynamic target)' }
                        $findings += & $add "hooks.$($event.Name)[$index]" "matcher=$($entry.matcher); type=$($hook.type); target=$target" 'potential restriction' 'Review hook behavior and its source; Setup does not remove foreign hooks or execute them during audit.' $false
                    }
                    $index++
                }
            }
            # Recognized controls, not a policy interpreter. Unknown fields are retained.
            foreach ($field in @('permissions.disableBypassPermissionsMode','permissions.blockReadsOutsideWorkingDirectories','permissions.additionalDirectories','allowManagedPermissionRulesOnly','allowManagedHooksOnly','allowManagedMcpServersOnly','allowedMcpServers','deniedMcpServers','enabledMcpjsonServers','disabledMcpjsonServers','sandbox','disableAllHooks','managedSourcesBehavior','policyHelper')) {
                $setting = Get-KitField $value $field
                if ($null -ne $setting) {
                    $findings += & $add $field (ConvertTo-Json -InputObject $setting -Depth 100 -Compress) 'potential restriction' 'Review this control at the listed source and verify its effect in the session; reconcile leaves it unchanged.' $false
                }
            }
        }
        if ($findings.Count -eq $start -and $state -eq 'inspected') { $findings += & $add '' '' 'no relevant finding' 'No identified restriction in this source; runtime restrictions may remain.' $false }
    }
    # Lists are additive within ordinary local scopes; scalar mode uses local > project > user.
    # Managed-only rules and remote policy prevent an unconditional effective verdict.
    $modes = @($coverage | Where-Object { $_.Scope -in @('user','project','local') -and $null -ne $_.Value.permissions.defaultMode })
    $winner = $modes | Sort-Object { @('user','project','local').IndexOf($_.Scope) } | Select-Object -Last 1
    foreach ($finding in $findings) {
        if ($finding.Scope -in @('user','project','local') -and $finding.Field -in @('permissions.ask','permissions.deny')) { $finding.Activation = 'additive in local files; unknown if managed-only controls or runtime sources override' }
        if ($finding.Field -eq 'permissions.defaultMode' -and $finding.Scope -in @('user','project','local')) {
            $finding.Activation = if ($winner.Source -eq $finding.Source) { 'highest inspected local mode; runtime/managed overrides unknown' } else { 'shadowed by a higher inspected local mode' }
        }
    }
    [pscustomobject]@{ Coverage=$coverage; Findings=$findings; ErrorCount=$errors; RuleCount=@($findings | Where-Object { $_.Effect -in @('blocks when matched','requires approval when matched') }).Count }
}

function Write-KitBlockAudit {
    param($Audit)
    Write-Host ($Audit.Coverage | Select-Object Scope,State,Source | Format-Table -Wrap | Out-String -Width 120)
    foreach ($finding in $Audit.Findings) {
        Write-Host ("[{0}] {1}: {2}" -f $finding.Effect,$finding.Scope,$finding.Source)
        if ($finding.Field) { Write-Host "  $($finding.Field): $($finding.Rule)" }
        elseif ($finding.Rule) { Write-Host "  Detail: $($finding.Rule)" }
        Write-Host "  Activation: $($finding.Activation)"
        Write-Host "  Reconcile edit eligible: $($finding.EditEligible)"
        Write-Host "  Remedy: $($finding.Remediation)"
    }
    if ($Audit.ErrorCount) { Write-Host 'Audit incomplete: one or more requested sources could not be inspected.' }
    elseif (-not $Audit.RuleCount) { Write-Host 'No blocking permission rules found in inspected sources; runtime restrictions may remain.' }
    else { Write-Host "$($Audit.RuleCount) rule findings; $(@($Audit.Findings | Where-Object { $_.Effect -in @('potential restriction','unknown/error','mode override') }).Count) other restrictions or unknowns. See source and remedy above." }
}

function Assert-KitWritableIdentity {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $managed = [IO.Path]::GetFullPath((Get-KitManagedRoot)).TrimEnd('\')
    if ($full.Equals($managed,[StringComparison]::OrdinalIgnoreCase) -or $full.StartsWith($managed+'\',[StringComparison]::OrdinalIgnoreCase)) { throw "Managed target is report-only: $full" }
    # Reparse points and linked files make the apparent scope ambiguous. Do not follow them for edits.
    $ancestor = $full
    while ($ancestor) {
        if (Test-Path -LiteralPath $ancestor -ErrorAction Stop) {
            $item = Get-Item -LiteralPath $ancestor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.LinkType -eq 'HardLink') { throw "Ambiguous linked target: $ancestor" }
        }
        $parent = Split-Path -Parent $ancestor
        if ($parent -eq $ancestor) { break }
        $ancestor = $parent
    }
    return $full
}

function ConvertTo-KitJson {
    param($Value)
    # ConvertTo-Json silently stringifies excessive nesting in Windows PowerShell.
    # Reject it explicitly before serialization, including unknown/custom values.
    function Assert-JsonDepth($Node,[int]$Depth) {
        if ($Depth -gt 90) { throw 'Settings nesting exceeds the supported lossless serialization depth (90).' }
        if ($Node -is [pscustomobject]) { foreach ($property in $Node.PSObject.Properties) { Assert-JsonDepth $property.Value ($Depth+1) } }
        elseif ($Node -is [System.Collections.IDictionary]) { foreach ($key in $Node.Keys) { Assert-JsonDepth $Node[$key] ($Depth+1) } }
        elseif ($Node -is [array]) { foreach ($entry in $Node) { Assert-JsonDepth $entry ($Depth+1) } }
    }
    Assert-JsonDepth $Value 0
    return ConvertTo-Json -InputObject $Value -Depth 100 -Compress
}

function Get-KitByteHash {
    param([byte[]]$Bytes)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','') } finally { $sha.Dispose() }
}

function Get-KitFileHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash
}

function New-KitSettingsPlan {
    param([string]$ClaudeRoot,[string]$ProjectRoot,[switch]$SkipBypass,[switch]$SkipClearBlockingRules)
    $root = Resolve-KitConfigRoot $ClaudeRoot
    $project = Resolve-KitProjectRoot $ProjectRoot
    $targets = @([pscustomobject]@{Path=(Join-Path $root 'settings.json');Scope='user'})
    if ($project) {
        $targets += [pscustomobject]@{Path=(Join-Path $project '.claude/settings.json');Scope='project'}
        $targets += [pscustomobject]@{Path=(Join-Path $project '.claude/settings.local.json');Scope='local'}
    }
    $seen = @{}; $plans = @()
    foreach ($target in $targets) {
        $path = Assert-KitWritableIdentity $target.Path
        if ($seen.ContainsKey($path)) { continue }
        $seen[$path] = $true
        $exists = Test-Path -LiteralPath $path -ErrorAction Stop
        if (-not $exists -and $target.Scope -ne 'user') { continue }
        $bytes = if ($exists) { [IO.File]::ReadAllBytes($path) } else { [byte[]]@() }
        $before = if ($exists) { ConvertFrom-KitSettingsJson -Raw ([IO.File]::ReadAllText($path)) -Path $path } else { [pscustomobject]@{} }
        if ($exists -and (Get-KitFileHash $path) -ne (Get-KitByteHash $bytes)) { throw "Settings changed while reading: $path" }
        $beforeJson = ConvertTo-KitJson $before
        $after = ConvertFrom-Json -InputObject $beforeJson
        if ($target.Scope -eq 'user') { $after = Merge-KitSettings -Settings $after -ClaudeRoot $root -SkipBypass:$SkipBypass }
        elseif (-not $SkipBypass -and $after.permissions) { $after.permissions.PSObject.Properties.Remove('defaultMode') }
        if (-not $SkipClearBlockingRules) {
            if (-not $after.permissions) { $after | Add-Member permissions ([pscustomobject]@{}) -Force }
            foreach ($key in @('ask','deny')) { $after.permissions | Add-Member $key @() -Force }
        }
        $json = ConvertTo-KitJson $after
        [void](ConvertFrom-KitSettingsJson -Raw $json -Path $path)
        if ($beforeJson -ceq $json) { continue }
        $fields = @()
        foreach ($field in @('permissions.defaultMode','permissions.ask','permissions.deny','permissions.additionalDirectories','hooks.Stop')) {
            $old = ConvertTo-KitJson (Get-KitField $before $field)
            $new = ConvertTo-KitJson (Get-KitField $after $field)
            if ($old -cne $new) { $fields += [pscustomobject]@{Field=$field;Before=$old;After=$new} }
        }
        $writtenBytes = [Text.UTF8Encoding]::new($false).GetBytes($json)
        $plans += [pscustomobject]@{Path=$path;Scope=$target.Scope;OriginalExists=[bool]$exists;OriginalBytes=$bytes;OriginalHash=$(if ($exists) { Get-KitByteHash $bytes } else { $null });After=$after;Json=$json;WrittenHash=(Get-KitByteHash $writtenBytes);Fields=$fields}
    }
    # No partial pipeline output if a later target failed validation.
    return $plans
}

function Write-KitAtomicBytes {
    param([string]$Path,[byte[]]$Bytes,$ExpectedHash)
    $temp = Join-Path (Split-Path -Parent $Path) ('.autonomy-'+[guid]::NewGuid().ToString('n')+'.tmp')
    try {
        [IO.File]::WriteAllBytes($temp,$Bytes)
        if ($PSBoundParameters.ContainsKey('ExpectedHash') -and (Get-KitFileHash $Path) -ne $ExpectedHash) { throw "Concurrent edit immediately before replacement: $Path" }
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temp,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temp,$Path) }
    } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
}

function Read-KitManifest {
    param([string]$ClaudeRoot)
    $path = Join-Path $ClaudeRoot 'autonomy-kit/settings-history.json'
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{SchemaVersion=1;Baselines=@();Operations=@()} }
    try {
        $manifest = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($path)) -ErrorAction Stop
        if ($manifest.SchemaVersion -ne 1 -or $manifest.Baselines -isnot [array] -or $manifest.Operations -isnot [array]) { throw 'Unsupported manifest shape/version' }
        return $manifest
    } catch { throw "Cannot read recovery manifest '$path': $($_.Exception.Message). Retain this file and its backups; configuration was not reconciled." }
}

function Write-KitManifest {
    param([string]$ClaudeRoot,$Manifest)
    $path = Join-Path $ClaudeRoot 'autonomy-kit/settings-history.json'
    Write-KitAtomicBytes -Path $path -Bytes ([Text.UTF8Encoding]::new($false).GetBytes((ConvertTo-KitJson $Manifest)))
}

function Open-KitOperationLock {
    param([string]$ClaudeRoot)
    $stage = Join-Path $ClaudeRoot 'autonomy-kit'
    [void](Assert-KitWritableIdentity (Join-Path $stage 'settings-history.json'))
    [void][IO.Directory]::CreateDirectory($ClaudeRoot)
    # Outside staging so whole-kit cleanup can retain the lock until deletion ends.
    $lockPath=Join-Path $ClaudeRoot '.autonomy-kit.settings.lock'
    [void](Assert-KitWritableIdentity $lockPath)
    try { return [IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None) }
    catch { throw "Another configuration/restore operation holds '$lockPath', or the lock is inaccessible: $($_.Exception.Message)" }
}

function Assert-KitBackup {
    param($Entry,[string]$ClaudeRoot)
    [void](Assert-KitWritableIdentity $Entry.Path)
    if ($Entry.OriginalExists) {
        $stage = [IO.Path]::GetFullPath((Join-Path $ClaudeRoot 'autonomy-kit')).TrimEnd('\')+'\'
        if (-not $Entry.BackupPath -or -not ([IO.Path]::GetFullPath($Entry.BackupPath)).StartsWith($stage,[StringComparison]::OrdinalIgnoreCase)) { throw "Recovery backup is outside the recorded kit stage for '$($Entry.Path)'" }
        if (-not $Entry.OriginalHash -or (Get-KitFileHash $Entry.BackupPath) -ne $Entry.OriginalHash) { throw "Missing/corrupt backup '$($Entry.BackupPath)' for '$($Entry.Path)'; expected SHA256 $($Entry.OriginalHash). Retain recovery state and recover that exact backup before retrying." }
    }
}

function Repair-KitPendingOperation {
    param([string]$ClaudeRoot,$Manifest)
    foreach ($operation in @($Manifest.Operations | Where-Object { $_.State -in @('prepared','writing','recovery-incomplete') })) {
        $incomplete = @()
        foreach ($entry in $operation.Files) {
            try {
                Assert-KitBackup $entry $ClaudeRoot
                $current = Get-KitFileHash $entry.Path
                if ($current -eq $entry.OriginalHash) { $entry.State='recovered'; continue }
                if ($current -ne $entry.WrittenHash) { throw "Concurrent/unknown contents at '$($entry.Path)'" }
                if ($entry.OriginalExists) { Write-KitAtomicBytes -Path $entry.Path -Bytes ([IO.File]::ReadAllBytes($entry.BackupPath)) -ExpectedHash $current }
                else { [IO.File]::Delete($entry.Path) }
                if ((Get-KitFileHash $entry.Path) -ne $entry.OriginalHash) { throw "Recovery verification failed: $($entry.Path)" }
                $entry.State='recovered'
            } catch { $incomplete += "$($_.Exception.Message). Target: $($entry.Path); original backup: $($entry.BackupPath); original SHA256: $($entry.OriginalHash); operation: $($operation.Id). Preserve current contents, restore the exact original bytes (or remove an originally absent target), then rerun Setup." }
        }
        $operation.State = if ($incomplete.Count) { 'recovery-incomplete' } else { 'recovered' }
        Write-KitManifest $ClaudeRoot $Manifest
        if ($incomplete.Count) { throw ($incomplete -join "`n") }
    }
}

function Invoke-KitSettingsOperation {
    param([string]$ClaudeRoot,[object[]]$Plan,[System.IO.FileStream]$OperationLock)
    $root = Resolve-KitConfigRoot $ClaudeRoot
    $manifest = Read-KitManifest $root
    if ($manifest.RestorePending -or @($manifest.Operations | Where-Object State -eq 'restore-incomplete').Count) { throw 'An interrupted restore must finish before Setup can continue. Run Uninstall with -RestoreLastReconcile for an operation restore, or normal Uninstall for a baseline restore.' }
    $pending = @($manifest.Operations | Where-Object { $_.State -in @('prepared','writing','recovery-incomplete') })
    if (-not $Plan.Count -and -not $pending.Count) { Write-Host 'Settings already match; no settings writes or history added.'; return }
    $lock = if ($OperationLock) { $OperationLock } else { Open-KitOperationLock $root }
    try {
        $manifest = Read-KitManifest $root
        if ($manifest.RestorePending -or @($manifest.Operations | Where-Object State -eq 'restore-incomplete').Count) { throw 'Finish the interrupted restore before starting another settings operation.' }
        Repair-KitPendingOperation $root $manifest
        if ($pending.Count) { throw 'Previous operation recovered. Rerun Setup to plan from the recovered files.' }
        if (-not $Plan.Count) { return }
        $id = [guid]::NewGuid().ToString('n')
        $backupRoot = Join-Path $root "autonomy-kit/recovery/$id"
        [void][IO.Directory]::CreateDirectory($backupRoot)
        $entries = @(); $index=0
        foreach ($change in $Plan) {
            [void](Assert-KitWritableIdentity $change.Path)
            if ((Get-KitFileHash $change.Path) -ne $change.OriginalHash) { throw "Settings changed after preflight: $($change.Path). No planned replacement performed; rerun Setup." }
            $backup = $null
            if ($change.OriginalExists) {
                $backup = Join-Path $backupRoot "$index.original.json"
                [IO.File]::WriteAllBytes($backup,$change.OriginalBytes)
                if ((Get-KitFileHash $backup) -ne $change.OriginalHash) { throw "Backup verification failed: $backup" }
            }
            $entry = [pscustomobject]@{Path=$change.Path;Scope=$change.Scope;OriginalExists=$change.OriginalExists;OriginalHash=$change.OriginalHash;BackupPath=$backup;WrittenHash=$change.WrittenHash;Fields=$change.Fields;State='prepared'}
            $entries += $entry
            if (-not @($manifest.Baselines | Where-Object Path -eq $change.Path).Count) {
                $baseline = ConvertFrom-Json -InputObject (ConvertTo-KitJson $entry)
                if ($change.Scope -eq 'user') {
                    $legacy = "$($change.Path).pre-autonomy-kit"
                    if (Test-Path -LiteralPath $legacy) {
                        $baseline.BackupPath = Join-Path $backupRoot "$index.baseline.json"
                        [IO.File]::WriteAllBytes($baseline.BackupPath,[IO.File]::ReadAllBytes($legacy))
                        $baseline.OriginalExists=$true; $baseline.OriginalHash=Get-KitFileHash $baseline.BackupPath
                    } elseif (Test-Path -LiteralPath "$legacy.absent") {
                        $baseline.OriginalExists=$false; $baseline.OriginalHash=$null; $baseline.BackupPath=$null
                        $created = Join-Path $root 'autonomy-kit/settings.created-by-kit.json'
                        if (Test-Path -LiteralPath $created) { $baseline.WrittenHash=Get-KitFileHash $created }
                    }
                }
                $manifest.Baselines += $baseline
            }
            else { ($manifest.Baselines | Where-Object Path -eq $change.Path).State='prepared' }
            $index++
        }
        $operation = [pscustomobject]@{Id=$id;Time=[DateTime]::UtcNow.ToString('o');State='prepared';Files=$entries}
        $manifest.Operations += $operation
        Write-KitManifest $root $manifest
        try {
            $operation.State='writing'; Write-KitManifest $root $manifest
            for ($i=0; $i -lt $Plan.Count; $i++) {
                $change=$Plan[$i]; $entry=$entries[$i]
                if ((Get-KitFileHash $change.Path) -ne $entry.OriginalHash) { throw "Concurrent edit detected: $($change.Path)" }
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $change.Path))
                Write-KitAtomicBytes -Path $change.Path -Bytes ([Text.UTF8Encoding]::new($false).GetBytes($change.Json)) -ExpectedHash $entry.OriginalHash
                if ((Get-KitFileHash $change.Path) -ne $entry.WrittenHash) { throw "Post-write verification failed: $($change.Path)" }
                [void](ConvertFrom-KitSettingsJson -Raw ([IO.File]::ReadAllText($change.Path)) -Path $change.Path)
                $entry.State='written'; Write-KitManifest $root $manifest
            }
            $operation.State='completed'; Write-KitManifest $root $manifest
            Write-Host "Completed settings operation $id ($($Plan.Count) files)."
        } catch {
            $failure=$_.Exception.Message
            # A failed final manifest write must still roll back the live files.
            # The in-memory object may already say completed while disk says writing.
            $operation.State='writing'
            try { Repair-KitPendingOperation $root $manifest } catch { throw "Settings operation failed: $failure`nRecovery incomplete: $($_.Exception.Message)" }
            throw "Settings operation failed and was recovered: $failure"
        }
    } finally { if (-not $OperationLock) { $lock.Dispose() } }
}

function Restore-KitSettingsOperation {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$ClaudeRoot,[switch]$Baseline,[System.IO.FileStream]$OperationLock)
    $root = Resolve-KitConfigRoot $ClaudeRoot
    $manifest = Read-KitManifest $root
    if ($manifest.RestorePending -and (($Baseline -and $manifest.RestorePending -ne 'baseline') -or (-not $Baseline -and $manifest.RestorePending -eq 'baseline'))) { throw "Finish the pending $($manifest.RestorePending) restore using its original restore mode." }
    if (@($manifest.Operations | Where-Object { $_.State -in @('prepared','writing','recovery-incomplete') }).Count) { throw 'An unfinished settings operation requires recovery before restore. Run Setup to recover, or use the exact backups in settings-history.json.' }
    # Choose latest successful operation including restored: never step backwards on repeat.
    $operation = @($manifest.Operations | Where-Object { $_.State -in @('completed','restored','restore-incomplete') }) | Select-Object -Last 1
    if ($Baseline) { $entries=@($manifest.Baselines | Where-Object State -ne 'restored') }
    elseif (-not $operation -or $operation.State -eq 'restored') { Write-Host 'Latest settings operation is already restored, or no completed operation exists.'; return }
    else { $entries=@($operation.Files | Where-Object State -ne 'restored') }
    if (-not $entries.Count -and -not $manifest.RestorePending) { return }
    foreach ($entry in $entries) { Assert-KitBackup $entry $root }
    if (-not $PSCmdlet.ShouldProcess(($entries.Path -join ', '),'Back up current bytes and restore entire recorded settings files')) { return }
    $lock = if ($OperationLock) { $OperationLock } else { Open-KitOperationLock $root }
    try {
        # Guard against another installer/restore changing history since selection.
        if ((ConvertTo-KitJson (Read-KitManifest $root)) -cne (ConvertTo-KitJson $manifest)) { throw 'Recovery history changed; rerun restore.' }
        $restoreId=if ($Baseline) { 'baseline' } else { $operation.Id }
        $manifest | Add-Member RestorePending $restoreId -Force
        if (-not $Baseline) { $operation.State='restore-incomplete' }
        Write-KitManifest $root $manifest
        $errors=@()
        foreach ($entry in $entries) {
            try {
                Assert-KitBackup $entry $root
                if (-not (Test-Path -LiteralPath (Split-Path -Parent $entry.Path) -PathType Container)) { throw "Missing/moved parent directory: $($entry.Path)" }
                $current = Get-KitFileHash $entry.Path
                if (-not $entry.OriginalExists -and $current -and $current -ne $entry.WrittenHash) { throw "Kept modified kit-created file: $($entry.Path)" }
                if ($current) {
                    $backupLabel=if ($Baseline) { 'before-uninstall' } else { 'before-restore' }
                    $preserved="$($entry.Path).$backupLabel-$([guid]::NewGuid().ToString('n')).bak"
                    [IO.File]::WriteAllBytes($preserved,[IO.File]::ReadAllBytes($entry.Path))
                    if ((Get-KitFileHash $preserved) -ne $current) { throw "Before-restore backup failed: $preserved" }
                }
                if ((Get-KitFileHash $entry.Path) -ne $current) { throw "Concurrent edit before restore: $($entry.Path)" }
                if ($entry.OriginalExists) { Write-KitAtomicBytes -Path $entry.Path -Bytes ([IO.File]::ReadAllBytes($entry.BackupPath)) -ExpectedHash $current }
                elseif ($current) { [IO.File]::Delete($entry.Path) }
                if ((Get-KitFileHash $entry.Path) -ne $entry.OriginalHash) { throw "Restore verification failed: $($entry.Path)" }
                $entry.State='restored'
                Write-KitManifest $root $manifest
            } catch { $errors += $_.Exception.Message }
        }
        if (-not $Baseline) { $operation.State=if ($errors.Count) { 'restore-incomplete' } else { 'restored' } }
        if (-not $errors.Count) { $manifest.RestorePending=$null }
        Write-KitManifest $root $manifest
        if ($errors.Count) { throw ("Restoration incomplete; recovery records retained.`n"+($errors -join "`n")) }
    } finally { if (-not $OperationLock) { $lock.Dispose() } }
}
