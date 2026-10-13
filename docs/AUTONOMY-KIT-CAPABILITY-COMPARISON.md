# Autonomy kit capability comparison

2026-10-13 | Repository inspection, not a new installation or runtime certification

Compared [Codex v2.0.0 at 1e2f0e8](https://github.com/scottconverse/codex-desktop-autonomy-kit/tree/1e2f0e85d0e1982809913f18caa2c0c5006a0b21) with [Claude Code kit v1.6.1 at df512e2](https://github.com/scottconverse/cowork-autonomy-kit/tree/df512e24614243b52b864cc45edbcead0c96cc17). The proposed column refers to spec v1.2, targeting Claude kit release v2.0.0; it is not shipped functionality.

The kits share the same practical aim: user-scope tools, persistent instructions, permissive configuration, diagnostics, and optional administrator execution. The Codex kit currently has more supporting autonomy features. The Claude proposal improves permission visibility beyond either kit's current dashboard, but will not make their runtime permission systems identical.

| Capability | Codex kit today | Claude Code kit today | Claude proposal |
|---|---|---|---|
| Main surface | Windows Codex Desktop | Windows Claude Desktop Code tab and CLI; excludes Cowork tab | Same scope |
| Tools | User-scope development bootstrap and browser tooling | Similar bootstrap with Playwright/Chromium | No change |
| Existing custom settings | Reconciles three autonomy keys in TOML; preserves other text/formatting | JSON merge sets user bypass, retains existing ask/deny and unrelated values | Clears selected user/project ask/deny; correct user-mode inheritance |
| No-prompt configuration | `approval_policy=never`, `sandbox_mode=danger-full-access`, Windows sandbox setting | User `permissions.defaultMode=bypassPermissions`; Desktop enablement still needed | Same underlying mode; remaining restrictions reported |
| Command-rule mechanism | Generated execpolicy allow rules for discovered shell paths and command names; validates with Codex CLI | No matching kit-owned command-rules component | No invented direct equivalent |
| Restriction diagnostics | Rules-file freshness/BOM/shell coverage; configuration and helper status | User permission counts, profiles, tools, helper status | Provenance across selected files and local policy, hook uncertainty, explicit coverage limits |
| Dedicated recovery guidance | `docs/BLOCKED-BY-POLICY.md` | General setup/developer documentation | New `docs/UNBLOCKING.md` |
| Capability self-assessment | Installed `capability-check` skill and managed global AGENTS block | General action/verification guidance; no equivalent installed skill found | Remains a separate possible enhancement |
| Instructions | Core/depth profiles staged; custom config does not receive new developer instructions during reconcile | Core imports the depth profile each session; customized live profiles retained | Existing behavior retained |
| Admin execution | Highest-privilege scheduled-task helper; arbitrary trusted PowerShell scripts | Same broad practical capability, different roots/state paths | No helper redesign |
| Concurrent helper requests | `Queue` task policy, atomic publication, drain loop | `IgnoreNew`, serial drain; README acknowledges a final-empty-check/exit race | Known difference remains outside unblock scope |
| Remote bootstrap integrity | uv/Scoop downloads checked against pinned SHA-256 values | Inspected Setup invokes uv/Scoop download-and-execute flows without equivalent pins | Separate possible enhancement |
| Recovery baseline | Config backup manifest records exact backup and hash | First pre-kit snapshots; current-file backup before restore | Retains pre-kit baseline, adds project tracking and latest-settings-operation restore |
| Source reuse terms | MIT license | README says no reuse license provided | No license change in this specification |

## What the Codex rules actually establish

The inspected `Get-CommandRulesText` implementation writes broad executable-prefix allows for discovered shells, plus command-name rules. This is wider than a precise allowlist for one delete flag. Its validation exercises sample arguments with `codex execpolicy check`; that proves those samples against the supplied rule file, not every possible session policy or command spelling. See [Codex Setup](https://github.com/scottconverse/codex-desktop-autonomy-kit/blob/1e2f0e85d0e1982809913f18caa2c0c5006a0b21/Setup-Autonomy.ps1).

The kit documents these rules as addressing built-in force-delete/link-opener rejections. That does not establish an override of explicit forbidden rules, enterprise requirements, or service-side controls. Official documentation says the strictest matching rule wins, and compound-command handling affects which invocation is matched. [OpenAI rule semantics](https://learn.chatgpt.com/docs/agent-configuration/rules)

Consequently, port the diagnostic and recovery pattern, not a claim that either kit can switch off all safety or platform enforcement. Also avoid repeating an exhaustive “only these commands can ever block” claim across product versions.

## Where the Claude feature differs

Its core job is to find and remove configured ask/deny entries at the selected local scopes, correct mode inheritance, and explain restrictions left behind. A static inventory cannot establish an active Desktop session's full policy. Dynamic hooks and uninspected launch/host policy must remain visible as uncertainty rather than being counted as cleared.

This is a stronger source-attribution feature than either inspected Doctor currently offers. It is also a narrower intervention than deleting every hook, sandbox setting, or managed source. That boundary is explicit in the revised spec and preserves its owner-approved user/project scope.

## Recommended handling of the other differences

Carry automatic local reconcile, exact backup attribution, a dedicated troubleshooting guide, and honest diagnostics into this release. Keep capability-skill parity, bootstrap hash pinning, and helper queue parity on a separate list. Each could be useful, especially the acknowledged helper scheduling race, but none is required to implement the requested permission audit correctly.

Do not describe either kit as an automatic grant of authority for unrelated tasks. The elevated helpers provide OS capability; task authorization and application/service boundaries remain separate.

## Source map and evidence limits

- Configuration, tool bootstrap, rule generation, and installed skill: each repository's `Setup-Autonomy.ps1`; [Codex README](https://github.com/scottconverse/codex-desktop-autonomy-kit/blob/1e2f0e85d0e1982809913f18caa2c0c5006a0b21/README.md), [Claude README](https://github.com/scottconverse/cowork-autonomy-kit/blob/df512e24614243b52b864cc45edbcead0c96cc17/README.md).
- Recovery: each repository's `Uninstall-Autonomy.ps1`; Claude `tests/Test-SettingsMerge.ps1` and developer manual.
- Helper behavior: [Codex helper documentation](https://github.com/scottconverse/codex-desktop-autonomy-kit/blob/1e2f0e85d0e1982809913f18caa2c0c5006a0b21/elevated-dev-helper/README.md), [Claude helper documentation](https://github.com/scottconverse/cowork-autonomy-kit/blob/df512e24614243b52b864cc45edbcead0c96cc17/elevated-dev-helper/README.md). Queue reliability here is a source/documentation comparison, not a newly run stress test.
- Audit extent: each repository's `Doctor-Autonomy.ps1`.

Repository files were read from fresh clones at the commits above; a cached GitHub web view showed older Codex version text, so this comparison uses the checked-out source. No real configuration, installed helper, or runtime permission mode was changed for the comparison.
