# Cowork Autonomy Kit

**Version 1.5.1 · Windows** — see [CHANGELOG.md](CHANGELOG.md).

Private personal kit for configuring Claude Code (in Cowork mode) toward maximum practical
software-development autonomy on Windows machines, within Claude Code, operating-system, and
higher-priority instruction boundaries.

## Contents

- `Install.cmd` — **double-click entry point.** Forwards to `Setup-Autonomy.ps1` with
  `-ExecutionPolicy Bypass` and pauses at end so the console stays open.
- `Setup-Autonomy.ps1` — **one-command fresh-machine bootstrap.** Installs the toolchain
  (Python + `python3` shim, uv, scoop, Node, gh, ripgrep/jq/sqlite, Playwright + browsers),
  the Cowork config (CLAUDE.md, hooks, settings), the approve watcher, and triggers the
  elevated-dev-helper UAC install if not already present.
- `Doctor-Autonomy.ps1` — read-only status dashboard (toolchain, config, watcher, helper).
- `Uninstall-Autonomy.ps1` — reverses the config layer, restores `.bak` files, removes the
  watcher task. Leaves toolchain alone. `-RemoveHelper` to also drop the elevated helper task.
- `CLAUDE-Cowork-Core.md` — compact standing instructions for everyday speed (use as your
  live `~/.claude/CLAUDE.md`).
- `CLAUDE-Cowork-Autonomous-Software-Development.md` — the full / depth operating profile,
  pulled in for broad or high-blast-radius work.
- `settings.autonomy.example.json` — Claude Code permission profile (`bypassPermissions`,
  empty `ask`/`deny`).
- `elevated-dev-helper/` — bounded elevated-helper pattern for admin actions when Claude Code
  runs non-admin.
- `tests/` — `Test-AutonomyKit.ps1` (capability harness), `Test-NoHardcodedPaths.ps1`
  (portability regression guard), `Test-NoBOM.ps1` (UTF-8 BOM regression guard),
  `Test-UninstallBakFilter.ps1` (bak-filter regression guard),
  `Test-SettingsMerge.ps1` (merge-idempotency regression guard), and `TEST-PLAN.md`.
- `hooks/` — desktop-notification parity with Codex's `notify` hook.
- `computer-use-approve-watcher/` — background watcher that auto-clicks the computer-use /
  browser / webfetch `Approve` dialog; includes a `routine-approve.template.json` (schema
  not end-to-end verified) for headless runs. See [its README](computer-use-approve-watcher/README.md).

## Intended Use

Use the profile as the persistent Claude instruction baseline for personal development
machines. It authorizes Claude to inspect, edit, install, configure, build, test, debug,
retry, verify, and clean up ordinary development work within higher-priority rules and real
OS/app boundaries.

## Quick start (fresh machine)

From a clean Cowork/Windows box, clone the kit, then either:

**Double-click `Install.cmd`** at the repo root (easiest). Or, equivalently, from a terminal:

```powershell
git clone https://github.com/scottconverse/cowork-autonomy-kit.git
cd cowork-autonomy-kit
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-Autonomy.ps1
# then RESTART Cowork so PATH, CLAUDE.md, and hooks load
```

Both paths trigger **one** Windows UAC prompt during setup — for the
elevated-dev-helper install in step 8. Click Yes once. Everything else is
user-scope, no admin. Pass `-SkipHelper` (terminal) or `Install.cmd -SkipHelper`
to skip the helper install entirely.

> **First-run SmartScreen note.** If you downloaded the kit as a ZIP rather than
> `git clone`, Windows tags the files with Mark-of-the-Web. Double-clicking
> `Install.cmd` may show "Windows protected your PC" — click **More info**, then
> **Run anyway**. One-time per ZIP. `git clone`'d files don't carry MOTW.

That installs the full toolchain and config below, idempotently, with **no admin**. The one
admin step (the elevated dev helper) stays optional and prints its own UAC installer at the
end. It exists because a clean box has **no real Python** (only the Store stub), **no
`python3`**, **no Node**, and **no user-scope package manager** — every gotcha this kit hit
on a real fresh install is encoded in the script's ordering.

### The no-admin install doctrine (Windows)

Windows autonomy is mostly a package-manager problem. Preference order, highest-autonomy
first:

| Channel | Admin? | Use for |
|---|---|---|
| `scoop install <x>` | no | CLI tools (gh, ripgrep, jq, sqlite, go, rust, dotnet-sdk, semgrep…) — the default |
| `uv tool install <x>` / `uv pip` | no | Python tools and envs (ruff, etc.) |
| `pip install <x>` | no | Python libraries (Playwright, …) |
| `npm i -g <x>` / `npx <x>` | no | Node tooling |
| `winget install <x> --scope user` | no | user-scope apps (Python, …) |
| portable zip → user dir + PATH | no | anything with no installer (Node was done this way) |
| elevated helper → `msiexec /i … /qn` | **yes (one UAC)** | true machine installs |

Note: `winget` works both *directly* and **through the elevated helper** (machine-scope, no
UAC) once the helper's process-runner is fixed (it is, in this kit). User-scope channels are
still preferred *first* — less friction, reversible, no system change — which is why scoop is
the keystone. Admin is available and reliable; it's just not the default.

## How To Apply (manual / detail)

> The Quick Start above (`Setup-Autonomy.ps1`) does everything below automatically and
> idempotently. This section explains the same flow step-by-step for anyone who wants to
> apply the kit by hand, or to understand exactly what Setup did.

1. **Back up first.** Copy your existing `~/.claude/CLAUDE.md` and `~/.claude/settings.json`
   to timestamped `.bak` files before changing them.
2. **Instructions (two-tier):** put `CLAUDE-Cowork-Core.md` into `~/.claude/CLAUDE.md` for
   everyday speed. Its depth rule points Claude to the full
   `CLAUDE-Cowork-Autonomous-Software-Development.md` for high-blast-radius work — keep that
   file in the kit (or alongside CLAUDE.md) so it can be loaded on demand.
3. **Permissions/autonomy:** `Setup-Autonomy.ps1` writes only `defaultMode: bypassPermissions`
   (plus empty `ask`/`deny` if they're absent) and the notify Stop hook. It does **not** set
   `additionalDirectories`, `allow`, or `enableAllProjectMcpServers`. Those live in
   `settings.autonomy.example.json` for **optional manual** merge — it shows the full profile.
   If you merge the example, Setup auto-substitutes `YOUR_USERNAME` → `%USERNAME%` on the next
   run, so the placeholder no longer needs hand-editing. On a box that already has `ask`/`deny`
   entries the installer **preserves** them.
4. **Staging vs live (re-running Setup safely):** the kit refreshes a *staging* copy of its
   reference files under `~/.claude/autonomy-kit/` on every run. The *live* files —
   `CLAUDE.md`, the depth profile, the notify hook script — are written **only on first
   install**. If they already exist they are backed up and **left unchanged**, so a re-run
   never clobbers customizations. Diff your live files against the staged copies (or run
   `Doctor-Autonomy.ps1`) when you want to pull in kit updates.
5. **Elevated helper:** `Setup-Autonomy.ps1` step 8 triggers the helper's UAC installer
   automatically when `ClaudeElevatedDevHelper` is absent. `-SkipHelper` to opt out. Manual
   path remains in `elevated-dev-helper/README.md`.
   Existing installations must run the helper installer directly to refresh its worker and
   invoker, then merge the new job-queue guidance into the live `~/.claude/CLAUDE.md`.
   Installation succeeds only after administrator and Windows-path self-tests pass.
6. **Notifications (optional):** Setup wires the `notify-turn-ended.ps1` Stop hook into
   `settings.json`. To replace it with your own, edit the live file at
   `~/.claude/hooks/notify-turn-ended.ps1`.

## Operating Model: requested vs. unrequested

The profile's governing line, mirrored from the Codex setup it was ported from:

- **Anything you explicitly request is done in the same turn**, to the maximum the OS and
  tool permissions allow — including destructive, privileged, or irreversible actions. No
  unrequested confirmations, no silent narrowing of your instructions.
- **Only *unrequested*, model-initiated** destructive / credential-sensitive / privileged /
  hard-to-reverse actions get a confirmation pause. That pause never applies to your
  requests.

## Origin

Lineage: this kit started as a port of a private Codex Desktop autonomy kit and has
since diverged into a standalone Cowork tool. The two-tier instruction design (compact
core + depth profile), the backup-before-install discipline, and the
requested-vs-unrequested operating line came from that original; everything else
(approve watcher, BOM-safe settings merge, staging-vs-live policy, Doctor/Uninstall,
the elevated-dev-helper queue pattern as applied here) is kit-native.

## Computer-use authorization

Two permission systems:

1. **Claude Code tool permissions** (Bash, PowerShell, file edits) — governed by
   `bypassPermissions`. Handled by the kit; never prompts.
2. **Computer-use** (`mcp__computer-use__*`: screenshots, clicking, native apps) — separate
   `request_access` dialog, per-session, app-enforced, not affected by `bypassPermissions`.

Handled by [`computer-use-approve-watcher/`](computer-use-approve-watcher/README.md), which
`Setup-Autonomy.ps1` installs and starts. The watcher polls UI Automation and clicks
`Approve` automatically — the same button serves the `computer:`, `browser:`, and
`webfetch:` permission-broker dialogs. Stop with `Uninstall-Autonomy.ps1` or
`Stop-ScheduledTask -TaskName ClaudeApproveWatcher`. Headless alternative (schema not
end-to-end verified): [`routine-approve.template.json`](computer-use-approve-watcher/routine-approve.template.json).

### Reference: how the gate behaves (verified against Claude `1.14271.0.0`, claude-code `2.1.181`)

- `request_access` enters the desktop app's permission broker as the pseudo-tool
  `computer:request_access`. The `computer:` / `browser:` / `webfetch:` family is special-cased
  to always open an interactive dialog, in a branch that returns before `bypassPermissions` /
  allow-rules / cached decisions are consulted.
- Promotion to a standing "always allow" rule is stripped — the app logs `always-allow suppressed`.
- Grants live on the **session** (`cuAllowedApps`), start empty each session, expire ~30 min.
  No on-disk allow-list (verified across Local Storage, IndexedDB, and `%APPDATA%\Claude`).

If you want to handle the gate manually instead of with the watcher: on first desktop need in
a session, call `request_access` once with the full app set you'll touch (e.g. `Claude`,
`Google Chrome`, `File Explorer`, plus the task app) — one approval covers the set; re-request
after ~30 min or on a "not in allowlist" error. For unattended runs, a scheduled task / routine
can carry `computer:request_access` in its `approvedPermissions` (per-task, not machine-wide).
Bash/PowerShell and the Chrome MCP don't carry the prompt.

## Safety Notes

- Keep this repo private.
- Review scripts before installing on a new machine.
- Do not commit credentials, tokens, helper queue jobs/logs, or machine-specific generated
  state (the `.gitignore` excludes `installed-config/`, `*.bak`, `config.toml`, and runtime
  state).
- Explicit requests for destructive/privileged/hard-to-reverse actions are carried out to the
  maximum extent the active permissions and OS allow. Only *unrequested* such actions get a
  confirmation pause. Higher-priority Claude Code, OS, legal, and safety rules still apply.
