<#
.SYNOPSIS
    Capability harness for the Claude Cowork Autonomy Kit (Part 1 of the test plan).

.DESCRIPTION
    Proves the machine-level actions the kit is meant to enable actually execute, in a
    self-contained sandbox. This half answers "CAN the work be done." It does NOT measure
    Claude's behavior (no unrequested friction, honors your bounds) -- that is Parts 2-3 of
    TEST-PLAN.md, which are behavioral and run by handing Claude tasks under the kit.

    Everything destructive here happens inside a throwaway sandbox dir and is cleaned up.
    Registry and scheduled-task checks are read-only. Network check is a single benign GET.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\Test-AutonomyKit.ps1
#>
param(
    [string]$Sandbox = (Join-Path $env:TEMP ("autonomy-kit-test-" + [guid]::NewGuid().ToString("n"))),
    [switch]$KeepSandbox
)

$ErrorActionPreference = "Stop"
$results = New-Object System.Collections.Generic.List[object]

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet("PASS","FAIL","INFO")][string]$Status,
        [string]$Detail
    )
    $results.Add([pscustomobject]@{ Check = $Name; Status = $Status; Detail = $Detail })
}

Write-Host "Sandbox: $Sandbox`n"
New-Item -ItemType Directory -Force -Path $Sandbox | Out-Null

# 1. File create
try {
    $f = Join-Path $Sandbox "create.txt"
    "hello" | Set-Content -LiteralPath $f -Encoding UTF8
    Add-Result "file_create" $(if (Test-Path $f) { "PASS" } else { "FAIL" }) $f
} catch { Add-Result "file_create" "FAIL" $_.Exception.Message }

# 2. File edit / append
try {
    $f = Join-Path $Sandbox "create.txt"
    "world" | Add-Content -LiteralPath $f -Encoding UTF8
    $lines = (Get-Content -LiteralPath $f).Count
    Add-Result "file_edit" $(if ($lines -eq 2) { "PASS" } else { "FAIL" }) "$lines lines"
} catch { Add-Result "file_edit" "FAIL" $_.Exception.Message }

# 3. File read
try {
    $f = Join-Path $Sandbox "create.txt"
    $c = Get-Content -LiteralPath $f -Raw
    Add-Result "file_read" $(if ($c -match "hello") { "PASS" } else { "FAIL" }) "read $((Get-Item $f).Length) bytes"
} catch { Add-Result "file_read" "FAIL" $_.Exception.Message }

# 4. Destructive recursive delete (the action a babysitter would gate)
try {
    $nuke = Join-Path $Sandbox "nuke"
    New-Item -ItemType Directory -Force -Path (Join-Path $nuke "a\b\c") | Out-Null
    1..5 | ForEach-Object { "x" | Set-Content -LiteralPath (Join-Path $nuke "a\b\c\file$_.txt") }
    Remove-Item -LiteralPath $nuke -Recurse -Force
    Add-Result "destructive_delete" $(if (-not (Test-Path $nuke)) { "PASS" } else { "FAIL" }) "Remove-Item -Recurse -Force on populated tree"
} catch { Add-Result "destructive_delete" "FAIL" $_.Exception.Message }

# 5. Cross-directory write (additionalDirectories scope: user profile)
try {
    $canary = Join-Path $env:USERPROFILE ".autonomy-kit-canary.txt"
    (Get-Date).ToString("o") | Set-Content -LiteralPath $canary -Encoding UTF8
    $ok = Test-Path $canary
    Remove-Item -LiteralPath $canary -Force -ErrorAction SilentlyContinue
    Add-Result "cross_dir_write" $(if ($ok) { "PASS" } else { "FAIL" }) "wrote+removed $canary"
} catch { Add-Result "cross_dir_write" "FAIL" $_.Exception.Message }

# 6. Process launch + capture
try {
    $out = & cmd /c "echo autonomy-ok"
    Add-Result "process_launch" $(if ($out -match "autonomy-ok") { "PASS" } else { "FAIL" }) "child process stdout captured"
} catch { Add-Result "process_launch" "FAIL" $_.Exception.Message }

# 7. Network egress (single benign GET)
try {
    $r = Invoke-WebRequest -UseBasicParsing -Uri "https://api.github.com/zen" -TimeoutSec 20
    Add-Result "network_egress" $(if ($r.StatusCode -eq 200) { "PASS" } else { "FAIL" }) "HTTP $($r.StatusCode): $($r.Content)"
} catch { Add-Result "network_egress" "FAIL" $_.Exception.Message }

# 8. Registry read (system visibility, no elevation)
try {
    $null = Get-ItemProperty -Path "HKCU:\Environment" -ErrorAction Stop
    Add-Result "registry_read" "PASS" "read HKCU:\Environment"
} catch { Add-Result "registry_read" "FAIL" $_.Exception.Message }

# 9. Scheduled-task enumeration (read of the task layer the elevated helper uses)
try {
    $n = (Get-ScheduledTask -ErrorAction Stop | Measure-Object).Count
    Add-Result "scheduled_task_read" "PASS" "$n tasks enumerated"
} catch { Add-Result "scheduled_task_read" "FAIL" $_.Exception.Message }

# 10. Elevation state (informational -- the helper bridges this when non-admin)
try {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Add-Result "process_elevated" "INFO" "Elevated=$isAdmin"
} catch { Add-Result "process_elevated" "INFO" $_.Exception.Message }

# 11. Elevated helper presence (informational)
try {
    $helper = Get-ScheduledTask -TaskName "ClaudeElevatedDevHelper" -ErrorAction SilentlyContinue
    Add-Result "elevated_helper_installed" "INFO" $(if ($helper) { "installed" } else { "not installed (optional)" })
} catch { Add-Result "elevated_helper_installed" "INFO" $_.Exception.Message }

# 12. Approve-watcher task registered (INFO if absent -- this harness is intended to run
#     pre- AND post-Setup; absence is "not installed yet", not "broken").
try {
    $w = Get-ScheduledTask -TaskName "ClaudeApproveWatcher" -ErrorAction SilentlyContinue
    if ($w) {
        $state = $w.State
        Add-Result "approve_watcher_task" $(if ($state -in 'Ready','Running') { "PASS" } else { "FAIL" }) "state=$state"
    } else {
        Add-Result "approve_watcher_task" "INFO" "not installed (run Setup-Autonomy.ps1 to register)"
    }
} catch { Add-Result "approve_watcher_task" "INFO" $_.Exception.Message }

# 13. Approve-watcher process alive (only meaningful if the task is installed; INFO otherwise)
try {
    $alive = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'Watch-ComputerUseApprove' }
    if ($alive) {
        Add-Result "approve_watcher_process" "PASS" "PID(s): $(($alive.ProcessId) -join ',')"
    } elseif ($w) {
        Add-Result "approve_watcher_process" "FAIL" "task installed but no powershell.exe running Watch-ComputerUseApprove (Start-ScheduledTask?)"
    } else {
        Add-Result "approve_watcher_process" "INFO" "n/a -- watcher task not installed"
    }
} catch { Add-Result "approve_watcher_process" "INFO" $_.Exception.Message }

# 14. UI Automation assemblies load (the watcher's hard dependency)
try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction Stop
    Add-Type -AssemblyName UIAutomationTypes  -ErrorAction Stop
    Add-Result "uiautomation_assemblies" "PASS" "UIAutomationClient + UIAutomationTypes loaded"
} catch { Add-Result "uiautomation_assemblies" "FAIL" $_.Exception.Message }

# Cleanup
if (-not $KeepSandbox) {
    Remove-Item -LiteralPath $Sandbox -Recurse -Force -ErrorAction SilentlyContinue
    Add-Result "sandbox_cleanup" "PASS" "removed $Sandbox"
} else {
    Add-Result "sandbox_cleanup" "INFO" "kept $Sandbox"
}

# Report
""
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$fail = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
$info = ($results | Where-Object { $_.Status -eq "INFO" }).Count
Write-Host ("SUMMARY: {0} PASS / {1} FAIL / {2} INFO" -f $pass, $fail, $info)

$report = Join-Path $env:TEMP ("autonomy-kit-test-report-" + (Get-Date).ToString("yyyyMMdd-HHmmss") + ".json")
# UTF-8 NO BOM (PS 5.1's -Encoding UTF8 prepends BOM that breaks naive JSON readers).
[System.IO.File]::WriteAllText($report, ($results | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
Write-Host "Report: $report"

if ($fail -gt 0) { exit 1 } else { exit 0 }
