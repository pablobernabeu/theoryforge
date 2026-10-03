// The two language runtimes with a stub engine: the reproducible-code panel
// must name the theory the engine holds, so a load that fails must leave the
// file name of the theory loaded before it.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const GOOD = "fixtures/panic-network.theory.yaml";
const OTHER = "fixtures/weak-theory.theory.yaml";

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
// theory it held before. A path listed in `broken` fails to load as well.
function withStubEngine(file, broken) {
  const RT = loadRuntime(file);
  const fsys = { ["/x/" + GOOD]: "id: panic", ["/x/" + OTHER]: "id: weak" };
  const engine = { theory: null };
  const load = (p) => {
    if (broken.includes(p) || String(fsys[p]).startsWith("- ")) throw new Error("Theory data must be a mapping");
    engine.theory = p;
    return JSON.stringify({ id: p, validation: { ok: true } });
  };
  RT._fixtures = { [GOOD]: "/x/" + GOOD, [OTHER]: "/x/" + OTHER };
  const write = (dest, buf) => { fsys[dest] = new TextDecoder().decode(buf); };
  if (file.startsWith("py")) {
    RT._py = { FS: { writeFile: write } };
    RT._app = { load, run: () => JSON.stringify({ on: engine.theory }) };
  } else {
    RT._webR = {
      FS: { writeFile: async (d, b) => write(d, b) },
      evalRString: async (code) => {
        const m = code.match(/^\.tf_load\("(.*)"\)$/);
        if (m) return load(m[1]);
        if (code === ".tf_run_call()") return JSON.stringify({ on: engine.theory });
        throw new Error("unexpected call " + code);
      },
    };
  }
  return { RT, engine };
}

const named = (code) => code.split("\n")[1];

for (const file of ["py/py-runtime.js", "r/r-runtime.js"]) {
  test(`${file}: a refused upload leaves the code naming the loaded theory`, async () => {
    const { RT, engine } = withStubEngine(file, []);
    await RT.loadExample(GOOD);
    await assert.rejects(RT.loadTheoryText("- id: x\n", "my-amended-theory.yaml"));
    const { raw, code } = await RT.run("check", {});
    assert.equal(raw.on, engine.theory);
    assert.match(named(code), /"panic-network\.theory\.yaml"/);
  });

  test(`${file}: an example that fails to load leaves the code naming the loaded theory`, async () => {
    const { RT } = withStubEngine(file, ["/x/" + OTHER]);
    await RT.loadExample(GOOD);
    await assert.rejects(RT.loadExample(OTHER));
    assert.match(named(RT.code("check", {})), /"panic-network\.theory\.yaml"/);
  });

  test(`${file}: a successful upload is named in the code`, async () => {
    const { RT } = withStubEngine(file, []);
    await RT.loadExample(GOOD);
    const s = await RT.loadTheoryText("id: mine\n", "mine.theory.yaml");
    assert.deepEqual(s.validation, { ok: true });
    assert.match(named(RT.code("check", {})), /"mine\.theory\.yaml"/);
  });
}
