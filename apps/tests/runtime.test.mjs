// The two language runtimes with a stub engine: the reproducible-code panel
// must name the theory the engine holds, so a load that fails must leave the
// file name of the theory loaded before it. The code reads a file the package
// ships through example_path(), asks for any other file to be saved beside the
// script first, and reads an uploaded prior by its own name.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const GOOD = "fixtures/panic-network.theory.yaml";
const OTHER = "fixtures/weak-theory.theory.yaml";
const APP_ONLY = "fixtures/self-determination.theory.yaml";
const CORPUS = "fixtures/panic-corpus.yaml";
// As the manifest lists them: build.mjs marks the files the package ships.
const EXAMPLES = [
  { name: "Panic", path: GOOD, shipped: true },
  { name: "Weak", path: OTHER, shipped: true },
  { name: "Self-determination", path: APP_ONLY, shipped: false },
];

// Evaluate a runtime without its CDN import and without starting the app.
function loadRuntime(file) {
  let src = readFileSync(path.join(here, "..", file), "utf8");
  src = src.replace(/^import .*$/m, "").replace("window.TF.start(RT);", "globalThis.__RT = RT;");
  const ctx = { window: { TF: { DIAG_SVG: ["venn", "rigour", "severity"] } }, TextEncoder, TextDecoder, JSON, console };
  ctx.globalThis = ctx;
  vm.createContext(ctx);
  vm.runInContext(src, ctx);
  return ctx.__RT;
}

// The engine refuses a top-level list, as tf.read and tf_read do, and keeps the
// theory it held before. A path listed in `broken` fails to load as well. A
// prior is held apart from the theory, and the lineage of a file that does not
// exist is null.
function withStubEngine(file, broken) {
  const RT = loadRuntime(file);
  const fsys = { ["/x/" + GOOD]: "id: panic", ["/x/" + OTHER]: "id: weak", ["/x/" + APP_ONLY]: "id: sdt" };
  const engine = { theory: null, prior: null };
  const refuse = (p) => broken.includes(p) || String(fsys[p]).startsWith("- ");
  const load = (p) => {
    if (refuse(p)) throw new Error("Theory data must be a mapping");
    engine.theory = p;
    return JSON.stringify({ id: p, validation: { ok: true } });
  };
  const loadPrior = (p) => {
    if (refuse(p)) throw new Error("Theory data must be a mapping");
    engine.prior = p;
    return JSON.stringify({ id: String(fsys[p]).slice(4).trim(), title: "", version: { id: "v1", parent_id: "" } });
  };
  const lineage = (paths) => JSON.stringify(paths.map((p) => (p in fsys
    ? { id: fsys[p].slice(4), title: "", version: { id: "v1", parent_id: "" } } : null)));
  RT._fixtures = { [GOOD]: "/x/" + GOOD, [OTHER]: "/x/" + OTHER, [APP_ONLY]: "/x/" + APP_ONLY };
  RT.examples = EXAMPLES;
  RT.corpora = [{ name: "Corpus", path: CORPUS, shipped: true }];
  RT._corpusFile = CORPUS;
  const write = (dest, buf) => { fsys[dest] = new TextDecoder().decode(buf); };
  if (file.startsWith("py")) {
    RT._py = { FS: { writeFile: write } };
    RT._app = {
      load, load_prior: loadPrior, lineage: (json) => lineage(JSON.parse(json)),
      run: () => JSON.stringify({ on: engine.theory }),
    };
  } else {
    RT._webR = {
      FS: { writeFile: async (d, b) => write(d, b) },
      evalRString: async (code) => {
        let m = code.match(/^\.tf_load\("(.*)"\)$/);
        if (m) return load(m[1]);
        m = code.match(/^\.tf_load_prior\("(.*)"\)$/);
        if (m) return loadPrior(m[1]);
        if (code === ".tf_lineage_call()") return lineage(JSON.parse(fsys["/tf/call.json"]).paths);
        if (code === ".tf_run_call()") return JSON.stringify({ on: engine.theory });
        throw new Error("unexpected call " + code);
      },
    };
  }
  return { RT, engine };
}

// The line that assigns `name`, and the line above a given line.
const readLine = (code, name) => code.split("\n").find((l) => new RegExp("^" + name + "( =| <-) ").test(l));
const lineAbove = (code, line) => { const ls = code.split("\n"); return ls[ls.indexOf(line) - 1]; };

for (const file of ["py/py-runtime.js", "r/r-runtime.js"]) {
  const py = file.startsWith("py");
  const read = (name, inner) => (py ? `${name} = tf.read(${inner})` : `${name} <- tf_read(${inner})`);
  const shipped = (f) => (py ? `tf.example_path("${f}")` : `tf_example_path("${f}")`);

  test(`${file}: a refused upload leaves the code naming the loaded theory`, async () => {
    const { RT, engine } = withStubEngine(file, []);
    await RT.loadExample(GOOD);
    await assert.rejects(RT.loadTheoryText("- id: x\n", "my-amended-theory.yaml"));
    const { raw, code } = await RT.run("check", {});
    assert.equal(raw.on, engine.theory);
    assert.match(readLine(code, "theory"), /"panic-network\.theory\.yaml"/);
  });

  test(`${file}: an example that fails to load leaves the code naming the loaded theory`, async () => {
    const { RT } = withStubEngine(file, ["/x/" + OTHER]);
    await RT.loadExample(GOOD);
    await assert.rejects(RT.loadExample(OTHER));
    assert.match(readLine(RT.code("check", {}), "theory"), /"panic-network\.theory\.yaml"/);
  });

  test(`${file}: a successful upload is named in the code`, async () => {
    const { RT } = withStubEngine(file, []);
    await RT.loadExample(GOOD);
    const s = await RT.loadTheoryText("id: mine\n", "mine.theory.yaml");
    assert.deepEqual(s.validation, { ok: true });
    assert.match(readLine(RT.code("check", {}), "theory"), /"mine\.theory\.yaml"/);
  });

  test(`${file}: a theory the package ships is read through example_path()`, async () => {
    const { RT } = withStubEngine(file, []);
    await RT.loadExample(GOOD);
    const code = RT.code("check", {});
    assert.equal(readLine(code, "theory"), read("theory", shipped("panic-network.theory.yaml")));
    assert.doesNotMatch(code, /beside this script/);
  });

  test(`${file}: an app-only example or an upload is to be saved beside the script first`, async () => {
    const { RT } = withStubEngine(file, []);
    await RT.loadExample(APP_ONLY);
    let code = RT.code("check", {});
    let line = readLine(code, "theory");
    assert.equal(line, read("theory", '"self-determination.theory.yaml"'));
    assert.match(lineAbove(code, line), /^# Save self-determination\.theory\.yaml beside this script first/);
    await RT.loadTheoryText("id: mine\n", "my theory.yaml");
    code = RT.code("check", {});
    line = readLine(code, "theory");
    assert.equal(line, read("theory", '"my theory.yaml"'));
    assert.match(lineAbove(code, line), /^# Save my theory\.yaml beside this script first/);
  });

  test(`${file}: a line break in an uploaded file's name cannot end the comment and leave code`, async () => {
    // A file name may hold a line feed or a carriage return. Either ends a
    // comment once the code is saved as a script and run, by Python or by R's
    // source(), so the rest of the name would run as code.
    const { RT } = withStubEngine(file, []);
    await RT.loadTheoryText("id: mine\n", "a\nimport os\r.yaml");
    const code = RT.code("check", {});
    const line = readLine(code, "theory");
    assert.equal(line, read("theory", '"a\\nimport os\\r.yaml"'));
    assert.match(lineAbove(code, line), /^# Save a\?import os\?\.yaml beside this script first/);
    assert.doesNotMatch(code, /\r/);
    assert.ok(!code.split("\n").some((l) => l.startsWith("import os")), "no part of the name stands as code");
  });

  test(`${file}: the corpus is read through example_path()`, () => {
    const { RT } = withStubEngine(file, []);
    for (const op of ["litmap", "landscape"]) {
      const code = RT.code(op, { min_link: 2 });
      assert.match(code, py ? /\ncorpus = tf\.read_corpus\(tf\.example_path\("panic-corpus\.yaml"\)\)\n/
        : /\ncorpus <- tf_read_corpus\(tf_example_path\("panic-corpus\.yaml"\)\)\n/);
    }
  });

  test(`${file}: the prior is read as a theory is, and an uploaded prior by its own name`, async () => {
    const { RT, engine } = withStubEngine(file, []);
    await RT.loadExample(GOOD);
    assert.equal(readLine(RT.code("appraise", { prior: OTHER }), "prior"), read("prior", shipped("weak-theory.theory.yaml")));
    let code = RT.code("appraise", { prior: APP_ONLY });
    let line = readLine(code, "prior");
    assert.equal(line, read("prior", '"self-determination.theory.yaml"'));
    assert.match(lineAbove(code, line), /^# Save self-determination\.theory\.yaml beside this script first/);
    // A prior the engine refuses names no file, and the engine keeps no prior.
    await assert.rejects(RT.loadPriorText("- id: x\n", "broken.yaml"));
    assert.equal(engine.prior, null);
    const lineage = await RT.loadPriorText("id: v0\n", "v0.theory.yaml");
    assert.equal(lineage.id, "v0");
    assert.match(engine.prior, /prior\.yaml$/);
    assert.equal(engine.theory, "/x/" + GOOD, "the theory stays loaded");
    code = RT.code("appraise", { prior: "upload" });
    line = readLine(code, "prior");
    assert.equal(line, read("prior", '"v0.theory.yaml"'));
    assert.match(lineAbove(code, line), /^# Save v0\.theory\.yaml beside this script first/);
  });

  test(`${file}: the examples' lineage is read without loading any of them`, async () => {
    const { RT, engine } = withStubEngine(file, []);
    const out = await RT.lineageOf(["/x/" + GOOD, "/x/missing.yaml"]);
    assert.equal(out.length, 2);
    assert.equal(out[0].id, "panic");
    assert.equal(out[1], null);
    assert.equal(engine.theory, null);
  });

  test(`${file}: implied independencies are reproduced with the cycles setting`, async () => {
    const { RT } = withStubEngine(file, []);
    await RT.loadExample(GOOD);
    assert.match(RT.code("implications", { cycles: "sigma" }),
      py ? /\nimplied = theory\.implications\(cycles="sigma"\)/ : /\nimplied <- tf_implications\(theory, cycles = "sigma"\)/);
  });
}

test("py/py-runtime.js: every file the Python code writes is opened as UTF-8", async () => {
  // open(name, "w") takes the locale's encoding, cp1252 on Windows, which
  // writes the ellipsis of a shortened label as a byte no XML parser reads.
  const { RT } = withStubEngine("py/py-runtime.js", []);
  await RT.loadExample(GOOD);
  const codes = [RT.code("check", {}), RT.code("severity", {})]
    .concat(["venn", "rigour", "severity"].map((t) => RT.code("diagram", { type: t })));
  for (const c of codes) {
    const opens = c.match(/open\([^)]*\)/g) || [];
    assert.ok(opens.length, c);
    for (const o of opens) assert.match(o, /, encoding="utf-8"\)$/);
  }
});

test("r/r-runtime.js: the simulate comment lists every element of the record", () => {
  const { RT } = withStubEngine("r/r-runtime.js", []);
  const code = RT.code("simulate", { steps: 30, dt: 0.1, k: 1, damping: 0.5, init: 1, method: "exact" });
  assert.match(code, /# list\(states, dt, steps, k, damping, init, method, ignored, opposed, trajectory\)$/m);
});
