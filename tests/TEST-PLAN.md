# v1.6.0 test plan

Run each script using powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/<name>.ps1, under Windows PowerShell 5.1:

- Test-SettingsMerge: AST-extracted real dedupe, hook upgrade, custom rules and SkipBypass.
- Test-UninstallBakFilter: real legacy strip, no timestamped-backup restore, WhatIf and no BOM.
- Test-Lifecycle: original files restored after two configuration runs; originally absent files removed; customized files kept; bad JSON unchanged; WhatIf.
- Test-NoBOM: JSON BOM checks.
- Test-NoHardcodedPaths: all tracked text and forward-slash sample proof.
- Test-HelperInstall: installed invoker, error propagation, ACL construction/readback failure and queue arrivals during processing.

Parse every .ps1 with the Windows PowerShell parser. Run npm test and npm run build for site checks including current-version consistency and minimum text size.

Mutation proof: temporarily break the actual Merge-KitSettings notify dedupe condition, run Test-SettingsMerge and require failure, then restore the source byte-for-byte and rerun. Do not mutate a pasted test implementation.

Windows CI runs the six regression tests and parsing on push and PR. It never runs full Setup, installs a helper, or runs Test-AutonomyKit. AST-extracted production configuration functions operate only in temp profiles; external task triggers and ACL system calls are mocked where needed. These tests do not establish installed ACLs or live administrator execution.

The optional Test-AutonomyKit capability harness performs machine-local probes and is not a CI test. Legacy watcher checks have been removed.

No clean-machine run and no live desktop-app test are performed by the coder. After release Scott runs Uninstall, Install.cmd, approves UAC, enables the Code tab bypass toggle, fully quits Claude from its tray, reopens, checks per-folder mode, tests file create/delete and helper CheckAdmin, and sends Doctor output.
