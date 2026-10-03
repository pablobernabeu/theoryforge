// apps/shared/app-core.js under a stub DOM and a stub runtime: start-up with
// blocked storage, failed uploads and restores, the validity chip and how a
// change of theory or a failed operation is reported.
import { test } from "node:test";
import assert from "node:assert/strict";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { makeWindow, runScript } from "./dom.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const CORE = path.join(here, "..", "shared", "app-core.js");

const EXAMPLES = [
  { name: "Theory A", path: "fixtures/a.theory.yaml", desc: "" },
  { name: "Theory B", path: "fixtures/b.theory.yaml", desc: "" },
];
const summaryOf = (id, validation) => ({ id, title: "Title " + id, counts: {}, validation });
const TRACEBACK = "Traceback (most recent call last):\n  File \"/pkg/_app.py\", line 50, in run\nAttributeError: 'str' object has no attribute 'get'";

// A runtime with the interface app-core expects. Its engine "loads" a file
// unless the text is a top-level list, and an upload whose text contains
// "bad" loads as an invalid theory with two problems.
function stubRuntime(extra) {
  return Object.assign({
    lang: "py", langLabel: "Python", engineLabel: "stub", accent: "#3776AB", docsUrl: "#",
    examples: [], corpora: [], active: null, failRun: false, badExamples: [],
    hasCorpus() { return false; },
    async init() {
      const summary = await this.loadExample(EXAMPLES[0].path);
      return { examples: EXAMPLES, version: "Python 3", pkgVersion: "0.0", summary };
    },
    async loadExample(p) {
      if (this.badExamples.includes(p)) throw new Error("Error: could not read " + p);
      this.active = p;
      return summaryOf(p.split("/").pop(), { ok: true });
    },
    async loadTheoryText(text, name) {
      if (text.startsWith("- ")) throw new Error("PythonError: Traceback (most recent call last):\n  File \"<exec>\"\nValueError: Theory data must be a mapping");
      this.active = name;
      return summaryOf(name, /bad/.test(text) ? { ok: false, message: "invalid theory object: unknown top-level field: predicitions; construct[0] missing/empty id" } : { ok: true });
    },
    async run(op) {
      if (this.failRun) throw new Error(TRACEBACK);
      const raw = op === "validate" ? { ok: true }
        : { report: { aggregate_score: 80, gate: "pass", n_blockers_failed: 0, maturity: "developing", items: [] }, svg: "<svg></svg>" };
      return { raw, code: "# computed on " + this.active };
    },
  }, extra || {});
}

async function boot(opts, rt) {
  const ctx = makeWindow(opts);
  runScript(ctx, CORE);
  rt = rt || stubRuntime();
  await ctx.TF.start(rt);
  const $ = (s) => ctx.document.querySelector(s);
  return { ctx, rt, $ };
}
const upload = (f, name, text) => f.dispatch("change", { target: { files: [{ name, text: async () => text }] } });

test("the app starts when the browser blocks site storage", async () => {
  const { $ } = await boot({ storage: "blocked" });
  assert.ok($("header.app"), "the header is rendered");
  assert.ok($("main#main"), "the main panel is rendered");
  assert.ok($("#boot").classList.contains("hidden"), "the boot overlay is dismissed");
  assert.equal($(".boot-error"), null);
  // The theme still cycles for the session, though it cannot be remembered.
  const toggle = $("#themeToggle");
  const seen = [];
  for (let i = 0; i < 3; i++) { await toggle.click(); seen.push(toggle.title); }
  assert.deepEqual(seen, ["Theme: light (click to change)", "Theme: dark (click to change)", "Theme: system (click to change)"]);
});

test("a start that fails before the boot panel exists still says so", async () => {
  const ctx = makeWindow();
  runScript(ctx, CORE);
  const rt = stubRuntime();
  Object.defineProperty(rt, "accent", { get() { throw new Error("no accent"); } });
  await ctx.TF.start(rt);   // must not reject
  const err = ctx.document.querySelector(".boot-error");
  assert.ok(err, "an error panel is shown");
  assert.match(err.textContent, /could not start/);
  assert.match(err.textContent, /no accent/);
});

test("a failed upload keeps the active theory and says which it is", async () => {
  const { $ } = await boot();
  await upload($("#fileInput"), "amended.theory.yaml", "- id: x\n");
  const wrap = $("#summaryWrap");
  assert.match(wrap.textContent, /Could not load amended\.theory\.yaml; the active theory is still Title a\.theory\.yaml/);
  assert.ok($("#summaryWrap .summary"), "the active summary card stays");
  // The error's final line is shown, the full text is kept in a details element.
  const box = $("#summaryWrap .error");
  assert.match(box.textContent, /ValueError: Theory data must be a mapping/);
  assert.ok($("#summaryWrap .error details"), "the full error is available");
  await $("#runBtn").click();
  assert.equal($("#codeBlock").textContent, "# computed on fixtures/a.theory.yaml");
});

test("the summary says whether the loaded theory is valid", async () => {
  const { $ } = await boot();
  assert.equal($("#summaryWrap .chip.valid").textContent, "valid");
  await upload($("#fileInput"), "mine.theory.yaml", "bad: theory\n");
  assert.equal($("#summaryWrap .chip.valid"), null);
  assert.equal($("#summaryWrap .chip.invalid").textContent, "2 problems");
});

test("a change of theory clears the result and the code", async () => {
  const { $ } = await boot();
  await $("#runBtn").click();
  assert.equal($("#codePanel").style.display, "");
  assert.match($("#codeBlock").textContent, /a\.theory\.yaml/);
  await $("#exampleSel").dispatch("change", { target: { value: "1" } });
  assert.equal($("#codePanel").style.display, "none");
  assert.equal($("#codeBlock").textContent, "");
  assert.equal($("#output .section"), null, "the old result is gone");
  assert.match($("#output").textContent, /Title b\.theory\.yaml/);
});

test("an operation that fails on an invalid theory says so and points to Validate", async () => {
  const { $, rt } = await boot();
  await upload($("#fileInput"), "mine.theory.yaml", "bad: theory\n");
  rt.failRun = true;
  await $("#runBtn").click();
  const out = $("#output");
  assert.match(out.textContent, /invalid theory/);
  assert.match(out.textContent, /2 problems/);
  assert.ok($("#output .error button.linklike"), "a button leads to Validate");
  assert.match($("#output .error .last").textContent, /^AttributeError: 'str' object has no attribute 'get'$/);
  assert.match($("#output .error details").textContent, /Traceback \(most recent call last\)/);
});

test("a failed restore of an upload falls back to the first example and says so", async () => {
  const saved = { "tf-app-py": JSON.stringify({ opId: "check", params: {}, ran: false, input: { mode: "upload", name: "gone.yaml", text: "- id: x\n" } }) };
  const { $ } = await boot({ stored: saved });
  assert.match($(".toast").textContent, /Could not restore gone\.yaml/);
  assert.match($("#summaryWrap").textContent, /Title a\.theory\.yaml/);
});

test("a failed restore of an example falls back to the first example and says so", async () => {
  const saved = { "tf-app-py": JSON.stringify({ opId: "check", params: {}, ran: false, input: { mode: "example", index: 1 } }) };
  const rt = stubRuntime({ badExamples: [EXAMPLES[1].path] });
  const { $ } = await boot({ stored: saved }, rt);
  assert.equal($("#exampleSel").value, "0");
  assert.match($(".toast").textContent, /Could not restore Theory B/);
  assert.match($("#summaryWrap").textContent, /Title a\.theory\.yaml/);
});
