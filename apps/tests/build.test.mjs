// apps/build.mjs: the Python vendor tree holds exactly the files its manifest
// lists, so bytecode caches left by an earlier import are never deployed.
import { test } from "node:test";
import assert from "node:assert/strict";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { buildPy } from "../build.mjs";

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
  } finally {
    await fs.rm(tmp, { recursive: true, force: true });
  }
});
