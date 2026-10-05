# Cowork Autonomy Kit

Version 1.5.1 · Windows · Independent community project, not affiliated with Anthropic.

A development-environment kit for Claude Code and Cowork on Windows: toolchain setup, persistent instructions, an elevated job helper, notifications, and diagnostic scripts. For developers comfortable reviewing scripts and managing their own machine.

[Website](https://scottconverse.github.io/cowork-autonomy-kit/) · [Setup guide](docs/SETUP.md) · [Latest release](https://github.com/scottconverse/cowork-autonomy-kit/releases/tag/v1.5.1) · [Changelog](CHANGELOG.md)

## What it does

- Checks for and installs development tools, preferring user-scope package managers.
- Stages instruction updates while preserving existing live instruction files for manual merging.
- Runs supported elevated jobs through a scheduled-task helper with JSON results and logs.
- Includes Doctor, configuration-layer uninstall, and regression tests.

## Before installing

Review the [full setup guide](docs/SETUP.md). Setup changes Claude Code permissions to `bypassPermissions` and installs a watcher that automatically clicks desktop permission dialogs. These changes reduce per-action review opportunities. The optional helper executes administrator-level scripts; trusted script paths do not sandbox their effects.

Download and extract the [v1.5.1 ZIP](https://github.com/scottconverse/cowork-autonomy-kit/releases/tag/v1.5.1), inspect the scripts, then run `Install.cmd` if you accept those changes. The helper requests Windows UAC approval. Restart Cowork after setup. The kit does not install Claude itself.

Existing helper installations require a direct helper-installer rerun, plus a manual merge of revised Core guidance into live instructions.

## Documentation

- [Comprehensive developer user manual](docs/DEVELOPER-MANUAL.md)
- [Detailed setup and safety notes](docs/SETUP.md)
- [Elevated helper](elevated-dev-helper/README.md)
- [Core instructions](CLAUDE-Cowork-Core.md)
- [Test plan](tests/TEST-PLAN.md)
- [Website development and deployment](site/README.md)

## Project status and participation

Functional but evolving. Helper regressions and existing-machine runtime checks passed for v1.5.1; clean-machine lifecycle and native Cowork behavioral testing were not performed. See the release notes for exact scope. Report reproducible problems through [GitHub Issues](https://github.com/scottconverse/cowork-autonomy-kit/issues).

## License

Public source, but no reuse license is currently provided. Public visibility does not imply an open-source license.
