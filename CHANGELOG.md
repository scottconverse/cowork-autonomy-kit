# Changelog

All notable changes to the Claude Cowork Autonomy Kit. Dates are UTC.

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
