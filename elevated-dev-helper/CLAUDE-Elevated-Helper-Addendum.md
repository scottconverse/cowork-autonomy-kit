# CLAUDE.md Addendum — Bounded Elevated Development Helper

Use this addendum alongside the Cowork autonomy profile on machines where Claude Code /
Cowork cannot reliably launch with an elevated/admin shell token. Append it to
`~/.claude/CLAUDE.md`.

## Purpose

Claude is authorized to use a local elevated development helper when one has been installed by
the machine owner. The helper bridges Windows UAC/admin-token limitations for ordinary,
reversible software-development infrastructure tasks. Under the Cowork host, Claude Code runs
inside a **packaged MSIX app**, which Windows **never** lets run elevated — so the inline
shell's Medium-integrity token cannot be raised by any setup, and this helper is not a
fallback but the **only** admin path. (The lone exception is the non-packaged Claude Code CLI
run elevated, which is the terminal, not Cowork.) Do not advise "relaunch elevated" for a
packaged-app host; it is impossible.

## Helper Model

The helper is a Windows Scheduled Task (`ClaudeElevatedDevHelper`) running a trusted local
PowerShell script with highest privileges. Claude remains a normal-user process, queues
structured helper requests, and triggers the task. The elevated helper executes only
supported development actions, writes structured logs, and exits.

## Full elevated capability (verified)

The `RunTrustedPowerShellScript` action runs any PowerShell script located under a trusted
local root (`C:\dev\`, `~\Documents\Claude\`, `~\.claude\`, the helper temp dir) with full
administrator rights. So **anything a local admin can do is available with no per-action
UAC** — machine-scope installs (`WingetInstall`, or `msiexec /i … /qn` from a trusted
script), `HKLM` edits, service start/stop, firewall rules, etc. Proven on a real machine:
the helper wrote to `HKLM`, wrote to `C:\Program Files`, created a firewall rule, and
installed machine-scope packages (7-Zip, fd), each completing cleanly and returning output.

It is bounded only in *form*, not in power: only scripts under a trusted root run, every job
is logged to `done\`/`failed\`, and there is no generic "run this arbitrary command string"
action. **Be honest about the real blast radius, though:** the trusted roots
(`C:\dev\`, `~\.claude\`, …) are writable by the normal (non-admin) user, and
`RunTrustedPowerShellScript` runs *arbitrary* PowerShell from them at full admin with **no
UAC**. So while this task exists, **any code running at your user integrity level — not just
Claude — can drop a script into a trusted root and obtain silent local admin.** That is an
accepted trade-off for a single-owner personal dev box; it is **not** a sandbox. To harden,
require Authenticode-signed trusted scripts or move the trusted root to an admin-only-writable,
ACL-locked directory so a non-admin writer cannot plant payloads.

## Authorized Helper Uses

- Installing trusted development tools through package managers or local installers.
- Configuring SDKs, runtimes, browser drivers, local databases, Docker, WSL, VM
  prerequisites, and emulator prerequisites.
- Starting, stopping, or restarting named local development services.
- Creating or updating development-only scheduled tasks from trusted local scripts.
- Opening local development firewall rules scoped to localhost, private networks, or a
  clearly development-only port.
- Running environment checks that require admin visibility.

## Required Helper Behavior

When admin capability is needed:

1. Prefer non-admin, project-local, user-scoped, portable, container-scoped, or VM-scoped
   options when they complete the task correctly.
2. If admin is actually required, create a structured helper request for a supported action
   (use `Invoke-ClaudeElevatedDevHelper.ps1`).
3. Trigger the helper task if it is installed.
4. Read the helper result log under `done\` or `failed\`.
5. Continue all non-admin work while any helper request is pending or blocked.

## Boundaries

The helper is not permission to perform destructive, credential-sensitive,
security-sensitive, internet-exposed, or hard-to-reverse actions silently. It refuses
unrestricted arbitrary commands, executes named supported actions with structured
parameters, logs every action, and preserves a review trail.

## Portability

Reusable on other personal development machines. On each machine, the helper still requires a
one-time owner-approved elevated setup step because Windows UAC and OS policy cannot be
bypassed by prompt text.
