# Read ledger for __PROJECT__

One row per upstream file read, with its real line count. The `read-ledger-gate` checks every
row against the file on disk and blocks code writes until the rows below are true and there are
enough of them. Format:

- <path relative to an upstream root, or absolute> — <lines> lines

Rows:

