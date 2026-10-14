# v2.0.0 verification evidence

Implementation checks: 2026-10-13. Existing-machine installation: 2026-10-14 UTC (October 13 local time). Runtime implementation is commit `b5cee47823b8024067d83c52402aac568dc5f201`; release documentation is included in the v2.0.0 tag. The [v2.0.0 release](https://github.com/scottconverse/cowork-autonomy-kit/releases/tag/v2.0.0) identifies the source archive and its SHA-256. This document distinguishes automated configuration coverage from real installation and authenticated runtime behavior.

## Scope and verification

Critical lane: persisted permission settings, concurrent writes, install/rollback. The changed boundary is selected user/project settings, their recovery records, and the Setup/Doctor/Uninstall command surfaces. Helper redesign, capability-skill parity and bootstrap pinning remain excluded.

The initial production-function baseline passed:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Test-SettingsMerge.ps1
SUMMARY: 9 PASS / 0 FAIL
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/Test-Lifecycle.ps1
SUMMARY: 13 PASS / 0 FAIL
```

The Windows CI sequence runs each test in a separate Windows PowerShell 5.1 process, using `powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/<name>.ps1`. Latest local results:

| Test | Exact summary/result |
|---|---|
| Test-BlockAudit | `SUMMARY: 12 PASS / 0 FAIL` |
| Test-Reconcile | `SUMMARY: 22 PASS / 0 FAIL` |
| Test-Recovery | `SUMMARY: 27 PASS / 0 FAIL` |
| Test-SettingsMerge | `SUMMARY: 9 PASS / 0 FAIL` |
| Test-UninstallBakFilter | `SUMMARY: 6 PASS / 0 FAIL` |
| Test-Lifecycle | `SUMMARY: 14 PASS / 0 FAIL` |
| Test-NoBOM | `PASS: no UTF-8 BOM in shipped JSON or live settings.json.` |
| Test-NoHardcodedPaths | `PASS: all tracked text files scanned, including forward-slash sample proof` |
| Test-HelperInstall | `SUMMARY: 30 PASS / 0 FAIL` |
| Test-AuditRegressions | `SUMMARY: 30 PASS / 0 FAIL` |

The complete sequence passed once. The affected recovery/lifecycle/reconcile/uninstall/audit regressions were rerun after the final lock/hash changes. All `.ps1` files were parsed with `System.Management.Automation.Language.Parser::ParseFile`; the run reported `PASS: parsed 22 PowerShell scripts`.

Hosted Windows runs exposed short-name temporary-path aliases in fixture comparisons: the config-root assertion, injected replacement-failure target and lifecycle error-path assertion. Expected roots and those fixtures now use canonical paths. The lifecycle failure was reproduced locally using a real Windows short-path alias; affected configuration tests were then exercised together with that temporary-path form. These corrections do not change production root resolution.

```text
npm test
PASS: anchors, unique headings/IDs, portable paths, disclosures, focus and reduced-motion styles
PASS: v2.0.0 consistency and minimum 12px text declarations
npm run build
PASS: static site built in dist/ (no dependencies)
```

No new dependency, framework or installer build was introduced. The site test now distinguishes the declared candidate version from legitimate older published-download and upgrade references.

## Requirement coverage

| Spec area | Evidence |
|---|---|
| 4: roots, explicit project and switch interactions | Reconcile fixtures cover all mode/rule skip combinations, paths with spaces, absent files, root override/invalid root, no project and zero-write SkipConfig. Real command probes cover cancellation, incompatible restore/helper options and WhatIf. Install.cmd continues forwarding `%*`. |
| 5: audit and status | BlockAudit exercises provenance, deny/ask effects, hook uncertainty, mode precedence, policy activation uncertainty, absent/malformed/unreadable/uninspected distinctions and read-only bytes. Real Doctor processes returned 0 for a deny and 1 for malformed JSON. |
| 6: selected edits, preservation and no-op | Reconcile covers user/project/local defaults and nested/allow preservation. Recovery checks byte-identical no-op settings and unchanged history, exact original bytes/hashes and a second project. Existing merge tests preserve foreign hooks. |
| 6-7: preflight, failure and concurrency | Malformed later-target preflight, a failed replacement, failed final manifest persistence, retained concurrent edit, late hash check, linked-target refusal and overlapping-operation lock assertions. |
| 7: recovery and restore | A child exits during actual restore; durable pending state blocks even an empty-plan reconcile, and retry restores exact originals. Latest-operation and first-touch baseline restore are distinct. Corrupt/missing backups, missing project, modified created files, repeat restore and WhatIf are exercised. |
| 8: test sensitivity | Initial meaningful RED assertions and three production-code mutations described below. Runtime limits are listed separately. |
| 9: docs and handoff | README, setup/manual, test plan, changelog, script help/wrapper examples and site candidate copy updated. UNBLOCKING documents defaults, scope, direct upgrade and exact recovery. Spec/comparison are included. Release documentation includes the user manual, architecture drawings and links to v2.0.0. |

## Sensitivity and independent review

Before implementation, the audit, planner and operation fixtures each failed on their intended observable assertion: missing deny provenance, missing selected plans and unchanged live deny respectively. Three temporary mutations of the actual production library subsequently gave:

```text
Test-BlockAudit, mutated deny effect: EXIT 1
FAIL: deny finding carries source, rule and configured effect
Test-Reconcile, inverted rule-clearing condition: EXIT 1
FAIL: default clears user rules
Test-Recovery, removed concurrent-edit recovery guard: EXIT 1
FAIL: automatic recovery never overwrites a concurrent edit
```

Each affected test passed after restoring the source; the mutation runner confirmed byte-for-byte source restoration. An initial Python child runner inherited an unsuitable PowerShell module environment and failed before its assertions; it was not counted as sensitivity evidence. The successful mutation checks used the same direct Windows PowerShell invocation as CI.

A separate verifier independently reproduced and then verified corrections for three defects: legacy user restore omitted by a project-only manifest, false recovery after final manifest persistence failure, and an interrupted restore being bypassed by a subsequent reconcile. Focused rechecks also covered zero-write WhatIf, caller-owned lock lifetime, contention, staging cleanup and lock reacquisition. No scoped findings remained. Hash checks narrow the concurrent-editor window; they do not implement filesystem compare-and-swap or an all-files atomic transaction.

## Runtime observations and limitations

The CLI probe used a disposable `CLAUDE_CONFIG_DIR` and project, without a permission-mode flag. It invoked:

```text
claude -p "In the current directory only, create autonomy-smoke.txt containing smoke-ok, read it, delete it, and report the three results. Do not access other files or run other commands." --output-format stream-json --verbose --no-session-persistence --max-budget-usd 0.25
```

CLI **2.1.280** emitted these initialization modes:

| User mode | Project mode | Observed session mode |
|---|---|---|
| default | bypassPermissions | default |
| bypassPermissions | default | default |
| bypassPermissions | absent | bypassPermissions |

This establishes default loading and the need to remove project overrides for this installed CLI. The requested file exercise stopped with the exact runtime result `Not logged in · Please run /login` (`is_error: true`, cost zero, no scratch file created). Therefore create/read/delete and permission-prompt behavior are **unverified**. No credentials were copied into the isolated configuration.

Desktop **2.37337.1.0** was running with bundled Claude Code **2.1.295**. A Windows UI Automation probe reached the Claude window but exposed only 16 accessibility descendants and no usable Code-session controls. A fresh Desktop Code scratch session was not exercised; its active mode and prompt behavior remain **unverified**. The CLI initialization result does not prove Desktop behavior. The subsequent existing-machine helper reinstall is recorded below. No complete clean-machine installation or authenticated Desktop file-operation test is claimed.

Both registry views are inspected conservatively; the exact view selected by each installed Claude runtime remains unestablished, and managed activation is labeled unknown. Remote/host/session policy is intentionally uninspected. Official policy-path and key documentation was consulted; no claim of complete effective-policy reconstruction is made.

## Scoped newcomer/documentation check

Partial coverage of changed configuration journeys on the existing Windows machine, with isolated profiles; this is not a full clean-machine walkthrough. Setup's printed default summary and cancellation were exercised. The cancel returned before tool installation and left zero files in the isolated config root. Doctor's rule/error verdicts and Uninstall's parameter rejection/WhatIf were exercised through actual entry scripts. Positive configuration and restore paths use the real production functions in the tests above.

The built site's changed install and status sections were rendered in headless Microsoft Edge at a 1280-pixel viewport and visually inspected: candidate versus published release wording, opt-outs and runtime limits are legible. The Playwright default browser binary was missing; existing Edge provided the rendering instead. Screenshots were captured successfully; a later console text-print encoding error did not invalidate those images. The published v1.6.1 release link was resolved with `gh release view v1.6.1 --json url,tagName`.

Raw local evidence inventory: per-test logs, mutation/green logs, runtime mode JSON, install/status screenshots, and the separate review's small reproduction scripts. These are retained with the working session; concise results and limitations are preserved here and in the PR. These implementation observations do not by themselves prove clean-machine or authenticated runtime behavior.

## Existing-machine uninstall and install

The actual v2.0.0 uninstaller removed a July legacy installation (no operation manifest), stripped its bypass default and notification hook, removed the legacy watcher task, and exited 0. The customized live CLAUDE.md remained byte-identical. A private backup of kit-related settings and staged files was retained before uninstall; credentials and chat history were not copied.

The actual Setup entry script and `Install.cmd -Yes` completed successfully. The final batch run used unmodified code and exited 0; all 12 tool checks passed. It installed the current notification hook and depth profile, configured user bypass with empty ask/deny arrays, preserved foreign hooks, and upgraded the elevated helper through its own installer. The helper's administrator and installed-path checks succeeded, and subsequent Setup verified the installed program hashes and task configuration. Doctor exited 0. No project was selected.

An initial indirect batch launch inherited Codex's PowerShell 7 module paths into Windows PowerShell 5.1 and failed to resolve Get-FileHash. The final launch used the standard Windows PowerShell module search path in its process environment. No persistent environment or source workaround was left behind. From an embedded PowerShell 7 host, launch Windows PowerShell directly or ensure a child cmd process receives a Windows PowerShell-compatible PSModulePath.

A fresh CLI 2.1.280 invocation with the live user settings, no permission-mode override and a disposable working directory emitted `permissionMode: bypassPermissions`. It then returned `Not logged in · Please run /login` and exit 1. This establishes configuration loading, not authenticated tool execution. Existing Desktop sessions were left running; the app toggle, full restart and current Desktop tool behavior remain unverified. The customized CLAUDE.md did not contain the optional depth-profile import; preserving it was intentional.

## Bounded clean Windows Sandbox probe

A fresh Windows 11 Enterprise Sandbox (10.0.26100, x64, Windows PowerShell 5.1) had no kit configuration, Claude, winget, Python, Node, Scoop or GitHub CLI. The actual `Install.cmd -Yes` entry point exited 1 before configuration with `The term 'winget' is not recognized`. This establishes the missing-prerequisite failure, not a successful clean-machine installation. Windows Package Manager / App Installer is now explicit in the prerequisites. No authenticated Claude session or complete dependency-absent installation is claimed from this probe.

## Release documentation checks

The landing page was rendered at 1440, 820 and 390 pixels with no horizontal overflow or browser script errors. Keyboard Tab reached the visible skip link. New user-manual and architecture links are exposed from the landing page and README. The repository About description/homepage were corrected to the Code-tab/CLI scope. Historical changelog entries and earlier releases remain historical; their versions are not rewritten.
