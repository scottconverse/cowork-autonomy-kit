# Claude Code Windows elevated helper

Serves Claude Code sessions in the desktop Code tab and CLI running as a normal, non-elevated Windows user. This helper does not configure the Cowork tab.

## Installation and migration

Run Install-ClaudeElevatedDevHelper-AsAdmin.cmd and approve UAC. The installer remains visible, propagates errors, and verifies administrator execution plus an installed-invoker script path containing spaces.

- Worker, invoker and path-test script: `%ProgramFiles%\ClaudeElevatedHelper\`, protected from non-admin writes.
- Queue, done, failed, logs, install-state.json and install-log.txt: `%ProgramData%\ClaudeElevatedHelper\`.
- Read install-state.json for data_root, install_root, invoker_script and task_name. Invoker defaults discover this state.
- Administrators and SYSTEM have full control. The installing user has Modify on queue only and Read on results, logs and state. ACLs are explicitly written, read back and checked; mismatch fails installation.
- A new C:\dev folder permits writes only by Administrators, SYSTEM and the installing user. An existing folder is inspected and broad write grants are warned about without changing its ACL.

The installer re-registers an old task against the new worker and data paths. An existing C:\dev\ClaudeElevatedHelper folder is retained; inspect pending jobs before deleting it. Custom roots must preserve the same protected-code and separate-data boundary.

## Submit and verify

```powershell
$state = Get-Content (Join-Path $env:ProgramData 'ClaudeElevatedHelper\install-state.json') -Raw | ConvertFrom-Json
& $state.invoker_script -Action CheckAdmin
```

The invoker atomically publishes a complete JSON job and triggers the scheduled task. Read done\<job_id>.result.json or failed\<job_id>.error.json under data_root. Require status=ok and, for child processes, result.exit_code=0. A done file alone does not prove the process succeeded.

## Supported actions and trust

CheckAdmin, WingetInstall, WingetUpgrade, RunTrustedPowerShellScript, StartService, StopService, RestartService, OpenDevFirewallPort and RegisterDevScheduledTask are supported. Trusted user-script roots are C:\dev\ and the task user's Documents\Claude\. The installed administrator-only path-test script is explicitly accepted for installer verification. The .claude and Temp directories are not trusted script roots. Lexical path validation is not a sandbox or a defense against user-controlled reparse points within a trusted root.

The task runs at highest privilege with MultipleInstances=IgnoreNew. Processing stays serial and drains new queue arrivals before exiting. A job arriving after the final empty-queue check and before task exit can miss its trigger; inspect state and trigger the task again if necessary. The kit does not claim that this last scheduling race is eliminated.

## Accepted risk

Code Claude writes under C:\dev\ can run as administrator without per-action UAC. The owner accepts this authority. Protected worker files prevent ordinary-user replacement of the elevated engine; they do not restrict the effects of owner-authorized scripts. Bypass mode offers no protection against prompt injection or unintended actions. Deny rules remain available. See https://code.claude.com/docs/en/permission-modes.

If verification fails, registration and files remain for repair. Read install-log.txt and do not assume the helper works. Uninstall-Autonomy.ps1 -RemoveHelper unregisters the task but retains code and data files.
