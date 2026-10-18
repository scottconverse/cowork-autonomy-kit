// Measurement for cowork-autonomy-kit (CI-standard checker task). Runs the checker's own test and
// the two repo guards in Windows PowerShell 5.1, parses each SUMMARY line, and writes a receipt
// only when every run exited 0. The measure-gate accepts a receipt newer than the newest code file,
// so re-run after every code change.
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const receipts = path.resolve("work", "receipts");
fs.mkdirSync(receipts, { recursive: true });

function run(script) {
  const r = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script], { encoding: "utf8" });
  const out = (r.stdout || "") + (r.stderr || "");
  const m = out.match(/SUMMARY: (\d+) PASS \/ (\d+) FAIL/);
  const passLine = out.match(/^PASS: .*$/m);
  return { script, exit: r.status, pass: m ? +m[1] : passLine ? 1 : 0, fail: m ? +m[2] : r.status === 0 ? 0 : 1, last: out.trim().split(/\r?\n/).pop() };
}

const runs = ["tests/Test-CiStandard.ps1", "tests/Test-NoBOM.ps1", "tests/Test-NoHardcodedPaths.ps1"].map(run);
const result = {
  runs,
  pass: runs.reduce((a, r) => a + r.pass, 0),
  fail: runs.reduce((a, r) => a + r.fail, 0),
  allExitZero: runs.every((r) => r.exit === 0),
};
for (const r of runs) console.log(`${r.script}: exit ${r.exit}; ${r.last}`);
if (!result.allExitZero) {
  console.error("measure: a run failed; no receipt written.");
  process.exit(1);
}
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const file = path.join(receipts, "receipt-" + stamp + ".json");
fs.writeFileSync(file, JSON.stringify({ at: stamp, ...result }, null, 1));
console.log("receipt: " + file);
console.log(JSON.stringify({ pass: result.pass, fail: result.fail }));
