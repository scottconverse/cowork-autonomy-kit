<#
.SYNOPSIS
    Tests for Test-CiStandard.ps1 against the fixture repositories under tests/fixtures/ci-standard.
    Runs the checker in a child Windows PowerShell process, like CI does, and asserts on exit code
    and on the PASS/FAIL rows (rule, file, line). Never touches a real repository.
#>
param([string]$Sandbox = (Join-Path $env:TEMP ("ci-standard-test-" + [guid]::NewGuid().ToString("n"))))
$ErrorActionPreference = 'Stop'
$script = Join-Path (Split-Path $PSScriptRoot -Parent) 'Test-CiStandard.ps1'
$fixtures = Join-Path $PSScriptRoot 'fixtures\ci-standard'
$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Name, [string]$Status, [string]$Detail) { $results.Add([pscustomobject]@{ Name = $Name; Status = $Status; Detail = $Detail }) }
function Run([string[]]$ArgList) {
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = (& powershell -NoProfile -ExecutionPolicy Bypass -File $script @ArgList 2>&1 | ForEach-Object { "$_" }) -join "`n"; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prev }
    return @{ Code = $code; Out = $out }
}
# Row regex: "<STATUS> <rule> <file>:<line>  <detail>". Rows are padded, so match on whitespace runs.
function Row([string]$Status, [string]$Rule, [string]$File, [int]$Line) { return ('(?m)^' + $Status + '\s+' + [regex]::Escape($Rule) + '\s+' + [regex]::Escape(".github/workflows/$File") + ':' + $Line + '\b') }
function Expect([string]$Name, [hashtable]$R, [string]$Pattern, [bool]$Present = $true) {
    $hit = $R.Out -match $Pattern
    if ($hit -eq $Present) { Add-Result $Name 'PASS' '' } else { Add-Result $Name 'FAIL' ("exit $($R.Code); pattern '$Pattern' present=$hit`n$($R.Out)") }
}

New-Item -ItemType Directory -Force $Sandbox | Out-Null
try {
    # 1. Good fixtures: three workflow kinds, all rules pass, exit 0.
    $r = Run @('-RepoRoot', (Join-Path $fixtures 'good'))
    if ($r.Code -eq 0) { Add-Result 'good: exit 0' 'PASS' '' } else { Add-Result 'good: exit 0' 'FAIL' "exit $($r.Code): $($r.Out)" }
    Expect 'good: summary has 0 FAIL' $r '(?m)^SUMMARY: 14 PASS / 0 FAIL$'
    Expect 'good: unfiltered PR workflow is required' $r '(?m)^\s+required \.github/workflows/required\.yml$'
    Expect 'good: path-filtered push workflow is a check' $r '(?m)^\s+check\s+\.github/workflows/nightly-docs\.yml$'
    Expect 'good: tag/dispatch workflow is an event' $r '(?m)^\s+event\s+\.github/workflows/release\.yml$'
    Expect 'good: nightly cron accepted with line' $r (Row 'PASS' 'nightly' 'nightly-docs.yml' 7)
    Expect 'good: cancel-in-progress PR expression accepted' $r (Row 'PASS' 'concurrency' 'nightly-docs.yml' 8)
    Expect 'good: reusable-workflow job skipped for timeout' $r "job 'checks'" $false
    Expect 'good: event workflow gets no nightly rule' $r 'nightly\s+\.github/workflows/release\.yml' $false
    Expect 'good: release workflow exempt from artifact-retention' $r 'artifact-retention\s+\.github/workflows/release\.yml' $false

    # 2. Bad fixtures: every rule fails somewhere, with the right file and line; exit 1.
    $r = Run @('-RepoRoot', (Join-Path $fixtures 'bad'))
    if ($r.Code -eq 1) { Add-Result 'bad: exit 1' 'PASS' '' } else { Add-Result 'bad: exit 1' 'FAIL' "exit $($r.Code): $($r.Out)" }
    Expect 'bad: summary counts' $r '(?m)^SUMMARY: 6 PASS / 12 FAIL / 1 INFO$'
    Expect 'bad: cancel-in-progress false fails at the concurrency line' $r (Row 'FAIL' 'concurrency' 'cancel-false.yml' 8)
    Expect 'bad: missing concurrency fails at the on: line' $r (Row 'FAIL' 'concurrency' 'every-push.yml' 2)
    Expect 'bad: unfiltered push on a non-required check' $r (Row 'FAIL' 'every-push' 'every-push.yml' 3)
    Expect 'bad: no schedule on a non-required check' $r (Row 'FAIL' 'nightly' 'every-push.yml' 2)
    Expect 'bad: weekly cron is not nightly' $r ((Row 'FAIL' 'nightly' 'weekly.yml' 6) + ".*'0 3 \* \* 1' is not nightly")
    Expect 'bad: timeout over budget at its own line' $r ((Row 'FAIL' 'job-timeout' 'cancel-false.yml' 14) + '.*timeout-minutes: 30 exceeds 10')
    Expect 'bad: missing timeout at the job line' $r (Row 'FAIL' 'job-timeout' 'every-push.yml' 7)
    Expect 'bad: expression timeout is INFO' $r (Row 'INFO' 'job-timeout' 'weekly.yml' 13)
    Expect 'bad: duplicate push main + pull_request (list-form branches)' $r (Row 'FAIL' 'duplicate-trigger' 'cancel-false.yml' 3)
    Expect 'bad: heavy marker without paths' $r (Row 'FAIL' 'heavy-paths' 'cancel-false.yml' 17)
    Expect 'bad: heavy marker without cache' $r (Row 'FAIL' 'heavy-cache' 'cancel-false.yml' 17)
    Expect 'bad: upload-artifact without retention-days' $r (Row 'FAIL' 'artifact-retention' 'every-push.yml' 13)
    Expect 'bad: required workflow gets no nightly rule' $r 'nightly\s+\.github/workflows/cancel-false\.yml' $false
    Expect 'bad: path-filtered push passes every-push' $r (Row 'PASS' 'every-push' 'weekly.yml' 3)

    # 3. Required budget: 11 unfiltered-PR jobs exceed 10; -MaxRequired and -Required change the count.
    $r = Run @('-RepoRoot', (Join-Path $fixtures 'too-many'))
    Expect 'budget: 11 required jobs fail' $r ((Row 'FAIL' 'required-budget' 'required.yml' 2) + '.*11 required jobs')
    if ($r.Code -eq 1) { Add-Result 'budget: exit 1' 'PASS' '' } else { Add-Result 'budget: exit 1' 'FAIL' "exit $($r.Code)" }
    $r = Run @('-RepoRoot', (Join-Path $fixtures 'too-many'), '-MaxRequired', '11')
    Expect 'budget: -MaxRequired 11 passes' $r ((Row 'PASS' 'required-budget' 'required.yml' 2) + '.*budget 11')
    if ($r.Code -eq 0) { Add-Result 'budget: exit 0 with raised budget' 'PASS' '' } else { Add-Result 'budget: exit 0 with raised budget' 'FAIL' "exit $($r.Code): $($r.Out)" }
    $r = Run @('-RepoRoot', (Join-Path $fixtures 'too-many'), '-Required', 'none.yml')
    Expect 'budget: -Required overrides the heuristic' $r '(?m)^PASS\s+required-budget\s+\.github/workflows:0\s+0 required job'

    # 4. .github/ci-standard.json: names the required workflow and raises maxJobMinutes.
    $r = Run @('-RepoRoot', (Join-Path $fixtures 'config'))
    if ($r.Code -eq 0) { Add-Result 'config: exit 0' 'PASS' '' } else { Add-Result 'config: exit 0' 'FAIL' "exit $($r.Code): $($r.Out)" }
    Expect 'config: listed workflow is required despite paths filter' $r '(?m)^\s+required \.github/workflows/checks\.yml$'
    Expect 'config: required workflow needs no nightly' $r '(?m)^FAIL\s+nightly' $false
    Expect 'config: maxJobMinutes 15 accepted from config' $r ((Row 'PASS' 'job-timeout' 'checks.yml' 11) + '.*timeout-minutes: 15')

    # 5. A repository with no workflows passes trivially.
    $empty = Join-Path $Sandbox 'empty'; New-Item -ItemType Directory -Force $empty | Out-Null
    $r = Run @('-RepoRoot', $empty)
    if ($r.Code -eq 0 -and $r.Out -match 'PASS: no workflow files') { Add-Result 'empty repo: PASS, exit 0' 'PASS' '' } else { Add-Result 'empty repo: PASS, exit 0' 'FAIL' "exit $($r.Code): $($r.Out)" }

    # 6. A BOM-prefixed workflow is read without the BOM breaking the top-level key scan.
    $bom = Join-Path $Sandbox 'bom\.github\workflows'; New-Item -ItemType Directory -Force $bom | Out-Null
    $good = Get-Content -LiteralPath (Join-Path $fixtures 'good\.github\workflows\required.yml') -Raw
    [System.IO.File]::WriteAllText((Join-Path $bom 'ci.yml'), $good, (New-Object System.Text.UTF8Encoding($true)))
    $r = Run @('-RepoRoot', (Join-Path $Sandbox 'bom'))
    if ($r.Code -eq 0 -and $r.Out -match '(?m)^\s+required \.github/workflows/ci\.yml$') { Add-Result 'BOM workflow parsed' 'PASS' '' } else { Add-Result 'BOM workflow parsed' 'FAIL' "exit $($r.Code): $($r.Out)" }
}
finally {
    Remove-Item -Recurse -Force $Sandbox -ErrorAction SilentlyContinue
}
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
$fails = @($results | Where-Object Status -eq 'FAIL').Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL" -f @($results | Where-Object Status -eq 'PASS').Count, $fails)
exit $(if ($fails) { 1 } else { 0 })
