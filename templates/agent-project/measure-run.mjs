// Measurement stub for __PROJECT__. Replace the body with the project's real measurement.
// The measure-gate only accepts a receipt newer than the newest code file, so this must be
// re-run after every code change. Until it is replaced it refuses to write a receipt.
import fs from "node:fs";
import path from "node:path";

const receipts = path.resolve("work", "receipts");
fs.mkdirSync(receipts, { recursive: true });

// TODO(owner): compute real numbers here. Example shape:
//   const result = { found: 12, expected: 17, acquired: 7, cited: 9, failed: 3 };
const result = null;

if (!result) {
  console.error("measure: this is the stub. Replace work/measure/run.mjs with the real measurement before claiming any number.");
  process.exit(1);
}
const stamp = new Date().toISOString().replace(/[:.]/g, "-");
const file = path.join(receipts, "receipt-" + stamp + ".json");
fs.writeFileSync(file, JSON.stringify({ at: stamp, ...result }, null, 1));
console.log("receipt: " + file);
console.log(JSON.stringify(result));
