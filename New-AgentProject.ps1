<#
.SYNOPSIS
    Turn the guardrails on for a project BEFORE the first agent prompt.

.DESCRIPTION
    Added Oct 17, 2026, after Siftwing: the hook kits existed on this machine and nothing turned
    them on for the new project, so two agents ran for two days with no gate. This script writes,
    for one project folder:

      .claude\hook-kit.json      Claude hook kit policy (read-ledger, measure, sprint, double-check, rules)
      .codex\hook-kit.json       the same policy for the Codex hook kit (unless -SkipCodex)
      .claude\RULES.md           the owner's rules, injected into every prompt by inject-rules
      .claude\READ-LEDGER.md     empty ledger the read-ledger-gate checks
      work\measure\run.mjs       measurement stub that refuses to write a receipt until replaced
      work\receipts\             where receipts go
      CLAUDE.md / AGENTS.md      one pointer line each (appended, or created)

    It refuses to finish unless the Claude hook kit is installed (its entries are in the user
    settings.json). It also requires the Codex hook kit (CODEX_HOME\hooks.json) unless -SkipCodex.
    Existing files are never overwritten unless -Force.

.PARAMETER ProjectRoot
    The project folder. Must exist.
.PARAMETER Upstream
    One or more folders the read ledger's relative paths are looked up in. Default: the project.
.PARAMETER SkipCodex
    Do not write .codex\hook-kit.json and do not require the Codex kit.
.PARAMETER Force
    Overwrite files this script owns.
.PARAMETER ClaudeRoot
    Claude settings folder. Default: $env:CLAUDE_CONFIG_DIR or %USERPROFILE%\.claude.
.PARAMETER CodexHome
    Codex home. Default: $env:CODEX_HOME or %USERPROFILE%\.codex.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\New-AgentProject.ps1 -ProjectRoot C:\dev\myproj -Upstream C:\upstream\wagalo,C:\upstream\wigolo
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string[]]$Upstream,
    [switch]$SkipCodex,
    [switch]$Force,
    [string]$ClaudeRoot,
    [string]$CodexHome
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\AutonomySettings.ps1')

$project = Resolve-KitProjectRoot $ProjectRoot
$name = Split-Path $project -Leaf
$claudeRoot = Resolve-KitConfigRoot $ClaudeRoot
if (-not $CodexHome) { $CodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE '.codex' } }
$templates = Join-Path $PSScriptRoot 'templates\agent-project'
if (-not $Upstream -or -not $Upstream.Count) { $Upstream = @($project) }

function Step($m) { Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Say($m) { Write-Host "  $m" }
$written = New-Object System.Collections.Generic.List[string]
$skipped = New-Object System.Collections.Generic.List[string]

# ---- 1. Are the kits installed? Refuse early; a config with no kit behind it is false comfort.
Step 'Check the hook kits are installed'
$settingsPath = Join-Path $claudeRoot 'settings.json'
$claudeOk = $false
if (Test-Path -LiteralPath $settingsPath) {
    $raw = Get-Content -LiteralPath $settingsPath -Raw
    $claudeOk = ($raw -match 'hook-kit[\\/]+hooks[\\/]+read-ledger-gate\.mjs') -and ($raw -match 'hook-kit[\\/]+hooks[\\/]+measure-gate\.mjs')
}
if (-not $claudeOk) {
    throw "The Claude hook kit is not installed: $settingsPath has no read-ledger-gate / measure-gate entries. Run `node install.mjs` in claude-hook-kit first."
}
Say "Claude hook kit: registered in $settingsPath"
$codexOk = $false
$codexHooks = Join-Path $CodexHome 'hooks.json'
if (-not $SkipCodex) {
    if (Test-Path -LiteralPath $codexHooks) { $codexOk = (Get-Content -LiteralPath $codexHooks -Raw) -match 'codex-hook-kit' }
    if (-not $codexOk) {
        throw "The Codex hook kit is not installed: $codexHooks is missing or has no codex-hook-kit entries. Run `node install.mjs` in codex-hook-kit, trust the hooks in Codex, or pass -SkipCodex."
    }
    Say "Codex hook kit: registered in $codexHooks"
} else { Say 'Codex: skipped (-SkipCodex)' }

# ---- 2. Write files from templates.
function Write-Owned {
    param([string]$Relative, [string]$Content)
    $target = Join-Path $project $Relative
    if ((Test-Path -LiteralPath $target) -and -not $Force) { $skipped.Add($Relative); return }
    $dir = Split-Path $target -Parent
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [IO.File]::WriteAllText($target, $Content, (New-Object System.Text.UTF8Encoding($false)))
    $written.Add($Relative)
}
function Fill {
    param([string]$Text, [string]$ConfigDir)
    $up = ($Upstream | ForEach-Object { ($_ -replace '\\', '/') }) -join '", "'
    return $Text.Replace('__PROJECT__', $name).Replace('__CONFIG_DIR__', $ConfigDir).Replace('__UPSTREAM__', $up)
}
# -Encoding UTF8: Windows PowerShell 5.1 would otherwise read the templates' em dashes as mojibake.
$tplRules = Get-Content -LiteralPath (Join-Path $templates 'RULES.md') -Raw -Encoding UTF8
$tplLedger = Get-Content -LiteralPath (Join-Path $templates 'READ-LEDGER.md') -Raw -Encoding UTF8
$tplKit = Get-Content -LiteralPath (Join-Path $templates 'hook-kit.json') -Raw -Encoding UTF8
$tplMeasure = Get-Content -LiteralPath (Join-Path $templates 'measure-run.mjs') -Raw -Encoding UTF8

Step "Write the project files in $project"
Write-Owned '.claude\RULES.md' (Fill $tplRules '.claude')
Write-Owned '.claude\READ-LEDGER.md' (Fill $tplLedger '.claude')
Write-Owned '.claude\hook-kit.json' (Fill $tplKit '.claude')
if (-not $SkipCodex) {
    # The Codex kit reads .codex/hook-kit.json; the rules and ledger stay in .claude so both hosts share one copy.
    Write-Owned '.codex\hook-kit.json' (Fill $tplKit '.claude')
}
Write-Owned 'work\measure\run.mjs' (Fill $tplMeasure '.claude')
$receipts = Join-Path $project 'work\receipts'
if (-not (Test-Path -LiteralPath $receipts)) { New-Item -ItemType Directory -Force $receipts | Out-Null; $written.Add('work\receipts\') }

# Pointer lines in the host instruction files, once.
foreach ($hostFile in @('CLAUDE.md', 'AGENTS.md')) {
    if ($hostFile -eq 'AGENTS.md' -and $SkipCodex) { continue }
    $target = Join-Path $project $hostFile
    $line = "- Project rules: read `.claude/RULES.md` first. Hooks enforce the read ledger, the measurement receipt and the citation ledger; see `.claude/hook-kit.json`."
    $existing = if (Test-Path -LiteralPath $target) { Get-Content -LiteralPath $target -Raw } else { '' }
    if ($existing -match [regex]::Escape('.claude/RULES.md')) { $skipped.Add($hostFile); continue }
    $prefix = if ($existing) { $existing.TrimEnd() + "`n`n" } else { "# $name`n`n" }
    [IO.File]::WriteAllText($target, $prefix + $line + "`n", (New-Object System.Text.UTF8Encoding($false)))
    $written.Add($hostFile)
}

# ---- 3. Validate what was written.
Step 'Validate'
foreach ($rel in @('.claude\hook-kit.json') + $(if (-not $SkipCodex) { @('.codex\hook-kit.json') } else { @() })) {
    $p = Join-Path $project $rel
    try { $null = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json } catch { throw "$rel is not valid JSON: $($_.Exception.Message)" }
    Say "$rel parses"
}
$ledgerGate = Join-Path $claudeRoot 'hook-kit\hooks\read-ledger-gate.mjs'
if (Test-Path -LiteralPath $ledgerGate) {
    # Prove the gate is live here: a code write with an empty ledger must be blocked (exit 2).
    $ev = @{ tool_name = 'Write'; cwd = $project; tool_input = @{ file_path = (Join-Path $project 'src\probe.ts'); content = 'x' } } | ConvertTo-Json -Compress
    $evFile = Join-Path $env:TEMP ("new-agent-project-probe-" + [guid]::NewGuid().ToString('n') + '.json')
    [IO.File]::WriteAllText($evFile, $ev, (New-Object System.Text.UTF8Encoding($false)))
    # Run through cmd so stdin is a file and the hook's stderr cannot become a terminating error here.
    $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $out = (cmd /c "node ""$ledgerGate"" < ""$evFile"" 2>&1" | ForEach-Object { "$_" }) -join "`n"; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $prevEap; Remove-Item -LiteralPath $evFile -Force -ErrorAction SilentlyContinue }
    if ($code -eq 2) { Say 'read-ledger-gate: blocks a code write here (exit 2). The gate is live.' }
    else { throw "read-ledger-gate did not block a code write in $project (exit $code). Output: $out" }
} else { Say "read-ledger-gate not found at $ledgerGate; could not prove the gate is live (installed copy missing?)" }

Step 'Done'
foreach ($w in $written) { Say "wrote   $w" }
foreach ($s in $skipped) { Say "kept    $s (exists; use -Force to overwrite)" }
Say ''
Say 'Next: edit .claude\hook-kit.json (upstreamRoots, mustMention, minEntries, minLines, measureCommand),'
Say '      replace work\measure\run.mjs with the real measurement, then give the agent its first prompt.'
if (-not $SkipCodex) { Say '      Codex: make sure the kit hooks are trusted (/hooks) before the first Codex session.' }
