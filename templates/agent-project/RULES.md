# Project rules for __PROJECT__

These are enforced by hooks where a hook exists. The rest are the owner's words.

1. **Read the upstream code before writing new code.** Every file you read goes in
   `.claude/READ-LEDGER.md` as `- <path> — <lines> lines`. The `read-ledger-gate` blocks code
   writes until the ledger is real.
2. **Every step ends with a number you can read yourself.** Run the measurement
   (`work/measure/run.mjs`) and write the receipt to `work/receipts/`. The `measure-gate` blocks
   "done" while code is newer than the newest receipt.
3. **Cite only what you read.** An audit, review or handoff document carries a
   `## Verification ledger`. `VERIFIED: <claim> | <path>:<line>` only for files this session's
   tool calls read; otherwise `UNVERIFIED: <claim> - not checked`. The `citation-gate` enforces it.
4. **A negative result is a probe, not a conclusion.** Write "grep for X in Y found none", never
   "Y has no X". Name the instrument and its blind spot.
5. **Never kill a process by name or command-line pattern.** Only a PID you own, listed first.
6. **Never write a credential, token or key into any file.** Env only. Leak checks print file
   names only.
7. **One step at a time.** State what the step is, do it, show the receipt, stop. No side work
   (no redesigns, no websites, no docs beyond the receipt) unless the owner asked for it.
8. **Pushing, publishing, deleting and archiving are outward-facing.** Ask first.
