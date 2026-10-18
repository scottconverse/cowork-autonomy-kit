# Claude Code Windows Autonomy Kit

Version 2.0.0 - Windows - Independent community project, not affiliated with Anthropic.

Full-permission setup for Claude Code on Windows: the desktop app's Code tab and the CLI.

The Cowork tab is not in scope. Cowork has its own permission modes and runs commands in a VM or in the cloud.

The repository and CLAUDE-Cowork-*.md filenames are historical and remain stable for existing installs.

[Website](https://scottconverse.github.io/cowork-autonomy-kit/) | [User manual](docs/USER-MANUAL.md) | [Setup guide](docs/SETUP.md) | [Latest release](https://github.com/scottconverse/cowork-autonomy-kit/releases/tag/v2.0.0) | [Changelog](CHANGELOG.md)

## What it does

- Installs missing user-scope developer tools, Playwright and its Chromium browser.
- Merges Claude Code settings, preserving custom keys while clearing selected ask/deny arrays by default. Use `-SkipClearBlockingRules` to retain rules.
- Stages profiles and preserves customized live instruction files. The Core imports the depth profile every session, which costs context.
- Installs an optional administrator helper with protected program files and separate queue/results storage.
- Provides Doctor, configuration rollback, and isolated regression tests.
- `New-AgentProject.ps1` turns the hook-kit guardrails on for a project before its first agent prompt: writes `.claude\hook-kit.json` (and `.codex\hook-kit.json`), `RULES.md`, an empty read ledger, a measurement stub and a receipts folder, then proves the read-ledger gate blocks a code write there. Refuses to finish if a kit is not installed.
- `Test-CiStandard.ps1 -RepoRoot <repo>` audits a repository's `.github/workflows/*.yml` against the owner's CI standard: required checks kept to about 10, non-required checks path-filtered plus nightly and never on every push, `concurrency` with `cancel-in-progress` on every workflow, every job under a 10-minute `timeout-minutes`. One PASS/FAIL row per rule with file and line; exit 1 on any FAIL. Ported from the archived `check_actions_budget.py`; see `docs/handoff-ci-standard-check.md` for what was carried, inverted or dropped.

## Before installing

Use native Windows with Windows PowerShell 5.1 and Windows Package Manager (`winget`, provided by Microsoft App Installer). Install Claude separately and sign in for actual sessions. Setup uses winget when Python is missing.

In Claude: Settings, Claude Code, turn on 'Allow bypass permissions mode'. Without it the Code tab cannot use Bypass permissions.

Review the [setup guide](docs/SETUP.md) before running `Install.cmd`. Setup shows its changes and asks `Continue? [y/N]`; `-Yes` skips that question. It sets user `permissions.defaultMode = "bypassPermissions"`, removes mode overrides from existing explicitly selected project settings, clears their ask/deny arrays, and wires a user notification hook. `-SkipBypass` preserves mode keys; `-SkipClearBlockingRules` preserves rules. `-ProjectRoot "C:\dev\Example Project"` selects a project; no projects are scanned automatically. It never hides Anthropic's warning dialogs. The owner accepts the risk described here.

Anthropic states: "`bypassPermissions` offers no protection against prompt injection or unintended actions." [Permission modes](https://code.claude.com/docs/en/permission-modes). With the helper installed, code Claude writes under `C:\dev\` can run as administrator without a UAC prompt for each action. Trusted roots do not sandbox script effects. Retained `deny` rules still apply in bypass mode; use `-SkipClearBlockingRules` to retain them during Setup. Managed policy, hooks, Desktop mode selection and built-in restrictions may still limit execution.

Download the [v2.0.0 ZIP](https://github.com/scottconverse/cowork-autonomy-kit/releases/download/v2.0.0/cowork-autonomy-kit-v2.0.0.zip), verify it against the release SHA256SUMS.txt, extract it, inspect it, then run `Install.cmd`. The optional helper requests Windows UAC approval. The kit does not install Claude itself.

Fully quit Claude (right-click the Claude icon in the system tray, Quit), then open it again. A new session alone does not load new PATH entries; the desktop app does not read PowerShell profiles.

## Upgrading

Upgrade directly from v1.6.1 by running the new Setup; do not uninstall first. The first pre-kit snapshots are preserved and each settings change gets an exact recovery record. Older helper/watcher migrations remain separate; see the setup guide. For a customized live CLAUDE.md, add `@CLAUDE-Cowork-Autonomous-Software-Development.md` on its own line if Doctor reports the import missing.

Version 2.0.0 changes defaults: selected ask/deny rules are now cleared unless you opt out. [Unblocking and recovery](docs/UNBLOCKING.md) covers Doctor coverage, both opt-outs, `CLAUDE_CONFIG_DIR`, project settings, interrupted operations and `-RestoreLastReconcile`.

## Documentation and verification

- [Architecture and recovery diagrams](docs/ARCHITECTURE.md)
- [Capability comparison with the Codex kit](docs/AUTONOMY-KIT-CAPABILITY-COMPARISON.md)
- [Developer manual](docs/DEVELOPER-MANUAL.md)
- [Elevated helper](elevated-dev-helper/README.md)
- [Core instructions](CLAUDE-Cowork-Core.md)
- [Test plan](tests/TEST-PLAN.md)
- [Website development](site/README.md)

Windows regression tests passed 150 assertions. An existing-machine walkthrough ran the legacy uninstall, full Install.cmd, Doctor and elevated-helper verification successfully. A fresh CLI loaded bypassPermissions but failed authentication, so file actions and prompt behavior were not proven. Desktop runtime activation and a clean-machine installation remain unverified. See [verification evidence](docs/IMPLEMENTATION-EVIDENCE.md).

Historical v1.6.1 verification is recorded in the changelog. For v2.0.0, see [verification evidence](docs/IMPLEMENTATION-EVIDENCE.md). Configuration tests do not prove a prompt-free Desktop or CLI session.

## License

Public source, but no reuse license is provided. Public visibility does not imply an open-source license.
