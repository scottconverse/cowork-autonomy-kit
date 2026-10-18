<#
.SYNOPSIS
    CI-standard check for a repository's GitHub Actions workflows. Reports PASS/FAIL per rule
    with file and line; exits 1 on any FAIL.

.DESCRIPTION
    Port of scripts/check_actions_budget.py (agent-pipeline-codex, archived) to Windows
    PowerShell 5.1, re-aimed at the owner's CI standard (~/.claude/CLAUDE.md, "CI standard"):

      - Run only the checks that protect the product; make only those required; about 10.
      - A check that does not block a merge runs only when its own files change, plus once a
        night on main. It never runs on every push.
      - Every workflow cancels the old run when a new commit is pushed to the same branch
        (concurrency with cancel-in-progress on PRs).
      - Split any check over 10 minutes.

    Rules (id -> origin):
      required-budget     standard. Jobs in required workflows <= -MaxRequired (default 10).
      every-push          standard. A non-required workflow with a push/pull_request trigger
                          that has no `paths:` filter runs on every push -> FAIL.
      nightly             standard. A non-required workflow needs a nightly cron. The original
                          FORBADE daily crons ("weekly is the maximum default"); the standard
                          requires one nightly run on main, so the rule is inverted here.
      concurrency         original + standard. The original exempted release/tag workflows and
                          demanded the exact group `${{ github.workflow }}-${{ github.ref }}`.
                          The standard says every workflow, and names only the behaviour, so
                          here every workflow needs a `concurrency:` block with a `group:` and
                          `cancel-in-progress: true` (or an expression naming pull_request).
      job-timeout         standard. Duration cannot be measured statically; the proxy is that
                          every job declares `timeout-minutes` <= -MaxJobMinutes (default 10).
                          Reusable-workflow jobs (job-level `uses:`) are skipped; a non-numeric
                          value is reported INFO.
      duplicate-trigger   original, carried unchanged: pull_request plus push-to-main on one
                          workflow is a duplicate validation run. The standard is silent.
      heavy-paths         original, carried unchanged: a heavy marker (docker build, playwright
      heavy-cache         install, ...) needs a `paths:` filter and cache coverage.
      artifact-retention  original, carried unchanged (release/tag workflows exempt):
                          upload-artifact steps set `retention-days: 7`.

    Not carried over (see docs/handoff-ci-standard-check.md): changed-files/--run/--base-ref git
    modes, the macOS/Windows PR runner bans, the single-Python-version matrix rule.

    "Required" means a workflow that blocks every PR. With no configuration the heuristic is: a
    workflow with a pull_request/pull_request_target trigger that has no `paths:` filter. Override
    with -Required (workflow file names) or `.github/ci-standard.json`:
        { "required": ["windows.yml"], "maxRequired": 10, "maxJobMinutes": 10 }
    Workflows with no push/pull_request trigger (tag-only, workflow_dispatch, schedule-only) are
    events, not checks; every-push and nightly do not apply to them.

    This is a text scanner, not a YAML parser. It understands the indentation shapes GitHub
    workflows actually use; anchors, multi-document files and flow mappings are out of scope.

.PARAMETER RepoRoot
    Repository root containing .github/workflows.
.PARAMETER Required
    Workflow file names (e.g. ci.yml) treated as required. Replaces the heuristic and the config.
.PARAMETER MaxRequired
    Budget of required jobs. Default 10 ("about 10").
.PARAMETER MaxJobMinutes
    Largest acceptable `timeout-minutes` per job. Default 10.
.PARAMETER PassThru
    Also emit one object per result.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-CiStandard.ps1 -RepoRoot C:\dev\MyRepo
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [string[]]$Required,
    [int]$MaxRequired = 10,
    [int]$MaxJobMinutes = 10,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'

$HeavyMarkers = @('apt-get install', 'docker build', 'docker/build-push-action', 'install browsers',
    'playwright install', 'setup-texlive', 'texlive', 'ollama pull', 'cleanroom', 'e2e')
$CacheMarkers = @('actions/cache@', 'cache: pip', 'cache: npm', 'cache-from:', 'cache-to:')

# ---- line helpers -------------------------------------------------------------------------
function Get-Indent([string]$s) { return ($s.Length - $s.TrimStart(' ').Length) }
function Test-Skippable([string]$s) { return ($s.Trim() -eq '' -or $s.TrimStart().StartsWith('#') -or $s -match '^---\s*$') }
function Get-InlineValue([string]$line) {
    if ($line -match '^\s*[^:]+?\s*:\s*(.*)$') { return ($matches[1] -replace '\s+#.*$', '').Trim() }
    return ''
}
function Get-ChildIndices([string[]]$lines, [int]$parent) {
    $pi = Get-Indent $lines[$parent]
    $out = New-Object System.Collections.Generic.List[int]
    for ($i = $parent + 1; $i -lt $lines.Count; $i++) {
        if (Test-Skippable $lines[$i]) { continue }
        if ((Get-Indent $lines[$i]) -le $pi) { break }
        $out.Add($i)
    }
    return ,@($out)
}
function Get-DirectChildren([string[]]$lines, [int]$parent) {
    $kids = Get-ChildIndices $lines $parent
    if ($kids.Count -eq 0) { return ,@() }
    $min = ($kids | ForEach-Object { Get-Indent $lines[$_] } | Measure-Object -Minimum).Minimum
    return ,@($kids | Where-Object { (Get-Indent $lines[$_]) -eq $min })
}
function Find-Key([string[]]$lines, [int[]]$indices, [string]$key) {
    $re = '^\s*(-\s*)?[''"]?' + [regex]::Escape($key) + '[''"]?\s*:'
    foreach ($i in $indices) { if ($lines[$i] -match $re) { return $i } }
    return -1
}
function Test-NightlyCron([string]$expr) {
    if ($expr -in @('@daily', '@midnight')) { return $true }
    $f = $expr -split '\s+'
    return ($f.Count -eq 5 -and $f[2] -eq '*' -and $f[3] -eq '*' -and $f[4] -eq '*')
}
function Test-CancelValue([string]$v) {
    return ($v -eq 'true' -or ($v -like '*${{*' -and $v -like '*pull_request*'))
}
function Test-ConcurrencyBlock([string[]]$lines, [int]$idx) {
    # true when the block under $idx has a group and an acceptable cancel-in-progress value
    $kids = Get-DirectChildren $lines $idx
    $g = Find-Key $lines $kids 'group'
    $c = Find-Key $lines $kids 'cancel-in-progress'
    return ($g -ge 0 -and $c -ge 0 -and (Test-CancelValue (Get-InlineValue $lines[$c])))
}

# ---- workflow model ---------------------------------------------------------------------
function Read-Workflow([System.IO.FileInfo]$file) {
    $text = [System.IO.File]::ReadAllText($file.FullName)   # ReadAllText strips a UTF-8 BOM
    $lines = @($text -split "`r?`n")
    $top = @(0..($lines.Count - 1) | Where-Object { -not (Test-Skippable $lines[$_]) -and (Get-Indent $lines[$_]) -eq 0 })

    $triggers = New-Object System.Collections.Generic.List[object]
    $onIdx = Find-Key $lines $top 'on'
    if ($onIdx -ge 0) {
        $val = Get-InlineValue $lines[$onIdx]
        $add = { param($name, $line) $triggers.Add([pscustomobject]@{ Name = $name; Line = $line; HasPaths = $false; HasBranches = $false; HasTags = $false; OnMain = $false; Crons = @() }) }
        if ($val -match '^\[(.*)\]$') {
            foreach ($n in ($matches[1] -split ',')) { $n = $n.Trim(" '`""); if ($n) { & $add $n ($onIdx + 1) } }
        } elseif ($val) {
            & $add $val ($onIdx + 1)
        } else {
            foreach ($k in (Get-DirectChildren $lines $onIdx)) {
                $t = $lines[$k].Trim()
                if ($t -match '^-\s*(.+)$') { & $add ($matches[1].Trim(" '`"")) ($k + 1); continue }
                if ($t -notmatch '^[''"]?([A-Za-z_]+)[''"]?\s*:') { continue }
                $name = $matches[1]
                & $add $name ($k + 1)
                $trig = $triggers[$triggers.Count - 1]
                $tk = Get-DirectChildren $lines $k
                $trig.HasPaths = (Find-Key $lines $tk 'paths') -ge 0
                $trig.HasTags = (Find-Key $lines $tk 'tags') -ge 0
                $bi = Find-Key $lines $tk 'branches'
                if ($bi -ge 0) {
                    $trig.HasBranches = $true
                    $bv = Get-InlineValue $lines[$bi]
                    if ($bv -match '(^|[\[,\s''"])main([\]\s,''"]|$)') { $trig.OnMain = $true }
                    foreach ($c in (Get-ChildIndices $lines $bi)) { if ($lines[$c] -match '^\s*-\s*[''"]?main[''"]?\s*$') { $trig.OnMain = $true } }
                }
                if ($name -eq 'schedule') {
                    foreach ($c in (Get-ChildIndices $lines $k)) {
                        if ($lines[$c] -match 'cron:\s*[''"]([^''"]+)[''"]') { $trig.Crons += ,([pscustomobject]@{ Expr = $matches[1]; Line = $c + 1 }) }
                    }
                }
            }
        }
    }

    $jobs = New-Object System.Collections.Generic.List[object]
    $jobsIdx = Find-Key $lines $top 'jobs'
    if ($jobsIdx -ge 0) {
        foreach ($j in (Get-DirectChildren $lines $jobsIdx)) {
            if ($lines[$j] -notmatch '^\s*[''"]?([^\s:''"]+)[''"]?\s*:') { continue }
            $jk = Get-DirectChildren $lines $j
            $jobs.Add([pscustomobject]@{
                Name       = $matches[1]; Line = $j + 1; Keys = $jk
                IsReusable = ((Find-Key $lines $jk 'uses') -ge 0)
                TimeoutIdx = (Find-Key $lines $jk 'timeout-minutes')
                ConcIdx    = (Find-Key $lines $jk 'concurrency')
            })
        }
    }

    $checkTriggers = @($triggers | Where-Object {
        $_.Name -in @('push', 'pull_request', 'pull_request_target') -and -not ($_.Name -eq 'push' -and $_.HasTags -and -not $_.HasBranches) })
    $prUnfiltered = @($triggers | Where-Object { $_.Name -like 'pull_request*' -and -not $_.HasPaths }).Count -gt 0
    $tagTrigger = @($triggers | Where-Object { $_.HasTags }).Count -gt 0

    return [pscustomobject]@{
        File = $file; Rel = ('.github/workflows/' + $file.Name); Lines = $lines; Text = $text
        OnLine = $(if ($onIdx -ge 0) { $onIdx + 1 } else { 1 })
        Triggers = $triggers.ToArray(); CheckTriggers = $checkTriggers; Jobs = $jobs.ToArray()
        ConcurrencyIdx = (Find-Key $lines $top 'concurrency')
        HeuristicRequired = $prUnfiltered
        IsCheck = ($checkTriggers.Count -gt 0)
        # The original also treated "release"/"tag" in the file name as release workflows.
        IsReleaseOrTag = ($tagTrigger -or $file.Name -match '(?i)release|tag')
        Kind = ''
    }
}

# ---- results ----------------------------------------------------------------------------
$results = New-Object System.Collections.Generic.List[object]
function Add-Result([string]$Rule, [string]$Status, [string]$File, [int]$Line, [string]$Detail) {
    $results.Add([pscustomobject]@{ Rule = $Rule; Status = $Status; File = $File; Line = $Line; Detail = $Detail })
}

# ---- main -------------------------------------------------------------------------------
$root = (Resolve-Path -LiteralPath $RepoRoot).ProviderPath
$wfDir = Join-Path $root '.github\workflows'
$files = @()
if (Test-Path -LiteralPath $wfDir -PathType Container) {
    $files = @(Get-ChildItem -LiteralPath $wfDir -File | Where-Object { $_.Extension -in @('.yml', '.yaml') } | Sort-Object Name)
}
if ($files.Count -eq 0) {
    Write-Host "PASS: no workflow files under $wfDir" -ForegroundColor Green
    Write-Host 'SUMMARY: 0 PASS / 0 FAIL'
    exit 0
}

$configPath = Join-Path $root '.github\ci-standard.json'
$requiredNames = $null
if ($Required) { $requiredNames = @($Required) }
elseif (Test-Path -LiteralPath $configPath) {
    $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ($cfg.PSObject.Properties.Name -contains 'required') { $requiredNames = @($cfg.required) }
    if (-not $PSBoundParameters.ContainsKey('MaxRequired') -and $cfg.PSObject.Properties.Name -contains 'maxRequired') { $MaxRequired = [int]$cfg.maxRequired }
    if (-not $PSBoundParameters.ContainsKey('MaxJobMinutes') -and $cfg.PSObject.Properties.Name -contains 'maxJobMinutes') { $MaxJobMinutes = [int]$cfg.maxJobMinutes }
}

$workflows = @($files | ForEach-Object { Read-Workflow $_ })
foreach ($w in $workflows) {
    $isRequired = $(if ($null -ne $requiredNames) { $requiredNames -contains $w.File.Name } else { $w.HeuristicRequired })
    $w.Kind = $(if ($isRequired) { 'required' } elseif ($w.IsCheck) { 'check' } else { 'event' })
}

# required-budget (repository-level)
$reqWf = @($workflows | Where-Object Kind -eq 'required')
$reqJobs = ($reqWf | ForEach-Object { $_.Jobs.Count } | Measure-Object -Sum).Sum
if (-not $reqJobs) { $reqJobs = 0 }
$reqList = $(if ($reqWf) { ($reqWf | ForEach-Object { $_.File.Name }) -join ', ' } else { '(none)' })
$budgetLine = $(if ($reqWf) { $reqWf[0].OnLine } else { 0 })
$budgetFile = $(if ($reqWf) { $reqWf[0].Rel } else { '.github/workflows' })
if ($reqJobs -gt $MaxRequired) { Add-Result 'required-budget' 'FAIL' $budgetFile $budgetLine "$reqJobs required jobs in [$reqList]; the standard allows about $MaxRequired. Make only the checks that protect the product required." }
else { Add-Result 'required-budget' 'PASS' $budgetFile $budgetLine "$reqJobs required job(s) in [$reqList]; budget $MaxRequired" }

foreach ($w in $workflows) {
    $lines = $w.Lines

    # concurrency: every workflow (standard), not just non-release ones (original)
    $ok = $false; $where = $w.OnLine
    if ($w.ConcurrencyIdx -ge 0) { $where = $w.ConcurrencyIdx + 1; $ok = Test-ConcurrencyBlock $lines $w.ConcurrencyIdx }
    if (-not $ok -and $w.Jobs.Count -gt 0 -and @($w.Jobs | Where-Object { $_.ConcIdx -lt 0 }).Count -eq 0) {
        $ok = @($w.Jobs | Where-Object { -not (Test-ConcurrencyBlock $lines $_.ConcIdx) }).Count -eq 0
        if ($ok) { $where = $w.Jobs[0].ConcIdx + 1 }
    }
    if ($ok) { Add-Result 'concurrency' 'PASS' $w.Rel $where 'cancels superseded runs' }
    elseif ($w.ConcurrencyIdx -ge 0) { Add-Result 'concurrency' 'FAIL' $w.Rel $where 'concurrency block needs group: and cancel-in-progress: true (or an expression naming pull_request)' }
    else { Add-Result 'concurrency' 'FAIL' $w.Rel $where 'missing concurrency block with cancel-in-progress' }

    if ($w.Kind -eq 'check') {
        # every-push: a non-required check must run only when its own files change
        $unfiltered = @($w.CheckTriggers | Where-Object { -not $_.HasPaths })
        if ($unfiltered.Count) { foreach ($t in $unfiltered) { Add-Result 'every-push' 'FAIL' $w.Rel $t.Line "non-required check runs on every $($t.Name); add a paths: filter for its own files" } }
        else { Add-Result 'every-push' 'PASS' $w.Rel $w.CheckTriggers[0].Line 'path-filtered' }

        # nightly: plus once a night on main (inverted from the original's daily-cron ban)
        $crons = @($w.Triggers | Where-Object Name -eq 'schedule' | ForEach-Object { $_.Crons })
        $nightly = @($crons | Where-Object { Test-NightlyCron $_.Expr })
        if ($nightly.Count) { Add-Result 'nightly' 'PASS' $w.Rel $nightly[0].Line "cron '$($nightly[0].Expr)'" }
        elseif ($crons.Count) { Add-Result 'nightly' 'FAIL' $w.Rel $crons[0].Line "cron '$($crons[0].Expr)' is not nightly; a non-required check runs once a night on main" }
        else { Add-Result 'nightly' 'FAIL' $w.Rel $w.OnLine 'no schedule; a non-required check runs once a night on main' }
    }

    # job-timeout
    foreach ($j in $w.Jobs) {
        if ($j.IsReusable) { continue }
        if ($j.TimeoutIdx -lt 0) { Add-Result 'job-timeout' 'FAIL' $w.Rel $j.Line "job '$($j.Name)' has no timeout-minutes; declare $MaxJobMinutes or less, or split the check"; continue }
        $v = Get-InlineValue $lines[$j.TimeoutIdx]
        $n = 0
        if ([int]::TryParse($v, [ref]$n)) {
            if ($n -le $MaxJobMinutes) { Add-Result 'job-timeout' 'PASS' $w.Rel ($j.TimeoutIdx + 1) "job '$($j.Name)' timeout-minutes: $n" }
            else { Add-Result 'job-timeout' 'FAIL' $w.Rel ($j.TimeoutIdx + 1) "job '$($j.Name)' timeout-minutes: $n exceeds $MaxJobMinutes; split it into parallel parts" }
        } else { Add-Result 'job-timeout' 'INFO' $w.Rel ($j.TimeoutIdx + 1) "job '$($j.Name)' timeout-minutes is an expression ('$v'); not checked" }
    }

    # duplicate-trigger (carried from the original)
    $hasPr = @($w.Triggers | Where-Object { $_.Name -like 'pull_request*' }).Count -gt 0
    $pushMain = @($w.Triggers | Where-Object { $_.Name -eq 'push' -and $_.OnMain })
    if ($hasPr -and $pushMain.Count) { Add-Result 'duplicate-trigger' 'FAIL' $w.Rel $pushMain[0].Line 'duplicates pull_request main and push main for the same validation workflow' }
    elseif ($w.Triggers.Count) { Add-Result 'duplicate-trigger' 'PASS' $w.Rel $w.OnLine 'no duplicate validation trigger' }

    # heavy-paths / heavy-cache (carried from the original)
    $lower = $w.Text.ToLowerInvariant()
    $heavyLine = 0
    for ($i = 0; $i -lt $lines.Count -and -not $heavyLine; $i++) { foreach ($m in $HeavyMarkers) { if ($lines[$i].ToLowerInvariant().Contains($m)) { $heavyLine = $i + 1; break } } }
    if ($heavyLine) {
        if ($lower.Contains('paths:')) { Add-Result 'heavy-paths' 'PASS' $w.Rel $heavyLine 'heavy workflow has a paths filter' }
        else { Add-Result 'heavy-paths' 'FAIL' $w.Rel $heavyLine 'heavy workflow is missing paths filters' }
        $cached = @($CacheMarkers | Where-Object { $lower.Contains($_) }).Count -gt 0
        if ($cached) { Add-Result 'heavy-cache' 'PASS' $w.Rel $heavyLine 'heavy workflow has cache coverage' }
        else { Add-Result 'heavy-cache' 'FAIL' $w.Rel $heavyLine 'heavy workflow is missing cache coverage for expensive installs/downloads' }
    }

    # artifact-retention (carried from the original, including its release/tag exemption)
    if (-not $w.IsReleaseOrTag) {
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch 'uses:\s*actions/upload-artifact@') { continue }
            $base = Get-Indent $lines[$i]
            $block = @($lines[$i])
            for ($k = $i + 1; $k -lt $lines.Count; $k++) {
                if ($lines[$k].TrimStart().StartsWith('- ') -and (Get-Indent $lines[$k]) -le $base) { break }
                $block += $lines[$k]
            }
            if (($block -join "`n") -match 'retention-days:\s*7\b') { Add-Result 'artifact-retention' 'PASS' $w.Rel ($i + 1) 'retention-days: 7' }
            else { Add-Result 'artifact-retention' 'FAIL' $w.Rel ($i + 1) 'upload-artifact step is missing retention-days: 7' }
        }
    }
}

# ---- report -----------------------------------------------------------------------------
Write-Host "CI standard: $root"
foreach ($w in $workflows) { Write-Host ("  {0,-8} {1}" -f $w.Kind, $w.Rel) }
Write-Host ''
foreach ($r in $results) {
    $color = switch ($r.Status) { 'PASS' { 'Green' } 'FAIL' { 'Red' } default { 'Yellow' } }
    Write-Host ("{0,-4} {1,-19} {2}:{3}  {4}" -f $r.Status, $r.Rule, $r.File, $r.Line, $r.Detail) -ForegroundColor $color
}
$pass = @($results | Where-Object Status -eq 'PASS').Count
$fail = @($results | Where-Object Status -eq 'FAIL').Count
$info = @($results | Where-Object Status -eq 'INFO').Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL" -f $pass, $fail) -NoNewline
if ($info) { Write-Host (" / {0} INFO" -f $info) } else { Write-Host '' }
if ($PassThru) { $results }
exit $(if ($fail) { 1 } else { 0 })
