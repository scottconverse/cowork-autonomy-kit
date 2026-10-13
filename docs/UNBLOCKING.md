# Permission reconciliation and recovery

The v2.0.0 candidate clears selected local permission rules and reports remaining restrictions. It does not guarantee that Claude can perform every operation without interaction. Native Windows PowerShell 5.1, the CLI and Desktop's Code tab are the intended surfaces. Cowork, WSL, cloud sessions and other operating systems are not covered.

## Choose the scope

```powershell
.\Install.cmd -ProjectRoot "C:\dev\Example Project"
.\Doctor-Autonomy.ps1 -ProjectRoot "C:\dev\Example Project"
```

Setup uses `CLAUDE_CONFIG_DIR` when nonempty, otherwise `%USERPROFILE%\.claude`. Doctor and Uninstall use the same root. An invalid root fails instead of falling back. The project argument must identify an existing directory. Only its existing `.claude/settings.json` and `.claude/settings.local.json` are selected; there is no recursive search or project-file creation. Linked/ambiguous edit targets and managed paths are rejected.

Default Setup empties the entire selected `permissions.ask` and `permissions.deny` arrays. It sets `permissions.defaultMode` to `bypassPermissions` in the user file and removes project mode overrides so that inheritance can work. It preserves unrelated keys and nesting, allow rules and foreign hooks. User notification wiring is part of the same settings operation; projects do not receive it.

Bypass offers no protection against prompt injection or unintended actions. Review untrusted content and the scope you select. Existing managed policy, hooks, built-in checks and live session choices may still apply.

| Option | Effect |
|---|---|
| `-SkipClearBlockingRules` | Retain existing ask/deny arrays; absent user arrays can still be initialized |
| `-SkipBypass` | Preserve user and project mode keys; still clear arrays by default |
| Both | Preserve existing rules and modes; notification setup can still change the user file |
| `-SkipConfig` | No settings, profile, staging, snapshot or history writes; tool/helper options keep their meaning |
| `-Yes` | Skip Setup's existing confirmation |

```powershell
.\Install.cmd -SkipClearBlockingRules
.\Install.cmd -SkipBypass -SkipClearBlockingRules
```

Upgrade directly from v1.6.1 by running the new Setup. Original pre-kit snapshots are retained. The settings immediately before the upgrade are recorded separately for last-operation restore. An old approval-watcher/helper migration is a separate route described in the setup guide.

## Read Doctor's findings

The shared audit inspects the resolved user file, selected project files, both Windows registry views of the `Settings` value under HKLM/HKCU `SOFTWARE\Policies\ClaudeCode`, and Program Files `ClaudeCode\managed-settings.json` plus JSON drop-ins in `managed-settings.d`. It never edits policy or runs hooks. Reading both registry views prevents the auditing PowerShell process from hiding the other view; it does not assert which view a particular Claude build selects.

Each finding names its source and field, configured effect, activation confidence, remedy and whether the reconcile can edit it. Deny means **blocks when matched**; ask means **requires approval when matched** (unattended use can deny). Hook matcher/type/target entries are **potential restrictions**, not observed failures. Local permission lists are additive; the highest inspected local scalar mode wins among user, project and local files. Managed-only controls, policy selection and runtime overrides keep the effective result uncertain.

Recognized report-only controls include bypass-disable, outside-working-directory reads, additional directories, managed-only permission/hook/MCP controls, MCP allow/deny settings, sandbox settings, hook disablement, managed source composition and policy helpers. Unknown keys survive edits. A setting's presence is reported for review, not automatically classified as a runtime denial.

Remote/host policies, launch flags, alternate settings files, live session permissions, Desktop toggle/folder selection, dynamic plugin/skill/agent hooks and built-in tool restrictions remain explicitly uninspected. Check `/status` and the actual session. The Desktop enablement toggle and remembered folder mode can matter independently of the user default.

Doctor exits zero when static inspection completes, including when restrictions are found. Malformed or unreadable requested static sources make it fail. Declared runtime coverage limitations do not alone cause failure. “No blocking permission rules found in inspected sources” does not mean unrestricted execution.

## Restore a settings operation

```powershell
.\Uninstall-Autonomy.ps1 -RestoreLastReconcile -WhatIf
.\Uninstall-Autonomy.ps1 -RestoreLastReconcile
```

This restores the entire saved files from the latest completed settings operation and leaves profiles, helper and tools installed. It verifies original backup hashes and saves current bytes to unique `.before-restore-*.bak` files first. Later edits remain recoverable in those files. A repeat does not step backward to older history. It rejects `-RemoveHelper` in this mode.

Originally absent files are removed only when their bytes still match the operation's write. Modified files are retained and reported as incomplete restoration. Missing/moved projects are not recreated at guessed locations. A reinstall can reapply the default-on reconcile.

Normal `Uninstall-Autonomy.ps1` restores original user pre-kit state and every recorded project first-touch baseline, preserving current bytes as `.before-uninstall-*.bak`. It retains recovery state when a path or backup remains unresolved. General-purpose tools remain installed. `-WhatIf` makes no writes, including backups, locks and manifest updates.

## Interrupted or failed operations

Settings history is in `<config-root>\autonomy-kit\settings-history.json`; exact backups are under its `recovery` directory. It records original existence, backup path, SHA-256 hashes, written hash, changed fields, operation ID/time and state. It does not choose the newest `.bak` file. A no-op creates no settings backup or operation.

All selected settings are validated before configuration writes. The writer prepares backups and history before the first replacement, rechecks original hashes, and atomically replaces each file through a sibling temporary file. This is not an atomic transaction across all files. A failure attempts to restore only files still matching its own writes, retaining concurrent edits. A short exclusive lock protects kit history from overlapping kit operations, including staging cleanup. Its empty `.autonomy-kit.settings.lock` file remains beside the staging directory after uninstall; the file's existence does not mean an operation is running.

An unfinished reconcile is recovered before another reconcile is allowed. After successful recovery, rerun Setup to plan from the recovered files. If current bytes match neither original nor written hashes, Setup names the exact target, operation, backup and expected hash; it does not overwrite the unknown contents. Preserve that current file first, then restore the exact recorded original. For example, using paths copied from that entry:

```powershell
$target = 'C:\dev\Example Project\.claude\settings.json'
$backup = 'C:\path\to\config\autonomy-kit\recovery\OPERATION-ID\1.original.json'
$expectedHash = 'SHA256-FROM-THE-ENTRY'
if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -ne $expectedHash) {
    throw 'Backup does not match the recorded original; recover the correct backup first.'
}
Copy-Item -LiteralPath $target -Destination ($target + '.manual-preserved-' + [guid]::NewGuid() + '.bak')
Copy-Item -LiteralPath $backup -Destination $target -Force
```

For an originally absent target, preserve the current bytes and remove that exact target instead of copying a nonexistent original. Never delete the manifest to dismiss an error. Missing/corrupt backups must be recovered from another known exact copy before restore can proceed. Do not guess another project location.

A pending last-operation restore resumes with `-RestoreLastReconcile`; a pending baseline restore resumes with normal Uninstall. Setup refuses to reconcile while a restore remains pending. A lock-contention error means another operation holds the lock or access failed; wait for the actual operation to finish or correct the reported access error.

See [candidate evidence](IMPLEMENTATION-EVIDENCE.md) for what was actually exercised. Platform references: [settings](https://code.claude.com/docs/en/settings), [managed policy](https://code.claude.com/docs/en/managed-settings), [permission modes](https://code.claude.com/docs/en/permission-modes).
