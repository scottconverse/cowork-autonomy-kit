# Claude Code Windows setup

Version 2.0.0 candidate (unreleased) - Windows

Full-permission setup for Claude Code on Windows: the desktop app's Code tab and the CLI.

The Cowork tab is not in scope. Cowork has its own permission modes and runs commands in a VM or in the cloud.

The repo name and CLAUDE-Cowork-*.md names are historical. They remain unchanged so existing paths keep working.

## Quick start

1. In Claude: Settings, Claude Code, turn on 'Allow bypass permissions mode'. Without it the Code tab cannot use Bypass permissions.
2. Review the scripts and accepted risks in [README](../README.md). Download and extract the ZIP or clone the repository.
3. Run `Install.cmd`, review the printed summary, and answer y. `Install.cmd -Yes` is available for scripted runs. `-SkipBypass` preserves mode keys; `-SkipClearBlockingRules` preserves existing ask/deny arrays; `-SkipHelper` avoids helper installation. Add `-ProjectRoot "C:\dev\Example Project"` to reconcile that project.
4. Fully quit Claude (right-click the Claude icon in the system tray, Quit), then open it again. A new session alone does not load new PATH entries; the desktop app does not read PowerShell profiles.
5. Run `Doctor-Autonomy.ps1` and check the live profile import, tools, settings and helper state.

Setup installs Python, uv, Scoop, Node, gh, ripgrep, jq, SQLite, Playwright + chromium browser. It snapshots the original settings.json and CLAUDE.md once, records exact settings-operation backups and SHA-256 hashes, stages kit reference files, and merges the notification hook. Unchanged kit-owned instruction files update automatically; customized files remain intact. Malformed JSON or invalid permission/hook shapes stop configuration before configuration files are written. Missing required tools or failed browser installation cause a failing Setup exit code.

## Settings and instructions

Setup sets bypass only in user settings and removes mode overrides from existing selected project settings unless `-SkipBypass` is passed. It clears selected ask/deny arrays entirely unless `-SkipClearBlockingRules` is passed. Unrelated keys and foreign hooks remain. `-SkipConfig` skips settings, profiles, staging, snapshots and history writes. User files live under `CLAUDE_CONFIG_DIR` when set, otherwise `%USERPROFILE%\.claude`. Missing project files are not created. No setting suppresses Anthropic warning dialogs. The desktop app and CLI read the same settings and CLAUDE.md files.

The live Core imports the depth profile with a real standalone line:

```text
@CLAUDE-Cowork-Autonomous-Software-Development.md
```

Both files are installed beside each other under ~/.claude. The full profile loads every session and consumes context. Customized live CLAUDE.md is preserved; add that line yourself if Doctor reports it missing. A live file matching the previous staged kit copy updates automatically.

## Which shell runs commands

The Code tab uses Git Bash if installed, otherwise the PowerShell tool. PowerShell can also be explicitly enabled as the primary tool. The kit's Stop hook forces PowerShell with `"shell": "powershell"` and does not use a matcher. See [hooks](https://code.claude.com/docs/en/hooks).

## Folder still prompts

A folder still prompts after Setup: in the Code tab, open the mode selector next to the send button and pick Bypass permissions once for that folder. The app remembers a picked mode per folder and it overrides `defaultMode`.

## Helper and migration

The helper serves normal, non-elevated Claude Code sessions in the Code tab and CLI. Programs default to `%ProgramFiles%\ClaudeElevatedHelper`; data defaults to `%ProgramData%\ClaudeElevatedHelper`. Discovery state always lives at `%ProgramData%\ClaudeElevatedHelper\install-state.json`, including with a custom data root. Setup checks installed files, task arguments, scheduling and verified state before skipping installation; repairs retain recorded custom paths. See [helper documentation](../elevated-dev-helper/README.md).

For the direct v1.6.1 upgrade, run Setup without uninstalling. Only installations still carrying the old approval watcher need the separate legacy Uninstall migration, which also restores pre-kit configuration. Run the helper installer directly to re-register the task with the new paths, then Setup. The old C:\dev\ClaudeElevatedHelper directory is retained; check pending jobs before deleting it.

## Computer use

See the full profile's computer-use section for the single operating rule. The kit installs no dialog-clicking watcher. Desktop permission and browser safety checks still apply in bypass mode.

## Rollback and verification

`Uninstall-Autonomy.ps1 -RestoreLastReconcile` restores the entire files saved by the latest completed settings operation, retaining profiles/tools/helper and backing up later edits first. Repeating it does not undo older operations. Reinstalling can reapply the reconcile. Normal Uninstall restores each recorded project first-touch baseline and the first pre-kit snapshots and first saves current files to unique `.before-uninstall-*.bak` backups so later owner edits remain recoverable. If a file was originally absent it is removed only when still equal to the installed staged copy. Legacy settings without snapshots have only the kit defaultMode and notify hook stripped; timestamped backups are never selected as a substitute for the true baseline. `-WhatIf` makes no writes. General-purpose tools remain installed.

Tests and CI run configuration functions in temporary roots, never the full Setup or a live helper installation. Current runtime limits are in [verification evidence](IMPLEMENTATION-EVIDENCE.md). No clean-machine run was performed. See [unblocking and exact recovery commands](UNBLOCKING.md) and the [test plan](../tests/TEST-PLAN.md).

Official references: [desktop](https://code.claude.com/docs/en/desktop), [permission modes](https://code.claude.com/docs/en/permission-modes), [memory](https://code.claude.com/docs/en/memory), [settings](https://code.claude.com/docs/en/settings-reference).
