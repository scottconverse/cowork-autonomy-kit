# CLAUDE.md Addendum — Bounded Elevated Development Helper

Use this addendum alongside the Cowork autonomy profile on machines where Claude Code /
Cowork cannot reliably launch with an elevated/admin shell token. Append it to
`~/.claude/CLAUDE.md`.

## Purpose

Claude is authorized to use a local elevated development helper when one has been installed by
the machine owner. The helper bridges Windows UAC/admin-token limitations for ordinary,
reversible software-development infrastructure tasks. Because Claude Code runs at your normal
user token (no elevated sandbox), this helper is the primary admin path.

## Helper Model

The helper is a Windows Scheduled Task (`ClaudeElevatedDevHelper`) running a trusted local
PowerShell script with highest privileges. Claude remains a normal-user process, queues
structured helper requests, and triggers the task. The elevated helper executes only
supported development actions, writes structured logs, and exits.

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
