// apps/build.mjs: the Python vendor tree holds exactly the files its manifest
// lists, so bytecode caches left by an earlier import are never deployed. The
// manifest marks the examples each package ships, which the reproducible code
// reads through example_path().
import { test } from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { buildPy, manifestCorpora, manifestExamples } from "../build.mjs";

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

async function walk(dir, base = dir) {
  const out = [];
  for (const e of await fs.readdir(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) out.push(p.slice(base.length + 1) + "/", ...(await walk(p, base)));
    else out.push(p.slice(base.length + 1));
  }
  return out.map((f) => f.split(path.sep).join("/"));
}

test("the Python vendor tree leaves out __pycache__ and every file the manifest does not list", async () => {
  const tmp = await fs.mkdtemp(path.join(os.tmpdir(), "tf-build-"));
  try {
    const src = path.join(tmp, "src");
    await fs.mkdir(path.join(src, "__pycache__"), { recursive: true });
    await fs.mkdir(path.join(src, "schema", "__pycache__"), { recursive: true });
    for (const [f, text] of Object.entries({
      "__init__.py": "", "core.py": "", "py.typed": "", "schema/theory.schema.json": "{}",
      "schema/rigor_checklist.yaml": "", "__pycache__/core.cpython-312.pyc": "x",
      "schema/__pycache__/x.cpython-313.pyc": "x", "notes.txt": "",
    })) await fs.writeFile(path.join(src, f), text);
    const vendor = path.join(tmp, "vendor");
    const n = await buildPy(vendor, src);
    const manifest = JSON.parse(await fs.readFile(path.join(vendor, "manifest.json"), "utf8"));
    const onDisk = (await walk(path.join(vendor, "theoryforge"))).filter((f) => !f.endsWith("/"));
    assert.deepEqual(manifest.pyFiles, onDisk.map((f) => "theoryforge/" + f).sort());
    assert.equal(n, manifest.pyFiles.length);
    assert.deepEqual(manifest.pyFiles, [
      "theoryforge/__init__.py", "theoryforge/core.py", "theoryforge/py.typed",
      "theoryforge/schema/rigor_checklist.yaml", "theoryforge/schema/theory.schema.json",
    ]);
    const dirs = (await walk(path.join(vendor, "theoryforge"))).filter((f) => f.endsWith("/"));
    assert.deepEqual(dirs, ["schema/"]);
    // This package ships no examples, so the code must ask for every file.
    assert.ok(manifest.examples.length > 0);
    assert.ok(manifest.examples.every((e) => e.shipped === false));
    assert.ok(manifest.corpora.every((c) => c.shipped === false));
  } finally {
    await fs.rm(tmp, { recursive: true, force: true });
  }
});

test("the manifest marks the examples each package ships and lists modality switching last", async () => {
  for (const dir of [path.join(repo, "python", "src", "theoryforge", "fixtures"),
    path.join(repo, "r", "theoryforge", "inst", "fixtures")]) {
    const examples = await manifestExamples(dir);
    assert.equal(examples.length, 10);
    assert.equal(examples[examples.length - 1].path, "fixtures/modality-switching.theory.yaml");
    assert.deepEqual(examples.filter((e) => e.shipped).map((e) => e.path), [
      "fixtures/panic-network.theory.yaml", "fixtures/panic-network-2026-v2.theory.yaml",
      "fixtures/weak-theory.theory.yaml", "fixtures/modality-switching.theory.yaml",
    ]);
    assert.deepEqual((await manifestCorpora(dir)).map((c) => [c.path, c.shipped]), [["fixtures/panic-corpus.yaml", true]]);
  }
});

test("the effort-recovery example promises what its default run shows", async () => {
  // At the defaults fatigue and recovery turn once each, and the loop is seen
  // to cycle only with less damping over more steps. What marks the default
  // run as a damped oscillation is fatigue overshooting zero, the level every
  // construct decays to: it starts at 1 and falls to about -0.23.
  const desc = (await manifestExamples(repo)).find((e) => e.path.endsWith("effort-recovery.theory.yaml")).desc;
  assert.doesNotMatch(desc, /oscillating trajectories/);
  assert.match(desc, /fatigue overshoots its resting level of zero/);
  assert.match(desc, /lower damping to 0\.1 and raise steps to 150/i);
  // The comment markers are dropped, so a phrase that wraps onto the next line
  // of the header is read whole.
  const header = (await fs.readFile(path.join(repo, "apps", "examples", "effort-recovery.theory.yaml"), "utf8"))
    .split(/\r?\n/).filter((l) => l.startsWith("#")).map((l) => l.replace(/^#\s?/, "")).join(" ");
  assert.doesNotMatch(header, /oscillating trajectories/);
  assert.match(header, /fatigue overshoots its resting level of zero/);
  assert.match(header, /damping to 0\.1 and raise steps to 150/);
});
