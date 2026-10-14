# Spec: Claude Code block-source audit and permission reconcile

Version 1.2 | 2026-10-13 | revised by Codex from v1.1 at Scott's request

Status: normative v1.2 specification implemented for kit v2.0.0. Verification and runtime limitations are recorded in [IMPLEMENTATION-EVIDENCE.md](IMPLEMENTATION-EVIDENCE.md).
Target kit release: **v2.0.0**.

Canonical repository copy: `docs/COWORK-KIT-UNBLOCK-SPEC.md`; imported from the owner-approved v1.2 document.

Spec versioning: minor revisions clarify or add requirements; major revisions reverse an owner decision. This revision preserves D1-D3 and the default-on plan. Correcting an ineffective project-mode setting is an implementation correction, not a reversal of maximum-autonomy intent.

## 1. Outcome and scope

Add a shared, read-only block-source audit to Setup and Doctor. Normal Setup automatically clears all `permissions.ask` and `permissions.deny` entries in the user's settings and existing settings files under an explicitly supplied project root. It configures bypass at user scope and removes project mode overrides so the user default can apply. Every change is recoverable and reported.

The product promise is: **clear the selected local permission rules, identify remaining restrictions and uncertainty, and never report an incomplete audit as proof of unrestricted execution.** It is not a promise that every Claude operation will run without interaction.

Supported surface: native Windows, Windows PowerShell 5.1, Claude Desktop's **Code tab** and the local Claude Code CLI. The historical repository name does not make this a Cowork-tab installer. WSL, Linux/macOS, cloud sessions, and the Cowork tab are outside this release's execution scope; list them as uninspected when relevant.

No helper redesign, toolchain migration, new capability-check skill, instruction-profile rewrite, browser-approval automation, or remote-policy modification is included. Those are comparison findings, not added acceptance gates.

## 2. Evidence baseline

Repository source inspected on 2026-10-13:

- [Cowork kit v1.6.1 baseline, df512e2](https://github.com/scottconverse/cowork-autonomy-kit/tree/df512e24614243b52b864cc45edbcead0c96cc17).
- [Codex kit v2.0.0 baseline, 1e2f0e8](https://github.com/scottconverse/codex-desktop-autonomy-kit/tree/1e2f0e85d0e1982809913f18caa2c0c5006a0b21).

At the v1.6.1 baseline, Cowork Setup already merges JSON, sets user bypass unless skipped, retains existing ask/deny, and maintains a notification hook. Doctor reports user-layer counts. Uninstall restores first pre-kit snapshots, preserves current files before restoration, and deliberately avoids guessing from timestamped backups. These are source observations, not newly executed install tests.

Platform facts affecting this design:

- Claude's user default can select bypass. Current documentation says a project-file bypass default makes terminal sessions start in Manual; do not write that setting into projects. Explicit ask/deny, critical-path deletion checks, and mandatory-interaction tools can survive bypass. Desktop additionally has an enablement toggle and remembered folder mode. Record the actual CLI/app versions used for validation; do not invent a minimum supported version from these documentation observations. [Permission modes](https://code.claude.com/docs/en/permission-modes)
- `CLAUDE_CONFIG_DIR` relocates the user configuration. Command-line settings and managed sources can override ordinary files. `/status` can help confirm loaded sources, but does not prove which source supplied every key. [Settings](https://code.claude.com/docs/en/settings)
- Windows policy may come from remote administration, HKLM/HKCU registry, or managed files/drop-ins. HKCU can be user-writable and administrators can edit local policy; report-only is this kit's scope boundary, not a claim of filesystem impossibility. [Managed settings](https://code.claude.com/docs/en/managed-settings)
- Hooks may originate in settings, plugins, skills, or agents and make input-dependent decisions. Merely finding a hook does not prove a particular call will be denied. [Hooks](https://code.claude.com/docs/en/hooks)

Implementation validation must confirm these specific behaviors against the installed target version. The v2.0.0 evidence record distinguishes verified configuration behavior from unverified runtime interactions. If behavior differs, document the supported version and adjust the implementation; do not silently retain a known ineffective setting. Later releases are unverified until checked.

## 3. Owner decisions retained

1. **D1: empty entirely.** Clear complete ask/deny arrays; do not guess which rules the owner wanted removed.
2. **D2: release v2.0.0.** Existing installations change behavior by default.
3. **D3: edit user plus explicitly selected project files automatically.** No extra permission request for shared/committed project settings. Managed sources remain report-only, as in the original plan, regardless of ACLs.
4. **Default-on reconcile with `-SkipClearBlockingRules`.** Retained from v1.1's plan. This was originally a derived default, not an additional quoted owner answer.

“Every writable layer” means the enumerated user/project targets, not a recursive disk search, arbitrary plugin files, registry policies, or every path a process can access.

## 4. Command surface and switch interaction

Add optional `-ProjectRoot <path>` to Setup and Doctor. Resolve it to an existing absolute directory; it identifies the project root directly. Do not infer a different root from the installer's working directory. Inspect only that root's `.claude/settings.json` and `.claude/settings.local.json`; no recursive project discovery. With no project argument, explicitly report project coverage as not requested.

Resolve the user configuration root from nonempty `CLAUDE_CONFIG_DIR`, otherwise `%USERPROFILE%\.claude`. Apply that resolution consistently to Setup, Doctor, snapshots, staging, and Uninstall. Record the resolved path. Reject an invalid root before configuration mutation; do not silently fall back.

| Setup option | Required behavior |
|---|---|
| No new skip flags | Clear selected ask/deny arrays, set user bypass, remove existing project `permissions.defaultMode` overrides. |
| `-SkipClearBlockingRules` | Preserve existing ask/deny values. Existing initialization of absent arrays may continue in the user merge. Mode reconcile and normal notification setup still run. |
| `-SkipBypass` | Preserve all mode keys, including project overrides. Rule clearing still runs unless separately skipped. |
| Both switches | Preserve existing rule arrays and mode keys; ordinary selected setup work still runs. No byte-preservation claim for files touched by the existing hook merge. |
| `-SkipConfig` | Overrides configuration operations: no settings/profile/staging/snapshot/manifest writes. Read-only audit may still run. Other tool/helper options retain their existing meanings. |
| `-Yes` | Skip the existing Setup confirmation, including the displayed reconcile changes. No additional confirmation flow. |

Do not introduce `-ClearBlockingRules`: reconcile is already the default. Update wrappers/help/examples consistently. Preserve `Install.cmd` argument forwarding, including quoted project paths.

Doctor remains read-only. Uninstall gains `-RestoreLastReconcile` for the bounded rollback described in section 7; normal Uninstall retains its whole-kit meaning. This mode must not uninstall tools, profiles, or the helper and must reject a simultaneous helper-removal request before doing work.

## 5. Audit contract

Use one collector shared by Setup and Doctor. Return ordinary PowerShell objects internally for tests and presentation; default public output is a readable table, not a JSON API.

### Sources and coverage

Inspect user settings and the two selected project files. On Windows, inspect these managed sources read-only when present:

- `Settings` registry values under `HKLM\SOFTWARE\Policies\ClaudeCode` and `HKCU\SOFTWARE\Policies\ClaudeCode` (account for the registry view used by the supported runtime).
- `managed-settings.json` and applicable JSON files in `managed-settings.d` under the documented Program Files ClaudeCode directory, derived from the platform path rather than a user-specific literal.

For each source distinguish absent, inspected, unreadable, malformed, and not inspected. Show policy content found locally without asserting it is the effective remote/host policy. Do not fetch account secrets or guess at undocumented remote caches. Remote/host policies, launch flags (including alternative settings sources), live session changes, Desktop toggle/folder selection, dynamically loaded hooks, and other execution environments receive explicit runtime/uninspected coverage entries.

Account for scalar precedence and additive permission lists when an effective result can be established from inspected sources. If policy-selection or managed-only controls make activation uncertain, retain provenance and label activation unknown; do not count every discovered source as active. A raw-file inventory must not masquerade as the live merged configuration.

### Findings

Each finding includes source path/registry key, scope, JSON field or hook location, raw rule or hook matcher/type/target, effect, activation confidence, remediation, and edit eligibility. Separate configured effect from observed runtime failure.

Required effects:

- **blocks when matched**: configured deny rule, subject to source activation.
- **requires approval when matched**: configured ask rule; unattended invocation may deny instead of displaying a prompt.
- **potential restriction**: dynamic hook or other setting whose impact cannot be established statically.
- **mode override**: a mode setting that prevents inheritance of the intended user default.
- **unknown/error**: unavailable source, invalid configuration, or unresolved activation.
- **no relevant finding**: inspected source with no identified restriction, not global permission proof.

Show all configured ask/deny entries with their original tool/pattern; do not build a new Claude rule interpreter. Inventory relevant configured hooks, including `PreToolUse` and permission/configuration hooks, as potential restrictions. Never execute arbitrary hooks, prompt hooks, or agent hooks to classify them. Mention plugin/skill/agent sources as uninspected unless their activation and source are actually known.

Also surface recognized mode-disable, managed-only, working-directory, sandbox, and MCP restriction settings when present. These remain report-only in this release. In particular, detect `permissions.disableBypassPermissionsMode` and `permissions.blockReadsOutsideWorkingDirectories`; empty arrays alone must not produce a clean bill of health while those restrictions remain. Use documented field names for the supported version and preserve unknown settings.

### Verdicts and status

Report separately: configurable rule findings, potential/runtime restrictions, and coverage errors. Prefer these messages:

- “No blocking permission rules found in inspected sources; runtime restrictions may remain.”
- “N rule findings; M other restrictions or unknowns. See source and remedy below.”
- “Audit incomplete: one or more requested sources could not be inspected.”

Always show the inspected roots and coverage summary. Never print “Claude Code will run routine dev commands without prompts.” A defaultMode value does not establish the current Desktop mode.

Doctor exits 0 when the requested static inspection completed, even if it found restrictions; exits nonzero for malformed/unreadable requested sources or other audit errors. Declared runtime blind spots are coverage limitations, not automatic command failure. Setup reports configuration success separately from remaining restrictions; failed requested configuration work must give a nonzero exit.

## 6. Reconcile contract

Targets are the user settings file and existing selected project settings files. User settings may be created. Missing project files/directories are reported absent and not created solely to hold empty arrays. Deduplicate identical target paths and reject ambiguous aliases or managed targets before writing.

Unless the corresponding switch skips it:

1. Set user `permissions.defaultMode` to `bypassPermissions`.
2. Remove `permissions.defaultMode` from each existing selected project file so it cannot override the user default. Record its exact old value. Do not install bypass as a project value.
3. Set selected `permissions.ask` and `permissions.deny` arrays to empty arrays.

Retain `allow`, other permissions, hooks, env, MCP settings, and unknown keys. Preserve JSON values and nesting; byte-for-byte formatting preservation is not promised for changed JSON. Do not silently truncate nested objects during serialization. Project edits must not install the user notification hook or other user profile content.

The new reconcile does not clear mode-disable flags, sandbox controls, hooks, or managed policy. It must identify them as remaining restrictions with a specific remedy, not claim to have cleared all blockers. Existing user notification setup and customized-profile preservation continue unchanged; there is no new instruction-profile content requirement.

Read and validate every target before configuration writes: JSON object shape, relevant arrays/types, serialization viability, target identity, and readable original bytes. Malformed targets abort configuration work with exact source/reason; never replace malformed settings with an empty object. An unavailable writable target must not be silently skipped as success.

Plan semantic changes before writing. An already-correct file is a true no-op: no rewrite, no extra backup, no new history entry. Show a field-level before/after diff only for changed keys; do not dump unrelated env values, credentials, or whole settings files.

Back up exact original bytes before changes; record missing-file state. Write validated UTF-8 without BOM through a same-directory temporary file and atomic replacement where available. Recheck the original hash before replacement to avoid overwriting an intervening edit. Validate the resulting JSON and intended values. Print a before/after audit so retained restrictions stay visible.

## 7. Backups, recovery, and uninstall

Extend existing lifecycle logic; do not replace it with newest-backup guessing. Maintain a small manifest in the resolved kit staging directory containing schema version, operation ID/time, absolute target paths, original existence, exact backup paths and SHA-256 hashes, written hashes, changed fields, and per-file operation state. Record prepared recovery information before the first replacement. Backups must not collide or be overwritten on repeat runs.

Preserve the first pre-kit user snapshot. Record a first-touch original/absent baseline for every project edited by this feature and retain it across subsequent installations, including installs targeting other projects. All configuration edits to a settings file in one Setup run, including the existing user hook merge, form one recorded settings operation; do not take a misleading baseline after half the edits.

Failure handling:

- Validation or backup failure: no live configuration changes.
- Failure after replacements begin: attempt to restore files changed by that operation, using exact recorded backups. Restore only if the live bytes still match the just-written state; never overwrite a concurrent edit during automatic recovery.
- Incomplete recovery or interrupted previous operation: report exact paths, retain manifest/backups, exit nonzero, and require recovery of that operation before starting another reconcile. Never claim all-files transactional atomicity.

`Uninstall-Autonomy.ps1 -RestoreLastReconcile` restores the most recent completed settings operation, leaving the kit installed. Verify backup hashes first. Preserve every current file in a unique before-restore backup before replacing it, so later user edits remain recoverable. Report that the entire saved file is restored. For a previously absent file, remove only if it still matches the recorded written hash; retain modified files and report incomplete restoration. After a successful restore, mark the operation restored so repeating the command does not walk backward through older history accidentally.

Normal Uninstall restores the original pre-kit user baseline using current semantics and each recorded project's first-touch baseline, preserving current bytes first. Never search for projects or restore an arbitrary latest `.bak-*`. Missing/moved projects are reported, not recreated at guessed paths; corrupt or missing backups are errors. Preserve unresolved manifest entries and backups instead of deleting the only recovery information. Kit-created files are removed only when unchanged. `-WhatIf` performs no writes, including backups or history updates.

A reinstall may reapply the default-on reconcile after restoration. Explain this in the recovery instructions.

## 8. Verification proportional to the change

Use existing production-function imports and temporary roots; no separate elaborate harness. Tests must call the same collector/reconcile/lifecycle functions used by the scripts, without touching real settings, registry, helper tasks, or accounts.

Extend existing merge/lifecycle tests and add `tests/Test-BlockAudit.ps1` as needed:

1. A user/project/local/managed fixture reports exact rule provenance, hook uncertainty, mode overrides, and absent/unreadable/malformed distinctions. Managed precedence uncertainty cannot produce an unconditional effective verdict.
2. Default reconcile clears user and both existing project arrays, sets bypass only at user scope, removes project mode overrides, and preserves unrelated nested values and all foreign hooks. Managed bytes remain unchanged.
3. Exercise the switch table, config-root override, quoted project path, no-project scope, and absent project files. `-SkipConfig` makes no configuration or recovery writes. Do not assert whole-file byte identity for `-SkipBypass` alone.
4. Repeat reconcile on already-correct inputs: identical bytes, no added backups/history. Check exact backup contents and hash attribution.
5. Malformed second target causes zero live changes; one focused simulated write failure verifies recovery and truthful failure reporting. An intervening change is retained and reported.
6. Restore-latest and full Uninstall use the specified distinct baselines across more than one project. Cover later user edits, missing/corrupt backup, missing project, created-file protection, repeated restore, and zero-write `-WhatIf` using compact fixtures.
7. For new logic assertions, demonstrate sensitivity with a deliberately wrong outcome or a temporary mutation, then restore it. Planting a deny rule and seeing a passing assertion alone is not evidence that the assertion would catch broken behavior.

Run the affected existing tests plus the repository's required BOM/path checks; wire the new test into the normal runner and Windows CI. Keep regex assertions CRLF-tolerant. Do not rebuild unrelated installers or broaden testing without a concrete failure/risk.

For the behavioral claim, perform one small scratch-folder exercise on each advertised surface: fresh Desktop Code session and CLI session, using the actual supported versions. Verify an active bypass mode, create/read/delete a disposable file with a routine tool call, and observe whether a permission prompt occurred. Do not explicitly pass a mode flag when testing whether the configured default loaded. Use Desktop's legitimate toggle/folder controls where required and record them; do not click through unrelated approvals automatically. Do not test critical-path deletion or real credential entry.

Record surface/version, configuration scope, observed mode, action, result, and prompt observation. JSON/unit tests prove edits and reporting; a CLI run cannot establish Desktop behavior. If either runtime cannot be exercised, label it unverified and do not claim that surface was proven prompt-free. Existing platform restrictions are not defects to evade.

## 9. Documentation and delivery

Add `docs/UNBLOCKING.md`: source discovery, rule versus hook versus mode versus runtime failures, exact commands, default-on behavior, opt-outs, backups, recovery, supported environments, and limits. Update README, setup guide, developer manual, test plan, changelog, script help, wrappers, and any public version/install text affected by v2.0.0.

Example normal commands:

```powershell
.\Install.cmd -ProjectRoot "C:\dev\Example Project"
.\Doctor-Autonomy.ps1 -ProjectRoot "C:\dev\Example Project"
.\Install.cmd -SkipClearBlockingRules
.\Install.cmd -SkipBypass -SkipClearBlockingRules
.\Uninstall-Autonomy.ps1 -RestoreLastReconcile
.\Uninstall-Autonomy.ps1 -WhatIf
```

Document a direct v1.6.1-to-v2.0.0 upgrade that retains pre-kit snapshots and records the pre-upgrade settings operation. Do not require blanket uninstall-first for this feature; retain separate instructions only where an older helper migration actually requires them.

Do not claim the absence of managed policy on Scott's machine without inspecting it during an authorized install/audit. Neither kit configuration nor an administrator helper overrides every application, organization, OS, or service boundary. Retain the existing concise bypass/prompt-injection warning beside the changed defaults.

Delivery: implementation branch, focused checks and review, PR with evidence, then Scott's merge/tag/publish decision. The spec rewrite itself does not authorize installation or publication.

## 10. Codex capability comparison and scope boundary

The accompanying `AUTONOMY-KIT-CAPABILITY-COMPARISON.md` records current capabilities and supporting source files. Its conclusions are part of the design rationale, not an instruction to port every feature.

For this release, borrow the Codex kit's automatic reconcile, field-level change reporting, exact backup attribution, and dedicated unblock guide. Claude needs a broader source audit and different permission edits. Do not generate fictitious Claude `.rules` files or describe Codex's local rules as a universal safety override. Codex rule conflicts use the most restrictive matching decision. [OpenAI rules documentation](https://learn.chatgpt.com/docs/agent-configuration/rules)

## 11. Numbered change log

1. **v1.0, 2026-10-13:** initial audit/opt-in reconcile proposal, based on Cowork v1.6.1; D1-D3 open.
2. **v1.1, 2026-10-13:** recorded D1 empty arrays, D2 release v2.0.0, D3 user/project edits; derived default-on reconcile with an opt-out. Several tests and examples still reflected v1.0.
3. **v1.2, 2026-10-13:** reconciled defaults, flags, tests, and scope; corrected project-mode behavior and absolute platform claims; defined coverage/unknown findings, config-root resolution, managed-source reporting, no-op behavior, multi-file recovery and restore semantics, versioned runtime evidence, direct upgrade behavior, and source-backed Codex comparison. D1-D3 and the planned kit release version are unchanged.
