# computer-use-approve-watcher

Background watcher that auto-clicks the Claude computer-use **Approve** dialog using
Windows UI Automation. With it running, the per-session gate is invisible.

## What it does

`Watch-ComputerUseApprove.ps1` polls the UI Automation tree every 500ms for a button
named `Approve` belonging to the Claude process and invokes it. Runs as your user, no
admin. One watcher covers all three Claude permission-broker dialogs — `computer:`,
`browser:`, and `webfetch:` — because they all surface the same `Approve` button. Tunable:

```powershell
Watch-ComputerUseApprove.ps1 -TargetLabel 'Allow' -TargetProcs @('Claude','ClaudeHelper') `
                             -PollMs 250 -DebounceMs 500
```

## Install

`Setup-Autonomy.ps1` installs and starts it. Manual install (logon scheduled task,
user-scope):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  "<kit>\computer-use-approve-watcher\Install-ApproveWatcherTask.ps1"
Start-ScheduledTask -TaskName ClaudeApproveWatcher
```

Manual run (no task):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  "<kit>\computer-use-approve-watcher\Watch-ComputerUseApprove.ps1"
```

## Status

```powershell
Get-ScheduledTask  -TaskName ClaudeApproveWatcher
Get-ScheduledTaskInfo -TaskName ClaudeApproveWatcher
Get-Process -Name powershell | Where-Object { $_.MainWindowTitle -match 'Approve' }
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  "<kit>\computer-use-approve-watcher\Install-ApproveWatcherTask.ps1" -Uninstall
```

Moved the kit directory? Re-run the installer — the task points at the script's current path.

## Headless alternative

For fully unattended runs with no desktop session, see
[`routine-approve.template.json`](routine-approve.template.json) — a Claude Code routine /
scheduled-task template that carries `computer:` / `browser:` / `webfetch:` pre-approval
in its own `approvedPermissions` array. **Schema not end-to-end verified — confirm against
your Claude Code routines version before relying on it.** The watcher and routines coexist;
pick whichever fits the run.
