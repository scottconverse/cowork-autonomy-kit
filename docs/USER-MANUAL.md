# User manual

Claude Code Windows Autonomy Kit v2.0.0

The kit prepares a Windows machine for Claude Desktop's **Code tab** and the local Claude Code CLI. The Cowork tab has a separate execution environment and is outside this kit's scope. The kit does not install Claude, create an account, or sign you in.

## Install

Prerequisites: native Windows, Windows PowerShell 5.1, and Windows Package Manager (`winget`, supplied by Microsoft App Installer). Setup uses winget for missing Python; a bare Windows Sandbox image may not include winget. Install Claude separately and use a working signed-in account for runtime verification.

1. Download the [v2.0.0 ZIP](https://github.com/scottconverse/cowork-autonomy-kit/releases/download/v2.0.0/cowork-autonomy-kit-v2.0.0.zip) and [SHA256SUMS.txt](https://github.com/scottconverse/cowork-autonomy-kit/releases/download/v2.0.0/SHA256SUMS.txt). Compare the ZIP's hash with `Get-FileHash .\cowork-autonomy-kit-v2.0.0.zip -Algorithm SHA256`.
2. Extract the ZIP and review [what Setup changes](SETUP.md). Open Windows PowerShell in the extracted directory and run `.\Install.cmd`, or double-click it. Read the summary and answer `y`.
3. Approve Windows UAC if installing or repairing the optional elevated helper. Keep its installer window open until it finishes. A nonzero installer exit means setup is incomplete; preserve the error and repair that step.
4. Fully quit Claude using its system-tray icon, then reopen it so it receives updated PATH entries. In **Settings → Claude Code**, enable **Allow bypass permissions mode**. In the Code tab, select **Bypass permissions** for the working folder if its remembered mode still prompts.
5. From the extracted directory, run Doctor with the command below. Sign in to Claude if the app or CLI requests it. Installation success does not establish account access.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Doctor-Autonomy.ps1
```

The default install clears the user settings' entire ask/deny arrays and selects bypassPermissions. This removes local safeguards. Bypass does not protect against prompt injection or unintended actions. With the helper installed, trusted scripts can run as administrator without a new UAC prompt for each action. Managed policy, app state, hooks and built-in restrictions can still apply. Read the [accepted risks](../README.md#before-installing) before proceeding.

## Choose settings and project scope

Run these commands from the extracted release directory. Arguments pass through Install.cmd to Setup.

| Intent | Command |
|---|---|
| Default user setup | `.\Install.cmd` |
| Keep existing ask/deny rules | `.\Install.cmd -SkipClearBlockingRules` |
| Keep both existing modes and rules | `.\Install.cmd -SkipBypass -SkipClearBlockingRules` |
| Include one project | `.\Install.cmd -ProjectRoot "C:\dev\Example Project"` |
| Omit administrator helper | `.\Install.cmd -SkipHelper` |
| Scripted run without Setup's question | `.\Install.cmd -Yes` |

Selecting a project edits only its existing `.claude/settings.json` and `.claude/settings.local.json`. Setup removes their mode overrides so the user default can apply; it never scans other projects or creates missing project settings. Review shared project-file changes before committing them. `-SkipBypass` alone still clears ask/deny rules. `-SkipConfig` skips all kit configuration/profile/history changes while other installation steps remain eligible to run.

All commands use `CLAUDE_CONFIG_DIR` if set, otherwise `%USERPROFILE%\.claude`. Use the same environment when installing, diagnosing and restoring. Invalid roots fail instead of silently selecting another profile.

## Everyday use and instructions

Open the Code tab or CLI in your chosen project and state the task. The kit installs development tools and instructions; it does not grant authorization for unrelated actions or make all app interactions automatic.

Setup stages the Core and depth profile, then installs them into the resolved user configuration root. Existing customized instruction files remain intact. If Doctor reports a missing depth import, add the following standalone line to your live CLAUDE.md while preserving its other instructions:

```text
@CLAUDE-Cowork-Autonomous-Software-Development.md
```

The depth file must be beside CLAUDE.md. Its content loads every session and consumes context. Historical `CLAUDE-Cowork-*` filenames remain for compatibility.

## Start a new agent project with the gates on

Added Oct 17, 2026, after a two-day agent run on a project where the hook kits existed on the machine and nothing had turned them on. Run this once per project, before the first prompt:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\New-AgentProject.ps1 -ProjectRoot C:\dev\myproj -Upstream C:\upstream\a,C:\upstream\b
```

It writes `.claude\hook-kit.json` and `.codex\hook-kit.json` (policy for the Claude and Codex hook kits: read-ledger, measure, sprint, double-check, rules injection), `.claude\RULES.md`, an empty `.claude\READ-LEDGER.md`, `work\measure\run.mjs` (a stub that refuses to write a receipt until replaced) and `work\receipts\`, and appends one pointer line to `CLAUDE.md` and `AGENTS.md`. Existing files are kept unless `-Force`.

It refuses to finish unless the Claude hook kit is registered in the user `settings.json`, and unless the Codex kit is registered in `CODEX_HOME\hooks.json` (pass `-SkipCodex` to leave Codex out). At the end it runs the installed `read-ledger-gate` against a fake code write in the project and requires exit 2, so "the gate is on" is a measured fact, not a hope.

Then edit `.claude\hook-kit.json` (`upstreamRoots`, `mustMention`, `minEntries`, `minLines`, `measureCommand`), replace the measurement stub, and in Codex make sure the kit hooks are trusted. The kits live at [claude-hook-kit](https://github.com/scottconverse/claude-hook-kit) and [codex-hook-kit](https://github.com/scottconverse/codex-hook-kit).

## Diagnose a restriction

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Doctor-Autonomy.ps1 -ProjectRoot "C:\dev\Example Project"
```

Doctor names the inspected source and field, explains potential restrictions and suggests a remedy. Exit 0 means static inspection completed, including when restrictions were found. It does not mean an authenticated session, every tool or every folder is unrestricted. Check the live session's `/status`, Desktop toggle and folder mode separately. For missing commands, fully restart Claude and check PATH. For an authentication error, sign in through Claude; reinstalling the kit is not an authentication repair.

See [unblocking and recovery](UNBLOCKING.md) for policy coverage, hooks and interrupted operations. Doctor reports managed policy without modifying it.

## Upgrade

Run the new release's installer directly over v1.6.1. You normally do not uninstall first. First pre-kit snapshots remain the uninstall baseline; new settings changes get their own recovery records. Setup updates unchanged kit-owned files and repairs stale helper registration/files while preserving recorded custom helper roots. A much older approval-watcher migration has a separate path in [Setup](SETUP.md#helper-and-migration).

## Undo settings or uninstall

Preview the desired operation with `-WhatIf`; previews make no writes.

```powershell
# Restore just the latest completed settings operation; retain the kit.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Autonomy.ps1 -RestoreLastReconcile -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Autonomy.ps1 -RestoreLastReconcile

# Restore first pre-kit configuration and remove kit staging.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Autonomy.ps1 -WhatIf
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-Autonomy.ps1
```

Latest-operation restore saves later file edits to unique `.before-restore-*.bak` files before restoring whole files. It is not an undo stack; repeating it does not undo older operations. Normal uninstall restores recorded project baselines as well as original user configuration, saving current files before restoration. Originally absent files are removed only if still unchanged; modified files are retained. Legacy installs with no true baseline have only the kit bypass default and notification hook stripped. Make an independent copy of legacy settings before uninstalling: that fallback does not create a current-file backup.

General developer tools remain installed. Add `-RemoveHelper` to normal uninstall to unregister the elevated task; helper code/data files remain. Do not combine it with `-RestoreLastReconcile`. A failed restore retains recovery records; follow [the exact recovery procedure](UNBLOCKING.md#interrupted-or-failed-operations) rather than deleting history. Fully restart Claude after configuration changes.

## What was verified

The v2.0.0 Windows regression suite passed 150 assertions. On an existing machine, legacy uninstall, the actual installer entrypoint and Doctor exited 0, and the installed elevated helper was verified. Customized CLAUDE.md survived. A fresh CLI reported bypassPermissions but failed authentication, leaving file actions and prompt behavior unverified. Desktop runtime activation and clean-machine installation remain unverified. See [the evidence record](IMPLEMENTATION-EVIDENCE.md).

For implementation details, read the [architecture](ARCHITECTURE.md) and [developer manual](DEVELOPER-MANUAL.md).
