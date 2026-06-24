# Claude Cowork Autonomy Kit

**Version 1.2.2 · Windows · ported from the Codex Desktop Autonomy Kit** — see
[CHANGELOG.md](CHANGELOG.md).

Private personal kit for configuring Claude Code (in Cowork mode) toward maximum practical
software-development autonomy on Windows machines, within Claude Code, operating-system, and
higher-priority instruction boundaries.

## Contents

- `Setup-Autonomy.ps1` — **one-command fresh-machine bootstrap.** Installs the whole
  toolchain (Python + `python3` shim, uv, scoop, Node, gh, ripgrep/jq/sqlite, Playwright +
  browsers) and the Cowork config (CLAUDE.md, hooks, settings), all user-scope / no-admin.
- `CLAUDE-Cowork-Core.md` — compact standing instructions for everyday speed (use as your
  live `~/.claude/CLAUDE.md`).
- `CLAUDE-Cowork-Autonomous-Software-Development.md` — the full / depth operating profile,
  pulled in for broad or high-blast-radius work.
- `settings.autonomy.example.json` — Claude Code permission profile (`bypassPermissions`,
  empty `ask`/`deny`). This is where autonomy actually happens.
- `elevated-dev-helper/` — bounded elevated-helper pattern for admin actions when Claude Code
  runs non-admin (Claude has no elevated sandbox, so this is the primary admin path).
- `tests/` — `Test-AutonomyKit.ps1` capability harness + `TEST-PLAN.md` (two-pole plan).
- `hooks/` — optional desktop-notification parity with Codex's `notify` hook.

## Intended Use

Use the profile as the persistent Claude instruction baseline for personal development
machines. It authorizes Claude to inspect, edit, install, configure, build, test, debug,
retry, verify, and clean up ordinary development work within higher-priority rules and real
OS/app boundaries.

## Quick start (fresh machine)

From a clean Cowork/Windows box, clone the kit and run the bootstrap (non-admin):

```powershell
git clone https://github.com/scottconverse/claude-cowork-autonomy-kit.git
cd claude-cowork-autonomy-kit
powershell -NoProfile -ExecutionPolicy Bypass -File .\Setup-Autonomy.ps1
# then RESTART Cowork so PATH, CLAUDE.md, and hooks load
```

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

1. **Back up first.** Copy your existing `~/.claude/CLAUDE.md` and `~/.claude/settings.json`
   to timestamped `.bak` files before changing them.
2. **Instructions (two-tier):** put `CLAUDE-Cowork-Core.md` into `~/.claude/CLAUDE.md` for
   everyday speed. Its depth rule points Claude to the full
   `CLAUDE-Cowork-Autonomous-Software-Development.md` for high-blast-radius work — keep that
   file in the kit (or alongside CLAUDE.md) so it can be loaded on demand.
3. **Permissions/autonomy:** `Setup-Autonomy.ps1` writes only `defaultMode: bypassPermissions`
   (plus empty `ask`/`deny` if they're absent) and the notify Stop hook. It does **not** set
   `additionalDirectories`, `allow`, or `enableAllProjectMcpServers`. Those live in
   `settings.autonomy.example.json` for **optional manual** merge — it shows the full profile, but
   its `additionalDirectories` ships a `YOUR_USERNAME` **placeholder you must edit** (replace with
   your account name, or remove the entry); pasted verbatim it's a no-op, not a real grant. Note:
   on a box that already has `ask`/`deny` entries the installer **preserves** them (it doesn't
   force them empty). If you want to gate or block a specific command, add it to `ask`/`deny` yourself.
4. **Elevated helper (optional):** see `elevated-dev-helper/README.md` for the one-time
   UAC-approved install.
5. **Notifications (optional):** wire `hooks/hooks.example.json` into settings to get a
   desktop toast when a turn ends.

## Operating Model: requested vs. unrequested

The profile's governing line, mirrored from the Codex setup it was ported from:

- **Anything you explicitly request is done in the same turn**, to the maximum the OS and
  tool permissions allow — including destructive, privileged, or irreversible actions. No
  unrequested confirmations, no silent narrowing of your instructions.
- **Only *unrequested*, model-initiated** destructive / credential-sensitive / privileged /
  hard-to-reverse actions get a confirmation pause. That pause never applies to your
  requests.

## What Changed From The Codex Version

| Codex | Claude Cowork |
|---|---|
| Codex Desktop (surface) | Claude Code in Cowork mode |
| `config.toml` `developer_instructions` | `~/.claude/CLAUDE.md` (compact core + full profile) |
| `approval_policy="never"` + `:danger-full-access` | `defaultMode: "bypassPermissions"` |
| `[windows] sandbox="elevated"` | *no analog* — runs as your user; elevated helper covers admin |
| `notify ... turn-ended` | optional Stop hook (`hooks/`) |
| Codex plugins / skills | Claude skills + subagents + MCP servers |
| `CodexElevatedDevHelper` / `C:\dev\CodexElevatedHelper` / `.codex` root | `ClaudeElevatedDevHelper` / `C:\dev\ClaudeElevatedHelper` / `.claude` root |

The hybrid two-tier instruction design (compact core + depth rule), the backup-before-install
step, and the requested-vs-unrequested operating line are all adopted from the installed
Codex hybrid configuration.

## Computer-use authorization (why it still prompts)

There are **two** permission systems, and this kit only governs one:

1. **Claude Code tool permissions** (Bash, PowerShell, file edits) — governed by
   `bypassPermissions`. These never prompt. ✔ handled by the kit.
2. **Computer-use** (`mcp__computer-use__*`: screenshots, clicking, controlling native apps) —
   governed by its **own** `request_access` dialog, **one per session**. ✘ **not** governed by
   `bypassPermissions`, and **cannot** be made standing by any local config.

This was investigated directly against the desktop app (Claude `1.14271.0.0`, claude-code
`2.1.181`) — see the full writeup with code citations: *computer-use-standing-consent findings*.
Summary of why it is unfixable from config:

- `request_access` enters the desktop app's permission broker as the pseudo-tool
  `computer:request_access`. That tool family (`computer:` / `browser:` / `webfetch:`) is
  **special-cased to always open an interactive dialog**, in a branch that returns **before** any
  `bypassPermissions` / allow-rule / cached-decision is consulted.
- Promotion to a standing "always allow" rule is **explicitly stripped** — the code logs
  `always-allow suppressed` for exactly these tools.
- Grants live only on the **session** (`cuAllowedApps`), start empty on every new session, and
  even **expire after 30 min** within a long session. There is **no global allow-list store** on
  disk to pre-seed (verified across Local Storage, IndexedDB, and all `%APPDATA%\Claude` config).
- This is an intentional human-in-the-loop boundary for the three tool families that act on the
  world outside the sandbox (native apps, the live browser, arbitrary URLs). The kit does **not**
  attempt to defeat it.

**Lowest-friction workflow:** on first desktop need in a session, call `request_access` **once**
with the *full* app set you'll touch (e.g. `Claude`, `Google Chrome`, `File Explorer`, + the task
app) and the clipboard/system-key flags you need — one approval covers the set; re-request after
~30 min or on an "not in allowlist" error. For unattended runs, a **scheduled task / routine** can
carry pre-approved `computer:request_access` in its `approvedPermissions` (the only standing path
the app exposes — per-task, not machine-wide). Prefer Bash/PowerShell and the Chrome MCP where they
suffice; neither carries the computer-use prompt.

`Setup-Autonomy.ps1` prints this same note during the config step so it isn't rediscovered the
hard way.

## Safety Notes

- Keep this repo private.
- Review scripts before installing on a new machine.
- Do not commit credentials, tokens, helper queue jobs/logs, or machine-specific generated
  state (the `.gitignore` excludes `installed-config/`, `*.bak`, `config.toml`, and runtime
  state).
- Explicit requests for destructive/privileged/hard-to-reverse actions are carried out to the
  maximum extent the active permissions and OS allow. Only *unrequested* such actions get a
  confirmation pause. Higher-priority Claude Code, OS, legal, and safety rules still apply.
