param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("CheckAdmin","WingetInstall","WingetUpgrade","RunTrustedPowerShellScript","StartService","StopService","RestartService","OpenDevFirewallPort","RegisterDevScheduledTask")]
    [string]$Action,

    [string]$Root,
    [string]$TaskName,
    [string]$PackageId,
    [string]$Scope,
    [string]$ScriptPath,
    [string[]]$Arguments,
    [string]$ServiceName,
    [int]$Port,
    [string]$Protocol,
    [string]$DevTaskName
)

$ErrorActionPreference = "Stop"

$statePath = Join-Path $env:ProgramData 'ClaudeElevatedHelper\install-state.json'
if ((-not $Root -or -not $TaskName) -and (Test-Path -LiteralPath $statePath)) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if (-not $Root) { $Root = [string]$state.data_root }
    if (-not $TaskName) { $TaskName = [string]$state.task_name }
}
if (-not $Root) { throw "Helper data root not recorded in $statePath; install or migrate the helper first." }
if (-not $TaskName) { $TaskName = 'ClaudeElevatedDevHelper' }

if (-not (Test-Path -LiteralPath $Root)) {
    throw "Helper root not found: $Root"
}

$queue = Join-Path $Root "queue"
New-Item -ItemType Directory -Force -Path $queue | Out-Null

$jobId = [guid]::NewGuid().ToString("n")
$job = [ordered]@{
    action = $Action
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    created_by = $env:USERNAME
}

if ($PackageId) { $job.packageId = $PackageId }
if ($Scope) { $job.scope = $Scope }
if ($ScriptPath) { $job.scriptPath = $ScriptPath }
if ($Arguments) { $job.arguments = $Arguments }
if ($ServiceName) { $job.serviceName = $ServiceName }
if ($Port) { $job.port = $Port }
if ($Protocol) { $job.protocol = $Protocol }
if ($DevTaskName) { $job.taskName = $DevTaskName }

$jobPath = Join-Path $queue ($jobId + ".json")
$tempPath = Join-Path $queue ($jobId + '.tmp')
$job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tempPath -Encoding UTF8
[IO.File]::Move($tempPath,$jobPath)

Start-ScheduledTask -TaskName $TaskName

@{
    queued = $true
    job_id = $jobId
    job_path = $jobPath
    task_name = $TaskName
    root = $Root
} | ConvertTo-Json -Depth 4
