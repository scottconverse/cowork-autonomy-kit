# Claude Elevated Development Helper

A reusable Windows helper pattern for machines where Claude Code / Cowork runs as a normal
(non-admin) process and cannot launch its shell with an administrator token.

## What It Does

- Installs a Windows Scheduled Task named `ClaudeElevatedDevHelper`.
- The task runs `ClaudeElevatedDevHelper.ps1` with highest privileges.
- Claude (or any normal user process) queues structured JSON jobs and triggers the task.
- The helper runs supported development actions and writes JSON results/logs.

The helper is agent-agnostic — it does not call or depend on Claude. It is a bounded,
file-queue-driven elevation bridge that Claude is *authorized* (in the profile) to drive when
admin is genuinely needed. Unlike Codex, which can run an elevated in-process sandbox, Claude
Code runs at your normal user token — so this helper is the primary path to admin actions.

## What It Does Not Do

Not an unrestricted admin command broker. It refuses arbitrary commands and supports named
development actions only:

- `CheckAdmin`
- `WingetInstall`
- `WingetUpgrade`
- `RunTrustedPowerShellScript`
- `StartService`
- `StopService`
- `RestartService`
- `OpenDevFirewallPort`
- `RegisterDevScheduledTask`

## Install

The one-time installer must be launched from an elevated PowerShell session because Windows
UAC controls creation of highest-privilege scheduled tasks.

For a click-driven install, double-click `Install-ClaudeElevatedDevHelper-AsAdmin.cmd` and
approve the Windows UAC prompt. A successful install reports an install location and a
self-test result where `is_admin` is `true`.

After installation, the helper root defaults to `C:\dev\ClaudeElevatedHelper`, with
`queue/`, `done/`, `failed/`, and `logs/` subfolders plus `install-log.txt` and
`install-state.json`.

Use `Test-ElevationState.ps1` only to inspect the process where it is launched.

## How Claude Uses It

```powershell
.\Invoke-ClaudeElevatedDevHelper.ps1 -Action WingetInstall -PackageId Git.Git
```

Claude then reads `C:\dev\ClaudeElevatedHelper\done\<job_id>.result.json` (or the matching
`failed\` file) and continues. Non-admin work proceeds while the job runs.

## Reuse On Other Machines

Copy this folder, review the paths, then perform the same one-time elevated setup. The Claude
addendum (`CLAUDE-Elevated-Helper-Addendum.md`) can be appended to that machine's
`~/.claude/CLAUDE.md`.

## Safety Model

The helper accepts only structured jobs and known action names. It logs every job start,
success, and failure. It restricts trusted script execution to local development roots
(`C:\dev\`, `~\Documents\Claude\`, `~\.claude\`, and the helper temp dir). It is for
reversible development infrastructure, not destructive system administration. Expand the
action list only when a real development task needs it, and keep each action structured.
