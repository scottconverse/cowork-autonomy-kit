# v2.0.0 candidate test plan

Run each script using powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/<name>.ps1, under Windows PowerShell 5.1:

- Test-BlockAudit: configured provenance, hook uncertainty, policy activation unknowns, coverage errors and read-only behavior.
- Test-Reconcile: user/project defaults, switch matrix, nested preservation, missing projects and malformed-target preflight.
- Test-Recovery: exact backups, no-op repeats, restore modes, injected failures, concurrent edits and WhatIf.
- Test-SettingsMerge: AST-extracted real dedupe, hook upgrade, custom rules and SkipBypass.
- Test-UninstallBakFilter: real legacy strip, no timestamped-backup restore, WhatIf and no BOM.
- Test-Lifecycle: original files restored after two configuration runs; originally absent files removed; customized files kept; bad JSON unchanged; WhatIf.
- Test-AuditRegressions: actual child-process argument round trips, atomic result publication, empty queued arguments, helper-state/file/task checks, profile upgrades, nested settings rejection, Doctor counts, rollback recovery, custom helper roots and Setup failure reporting.
- Test-NoBOM: JSON BOM checks.
- Test-NoHardcodedPaths: all tracked text and forward-slash sample proof.
- Test-HelperInstall: installed invoker, error propagation, ACL construction/readback failure and queue arrivals during processing.

Parse every .ps1 with the Windows PowerShell parser. Run npm test and npm run build for site checks including current-version consistency and minimum text size.

Mutation proof: temporarily break the actual Merge-KitSettings notify dedupe condition, run Test-SettingsMerge and require failure, then restore the source byte-for-byte and rerun. Do not mutate a pasted test implementation.

Windows CI runs the ten regression tests and parsing on push and PR. It never runs full Setup, installs a helper, or runs Test-AutonomyKit. AST-extracted production configuration functions operate only in temp profiles; external task triggers and ACL system calls are mocked where needed. These tests do not establish installed ACLs or live administrator execution.

The optional Test-AutonomyKit capability harness performs machine-local probes and is not a CI test. Legacy watcher checks have been removed.

Current evidence and honest runtime limitations are in [IMPLEMENTATION-EVIDENCE.md](../docs/IMPLEMENTATION-EVIDENCE.md). No clean-machine run was performed. For this change, runtime verification uses an isolated user configuration and scratch project, without a mode flag that could hide failed inheritance. Record actual mode, create/read/delete results and permission prompt observation separately for CLI and Desktop Code. Do not use old runtime evidence to claim this candidate was exercised.
