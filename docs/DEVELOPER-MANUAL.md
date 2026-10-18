# Claude Code Windows Autonomy Kit developer manual

Version 2.1.0

Full-permission setup for Claude Code on Windows: the desktop app's Code tab and the CLI.

The Cowork tab is not in scope. Cowork has its own permission modes and runs commands in a VM or in the cloud.

## 1. Product and prerequisites

The desktop Code tab is primary; the CLI is secondary. Native Windows, Windows PowerShell 5.1, Windows Package Manager (`winget`, from Microsoft App Installer, used for missing Python), and working Claude Code authentication are required for actual Claude sessions; this installer does not provision an account or subscription. The kit does not install Claude. Historical repo and CLAUDE-Cowork-*.md filenames remain stable.

## 2. Installation

In Claude: Settings, Claude Code, turn on 'Allow bypass permissions mode'. Without it the Code tab cannot use Bypass permissions.

Download and inspect the release ZIP, then run Install.cmd. Setup summarizes bypass, settings merge, CLAUDE.md, hook and optional helper/UAC changes before asking Continue? [y/N]. Declining makes no changes.

## 3. Switches

| Switch | Behavior |
|---|---|
| -Yes | Skip Setup's confirmation question |
| -SkipBypass | Leave defaultMode unchanged while performing other selected setup work |
| -SkipConfig | Skip settings, profiles, staging, snapshots and history writes |
| -SkipClearBlockingRules | Preserve selected ask/deny arrays; they are cleared by default |
| -ProjectRoot | Exact existing project root; edit only its existing .claude settings files |
| -SkipBrowsers | Skip Chromium download |
| -SkipHelper | Skip helper installation |

Install.cmd passes arguments through, for example Install.cmd -Yes -SkipHelper.

## 4. Tools, shell and restart

Python, uv, Scoop, Node/npm, gh, ripgrep, jq, SQLite and Playwright + chromium browser are installed when missing. User-scope channels are preferred. Code tab commands use Git Bash if installed, otherwise the PowerShell tool; explicitly enabling the PowerShell tool can make it primary. The notification hook forces shell=powershell. Stop hooks have no matcher.

Fully quit Claude (right-click the Claude icon in the system tray, Quit), then open it again. A new session alone does not load new PATH entries; the desktop app does not read PowerShell profiles.

## 5. Settings and memory

Desktop and CLI share settings and CLAUDE.md. Setup sets bypassPermissions at user scope, removes selected project mode overrides, and clears selected ask/deny arrays by default. -SkipClearBlockingRules retains those arrays. -SkipBypass preserves all mode keys. Unrelated nested values and foreign hooks survive. User configuration uses CLAUDE_CONFIG_DIR when set, otherwise %USERPROFILE%\.claude. It does not hide Anthropic warning dialogs.

Setup installs the Core as CLAUDE.md and the depth profile alongside it. The Core has a standalone @CLAUDE-Cowork-Autonomous-Software-Development.md import; it loads every session and costs context. Unchanged kit-owned live files update using the previous staged copy as the ownership baseline. Customized live files are backed up and preserved. Doctor reports the exact live import. Add the import manually if missing in a customized CLAUDE.md.

## 6. Helper installation and filesystem layout

The helper serves normal, non-elevated Code tab and CLI sessions. The visible UAC installer puts protected worker/invoker/path-test files in %ProgramFiles%\ClaudeElevatedHelper. Data defaults to %ProgramData%\ClaudeElevatedHelper. Discovery state always lives at %ProgramData%\ClaudeElevatedHelper\install-state.json, even with a custom data root. Recorded custom paths survive repair unless explicitly overridden; code and data must be separate.

The task points at the Program Files worker and passes the ProgramData data_root as -Root. Administrators/SYSTEM have FullControl. The installing user gets Modify only on queue, and Read on done, failed, logs and state. Installer reads ACLs back and compares owner, inheritance protection and every access rule, accepting equivalent Windows ordering and bookkeeping flags while refusing permission mismatches. Protected executable files permit no ordinary-user writes.

Migration re-registers the old task to the new paths. The old C:\dev\ClaudeElevatedHelper folder remains; inspect pending jobs before deletion. Installation requires real administrator and installed-invoker path-with-spaces self-tests. Failure retains task/files for repair and reports the log location.

## 7. Elevated actions and trusted paths

Use the installed invoker for CheckAdmin, WingetInstall, WingetUpgrade, RunTrustedPowerShellScript, service actions, OpenDevFirewallPort and RegisterDevScheduledTask. Read invoker_script, data_root and task_name from ProgramData install-state.json rather than guessing paths.

User-script roots: C:\dev\ and the task user's Documents\Claude\. .claude and Temp are removed from trust. The administrator-only installed path-test script is explicitly accepted for self-tests. Root checks are lexical and do not sandbox effects. When creating C:\dev, the installer allows writes only to the installing user, Administrators and SYSTEM. Existing ACLs are inspected and broad write grants warned about, not silently changed.

## 8. Queue, results and logs

The invoker publishes jobs atomically; the worker also publishes complete results and errors by renaming a sibling temporary file. Child-process arguments preserve spaces, embedded quotes, empty strings and trailing backslashes. The worker serially processes snapshots and rechecks until empty. MultipleInstances remains IgnoreNew. A narrow race after the last empty check and before exit remains; another trigger may be needed for a late job. Read result status and child exit_code; done alone is not process success. Logs and results are readable by the user but not writable outside queue.

## 9. Updating and recovery

Upgrade directly from v1.6.1 with Setup; keep the original pre-kit snapshots. Uninstall-first is only for a separately needed legacy watcher migration. Setup repairs a helper when verified state, installed program hashes or task configuration are stale. It preserves recorded custom paths; the helper installer can also be run directly. Add the depth import to a customized CLAUDE.md. Repair malformed settings before retrying: Setup validates JSON and nested permission/hook shapes, names the bad file, throws and leaves configuration unchanged. Missing tools or failed browser installation produce a failing exit code. First pre-kit snapshots are never replaced by reruns; timestamped backups remain additional recovery material.

## 10. Diagnostics and troubleshooting

Doctor is read-only. It accepts -ProjectRoot and reports rule provenance, mode overrides, potential hook/control restrictions, and source coverage in addition to the existing installation dashboard. Static inspection errors return nonzero; finding a configured rule does not. Remote policy, launch flags and live session state are explicitly uninspected. It does not guess where the app stores the bypass toggle.

| Symptom | Action |
|---|---|
| A folder still prompts after Setup | In the Code tab, open the mode selector next to the send button and pick Bypass permissions once for that folder. The app remembers a picked mode per folder and it overrides defaultMode. |
| Tool missing | Fully quit Claude from the system tray and reopen; inspect PATH and executable resolution. |
| Missing depth import | Add the standalone import to live CLAUDE.md; ensure the profile is beside it. |
| Bad settings.json | Fix the named invalid file; Setup refuses configuration writes. |
| Legacy watcher installed | Run Uninstall-Autonomy.ps1 to remove its task. |
| Helper result absent | Check task registration, logs and pending queue; a registered task alone proves no execution. |
| Result ok but action failed | Read result.exit_code and stderr and check the actual effect. |

## 11. Testing and verification

Run the Windows PowerShell 5.1 tests listed in tests/TEST-PLAN.md: BlockAudit, Reconcile, Recovery, SettingsMerge, UninstallBakFilter, Lifecycle, NoBOM, NoHardcodedPaths, HelperInstall and AuditRegressions, plus all-script parsing. Windows CI runs the same tests on push and PR. npm test checks site content/version/font constraints; npm run build builds the site. Tests AST-extract production functions, with temporary profile roots and mocked external task triggers; they do not run full Setup or install a live helper. The settings-dedupe mutation proof must fail when real dedupe is broken. Portability includes forward-slash paths in tracked text files.

The v2.0.0 existing-machine walkthrough completed the actual uninstaller, Install.cmd and Doctor with exit 0, and verified the installed helper. A fresh CLI loaded bypassPermissions but authentication failed; this does not prove file-action or prompt behavior. Desktop runtime remains unverified. Historical earlier-release verification is recorded separately. See [verification evidence](IMPLEMENTATION-EVIDENCE.md) for current checks and runtime limitations. A clean-machine installation remains unverified. The audit regressions also launch a real child executable to verify Windows argument handling.

## 12. Uninstallation and rollback

Normal Uninstall restores the first settings.json and CLAUDE.md pre-autonomy-kit snapshots and recorded project first-touch baselines. -RestoreLastReconcile instead restores only the latest settings operation and leaves the rest of the kit installed. It cannot be combined with -RemoveHelper. Missing/corrupt backups and unresolved paths retain recovery state and report failure. See [exact recovery instructions](UNBLOCKING.md). Before restoration, preserve current files in unique .before-uninstall-*.bak backups so later edits remain recoverable. An absent marker allows removal only if live bytes still match the staged kit copy. Modified files remain. For older installs without snapshots, strip only the kit bypass default and notify hook; do not restore a newest timestamped backup. WhatIf performs no writes, including in the legacy strip branch. Writes are UTF-8 without BOM. General-purpose tools stay installed. -RemoveHelper additionally unregisters the helper task; installed helper files and data remain.

## 13. Repository, website and releases

Keep runtime jobs, logs, snapshots and .gauntletgate artifacts out of Git. GitHub Actions uses full commit SHA pins. Release ZIPs are git archive of the exact annotated tag and have a versioned top-level directory; verify SHA256SUMS.txt. Site/version tests compare current docs and site against the newest changelog heading. No LICENSE is present; no reuse license is granted.

## 14. Accepted security risk and computer use

Anthropic states: "`bypassPermissions` offers no protection against prompt injection or unintended actions." See [permission modes](https://code.claude.com/docs/en/permission-modes). The owner accepts this risk. With the helper installed, code Claude writes under C:\dev\ can run as administrator without a UAC prompt per action. Retained deny rules still apply in bypass mode; pass -SkipClearBlockingRules during Setup to preserve them. Protected helper programs are not a sandbox for trusted scripts.

Computer-use behavior is defined in the full profile. No dialog-clicking watcher is installed. The Code tab asks once per app per session, and the browser offers Always allow per site. Browser safety checks and other platform exceptions can still prompt even in bypass mode.

## 15. Official references

[Desktop](https://code.claude.com/docs/en/desktop), [permission modes](https://code.claude.com/docs/en/permission-modes), [memory](https://code.claude.com/docs/en/memory), [hooks](https://code.claude.com/docs/en/hooks), [settings reference](https://code.claude.com/docs/en/settings-reference).

## 16. Implementation map

See [architecture](ARCHITECTURE.md) for setup, recovery and helper diagrams, and the [user manual](USER-MANUAL.md) for operational commands. `lib/AutonomySettings.ps1` is the shared definitions-only audit, plan, manifest, lock and restore implementation. `Setup-Autonomy.ps1` supplies the user settings merge and owns tool/config/profile/helper orchestration. `Doctor-Autonomy.ps1` reads the same source inventory without running hooks. `Uninstall-Autonomy.ps1` selects baseline or latest-operation restore and manages profile/task cleanup.
