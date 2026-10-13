# Claude Code Windows Autonomy Kit

Version 2.0.0 candidate (unreleased) - Windows - Independent community project, not affiliated with Anthropic.

Full-permission setup for Claude Code on Windows: the desktop app's Code tab and the CLI.

The Cowork tab is not in scope. Cowork has its own permission modes and runs commands in a VM or in the cloud.

The repository and CLAUDE-Cowork-*.md filenames are historical and remain stable for existing installs.

[Website](https://scottconverse.github.io/cowork-autonomy-kit/) | [Setup guide](docs/SETUP.md) | [Latest release](https://github.com/scottconverse/cowork-autonomy-kit/releases/tag/v1.6.1) | [Changelog](CHANGELOG.md)

## What it does

- Installs missing user-scope developer tools, Playwright and its Chromium browser.
- Merges Claude Code settings, preserving custom keys while clearing selected ask/deny arrays by default. Use `-SkipClearBlockingRules` to retain rules.
- Stages profiles and preserves customized live instruction files. The Core imports the depth profile every session, which costs context.
- Installs an optional administrator helper with protected program files and separate queue/results storage.
- Provides Doctor, configuration rollback, and isolated regression tests.

## Before installing

In Claude: Settings, Claude Code, turn on 'Allow bypass permissions mode'. Without it the Code tab cannot use Bypass permissions.

Review the [setup guide](docs/SETUP.md) before running `Install.cmd`. Setup shows its changes and asks `Continue? [y/N]`; `-Yes` skips that question. It sets user `permissions.defaultMode = "bypassPermissions"`, removes mode overrides from existing explicitly selected project settings, clears their ask/deny arrays, and wires a user notification hook. `-SkipBypass` preserves mode keys; `-SkipClearBlockingRules` preserves rules. `-ProjectRoot "C:\dev\Example Project"` selects a project; no projects are scanned automatically. It never hides Anthropic's warning dialogs. The owner accepts the risk described here.

Anthropic states: "`bypassPermissions` offers no protection against prompt injection or unintended actions." [Permission modes](https://code.claude.com/docs/en/permission-modes). With the helper installed, code Claude writes under `C:\dev\` can run as administrator without a UAC prompt for each action. Trusted roots do not sandbox script effects. Retained `deny` rules still apply in bypass mode; use `-SkipClearBlockingRules` to retain them during Setup. Managed policy, hooks, Desktop mode selection and built-in restrictions may still limit execution.

Download and extract the release ZIP, inspect it, then run `Install.cmd`. The optional helper requests Windows UAC approval. The kit does not install Claude itself.

Fully quit Claude (right-click the Claude icon in the system tray, Quit), then open it again. A new session alone does not load new PATH entries; the desktop app does not read PowerShell profiles.

## Upgrading

Upgrade directly from v1.6.1 by running the new Setup; do not uninstall first. The first pre-kit snapshots are preserved and each settings change gets an exact recovery record. Older helper/watcher migrations remain separate; see the setup guide. For a customized live CLAUDE.md, add `@CLAUDE-Cowork-Autonomous-Software-Development.md` on its own line if Doctor reports the import missing.

This major-version candidate changes defaults. [Unblocking and recovery](docs/UNBLOCKING.md) covers Doctor coverage, both opt-outs, `CLAUDE_CONFIG_DIR`, project settings, interrupted operations and `-RestoreLastReconcile`. The linked latest release is still the published v1.6.1; candidate code is not a published ZIP.

## Documentation and verification

- [Developer manual](docs/DEVELOPER-MANUAL.md)
- [Elevated helper](elevated-dev-helper/README.md)
- [Core instructions](CLAUDE-Cowork-Core.md)
- [Test plan](tests/TEST-PLAN.md)
- [Website development](site/README.md)

Isolated Windows PowerShell 5.1 lifecycle and regression tests cover the real installer functions. A clean-machine installation remains unverified. See release notes for exact evidence.

Historical v1.6.1 verification is recorded in the changelog. For this candidate, see [verification evidence](docs/IMPLEMENTATION-EVIDENCE.md). Configuration tests do not prove a prompt-free Desktop or CLI session.

## License

Public source, but no reuse license is provided. Public visibility does not imply an open-source license.
