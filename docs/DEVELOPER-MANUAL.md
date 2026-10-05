# Cowork Autonomy Kit Developer User Manual

For developers operating and maintaining Claude Code or Cowork on a personal Windows development machine.

**Software reference:** v1.5.1 runtime scripts, with the subsequent landing-page source at commit `b6cd25406c94dd53e6484a8910d709f4d135107f`. **Manual date:** October 4, 2026. This manual is published with the repository documentation; it is not part of the previously published v1.5.1 ZIP.

The kit is a collection of PowerShell scripts, instruction profiles, configuration examples, and scheduled-task helpers. It is not a replacement for Claude, an administrator version of the desktop app, or a guarantee that an agent will follow every instruction. This manual explains what the implementation changes, how to operate the elevated job interface, and how to verify and recover your environment.

## Contents

- [1. Architecture and responsibility](#1-architecture-and-responsibility)
- [2. Requirements and preflight](#2-requirements-and-preflight)
- [3. Installation](#3-installation)
- [4. Installed files and configuration](#4-installed-files-and-configuration)
- [5. Everyday development](#5-everyday-development)
- [6. Elevated helper installation](#6-elevated-helper-installation)
- [7. Elevated job API](#7-elevated-job-api)
- [8. Results, logs, and queue behavior](#8-results-logs-and-queue-behavior)
- [9. Updates and recovery](#9-updates-and-recovery)
- [10. Diagnostics and troubleshooting](#10-diagnostics-and-troubleshooting)
- [11. Testing and verification](#11-testing-and-verification)
- [12. Uninstallation and rollback](#12-uninstallation-and-rollback)
- [13. Maintaining the repository and website](#13-maintaining-the-repository-and-website)
- [14. Security and operational boundaries](#14-security-and-operational-boundaries)
- [15. Source reference](#15-source-reference)

## 1. Architecture and responsibility

There are three distinct layers. Instructions influence agent behavior. Claude's tool-permission configuration controls how the host handles tool requests. Windows privileges control what a process can actually do. Changing one layer does not automatically change the others.

```text
Repository                          Installed environment
Core + depth profiles   --------->  ~/.claude/ instructions
Setup + settings merge  --------->  toolchain, PATH, settings, hooks
Helper installer        --------->  elevated scheduled task

Normal shell / agent
    |
    v
Installed invoker -> queue/<id>.json -> scheduled-task worker
                                             |
                                             v
                                    supported elevated action
                                             |
                                             v
                                  done/result or failed/error
                                        + JSONL log
```

The elevated helper is independent of Claude: a normal shell can submit a job using the same invoker. The worker runs under the installer user's Windows identity with highest privileges, separately from the desktop agent. It does not elevate the agent process itself.

Use the kit only on a machine where you are authorized to change configuration and install software. Review executable scripts and upstream download sources. Instructions in the supplied profiles express the kit author's operating preferences; they do not override application policy, organizational controls, or Windows permissions.

## 2. Requirements and preflight

The runtime targets Windows and `powershell.exe`, including Windows PowerShell 5.1 and its .NET Framework process APIs. Other operating systems are not supported by these scripts. An exact Windows-version/architecture compatibility matrix has not been established; the winget fallback includes an x64 package path.

You need:

- Claude installed separately, with access to the Claude Code/Cowork environment you intend to configure.
- Windows PowerShell and access to the ScheduledTasks module.
- Internet access to the package managers and installers used by Setup.
- A working winget/Desktop App Installer installation for Python bootstrap and winget actions.
- Git if using the clone route; otherwise download the release ZIP.
- An account able to approve elevation for helper installation, if using the helper.
- Enough disk space for development tools and optional Playwright browsers. The kit specifies no minimum or fixed download size.

Run these read-only checks in a normal PowerShell session:

```powershell
$PSVersionTable
Get-Command powershell.exe, winget -ErrorAction SilentlyContinue
Get-Module -ListAvailable ScheduledTasks
Get-Command git -ErrorAction SilentlyContinue
```

Back up the entire existing `.claude` configuration using your usual backup process before installation. Include credentials in protected backups only; never commit or share them. Setup makes individual backups, but those are not a substitute for an independently selected recovery point.

**Important:** Setup sets `permissions.defaultMode` to `bypassPermissions` and installs an approval watcher that clicks desktop permission dialogs automatically. This removes review opportunities. Decide whether those changes are acceptable before running full Setup. There is no `-SkipWatcher` switch in this version.

## 3. Installation

### Acquire the code

Use the [v1.5.1 release](https://github.com/scottconverse/cowork-autonomy-kit/releases/tag/v1.5.1) for a fixed runtime snapshot. Download its ZIP and `SHA256SUMS.txt`; calculate the ZIP hash and compare the complete value with the matching checksum entry:

```powershell
Get-FileHash -LiteralPath .\cowork-autonomy-kit-1.5.1.zip -Algorithm SHA256
Get-Content -LiteralPath .\SHA256SUMS.txt
```

A checksum confirms integrity against the provided checksum, not publisher identity by itself. Extract the archive only after review. Windows may mark downloaded scripts as internet-origin files or display SmartScreen warnings; examine those warnings and establish trust rather than indiscriminately unblocking files.

Alternatively, clone and select the release tag:

```powershell
git clone https://github.com/scottconverse/cowork-autonomy-kit.git
cd cowork-autonomy-kit
git checkout v1.5.1
```

The `main` branch includes later website/documentation changes and can evolve independently of the tag. Commands below assume the current directory is the kit's repository or extracted root, not `docs/`.

### Run Setup

Full Setup changes your machine. After accepting the permission changes, run from a **non-elevated** PowerShell session:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Setup-Autonomy.ps1
```

Or run `Install.cmd`, which forwards arguments, prints the exit code, and pauses so you can read the output. Execution-policy bypass is a process launch option, not administrator elevation. The optional helper has its own UAC installation step.

Setup proceeds through Python and a `python3.exe` copy, uv, Scoop, CLI tools, Playwright, configuration staging/merge, the approval watcher, and the elevated helper. Tool installation uses live upstream sources rather than a frozen dependency lockfile. Python discovery looks under the current user's `AppData\Local\Programs\Python\Python3*`; an interpreter elsewhere may not satisfy that discovery step.

### Setup switches

| Switch | Actual effect | What it does not skip |
|---|---|---|
| `-SkipConfig` | Skips instruction staging, live instruction/hook-file creation, and settings merge | Tool installs, watcher installation/start, helper step |
| `-SkipBrowsers` | Skips the Playwright browser download | Playwright package installation, other steps |
| `-SkipHelper` | Skips the elevated-helper installation step | Configuration, watcher, toolchain |

These switches can be combined, but **`-SkipConfig` is not a toolchain-only safety boundary** despite the script's parameter summary. Use separately reviewed individual components if you do not want the watcher. There is no full-Setup preview mode or transaction rollback.

### Finish and inspect

Restart Cowork/Claude Code and open a new terminal so the updated user PATH and instructions can load. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Doctor-Autonomy.ps1
```

Read every warning. Some external tool failures produce warnings or missing-tool summaries rather than a failed Setup exit. Exit zero alone does not prove the entire environment is ready.

## 4. Installed files and configuration

`~` below means the Windows user profile of the relevant process, not a repository folder.

| Location | Purpose and ownership |
|---|---|
| `~\.claude\CLAUDE.md` | Live Core instructions; existing content is backed up and preserved |
| `~\.claude\CLAUDE-Cowork-Autonomous-Software-Development.md` | Live depth profile; existing content is preserved |
| `~\.claude\hooks\notify-turn-ended.ps1` | Live notification script; existing content is preserved |
| `~\.claude\settings.json` | Parsed and merged by Setup |
| `~\.claude\autonomy-kit\` | Refreshed reference/staging copies; not the active instruction file |
| `*.bak-YYYYMMDD-HHmmss` beside live files | Timestamped backups; inspect before restoring |
| `C:\dev\ClaudeElevatedHelper\` | Default installed helper, jobs, results, and logs |
| User PATH and package-manager directories | Development tools; not removed by kit uninstall |

### Settings merge behavior

Setup overwrites `permissions.defaultMode` with `bypassPermissions`. It adds empty `ask` and `deny` arrays only if those properties do not already exist. It preserves other parsed settings and existing allow rules, and adds the notification Stop hook if a hook command containing `notify-turn-ended` is not already present. It substitutes `YOUR_USERNAME` in an existing `additionalDirectories` list.

Setup does **not** automatically copy the entire [example settings file](../settings.autonomy.example.json). In particular, it does not create the example's `additionalDirectories`, broad `allow` entries, or `enableAllProjectMcpServers` setting. Do not assume those are enabled because they appear in the example.

The merged settings file is written as UTF-8 without a byte-order mark. If existing settings cannot be parsed, Setup backs up the file, falls back to an empty settings object, and writes its kit settings. That can discard the active custom configuration. Validate and repair malformed JSON before rerunning Setup.

```powershell
Get-Content -LiteralPath "$env:USERPROFILE\.claude\settings.json" -Raw |
  ConvertFrom-Json | Out-Null
```

### Instructions and notifications

Edit the live Core file for your actual development preferences. Keep the depth profile accessible under the name referenced by Core. The profiles are instructions, not executable enforcement or additional permissions. A staged update does not become active until you merge it into the live file.

The notification script displays a Windows tray balloon after a turn ends, waits about 4.5 seconds, and disposes its icon. If the Windows Forms path fails, it attempts a console beep. Notification behavior depends on the interactive session and Windows settings; no guaranteed delivery mechanism exists.

## 5. Everyday development

Start by stating the repository, the desired change, acceptance criteria, and protected resources. Separate permission to inspect from permission to deploy, publish, delete data, or change shared infrastructure. An instruction profile should not be treated as proof that an agent has authority for an unrelated action.

A useful development brief is:

> In this repository, fix the failing parser test. Preserve my unrelated changes. Run the affected tests and report the exact result. Do not publish or change machine configuration.

Prefer ordinary user-scope tools for routine work. Choose elevation when the operation actually needs Windows administrator rights, not just because the helper exists. Keep secrets out of prompts, screenshots, repository commits, and job output.

Before declaring work complete, check the artifact that matters: test output for code, installed version for a package, actual service state for a service, and the public URL for a deployment. Agent prose is not a substitute for those observations.

The included approval watcher is an independent component, not an effect of Core instructions. Its mere presence or a running process does not prove that it correctly handles a current Claude UI. If you want manual desktop approvals again, stop and disable that task through Windows Task Scheduler; review configuration independently. Rerunning full Setup may reinstall/start it. This manual does not provide a watcher-extension or approval-circumvention recipe.

## 6. Elevated helper installation

### Install or refresh the default helper

After reviewing the helper scripts, use `elevated-dev-helper\Install-ClaudeElevatedDevHelper-AsAdmin.cmd` and approve the Windows UAC request. Alternatively, in an already elevated PowerShell session:

```powershell
& .\elevated-dev-helper\Install-ClaudeElevatedDevHelper.ps1
```

The installer copies the worker, invoker, and path-test script; creates the queue/result/log directories; registers a highest-privilege task; and writes installation metadata. It records the identity running the installer. Installing using a different administrator account changes the task identity and that identity's profile-dependent trusted paths.

The task uses an interactive logon principal, so the design is not an unattended boot service for a logged-out user. Its execution time limit is two hours, with multiple instances set to `IgnoreNew`.

### What the self-tests prove

The installer submits `CheckAdmin` through the installed invoker and requires administrator confirmation. It waits for the task to become idle, then submits `RunTrustedPowerShellScript` for `Self Test Path\Windows Path Test.ps1` under the install root. It requires job status `ok`, child exit code zero, administrator confirmation in the script output, and the exact script path returned.

Result waits allow up to 30 seconds each, with a separate up-to-30-second idle wait. These tests exercise installed files and a real path with spaces/backslashes. They do not test every supported action, every package installer, agent behavior, or all operating systems. They do not narrow the worker's capabilities.

Only after both tests pass is `install-state.json` marked `installed: true` and populated with test job IDs. On a verification failure, the installer throws and warns that the task/files remain. Metadata written before verification remains `installed: false`. Failures before metadata creation may leave a different partial state; always inspect what exists.

### Custom roots and task names

An already elevated session can choose a custom install root and task name:

```powershell
& .\elevated-dev-helper\Install-ClaudeElevatedDevHelper.ps1 `
  -InstallRoot 'C:\dev\ClaudeHelperCustom' `
  -TaskName 'ClaudeHelperCustom'
```

Choose a directory under an existing trusted script root. The installer does not extend the worker's allowlist automatically. A custom root outside that allowlist can install/register the task but fail its path self-test. The helper click-driven wrapper and the main Setup path use defaults; custom parameters require the direct PowerShell installer.

Use `install_root`, `task_name`, and `invoker_script` from your installation metadata. Doctor and `Uninstall-Autonomy.ps1 -RemoveHelper` target the default helper name/root, not arbitrary custom installations.

## 7. Elevated job API

### Initialize a client

Run in a normal PowerShell session after installation:

```powershell
$helperRoot = 'C:\dev\ClaudeElevatedHelper'
$helperState = Get-Content -LiteralPath (Join-Path $helperRoot 'install-state.json') -Raw |
  ConvertFrom-Json
if ($helperState.installed -ne $true) { throw 'Helper verification is not complete.' }
$helperClient = $helperState.invoker_script
$helperTaskName = $helperState.task_name
```

Metadata is an installation record, not an ongoing health check. Submit a `CheckAdmin` job to verify current execution. Never hand-write job JSON: the invoker uses `ConvertTo-Json` so Windows backslashes and spaces are serialized correctly.

```powershell
$submitted = (& $helperClient -Root $helperRoot -TaskName $helperTaskName `
  -Action CheckAdmin | Out-String) | ConvertFrom-Json
$submitted
```

The invoker creates a GUID-named job file, triggers the named scheduled task, and returns JSON containing `queued`, `job_id`, `job_path`, `task_name`, and `root`. It does not wait for completion. A successful submission does not mean the elevated action succeeded.

### Action reference

| Action | Client parameters | Implemented behavior and cautions |
|---|---|---|
| `CheckAdmin` | None beyond common root/task | Worker startup asserts elevation; action returns `ok` and `is_admin` |
| `WingetInstall` | `-PackageId`; optional `-Scope` | Exact, silent, noninteractive install; accepts package/source agreements. Only `Scope = user` adds a scope argument; other values do not explicitly force machine scope |
| `WingetUpgrade` | `-PackageId` | Exact, silent, noninteractive upgrade with agreements accepted; no scope forwarding |
| `RunTrustedPowerShellScript` | `-ScriptPath`; optional string-array `-Arguments` | Executes an existing trusted-path script using `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` |
| `StartService` | `-ServiceName` | Calls `Start-Service`; returns a requested-state label |
| `StopService` | `-ServiceName` | Calls `Stop-Service`; returns a requested-state label |
| `RestartService` | `-ServiceName` | Calls `Restart-Service -Force`; returns a requested-state label |
| `OpenDevFirewallPort` | `-Port`; optional `-Protocol` | Allows inbound port 1–65535 on the Private profile; TCP default; recognizes TCP/UDP, otherwise falls back to TCP |
| `RegisterDevScheduledTask` | `-DevTaskName`, `-ScriptPath` | Registers/overwrites a highest-privilege task for a trusted-path script; name permits letters, digits, dot, underscore, space and hyphen, length 1–80 |

Common parameters are `-Root` and `-TaskName`. `-DevTaskName` names the task being created; it is distinct from `-TaskName`, which selects the installed helper. The created development task has no trigger specified by this action, so registration does not itself schedule recurring execution. The action also does not explicitly check script-file existence before registration.

The invoker validates action names, but action-specific required fields are generally validated by the worker after submission. For example, a missing package ID can produce a failed job instead of an immediate client error.

### Trusted script locations

The worker canonicalizes the supplied path with `GetFullPath` and checks a case-insensitive prefix against:

```text
C:\dev\
<worker-user-profile>\Documents\Claude\
<worker-user-profile>\.claude\
<worker-user-profile>\AppData\Local\Temp\ClaudeElevatedHelper\
```

This is a lexical location check, not script signing, a content review, or a filesystem sandbox. A script launched from an allowed location can perform administrator actions elsewhere. Do not let untrusted processes replace scripts or write privileged jobs. The installer does not establish a hardened ACL policy for those directories.

### Example script job

Review and create your script first. The following submits an existing script; it does not create one:

```powershell
$submitted = (& $helperClient -Root $helperRoot -TaskName $helperTaskName `
  -Action RunTrustedPowerShellScript `
  -ScriptPath 'C:\dev\Example\InspectEnvironment.ps1' | Out-String) | ConvertFrom-Json
```

Make scripts fail explicitly when an operation fails. In Windows PowerShell 5.1, a native child's nonzero exit code does not automatically become a terminating PowerShell error. A script should inspect `$LASTEXITCODE` and propagate the relevant failure instead of printing a success message and exiting zero.

The runner only wraps arguments containing whitespace in double quotes. It is not a complete Windows argument-escaping implementation. Embedded quotes, empty-string arguments, and complicated trailing-backslash cases require separate testing. Prefer simple script interfaces; do not assume arbitrary argument strings round-trip because JSON paths do.

## 8. Results, logs, and queue behavior

The default installed directory has:

```text
ClaudeElevatedHelper/
  ClaudeElevatedDevHelper.ps1
  Invoke-ClaudeElevatedDevHelper.ps1
  Test-InstalledHelperPath.ps1
  install-state.json
  install-log.txt
  Self Test Path/Windows Path Test.ps1
  queue/<job-id>.json
  done/<job-id>.json
  done/<job-id>.result.json
  failed/<job-id>.json
  failed/<job-id>.error.json
  logs/helper.jsonl
```

For one submitted job, a bounded client wait can be written as follows. This example only reads results after the submission you performed; it does not submit another job:

```powershell
$doneFile = Join-Path $helperRoot "done\$($submitted.job_id).result.json"
$errorFile = Join-Path $helperRoot "failed\$($submitted.job_id).error.json"
$waitUntil = (Get-Date).AddMinutes(2)
while (-not (Test-Path -LiteralPath $doneFile) -and
       -not (Test-Path -LiteralPath $errorFile)) {
  if ((Get-Date) -ge $waitUntil) { throw 'Client wait expired; inspect the task and logs.' }
  Start-Sleep -Milliseconds 500
}
if (Test-Path -LiteralPath $errorFile) {
  $jobError = Get-Content -LiteralPath $errorFile -Raw | ConvertFrom-Json
  throw $jobError.error
}
$jobResult = Get-Content -LiteralPath $doneFile -Raw | ConvertFrom-Json
if ($jobResult.status -ne 'ok') { throw 'Unexpected job status.' }
if ($jobResult.action -in @('RunTrustedPowerShellScript','WingetInstall','WingetUpgrade')) {
  if ($null -eq $jobResult.result.exit_code -or $jobResult.result.exit_code -ne 0) {
    throw "Child failed: $($jobResult.result.exit_code); $($jobResult.result.stderr)"
  }
}
$jobResult.result
```

Two minutes is this example's client wait, not the worker's execution limit. A client timeout does not cancel the task. Increase the wait deliberately for a long installation, and investigate before resubmitting work with side effects.

### What success means

The worker writes outer `status: ok` when its action handler returns normally. Process actions return `exit_code`, `stdout`, and `stderr`; a nonzero exit code can still be wrapped in outer status `ok` and stored in `done`. Require both levels to indicate success. For service actions, independently inspect `Get-Service`; the result labels say the request was made, not that a lasting health check passed.

JSON files written by the invoker/worker use PowerShell's UTF-8 encoding, which can include a BOM on Windows PowerShell 5.1. PowerShell's JSON-reading pattern above handles this. Python consumers should use BOM-aware decoding such as `utf-8-sig`. Do not assume these runtime files share Setup's no-BOM settings-file behavior.

Logs contain `helper_start`, `job_start`, `job_ok`, `job_failed`, and `helper_stop` records with UTC timestamps. An outer `job_ok` record does not override a nonzero child exit code. Logs and captured output can contain sensitive data; protect them and redact before sharing. There is no automated rotation or retention policy.

### Queue scheduling limitations

The worker snapshots queued JSON files once at startup, sorts by last-write time, processes them serially, and exits. It is not a continuously listening daemon. The scheduled task ignores new start requests while already running. A job submitted after the snapshot can therefore remain queued even though the invoker reported submission.

For reliable operation in this version, use one producer, wait for each result and for the task to become idle before submitting the next action. There is no built-in durable multi-producer scheduler, atomic queue-claim protocol, cancellation API, or automatic retry/deduplication. Interrupted jobs may remain queued; rerunning can repeat side effects. Inspect state before retriggering a task.

Script and winget process actions permit up to one hour each. On timeout, the runner attempts to kill the immediate child process, not an entire descendant process tree. Output pipes are read asynchronously; after parent exit, each reader is given up to five seconds to finish, and unfinished output can be returned empty. Grandchild work may outlive the reported parent result. Verify the intended system effect.

## 9. Updates and recovery

Keep source updates, staged files, active configuration, and installed helper files distinct. Downloading a new ZIP or pulling Git does not by itself update the running environment.

1. Inspect repository status and preserve your local modifications before changing versions.
2. Read the target changelog and compare scripts before running them.
3. Select and protect a pre-update backup rather than relying only on the newest automatic backup.
4. Refresh components you intend to update. Full Setup also revisits permission settings and starts the watcher; use it only if you intend those effects.
5. Merge staged instruction/hook changes into the corresponding live files.
6. Rerun the helper installer directly if helper scripts changed. Main Setup skips an already registered default helper task, even if files are stale or verification previously failed.
7. Restart Claude and run diagnostics and the relevant tests.

Updating helper files while jobs are running is not a coordinated upgrade. Finish or otherwise account for pending work first. Retain the previous trusted version until the new helper verifies successfully.

If verification fails, do not treat the retained task as ready. Read `install-log.txt`, check failed jobs and task state, repair the specific problem, and rerun the reviewed helper installer. Do not silently delete the task or queue: they may contain evidence or pending actions. If you choose to roll back scripts, rerun the selected version's installer and verify again; file replacement alone is not proof of recovery.

## 10. Diagnostics and troubleshooting

### Read state without changing it

```powershell
& .\Doctor-Autonomy.ps1
Get-ScheduledTask -TaskName 'ClaudeElevatedDevHelper' -ErrorAction SilentlyContinue
Get-ScheduledTaskInfo -TaskName 'ClaudeElevatedDevHelper' -ErrorAction SilentlyContinue
Get-Content -LiteralPath 'C:\dev\ClaudeElevatedHelper\install-state.json' -Raw
Get-Content -LiteralPath 'C:\dev\ClaudeElevatedHelper\install-log.txt' -Tail 30
Get-Content -LiteralPath 'C:\dev\ClaudeElevatedHelper\logs\helper.jsonl' -Tail 30
```

Doctor is an inventory, not a repair command or proof of successful helper jobs. It reports tools, live/staged instruction comparisons, parsed settings, watcher presence/process, and default-helper task state. Custom helper installations need separate inspection using their recorded names and paths.

| Symptom | What to check and do |
|---|---|
| Tool missing after Setup | Restart terminal/Claude; inspect PATH and Setup warnings. Check actual executable resolution; Store aliases may not be a real Python installation |
| Scoop reports already installed | Setup supports an existing Scoop command; if tooling still fails, inspect the resolved Scoop path and its own output |
| New Core text has no effect | Compare live `CLAUDE.md` to staging; existing live content is intentionally preserved. Merge deliberately and restart the host |
| Settings parse error | Preserve original and backups; fix malformed JSON before Setup, because its fallback can replace active settings |
| Invoker not found | Install/update the helper directly from complete v1.5.1 sources; verify `invoker_script` and file existence |
| Invalid JSON or unrecognized escape sequence | Stop hand-writing jobs; use the installed invoker. For existing failures, inspect the error and original job without blindly replaying it |
| Path is not trusted | Check the worker user's profile and allowlisted roots. A custom install directory is not automatically allowlisted |
| Job remains in queue | Check Running versus Ready state, overlapping submissions, login identity, registration, and logs. A task presence check alone is insufficient |
| Result in done but action failed | Read `result.exit_code`, stderr and actual system state; outer `ok` is not process success |
| Self-test times out | Inspect the 30-second verification wait, task state and logs; registration/files may still exist. Do not repeatedly rerun without diagnosing |
| Winget cannot be resolved | Verify Desktop App Installer for the task user. The worker resolves a real package executable rather than trusting an alias |
| Long-running job times out | Check one-hour process/two-hour task limits and any surviving descendants; a timed-out client is a separate condition |
| Notification absent | Check hook wiring, interactive session and Windows notification settings; fallback beep may also be unavailable |

For a bug report, include kit version/source commit, Windows/PowerShell versions, default or custom task/root, the action and job ID, exact error, relevant redacted log lines, and minimal reproduction. Do not post complete configuration, credentials, or unrestricted command output.

## 11. Testing and verification

### Isolated regression scripts

From the kit root:

```powershell
$regressionScripts = @(
  'Test-HelperInstall.ps1',
  'Test-SettingsMerge.ps1',
  'Test-NoBOM.ps1',
  'Test-NoHardcodedPaths.ps1',
  'Test-UninstallBakFilter.ps1'
)
foreach ($regressionScript in $regressionScripts) {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File (Join-Path '.\tests' $regressionScript)
  if ($LASTEXITCODE -ne 0) { throw "Failed: $regressionScript" }
}
```

`Test-HelperInstall` extracts actual installer functions and the verification failure handler, exercises installed-file copying and the real invoker with a stubbed scheduled-task trigger, and uses fixture results to test failures. It does not install an elevated task or prove live elevation. The actual installer self-tests provide separate live evidence.

Settings-merge tests check repeated merges and foreign-hook preservation. BOM and hardcoded-path checks cover their defined files and exclusions, not every runtime file. Uninstall-backup tests guard backup filtering; they do not execute a full uninstall lifecycle.

### Machine capability harness

Review `tests/Test-AutonomyKit.ps1` before execution. It creates/edits/deletes temporary files, writes/removes a fixed user-profile canary, launches a child process, calls GitHub, enumerates tasks, inspects existing watcher state, and loads UI Automation assemblies. It is **not** a wholly read-only test. Do not run it if `.autonomy-kit-canary.txt` already contains something you need.

```powershell
if (Test-Path -LiteralPath "$env:USERPROFILE\.autonomy-kit-canary.txt") {
  throw 'Existing canary file would be overwritten.'
}
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-AutonomyKit.ps1
```

The harness writes a timestamped JSON report under the Windows temp directory. Informational rows are context, not failures. These checks show machine capabilities, not that Claude consumes the right instructions, respects all bounds, or successfully handles every desktop interaction. Behavioral acceptance is separate; see the [test plan](../tests/TEST-PLAN.md) and run it only against disposable data with clearly authorized actions.

### Published evidence versus future compatibility

The v1.5.1 release recorded `14 PASS / 0 FAIL` for helper regressions and `13 PASS / 0 FAIL / 2 INFO` for the capability harness on the existing maintainer machine. The downloaded release ZIP checksum and regression scripts were also verified. Clean-machine lifecycle testing, native Cowork behavioral testing, and independent watcher behavior testing were not performed for that release.

The later GitHub Pages workflow tests the website, not the Windows runtime. No Windows-runtime CI workflow is currently configured. Passing website CI does not validate a future installer change.

## 12. Uninstallation and rollback

Read the implementation and preserve a selected configuration snapshot first. Uninstall reverses the kit configuration layer; it is not a full machine restore.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Autonomy.ps1
```

Adding `-RemoveHelper` also unregisters the default elevated-helper task. The script stops/removes the watcher, restores the latest kit-format backups when present, otherwise removes selected kit settings/hooks, preserves some customized instruction files using staged-file comparisons, and removes the staging directory. General development tools and helper files/jobs/logs remain. Software, services, firewall rules, or development tasks created through helper jobs are not rolled back.

**Implementation caveats:**

- The most recent backup may already contain kit settings because repeated Setup backs up the current configuration. Select a genuinely pre-kit backup when your goal is full restoration.
- The no-backup settings branch writes `settings.json` outside its `ShouldProcess` guard. Consequently `-WhatIf` is not a reliable no-write preview for this version. Do not rely on it to protect active settings.
- That fallback uses Windows PowerShell's UTF-8 writer and can introduce a BOM, unlike Setup's no-BOM writer.
- `-RemoveHelper` unregisters the default helper but does not explicitly stop its running task first; account for active work separately. Custom helper names need a separately reviewed removal procedure.
- Restoring a backup restores all content in that backup, including changes unrelated to the kit. Inspect it before choosing it.

These are documented observations, not fixes made by this manual. After removal, inspect tasks and active configuration and restart Claude. Do not delete the remaining helper folder until you have accounted for pending jobs, logs, and any rollback evidence.

## 13. Maintaining the repository and website

Keep credentials, generated configuration, backups, queues, results, and logs out of Git. Review `.gitignore`; an ignored file can still be committed if explicitly forced, and a credential committed once remains in history. Use redacted secret scanning before publication.

When changing worker actions, keep the worker switch, invoker `ValidateSet`, action parameters, result semantics, docs, and tests synchronized. Preserve Windows PowerShell 5.1 compatibility: `ProcessStartInfo.ArgumentList` is not available there. Test the actual installed invoker and real scheduled-task boundary, not only fixtures. Include negative cases such as nonzero exits, missing fields, bad paths, timeouts, and retained-task warnings.

The landing page is a dependency-free static HTML/CSS site. With Node and Python available:

```powershell
npm test
npm run build
npm run preview
```

Preview at `http://localhost:4321`; `npm run dev` serves the source. Output is `dist/`, containing HTML/CSS with relative asset paths for the repository subpath. The Pages workflow uses Node 24, tests/builds eligible pull requests, and deploys eligible main-branch pushes to [the website](https://scottconverse.github.io/cowork-autonomy-kit/). Website-only rollback is a reviewed source revert followed by redeployment; do not rewrite an existing product tag.

Changes under `docs/` alone do not trigger the current Pages workflow and are not copied into the website by its build. This manual is not automatically published as a website page. Update deployment/source links deliberately if you later choose to publish it.

## 14. Security and operational boundaries

Treat the helper as a privileged execution path. The named-action interface limits accepted job types, but `RunTrustedPowerShellScript` permits broad administrator effects. It is not a secure sandbox merely because scripts reside under development roots. Review script ownership, writable paths, jobs, arguments and output; the current installer does not create a complete least-privilege isolation system.

The worker has no application-level authentication/signature on job files beyond the operating-system access to its filesystem/task. `created_by` is metadata, not verified authorization. Logging records actions, not a prevention mechanism. No credential store, encryption, remote API, signed-update system, or automatic incident recovery is implemented by this kit.

The helper's firewall action is inbound/Private-only; it does not manage every firewall policy. Winget is silent/noninteractive and depends on installer behavior and upstream availability. Approval watcher/UI behavior can change with Claude updates. The example headless approval schema is not established as end-to-end verified. App-specific permission semantics must be tested in the actual host; do not infer them from kit prose.

The repository is public, but it currently supplies no reuse license. Do not label it open-source or invent a license grant. Independent public source and an official vendor-supported integration are different things; this is not an Anthropic product.

## 15. Source reference

Use executable implementation as the authority when comments or older documentation disagree.

- [Setup implementation](../Setup-Autonomy.ps1) and [click-driven entry point](../Install.cmd)
- [Core instructions](../CLAUDE-Cowork-Core.md) and [depth profile](../CLAUDE-Cowork-Autonomous-Software-Development.md)
- [Settings example](../settings.autonomy.example.json)
- [Helper installer](../elevated-dev-helper/Install-ClaudeElevatedDevHelper.ps1), [invoker](../elevated-dev-helper/Invoke-ClaudeElevatedDevHelper.ps1), and [worker](../elevated-dev-helper/ClaudeElevatedDevHelper.ps1)
- [Doctor](../Doctor-Autonomy.ps1), [Uninstall](../Uninstall-Autonomy.ps1), and [notification hook](../hooks/notify-turn-ended.ps1)
- [Helper regression](../tests/Test-HelperInstall.ps1), [test plan](../tests/TEST-PLAN.md), and [changelog](../CHANGELOG.md)
- [Detailed setup guide](SETUP.md) and [website maintenance](../site/README.md)
