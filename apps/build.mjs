#!/usr/bin/env node
// Assemble the two browser apps by vendoring the current package sources.
//
// Each app runs the *real* package entirely client-side (R via webR, Python via
// Pyodide), so the source it executes must be the live package source. This
// script copies that source — plus the shared schema and the example fixtures —
// into apps/r/vendor and apps/py/vendor, and writes a manifest.json telling the
// app which files to fetch at start-up.
//
// Run locally before serving the apps, and in CI before deploying. The vendor
// directories are build artefacts (git-ignored); CI rebuilds them on every deploy
// so they can never go stale.

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "..");

const R_SRC = path.join(repo, "r", "theoryforge", "R");
const PY_SRC = path.join(repo, "python", "src", "theoryforge");
const SCHEMA = path.join(repo, "schema");
const FIXTURES = path.join(repo, "fixtures");
const APP_EXAMPLES = path.join(here, "examples");
// Single source of truth for the brand logo, so the apps cannot drift from it.
const LOGO = path.join(repo, "r", "theoryforge", "man", "figures", "logo.svg");

// Examples can be drawn from the shared fixtures (kept in lockstep with the
// golden/parity tests) or from apps/examples (app-only, isolated from CI). Each
// carries a one-line description shown in the app.
const EXAMPLES = [
  { name: "Panic disorder network (developing)", file: "panic-network.theory.yaml", src: FIXTURES,
    desc: "A well-developed network theory of panic — three constructs in a feedback loop. Passes the full rigour checklist." },
  { name: "Panic network, amended v2 (testing)", file: "panic-network-2026-v2.theory.yaml", src: FIXTURES,
    desc: "An amended version of the panic theory at the testing stage, with a fourth prediction and test outcomes." },
  { name: "Self-determination theory (developing)", file: "self-determination.theory.yaml", src: APP_EXAMPLES,
    desc: "Three basic needs driving intrinsic motivation. A solid theory with one precision warning." },
  { name: "Deliberately weak theory (draft)", file: "weak-theory.theory.yaml", src: FIXTURES,
    desc: "An underspecified draft kept as a worked example of what the checklist catches — it is blocked." },
];
const CORPUS = [{ name: "Panic literature corpus (demo)", file: "panic-corpus.yaml", src: FIXTURES }];

async function rmrf(p) {
  await fs.rm(p, { recursive: true, force: true });
}
async function copyInto(srcDir, destDir, filterExt) {
  await fs.mkdir(destDir, { recursive: true });
  const entries = await fs.readdir(srcDir, { withFileTypes: true });
  const copied = [];
  for (const e of entries) {
    const s = path.join(srcDir, e.name);
    const d = path.join(destDir, e.name);
    if (e.isDirectory()) {
      copied.push(...(await copyInto(s, d, filterExt)).map((f) => path.join(e.name, f)));
    } else if (!filterExt || filterExt.includes(path.extname(e.name).toLowerCase())) {
      await fs.copyFile(s, d);
      copied.push(e.name);
    }
  }
  return copied;
}
async function copyFiles(srcDir, destDir, names) {
  await fs.mkdir(destDir, { recursive: true });
  for (const n of names) await fs.copyFile(path.join(srcDir, n), path.join(destDir, n));
}
async function copyExamples(destDir) {
  await fs.mkdir(destDir, { recursive: true });
  for (const e of [...EXAMPLES, ...CORPUS]) await fs.copyFile(path.join(e.src, e.file), path.join(destDir, e.file));
}
const manifestExamples = () => EXAMPLES.map((e) => ({ name: e.name, path: `fixtures/${e.file}`, kind: e.kind || "theory", desc: e.desc || "" }));
const manifestCorpora = () => CORPUS.map((c) => ({ name: c.name, path: `fixtures/${c.file}`, desc: c.desc || "" }));
async function writeJson(p, obj) {
  await fs.writeFile(p, JSON.stringify(obj, null, 2) + "\n", "utf8");
}

async function buildR() {
  const vendor = path.join(here, "r", "vendor");
  await rmrf(vendor);
  // Package R source. Order is irrelevant (all definitions are lazy), but a
  // stable, deterministic order keeps the manifest diff-friendly.
  const rFiles = (await copyInto(R_SRC, path.join(vendor, "R"), [".r"])).sort();
  await copyFiles(SCHEMA, path.join(vendor, "schema"), ["theory.schema.json", "rigor_checklist.yaml"]);
  await copyExamples(path.join(vendor, "fixtures"));
  await fs.copyFile(LOGO, path.join(vendor, "logo.svg"));
  await writeJson(path.join(vendor, "manifest.json"), {
    rFiles: rFiles.map((f) => `R/${f}`),
    schema: { theory: "schema/theory.schema.json", checklist: "schema/rigor_checklist.yaml" },
    examples: manifestExamples(),
    corpora: manifestCorpora(),
  });
  return rFiles.length;
}

async function buildPy() {
  const vendor = path.join(here, "py", "vendor");
  await rmrf(vendor);
  // The Python package vendors its own schema/ inside the package dir, so a
  // wholesale copy of the package tree is import-ready and importlib-resources
  // resolves correctly.
  const pkgFiles = await copyInto(PY_SRC, path.join(vendor, "theoryforge"), null);
  await copyExamples(path.join(vendor, "fixtures"));
  await fs.copyFile(LOGO, path.join(vendor, "logo.svg"));
  const wanted = pkgFiles
    .filter((f) => f.endsWith(".py") || f.endsWith(".json") || f.endsWith(".yaml") || f.endsWith(".typed"))
    .map((f) => `theoryforge/${f.split(path.sep).join("/")}`)
    .sort();
  await writeJson(path.join(vendor, "manifest.json"), {
    pyFiles: wanted,
    examples: manifestExamples(),
    corpora: manifestCorpora(),
  });
  return wanted.length;
}

const nR = await buildR();
const nPy = await buildPy();
console.log(`vendored R: ${nR} source files -> apps/r/vendor`);
console.log(`vendored Python: ${nPy} package files -> apps/py/vendor`);
