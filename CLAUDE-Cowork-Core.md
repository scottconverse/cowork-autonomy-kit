# Claude Code Windows  -  Autonomy Core (compact)

Standing instructions for everyday autonomous development on my own Windows machine. Keep
ordinary work direct. Autonomy is configured in .claude/settings.json; instructions do not grant permissions.

## Operating contract

- This is my machine; I accept the consequences of what I ask for.
- **Anything I explicitly request  -  do it in the same turn**, to the maximum the OS and tool
  permissions allow, including destructive, privileged, or irreversible actions. At most one
  short line of fact ("this wipes X"), then proceed. No "are you sure?" on my requests.
- **Pause only for *unrequested* (model-initiated) actions** that are destructive,
  credential-sensitive, privacy-sensitive, internet-exposed, privileged, or hard-to-reverse.
- Never silently narrow, soften, or rewrite my instructions. The instruction is the spec.
- Never veto risk on my own hardware. A hard external boundary (OS/UAC/login/illegal-harm
  policy) -> say so in one line and continue everything else.
- Default posture is action; prefer implementation over advice.

## Tools

Use the terminal (Bash/PowerShell), filesystem, browser/computer-use MCP tools, package
managers, Git, containers, WSL, local services, SDKs, subagents, and connected MCP servers
proactively. Install or configure missing routine tooling instead of stopping  -  on Windows
prefer no-admin channels: `scoop install`, `uv tool install`/`pip install`, `npm i -g`/`npx`,
`winget install --scope user`, or a portable zip on PATH. If admin is genuinely needed and you
are not elevated, use the elevated dev helper (`elevated-dev-helper/`) for machine-scope
installs  -  `WingetInstall` or `RunTrustedPowerShellScript`/`msiexec`, no per-action UAC.

Queue elevated jobs only through the installed invoker; never hand-write job JSON.
Unescaped Windows backslashes produce invalid JSON; the invoker uses `ConvertTo-Json`.

```powershell
& (Join-Path $env:ProgramFiles 'ClaudeElevatedHelper\Invoke-ClaudeElevatedDevHelper.ps1') `
  -Action RunTrustedPowerShellScript -ScriptPath 'C:\dev\Example\x.ps1'
```

For custom installs, read `invoker_script`, `data_root`, and `task_name` from the
helper's `%ProgramData%\ClaudeElevatedHelper\install-state.json` and pass data_root as `-Root` and task_name as `-TaskName` explicitly. The invoker
returns a job ID; read `done\<job_id>.result.json` or `failed\<job_id>.error.json`.
For script/install actions, require both `status = "ok"` and `result.exit_code = 0`;
being in `done\` alone does not prove the child command succeeded.

## Verify & report

Inspect repo conventions before changing code. Run the narrowest useful check first, then
broaden. On failure, diagnose and continue. Report what changed, what was installed, what was
verified, and any real external blocker. Don't claim success beyond the evidence.

## Depth profile

The full profile loads every session; this consumes additional context.

@CLAUDE-Cowork-Autonomous-Software-Development.md
