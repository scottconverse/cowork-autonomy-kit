<#
.SYNOPSIS
    Tests for New-AgentProject.ps1. Uses a sandbox project and a fake Claude settings folder;
    never touches the real ~/.claude or ~/.codex. Needs the kit's read-ledger-gate.mjs for the
    live-gate assertion; that part is skipped with INFO when the installed copy is absent.
#>
param([string]$Sandbox = (Join-Path $env:TEMP ("new-agent-project-test-" + [guid]::NewGuid().ToString("n"))))
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path $PSScriptRoot -Parent) 'New-AgentProject.ps1'
$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Name, [string]$Status, [string]$Detail) { $results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }) }
function Run([string[]]$ArgList) {
    # A native command writing to stderr under 2>&1 becomes a terminating NativeCommandError when
    # $ErrorActionPreference is Stop (Windows PowerShell 5.1). Relax it for the capture only.
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script @ArgList 2>&1 | ForEach-Object { "$_" }) -join "`n"; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
    return @{ Code = $code; Out = $out }
}

New-Item -ItemType Directory -Force $Sandbox | Out-Null
try {
    $project = Join-Path $Sandbox 'proj'; New-Item -ItemType Directory -Force $project | Out-Null
    $fakeClaude = Join-Path $Sandbox 'claude-home'; New-Item -ItemType Directory -Force $fakeClaude | Out-Null
    $realKit = Join-Path $env:USERPROFILE '.claude\hook-kit'

    # 1. Refuses when the Claude kit is not installed.
    Set-Content -LiteralPath (Join-Path $fakeClaude 'settings.json') -Value '{"hooks":{}}' -Encoding UTF8
    $r = Run @('-ProjectRoot', $project, '-SkipCodex', '-ClaudeRoot', $fakeClaude)
    if ($r.Code -ne 0 -and $r.Out -match 'Claude hook kit is not installed') { Add-Result 'refuses without Claude kit' 'PASS' 'nonzero exit, named the missing kit' }
    else { Add-Result 'refuses without Claude kit' 'FAIL' "exit $($r.Code): $($r.Out)" }
    if (Test-Path (Join-Path $project '.claude\hook-kit.json')) { Add-Result 'writes nothing when refusing' 'FAIL' 'hook-kit.json was written' } else { Add-Result 'writes nothing when refusing' 'PASS' '' }

    # 2. Succeeds with a settings.json that has the kit entries; files land; JSON parses; pointers appended once.
    $fakeSettings = @{ hooks = @{ PreToolUse = @(@{ hooks = @(@{ type = 'command'; command = 'node "' + ($realKit -replace '\\', '/') + '/hooks/read-ledger-gate.mjs"' }) }); Stop = @(@{ hooks = @(@{ type = 'command'; command = 'node "' + ($realKit -replace '\\', '/') + '/hooks/measure-gate.mjs"' }) }) } } | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath (Join-Path $fakeClaude 'settings.json') -Value $fakeSettings -Encoding UTF8
    if (Test-Path -LiteralPath (Join-Path $realKit 'hooks\read-ledger-gate.mjs')) {
        New-Item -ItemType Directory -Force (Join-Path $fakeClaude 'hook-kit\hooks') | Out-Null
        Copy-Item (Join-Path $realKit 'hooks\read-ledger-gate.mjs') (Join-Path $fakeClaude 'hook-kit\hooks\') -Force
        Copy-Item (Join-Path $realKit 'lib') (Join-Path $fakeClaude 'hook-kit\lib') -Recurse -Force
    }
    Set-Content -LiteralPath (Join-Path $project 'CLAUDE.md') -Value "# existing`n`nkeep me" -Encoding UTF8
    $up = Join-Path $Sandbox 'upstream'; New-Item -ItemType Directory -Force $up | Out-Null
    $r = Run @('-ProjectRoot', $project, '-SkipCodex', '-ClaudeRoot', $fakeClaude, '-Upstream', $up)
    if ($r.Code -eq 0) { Add-Result 'succeeds with kit installed' 'PASS' '' } else { Add-Result 'succeeds with kit installed' 'FAIL' "exit $($r.Code): $($r.Out)" }
    foreach ($rel in @('.claude\hook-kit.json', '.claude\RULES.md', '.claude\READ-LEDGER.md', 'work\measure\run.mjs', 'work\receipts')) {
        if (Test-Path (Join-Path $project $rel)) { Add-Result "wrote $rel" 'PASS' '' } else { Add-Result "wrote $rel" 'FAIL' 'missing' }
    }
    if (Test-Path (Join-Path $project '.codex\hook-kit.json')) { Add-Result '-SkipCodex writes no .codex' 'FAIL' 'present' } else { Add-Result '-SkipCodex writes no .codex' 'PASS' '' }
    $cfg = Get-Content (Join-Path $project '.claude\hook-kit.json') -Raw | ConvertFrom-Json
    if ($cfg.'read-ledger-gate'.label -eq 'proj' -and $cfg.'read-ledger-gate'.upstreamRoots[0] -eq ($up -replace '\\', '/')) { Add-Result 'template substitution' 'PASS' '' } else { Add-Result 'template substitution' 'FAIL' ($cfg | ConvertTo-Json -Compress) }
    $claudeMd = Get-Content (Join-Path $project 'CLAUDE.md') -Raw
    if ($claudeMd -match 'keep me' -and ([regex]::Matches($claudeMd, [regex]::Escape('.claude/RULES.md')).Count -eq 1)) { Add-Result 'CLAUDE.md pointer appended once, content kept' 'PASS' '' } else { Add-Result 'CLAUDE.md pointer appended once, content kept' 'FAIL' $claudeMd }
    if ($r.Out -match 'read-ledger-gate: blocks a code write here') { Add-Result 'proves the gate is live' 'PASS' '' }
    elseif ($r.Out -match 'could not prove') { Add-Result 'proves the gate is live' 'INFO' 'installed kit absent; skipped' }
    else { Add-Result 'proves the gate is live' 'FAIL' $r.Out }

    # 3. Second run keeps files, appends nothing twice; -Force overwrites.
    $before = Get-Content (Join-Path $project '.claude\RULES.md') -Raw
    Add-Content (Join-Path $project '.claude\RULES.md') "`n9. owner edit"
    $r = Run @('-ProjectRoot', $project, '-SkipCodex', '-ClaudeRoot', $fakeClaude)
    $after = Get-Content (Join-Path $project '.claude\RULES.md') -Raw
    if ($r.Code -eq 0 -and $after -match 'owner edit' -and $r.Out -match 'kept\s+\.claude\\RULES\.md') { Add-Result 'idempotent: keeps edited files' 'PASS' '' } else { Add-Result 'idempotent: keeps edited files' 'FAIL' "exit $($r.Code): $($r.Out)" }
    $claudeMd = Get-Content (Join-Path $project 'CLAUDE.md') -Raw
    if (([regex]::Matches($claudeMd, [regex]::Escape('.claude/RULES.md')).Count -eq 1)) { Add-Result 'pointer not duplicated' 'PASS' '' } else { Add-Result 'pointer not duplicated' 'FAIL' $claudeMd }
    $r = Run @('-ProjectRoot', $project, '-SkipCodex', '-ClaudeRoot', $fakeClaude, '-Force')
    $after = Get-Content (Join-Path $project '.claude\RULES.md') -Raw
    if ($r.Code -eq 0 -and $after -notmatch 'owner edit') { Add-Result '-Force overwrites' 'PASS' '' } else { Add-Result '-Force overwrites' 'FAIL' "exit $($r.Code)" }

    # 4. Without -SkipCodex and no Codex hooks.json, refuses and names it.
    $fakeCodex = Join-Path $Sandbox 'codex-home'; New-Item -ItemType Directory -Force $fakeCodex | Out-Null
    $project2 = Join-Path $Sandbox 'proj2'; New-Item -ItemType Directory -Force $project2 | Out-Null
    $r = Run @('-ProjectRoot', $project2, '-ClaudeRoot', $fakeClaude, '-CodexHome', $fakeCodex)
    if ($r.Code -ne 0 -and $r.Out -match 'Codex hook kit is not installed') { Add-Result 'refuses without Codex kit' 'PASS' '' } else { Add-Result 'refuses without Codex kit' 'FAIL' "exit $($r.Code): $($r.Out)" }
    Set-Content -LiteralPath (Join-Path $fakeCodex 'hooks.json') -Value '{"hooks":{"Stop":[{"hooks":[{"command":"node C:/x/codex-hook-kit/hooks/measure-gate.mjs --codex"}]}]}}' -Encoding UTF8
    $r = Run @('-ProjectRoot', $project2, '-ClaudeRoot', $fakeClaude, '-CodexHome', $fakeCodex)
    if ($r.Code -eq 0 -and (Test-Path (Join-Path $project2 '.codex\hook-kit.json')) -and (Test-Path (Join-Path $project2 'AGENTS.md'))) { Add-Result 'writes .codex config and AGENTS.md when Codex kit present' 'PASS' '' } else { Add-Result 'writes .codex config and AGENTS.md when Codex kit present' 'FAIL' "exit $($r.Code): $($r.Out)" }
}
finally {
    Remove-Item -Recurse -Force $Sandbox -ErrorAction SilentlyContinue
}
$results | Format-Table -AutoSize | Out-String | Write-Host
$fails = @($results | Where-Object Status -eq 'FAIL').Count
Write-Host ("{0} PASS, {1} FAIL, {2} INFO" -f @($results | Where-Object Status -eq 'PASS').Count, $fails, @($results | Where-Object Status -eq 'INFO').Count)
exit $(if ($fails) { 1 } else { 0 })
