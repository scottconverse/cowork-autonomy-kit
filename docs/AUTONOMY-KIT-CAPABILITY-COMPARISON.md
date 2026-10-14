# Autonomy kit capability comparison

2026-10-13 | Claude Code kit v2.0.0 and [Codex kit v2.0.0 at 1e2f0e8](https://github.com/scottconverse/codex-desktop-autonomy-kit/tree/1e2f0e85d0e1982809913f18caa2c0c5006a0b21)

The kits share user-scope development tools, persistent instructions, permissive configuration, diagnostics and optional administrator execution. Their host applications use different permission systems. Claude kit v2.0.0 implements the previously proposed permission audit, selected local rule reconciliation and exact settings recovery. It does not implement every Codex-kit feature.

| Capability | Codex kit v2.0.0 inspected baseline | Claude Code kit v2.0.0 |
|---|---|---|
| Main surface | Windows Codex Desktop | Windows Claude Desktop Code tab and CLI; excludes Cowork tab |
| Tools | User-scope developer/bootstrap and browser tooling | User-scope development bootstrap with Playwright/Chromium |
| Configuration | Reconciles three autonomy keys in TOML while preserving other text/formatting | JSON value merge; clears selected user/project ask/deny by default while preserving unrelated settings |
| No-prompt defaults | approval_policy=never, sandbox_mode=danger-full-access and Windows sandbox configuration | User bypassPermissions default, project-mode override removal; Desktop enablement and remembered mode still matter |
| Command rules | Generated execpolicy allow rules for discovered shell paths and command names; validates sample commands with CLI | No equivalent kit-owned command-rules component |
| Restriction diagnostics | Rules freshness/BOM/shell coverage, configuration and helper dashboard | Source-attributed user/project/policy audit, potential hook/control restrictions and explicit uninspected runtime inputs |
| Recovery guide | docs/BLOCKED-BY-POLICY.md | [UNBLOCKING.md](UNBLOCKING.md), including interrupted settings operations |
| Capability self-assessment | Installed capability-check skill and managed global AGENTS block | General action/verification instructions; no equivalent installed skill |
| Instruction profiles | Staged Core/depth profiles; custom config does not receive new developer instructions during reconcile | Core imports depth each session; custom live instructions retained and missing import reported |
| Administrator execution | Highest-privilege scheduled-task helper; trusted PowerShell scripts | Same broad practical capability, with different roots/state paths and protected worker files |
| Helper concurrency | Queue task policy, atomic publication and drain loop | IgnoreNew, atomic publication and serial drain; final-empty-check/exit race remains |
| Remote bootstrap integrity | uv/Scoop downloads checked against pinned SHA-256 values | uv/Scoop download-and-execute flows without equivalent pins |
| Exact recovery | Backup manifest records exact original backup and hash | Retains first user pre-kit and project first-touch baselines; per-operation exact backups/hashes and latest-operation restore |
| Reuse license | MIT at the inspected baseline | No reuse license provided |

## Permission systems are not equivalent

The inspected Codex `Get-CommandRulesText` writes broad executable-prefix allows for discovered shells plus command-name rules. Its `codex execpolicy check` validation proves sample invocations against the supplied file, not every session policy or command spelling. See [the pinned Codex Setup source](https://github.com/scottconverse/codex-desktop-autonomy-kit/blob/1e2f0e85d0e1982809913f18caa2c0c5006a0b21/Setup-Autonomy.ps1).

Those rules do not establish an override of explicit forbidden rules, enterprise requirements or service-side controls. The [OpenAI rule semantics](https://learn.chatgpt.com/docs/agent-configuration/rules) describe strictest-match behavior and compound-command handling. Claude's [permission modes](https://code.claude.com/docs/en/permission-modes) are a different mechanism; there is no direct port of an execpolicy file.

Claude kit v2.0.0 clears complete ask/deny arrays only in selected user/project files, corrects local mode inheritance and reports remaining inspected restrictions. Managed sources stay read-only. Static inventory cannot prove the complete policy of a running Desktop session. Dynamic hooks, launch/host policy and Desktop choices remain visible as uncertainty.

## Remaining differences

Capability-skill parity, bootstrap hash pinning and helper queue parity remain possible future work. They are not shipped v2.0.0 features. Neither kit grants task authorization for unrelated actions; the elevated helper supplies operating-system capability, and application/service constraints remain separate.

## Source map and evidence

Claude implementation: [Setup](../Setup-Autonomy.ps1), [shared audit/recovery library](../lib/AutonomySettings.ps1), [Doctor](../Doctor-Autonomy.ps1), [Uninstall](../Uninstall-Autonomy.ps1), [helper](../elevated-dev-helper/README.md) and [architecture](ARCHITECTURE.md). Historical comparison began at [Claude v1.6.1, df512e2](https://github.com/scottconverse/cowork-autonomy-kit/tree/df512e24614243b52b864cc45edbcead0c96cc17); that is a baseline, not the current implementation.

Codex claims refer to the pinned source above and its [README](https://github.com/scottconverse/codex-desktop-autonomy-kit/blob/1e2f0e85d0e1982809913f18caa2c0c5006a0b21/README.md) and [helper documentation](https://github.com/scottconverse/codex-desktop-autonomy-kit/blob/1e2f0e85d0e1982809913f18caa2c0c5006a0b21/elevated-dev-helper/README.md). This is not a newly run Codex stress test.

Claude v2.0.0 has 150 passing Windows regression assertions and an existing-machine uninstall/install/Doctor/helper walkthrough. CLI initialization reported bypassPermissions but authentication failed, so file-action and prompt behavior remain unverified. Desktop runtime and clean-machine installation remain unverified. See [verification evidence](IMPLEMENTATION-EVIDENCE.md) for exact scope.
