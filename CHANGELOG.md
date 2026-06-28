# Changelog

All notable changes to the Claude Cowork Autonomy Kit. Dates are UTC.

## v1.4.0 — 2026-06-28

Cleared every finding from the v1.3.3 GauntletGate lite audit.

### Fixed (Major)
- `Setup-Autonomy.ps1` now writes `settings.json` UTF-8 **without BOM** via
  `[System.IO.File]::WriteAllText` + `UTF8Encoding($false)`. The previous
  `Set-Content -Encoding UTF8` prepended a BOM (PS 5.1 behavior) that breaks
  naive JSON consumers (python `json.loads`, many CI tools). Same fix applied
  to the JSON report `tests/Test-AutonomyKit.ps1` writes.
- `routine-approve.example.json` renamed to `routine-approve.template.json`
  with an honest header: the schema (`name`/`schedule`/`prompt`/`approvedPermissions`)
  was authored from documentation patterns but **not end-to-end verified** against
  an actual successful routine execution. Users must validate before relying on it.

### Added
- `tests/Test-NoBOM.ps1` — portability guard that scans all kit `.json` files and
  the live `~/.claude/settings.json` for UTF-8 BOM (`EF BB BF`); exit 1 on
  regression. Protects the BOM-free fix above.
- `.gitattributes` — `*.ps1`/`*.cmd` → CRLF, `*.md`/`*.json`/`*.toml`/`*.yml` →
  LF, common binaries marked. Stops the per-commit CRLF noise.

### Changed
- `Setup-Autonomy.ps1` step 5 no longer auto-upgrades Playwright on every re-run.
  It checks `pip show playwright` first and only `pip install`s on absence.
- `Setup-Autonomy.ps1` NEXT block now prints the absolute path to `Doctor-Autonomy.ps1`
  instead of `.\Doctor-Autonomy.ps1` (worked from the kit dir, confused from elsewhere).
- `Doctor-Autonomy.ps1` reports user-customized live files as
  `present, customized (...; staged copy: ...b) -- diff if you want to compare`
  instead of the alarming `DIFFERS from staged -- merge if you want kit updates`.
  Customizing a live file is the intended re-run-safe behavior, not a problem.
- `tests/Test-AutonomyKit.ps1` checks 12-13 (approve-watcher task + process) now
  return `INFO` when the watcher isn't installed yet, only `FAIL` if the task is
  registered but the process isn't running. The harness is intended to run pre-
  AND post-Setup; pre-Setup absence is "not installed yet," not a regression.
- `computer-use-approve-watcher/Install-ApproveWatcherTask.ps1` now uses
  `[CmdletBinding(SupportsShouldProcess)]` and wraps `Register-ScheduledTask` /
  `Unregister-ScheduledTask` in `ShouldProcess` checks. Consistent with the other
  kit scripts; supports `-WhatIf`.
- README "How To Apply" section opens with a callout pointing back to
  Quick Start (Setup-Autonomy.ps1 does this all automatically and idempotently).
- README + component README updated for the template rename and the schema-not-verified
  caveat.

### Notes
- `computer-use-approve-watcher/Watch-ComputerUseApprove.ps1` keeps the 500ms UIA
  tree-walk poll for now. Added a `ponytail:` comment naming the upgrade path
  (UIA `AddAutomationEventHandler` -- event-driven, no polling) so the deferred
  optimization is tracked, not lost. Idle cost is negligible; upgrade when CPU
  measurably matters.

## v1.3.3 — 2026-06-28

### Fixed (Uninstall greediness — restored unrelated backups)
- `Uninstall-Autonomy.ps1`'s `Restore-LatestBak` previously matched any
  `<name>.bak-*` file alongside the live file and restored the most recent. This
  greedily picked up backups created by other tools (e.g. `settings.json.bak-pre-ponytail`
  from a ponytail-plugin install), rolling settings further back than the kit ever
  wrote and silently dropping unrelated hook entries.
- Restore now requires the kit's own format: `<name>.bak-YYYYMMDD-HHmmss` (the
  format Setup's `Install-LiveOrLeave` writes). Non-kit backups in the same
  directory are listed in output so the user knows they exist but were skipped.

## v1.3.2 — 2026-06-28

### Fixed (Windows PowerShell 5.1 encoding + alias bugs surfaced by a real install)
- Replaced em-dashes (—) and en-dashes (–) with ASCII (`--`, `-`) in all .ps1 files.
  Without a BOM, PS 5.1 decodes the script body as the system codepage; the em-dash bytes
  become invalid sequence, producing "string is missing the terminator" parser errors that
  prevent the whole script from running. The most visible victim was
  `Install-ApproveWatcherTask.ps1`, which silently failed at parse time on first install —
  Setup then printed a false "installed + started" message and tried to `Start-ScheduledTask`
  on a task that was never registered.
- Renamed Doctor's `H` helper function to `Hdr`. `H` is PS 5.1's built-in alias for
  `Get-History`, and aliases take precedence over functions during command resolution, so
  every `H "Header"` call was being parsed as `Get-History -Id "Header"` and throwing
  `Cannot bind parameter 'Id'`.
- `Setup-Autonomy.ps1` step 7 now verifies the watcher task is actually registered before
  claiming success, and prints an actionable warning if not. No more silent "installed +
  started" lies when the installer crashed.

## v1.3.1 — 2026-06-28

### Changed (back-port: config-merge restraint from codex-desktop-autonomy-kit)
- `Setup-Autonomy.ps1` no longer overwrites existing live files. The kit now stages its
  reference copies under `~/.claude/autonomy-kit/` (always refreshed) and writes the live
  `~/.claude/CLAUDE.md`, `CLAUDE-Cowork-Autonomous-Software-Development.md`, and
  `hooks/notify-turn-ended.ps1` **only on first install**. If a live file exists, Setup
  backs it up and leaves the user's copy in place. Re-running Setup is safe.
- `Doctor-Autonomy.ps1` reports `staging dir` and per-file `present, matches staged` vs
  `present, DIFFERS from staged` so divergence is visible without manual diffing.
- `Uninstall-Autonomy.ps1` keeps customized live files: it removes a live file only if it
  matches the staged copy (else logs `kept ... (user-customized)`). Also removes the
  `autonomy-kit` staging dir.
- README adds an "Staging vs live (re-running Setup safely)" step and updates the
  `YOUR_USERNAME` note (auto-substituted, no longer hand-edit).

## v1.3.0 — 2026-06-28

### Added
- `computer-use-approve-watcher/` — background watcher that auto-clicks the computer-use /
  browser / webfetch `Approve` dialog via Windows UI Automation.
  - `Watch-ComputerUseApprove.ps1` — UIA polling watcher, tunable label/process/poll/debounce.
  - `Install-ApproveWatcherTask.ps1` — registers a user-scope logon scheduled task
    (`ClaudeApproveWatcher`, no admin); supports `-Uninstall`.
  - `routine-approve.example.json` — Claude Code routine template for headless runs that
    pre-grants `computer:` / `browser:` / `webfetch:` via `approvedPermissions`.
- `Setup-Autonomy.ps1`:
  - Step 7 installs and starts the watcher (default-on, no flag).
  - Step 8 triggers the elevated-dev-helper UAC installer if `ClaudeElevatedDevHelper` is
    not already registered. `-SkipHelper` opts out.
  - Auto-substitutes `YOUR_USERNAME` in `additionalDirectories` with `$env:USERNAME` on
    settings merge.
- `Doctor-Autonomy.ps1` — read-only status dashboard: toolchain presence, CLAUDE.md +
  settings state, watcher task + process status, helper task status. Flags unresolved
  `YOUR_USERNAME` placeholders.
- `Uninstall-Autonomy.ps1` — reverses the config layer: removes `ClaudeApproveWatcher`,
  restores most recent `settings.json.bak` / `CLAUDE.md.bak` (or strips kit-added entries
  if no backup), removes depth profile + notify hook. `-RemoveHelper` to also drop the
  elevated helper task. Toolchain untouched. Supports `-WhatIf`.
- `tests/Test-AutonomyKit.ps1` — three new checks: `approve_watcher_task` (registered +
  Ready/Running), `approve_watcher_process` (PS process alive running the watcher script),
  `uiautomation_assemblies` (UIA assemblies load).
- `CLAUDE-Cowork-Core.md` — one-paragraph note that `ClaudeApproveWatcher` auto-handles the
  permission-broker dialogs, so future sessions don't re-explain or editorialize about them.

### Changed
- Rewrote the README "Computer-use authorization" section: leads with "handled by the
  watcher", app-behavior facts kept as a reference subsection for anyone disabling it.
- Removed all "trade-off" / "opt-in escape hatch" / "single-user only" prescriptive framing
  from component and main READMEs. The kit is for personal machines; it doesn't
  editorialize about the owner's choices.
- `Setup-Autonomy.ps1`: removed the yellow "computer-use still prompts" console block (no
  longer true with the watcher running); replaced the "double-click the .cmd" NEXT step
  with `Doctor-Autonomy.ps1` and tool-install hints.

## v1.2.2 — 2026-06-24

### Fixed (docs — name the real root cause of non-elevation)
- The elevated-helper docs previously implied Claude Code merely "runs as a normal process
  and cannot launch its shell with an admin token," which read like a one-time-setup gap that
  the right configuration could close. It cannot. Clarified the actual, hard constraint:
  - `elevated-dev-helper/README.md`: added a **"Why inline elevation is impossible"** section.
    Under the Cowork host the Claude desktop app is a **packaged MSIX app**
    (`C:\Program Files\WindowsApps\Claude_…`, verifiable via `Get-AppxPackage -Name *Claude*`),
    and Windows **never** runs packaged apps elevated — no "Run as administrator", no
    scheduled-task launcher, no registry switch; disabling UAC (`EnableLUA=0`) breaks packaged
    apps outright. So no skill/prompt/profile can elevate the inline shell, and the helper is
    the **only** admin bridge (the lone exception being the non-packaged Claude Code CLI run
    elevated — the terminal, not Cowork).
  - `elevated-dev-helper/CLAUDE-Elevated-Helper-Addendum.md`: same clarification in *Purpose*;
    explicit instruction never to advise "relaunch elevated" for a packaged-app host.
- No behavior change; the helper was already correct. This release makes the docs honest about
  *why* it is necessary rather than optional.

## v1.2.1 — 2026-06-21

### Fixed (portability — no hardcoded paths)
- Removed machine-specific hardcoded paths from shipped files so the kit installs and runs on
  any machine:
  - `elevated-dev-helper/ClaudeElevatedDevHelper.ps1`: trusted roots now resolve the running
    user's profile via `$env:USERPROFILE` instead of assuming `C:\Users\<name>`.
  - `hooks/hooks.example.json`: the notify Stop-hook command now resolves the home directory at
    runtime via `$env:USERPROFILE` (was a hardcoded `C:\Users\Scott\...` path).
  - `settings.autonomy.example.json`: `additionalDirectories` no longer ships a real user path;
    it uses a clearly-marked `YOUR_USERNAME` placeholder with edit instructions.
- The installer (`Setup-Autonomy.ps1`) was already path-portable (derives everything from
  `$env:USERPROFILE`); this release brings the examples/helper in line.

### Fixed (GauntletGate full-lane findings, pre-push)
- **`hooks/hooks.example.json` notify command was broken.** The first portability attempt used
  `-Command "& '$env:USERPROFILE\...'"` — single quotes mean `$env:USERPROFILE` never expands, so
  the hook errored every turn. Replaced with a clearly-marked `<YOUR-HOME>` placeholder in the
  proven `-File "<abs>"` form (the installer still wires the real absolute path automatically).
- **Added `tests/Test-NoHardcodedPaths.ps1`** — a portability regression guard that fails if any
  shipped file reintroduces a literal `C:\Users\<account>` path (matches both `.ps1` single- and
  JSON double-backslash forms; placeholders + CHANGELOG history exempt). Closes the gap where the
  release's headline property had no test.
- **README step 3 corrected** to state what the installer actually writes (only
  `bypassPermissions` + the Stop hook; it preserves existing `ask`/`deny`) vs. the
  optional manual example, and that `additionalDirectories` ships an edit-me placeholder.
- **`Setup-Autonomy.ps1` now backs up an existing `~/.claude/CLAUDE.md`** before overwriting it
  (it already backed up `settings.json`; CLAUDE.md was being clobbered with no backup).
- **Elevated-helper addendum: honest blast-radius.** Documented that the user-writable trusted
  roots make `RunTrustedPowerShellScript` a no-UAC local-admin path for any code at the user's
  integrity level — it is an accepted single-owner trade-off, not a sandbox.

## v1.2.0 — 2026-06-21

### Docs / investigation
- **Computer-use standing-consent finding (HONEST NEGATIVE).** Investigated whether the
  per-session `request_access` computer-use prompt can be made standing like `bypassPermissions`.
  It **cannot** from any local config — verified against the desktop app bundle (Claude
  `1.14271.0.0`, claude-code `2.1.181`). The `computer:` / `browser:` / `webfetch:` tool families
  are special-cased in the permission broker to **always** open an interactive dialog (in a branch
  that returns before any bypass/allow-rule check), standing-rule promotion is **explicitly
  stripped** (`always-allow suppressed`), grants are session-scoped (`cuAllowedApps`, start empty,
  30-min TTL), and there is **no on-disk allow-list to pre-seed** (checked Local Storage,
  IndexedDB, Session Storage, and all `%APPDATA%\Claude` config). This is an intentional
  human-in-the-loop boundary; the kit does not attempt to defeat it.
- README: new **"Computer-use authorization (why it still prompts)"** section documenting the gate
  and the lowest-friction workflow (batch one `request_access` for the full app set; scheduled
  tasks as the only per-task standing path).
- `Setup-Autonomy.ps1`: config step now prints the computer-use note so it isn't rediscovered.
- `CLAUDE-Cowork-Autonomous-Software-Development.md` (depth profile): added a one-line caveat in
  the browser/computer-use section that the per-session `request_access` gate is app-enforced and
  not covered by `bypassPermissions`, with the batch-one-request guidance.

## v1.1.2 — 2026-06-20

### Docs
- Added this changelog and a version stamp in the README.
- Documented the elevated helper's **full admin capability** via
  `RunTrustedPowerShellScript` in the helper addendum (machine installs, `HKLM`, services,
  firewall — no per-action UAC), and added an elevated-helper verification lane (Part 4) to
  the test plan.

## v1.1.1 — 2026-06-20

### Fixed
- **Elevated helper process runner (the real fix).** Replaced the `Start-Process`→temp-file
  approach — which hung when a grandchild (`winget` → `msiexec`) inherited the redirected
  handles and kept them open after the parent exited — with `ProcessStartInfo` +
  `ReadToEndAsync` (concurrent pipe drain) + a bounded wait on the readers. Both
  `RunTrustedPowerShellScript` (arbitrary elevated PowerShell) and `WingetInstall`
  (machine-scope) now complete cleanly with **no UAC**. Verified on a real machine: `HKLM` /
  `C:\Program Files` / firewall writes and machine-scope installs (7-Zip, fd) all via the
  helper.
- Corrected docs that wrongly blamed `winget` for a "non-interactive task" limitation — it
  was the handle-inheritance bug above, not winget.

## v1.1.0 — 2026-06-20

### Added
- **`Setup-Autonomy.ps1`** — one-command, idempotent, no-admin fresh-machine bootstrap
  (real Python + `python3` shim, uv, scoop, Node, gh, ripgrep/jq/sqlite, Playwright +
  browsers, and the Cowork config: CLAUDE.md, depth profile, notify hook, `bypassPermissions`
  settings merge).
- **No-admin install doctrine** in the README and the profile's Installation Protocol: prefer
  `scoop` / `uv` / `pip` / `npm` / `winget --scope user` / portable zip; use admin (the
  elevated helper) only for true machine installs.

### Fixed
- First round of elevated-helper bugs: `ProcessStartInfo.ArgumentList` (absent in Windows
  PowerShell 5.1) and a stdout/stderr pipe-read deadlock. (Superseded by the v1.1.1 runner
  rewrite, which fixes the remaining hang.)

## v1.0.0 — 2026-06-20

### Added
- Initial port from the Codex Desktop Autonomy Kit: two-tier instruction profile (compact
  `CLAUDE-Cowork-Core.md` + full depth profile), `bypassPermissions` settings with empty
  `ask`/`deny`, bounded elevated dev helper, capability + two-pole behavioral test plan, and
  an optional turn-ended notification hook.
