// The reproducible code the apps show. Each Python snippet is downloaded as a
// script, so it must print its result rather than end in a bare expression,
// which a script evaluates and drops. This test runs every snippet, for every
// case the smoke scripts run, under CPython with the package's source and
// checks that it prints. It skips when no Python with PyYAML is at hand. The
// diagram snippets must point to a renderer that reads what they print:
// dagitty for the causal DAG, which Graphviz cannot read, and the packages'
// own renderers for the DOT views.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, mkdtempSync, copyFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { manifestCorpora, manifestExamples } from "../build.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(here, "..", "..");
const CASES = JSON.parse(readFileSync(path.join(ROOT, "scripts", "app_smoke_cases.json"), "utf8")).cases;

function loadRuntime(file) {
  let src = readFileSync(path.join(here, "..", file), "utf8");
  src = src.replace(/^import .* from ".*";$/m, "").replace("window.TF.start(RT);", "globalThis.__RT = RT;");
  const ctx = { window: { TF: { DIAG_SVG: ["venn", "rigour", "severity"] } }, TextEncoder, TextDecoder, JSON, console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(src, ctx);
  return ctx.__RT;
}

// A runtime set up as the app sets it up: the theory is the modality
// switching example, which the package ships and which has rivals, claims,
// bounds and an estimate, and for the appraisal the amended panic network
// with its parent as the prior. An uploaded corpus or rival is a file beside
// the script.
async function snippets(file) {
  const RT = loadRuntime(file);
  const shipped = path.join(ROOT, "python", "src", "theoryforge", "fixtures");
  RT.examples = await manifestExamples(shipped);
  RT.corpora = await manifestCorpora(shipped);
  RT._corpusUpload = "uploaded-corpus.yaml";
  RT._rivalFile = "rival.theory.yaml";
  RT._priorFile = "prior.theory.yaml";
  return CASES.map((c) => {
    const p = Object.assign({}, c.params);
    const appraise = c.op === "appraise";
    RT._theoryFile = appraise ? "panic-network-2026-v2.theory.yaml" : "modality-switching.theory.yaml";
    RT._theoryShipped = true;
    if (appraise) p.prior = "fixtures/panic-network.theory.yaml";
    if (c.op === "discriminate") p.rival = "alt_symbol_interdependency";
    if (p.start === "impulse") p.impulse = "c_sensorimotor_experience";
    return { name: c.op + " " + JSON.stringify(c.params), code: RT.code(c.op, p) };
  });
}

const DRIVER = String.raw`
import contextlib, io, json, os, sys, traceback
out = []
for s in json.load(sys.stdin):
    buf = io.StringIO()
    err = None
    try:
        with contextlib.redirect_stdout(buf):
            exec(compile(s["code"], s["name"], "exec"), {"__name__": "__main__"})
    except BaseException:
        err = traceback.format_exc(limit=3)
    out.append({"name": s["name"], "printed": len(buf.getvalue().strip()), "error": err})
print(json.dumps(out))
`;

function python() {
  for (const exe of ["python3", "python"]) {
    const r = spawnSync(exe, ["-c", "import yaml"], { encoding: "utf8" });
    if (r.status === 0) return exe;
  }
  return null;
}

test("every Python snippet runs as a script and prints its result", async (t) => {
  const exe = python();
  if (!exe) { t.skip("no Python with PyYAML"); return; }
  const tmp = mkdtempSync(path.join(os.tmpdir(), "tf-code-"));
  try {
    copyFileSync(path.join(ROOT, "fixtures", "panic-corpus.yaml"), path.join(tmp, "uploaded-corpus.yaml"));
    const list = await snippets("py/py-runtime.js");
    const env = Object.assign({}, process.env, { PYTHONPATH: path.join(ROOT, "python", "src"), MPLBACKEND: "Agg" });
    const r = spawnSync(exe, ["-c", DRIVER], { cwd: tmp, input: JSON.stringify(list), encoding: "utf8", env, maxBuffer: 64 << 20 });
    assert.equal(r.status, 0, r.stderr);
    const res = JSON.parse(r.stdout.trim().split("\n").pop());
    assert.equal(res.length, CASES.length);
    for (const x of res) {
      assert.equal(x.error, null, x.name + "\n" + x.error);
      assert.ok(x.printed > 0, x.name + " prints nothing");
    }
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
});

test("no Python snippet ends in a bare expression", async () => {
  // A script drops the value of an expression statement, so the last line of
  // code must print, write a file or loop over what it prints.
  for (const s of await snippets("py/py-runtime.js")) {
    const lines = s.code.split("\n").map((l) => l.replace(/\s+#.*$/, "")).filter((l) => l.trim() && !/^\s*#/.test(l));
    const last = lines[lines.length - 1];
    assert.match(last, /^\s*(print\(|fh\.write\(|for |except |try:)|^\s+print\(/, s.name + ": " + last);
  }
});

test("the causal DAG's code points to dagitty, and the DOT views to the packages' renderers", async () => {
  const py = loadRuntime("py/py-runtime.js"), r = loadRuntime("r/r-runtime.js");
  for (const RT of [py, r]) { RT._theoryFile = "t.yaml"; RT._theoryShipped = false; }
  const pyDag = py.code("diagram", { type: "causal_dag" }), rDag = r.code("diagram", { type: "causal_dag" });
  assert.match(pyDag, /https:\/\/dagitty\.net/);
  assert.match(rDag, /plot\(dagitty::graphLayout\(dagitty::dagitty\(ir\)\)\)/);
  for (const code of [pyDag, rDag]) assert.doesNotMatch(code, /graphviz\.Source|grViz|run Graphviz|render_diagram/);
  assert.match(py.code("diagram", { type: "nomological_net" }), /theory\.render_diagram\("nomological_net"\)\.render\(/);
  assert.match(r.code("diagram", { type: "nomological_net" }), /tf_render_diagram\(theory, "nomological_net"\)/);
});
