# Handoff: CI-standard check (`Test-CiStandard.ps1`)

Date: 2026-10-17. Nothing committed or pushed; all changes are in the working tree.

## What was built

- `Test-CiStandard.ps1` (repo root, beside `Doctor-Autonomy.ps1` and `New-AgentProject.ps1`, which is where this kit keeps its user-facing scripts). `-RepoRoot <repo>` reads `.github/workflows/*.yml|*.yaml`, prints one `PASS|FAIL|INFO <rule> <file>:<line> <detail>` row per rule, a `SUMMARY: n PASS / m FAIL` line in the repo's style, and exits 1 on any FAIL. Optional `-Required <names>`, `-MaxRequired` (10), `-MaxJobMinutes` (10), `-PassThru`, and an optional `.github/ci-standard.json` (`required`, `maxRequired`, `maxJobMinutes`).
- `tests/Test-CiStandard.ps1` plus fixture repositories under `tests/fixtures/ci-standard/` (`good`, `bad`, `too-many`, `config`). Runs the checker in a child Windows PowerShell process like CI does; 37 assertions.
- README bullet and CHANGELOG "Unreleased" line.

Port source: `scripts/check_actions_budget.py` (303 lines) and `tests/test_actions_budget.py` (142 lines) in the archived `agent-pipeline-codex` clone. Both read end to end before writing.

## Rule mapping

| Rule | Origin | Note |
|---|---|---|
| `required-budget` | standard | New. Jobs in required workflows <= 10. "Required" = heuristic (a `pull_request` trigger with no `paths:`), or the list in `-Required` / `.github/ci-standard.json`. The repo cannot see branch protection, so the explicit list is the durable answer. |
| `every-push` | standard | New. A non-required workflow whose `push`/`pull_request` trigger has no `paths:` filter. Tag-only pushes, `workflow_dispatch` and schedule-only workflows are events, not checks, and skip this rule. |
| `nightly` | standard, inverted | The original forbade daily crons ("weekly is the maximum default"). The standard says a non-required check runs once a night on main, so a non-required workflow now needs a nightly cron (`* * *` in the day/month/weekday fields, or `@daily`). Weekly fails with "is not nightly". |
| `concurrency` | original + standard | The original exempted release/tag workflows and demanded the exact group `${{ github.workflow }}-${{ github.ref }}`. The standard says every workflow, so no exemption; any `group:` is accepted; `cancel-in-progress` must be `true` or an expression naming `pull_request`. Job-level blocks count when every job has one. |
| `job-timeout` | standard | New. Duration is not measurable statically; the proxy is `timeout-minutes` <= 10 per job. Missing is FAIL (GitHub's default is 360 minutes), an expression is INFO, reusable-workflow jobs (`uses:` at job level) are skipped. |
| `duplicate-trigger` | original | Carried unchanged: `pull_request` plus push-to-main is a duplicate validation run. Standard is silent. |
| `heavy-paths`, `heavy-cache` | original | Carried unchanged, same marker and cache lists, same whole-text case-insensitive match (so a workflow named "E2E" trips the `e2e` marker at line 1, as it did in the original). |
| `artifact-retention` | original | Carried unchanged including the release/tag exemption (file name contains release/tag, or a `tags:` trigger); `retention-days: 7` exactly. |

## Not carried over, and why

- The changed-files modes (`git status`, `--run`, `--base-ref`, upstream discovery, and the pytest that mocks `subprocess.run`). The brief asks for a whole-repository audit of `-RepoRoot`; the kit's checks run on the whole tree. ~90 of the 303 lines.
- `macos-latest` and `windows-latest` PR bans with the `workflow-cost: windows-pr-justification` marker. Project-specific to the original repo; this kit is a Windows toolkit whose only product-protecting check runs on `windows-latest`, so the ban would fail the thing the standard says to keep.
- The single-Python-version matrix rule (Python 3.12). Project-specific.
- `policy_utils.find_repo_root`; `-RepoRoot` is explicit.
- `test_pipeline_scaffold_contains_workflow_cost_policy`, which asserted on files of the original repo's skill payload.

## What was verified and how

Commands run from the kit root in Windows PowerShell 5.1 (`powershell.exe -NoProfile -ExecutionPolicy Bypass -File ...`), last lines of output:

```text
tests/Test-CiStandard.ps1
SUMMARY: 37 PASS / 0 FAIL
tests/Test-NoBOM.ps1
PASS: no UTF-8 BOM in shipped JSON or live settings.json.
tests/Test-NoHardcodedPaths.ps1
PASS: all tracked text files scanned, including forward-slash sample proof
Test-CiStandard.ps1 -RepoRoot tests/fixtures/ci-standard/good
SUMMARY: 14 PASS / 0 FAIL            (exit 0)
Test-CiStandard.ps1 -RepoRoot tests/fixtures/ci-standard/bad
SUMMARY: 6 PASS / 12 FAIL / 1 INFO   (exit 1)
Test-CiStandard.ps1 -RepoRoot <this kit>
SUMMARY: 4 PASS / 6 FAIL             (exit 1)
```

Every `.ps1` under the kit parsed with `System.Management.Automation.Language.Parser::ParseFile` in Windows PowerShell 5.1 with zero errors.

Caveats on the repo guards: `Test-NoHardcodedPaths` scans `git ls-files`, and the new files are untracked, so that PASS does not cover them yet. A grep for `C:[\\/]+Users[\\/]+` over the new scripts, fixtures, README and this note found none; once the files are added the guard will scan them itself. `Test-NoBOM` scans every `.json` on disk including the new fixture `ci-standard.json`.

Run against this kit's own workflows the checker fails: `windows.yml` has no `concurrency` block and no `timeout-minutes`; `pages.yml` has no `timeout-minutes` on either job, no nightly schedule, and `push: branches: [main]` plus `pull_request` (the carried duplicate rule). Those are real findings against the standard, left for the owner; this task did not touch the workflows or add the checker to `windows.yml`'s test list.

## Blockers and how they were resolved

- The project's `read-ledger-gate` blocked the first Bash call that named a code file (it treats any code path in a command as a write target; `work/issue-ledger-false-positive.md` already records this). Resolved by reading both upstream files with the Read tool and writing the two ledger rows first.
- Windows PowerShell 5.1 throws "Argument types do not match" for `[pscustomobject]@{ Key = @($list) }` when `$list` is a `List[object]` holding PSCustomObjects. Resolved with `$list.ToArray()`; the bisect is reproducible with a one-line `powershell.exe -Command`.
- `work/measure/run.mjs` was the stub that refuses to write a receipt. Replaced with a measurement that runs the three tests above and writes a receipt only when all exit 0.

## Verification ledger

- VERIFIED: the original forbids daily crons and treats weekly as the maximum | <agent-pipeline-codex clone>/scripts/check_actions_budget.py:220-224
- VERIFIED: the original exempts release/tag workflows from the concurrency rule and requires the exact group string | <agent-pipeline-codex clone>/scripts/check_actions_budget.py:152-157,226-227
- VERIFIED: the original's heavy markers, cache markers, duplicate-trigger, macOS/Windows, Python-matrix and retention-days rules | <agent-pipeline-codex clone>/scripts/check_actions_budget.py:27-38,172-180,229-250
- VERIFIED: the original's changed-files and `--run`/`--base-ref` modes | <agent-pipeline-codex clone>/scripts/check_actions_budget.py:44-119,255-299
- VERIFIED: the original test's scaffold assertion and subprocess mock | <agent-pipeline-codex clone>/tests/test_actions_budget.py:103-142
- VERIFIED: `windows.yml` has `on: [push, pull_request]` and no `concurrency` or `timeout-minutes` | .github/workflows/windows.yml:2-8
- VERIFIED: `pages.yml` has `push: branches: [main]` with paths, `pull_request` with paths, a concurrency block, and no `timeout-minutes` | .github/workflows/pages.yml:2-13,15,27
- VERIFIED: the kit's `.gitattributes` sets `*.ps1 text eol=crlf` and `*.yml text eol=lf` | .gitattributes:3,15
- VERIFIED: `Test-NoHardcodedPaths` scans only `git ls-files` output | tests/Test-NoHardcodedPaths.ps1:11
- VERIFIED: CI standard text (about 10 required, own-files plus nightly, never every push, cancel-in-progress, split over 10 minutes) | ~/.claude/CLAUDE.md "CI standard" section
- UNVERIFIED: behaviour on a hosted `windows-latest` runner - not checked; only local Windows PowerShell 5.1 runs were made
- UNVERIFIED: GitHub's branch-protection "required" list for any repository - not checked; the checker cannot read it, which is why `-Required` and `.github/ci-standard.json` exist
