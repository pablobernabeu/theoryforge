// scripts/app_smoke.py and scripts/app_smoke.R run every operation the apps
// offer on every example, through the glue each engine runs in the browser.
// They read the operations from scripts/app_smoke_cases.json. That file must
// list every operation in apps/shared/app-core.js at the defaults the UI gives
// it, and once more for each other option of a select parameter (the ten
// diagram types, the cycles setting, the simulation's method and start, the
// literature method) and of the corpus (the two bundled corpora and an
// uploaded one). The prior, the rival and the construct an impulse starts in
// are left out, since the scripts choose them from the theory as the UI does.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { makeWindow, runScript } from "./dom.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const CORE = path.join(here, "..", "shared", "app-core.js");
const CASES = path.join(here, "..", "..", "scripts", "app_smoke_cases.json");

function expectedCases(ops) {
  const out = [];
  for (const op of ops) {
    const params = (op.params || []).filter((p) => !["theory", "rival", "construct"].includes(p.type));
    const defaults = Object.fromEntries(params.map((p) => [p.id, p.default]));
    out.push({ op: op.id, params: defaults });
    for (const p of params.filter((q) => q.type === "select" || q.type === "corpus")) {
      for (const o of p.options) {
        if (o !== p.default) out.push({ op: op.id, params: { ...defaults, [p.id]: o } });
      }
    }
  }
  // As the browser sends them: run() passes JSON.stringify(params).
  return JSON.parse(JSON.stringify(out));
}

test("the smoke cases are every operation the apps offer, at the UI's defaults", () => {
  const ctx = makeWindow();
  runScript(ctx, CORE);
  const want = expectedCases(ctx.TF.OPS);
  const got = JSON.parse(readFileSync(CASES, "utf8")).cases;
  assert.deepEqual(got, want);
  assert.equal(got.filter((c) => c.op === "diagram").length, 10);
});
