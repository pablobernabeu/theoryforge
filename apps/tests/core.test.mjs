// apps/shared/app-core.js under a stub DOM and a stub runtime: start-up with
// blocked storage, failed uploads and restores, the validity chip and how a
// change of theory or a failed operation is reported. The later tests cover the
// appraisal's prior, the implied-independencies operation, the saved example,
// the checklist's wording, whole-number parameters, the help's list of
// operations and the page title.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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
// Wait until cond() holds, checking every few milliseconds, and fail after a
// generous time, so that a test does not hang on the speed of the machine.
async function until(cond, what, ms = 10000) {
  const t0 = Date.now();
  while (!cond()) {
    if (Date.now() - t0 > ms) throw new Error("timed out waiting for " + (what || "the condition"));
    await new Promise((r) => setTimeout(r, 5));
  }
}

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

test("the summary says whether the loaded theory is well-formed", async () => {
  const { $ } = await boot();
  assert.equal($("#summaryWrap .chip.valid").textContent, "well-formed");
  assert.equal($("#summaryWrap .chip.valid").getAttribute("title"),
    "Full validation found no problem in the file's structure or references. This says nothing about whether the theory is valid.");
  await upload($("#fileInput"), "mine.theory.yaml", "bad: theory\n");
  assert.equal($("#summaryWrap .chip.valid"), null);
  assert.equal($("#summaryWrap .chip.invalid").textContent, "2 problems");
});

test("a change of theory clears the result and the code", async () => {
  const { $ } = await boot();
  await $("#runBtn").click();
  assert.equal($("#codePanel").style.display, "");
  assert.match($("#codeBlock").textContent, /a\.theory\.yaml/);
  await $("#exampleSel").dispatch("change", { target: { value: EXAMPLES[1].path } });
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
  assert.match(out.textContent, /a theory that is not well-formed/);
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

test("the causal DAG renders an association as a dashed edge with two arrowheads", () => {
  // DOT has no `<->`, so the bidirected lines of the dagitty export are
  // rewritten for Graphviz. A directed line is left as it is.
  const ctx = makeWindow();
  runScript(ctx, CORE);
  const { dagToDigraph } = ctx.TF.util;
  assert.equal(dagToDigraph("dag {\n  a -> b\n  a <-> c\n}\n"),
    "digraph causal_dag {\n  rankdir=LR;\n  node [shape=box, style=rounded];\n" +
    "  a -> b\n  a -> c [dir=both, style=dashed]\n}\n");
  // A quoted identifier is kept whole.
  assert.equal(dagToDigraph('dag {\n  "self-efficacy" <-> "task \\"persistence\\""\n}\n'),
    "digraph causal_dag {\n  rankdir=LR;\n  node [shape=box, style=rounded];\n" +
    '  "self-efficacy" -> "task \\"persistence\\"" [dir=both, style=dashed]\n}\n');
  // dagitty keeps a backslash that does not escape a quote, and DOT reads one
  // as an escape, so each quoted id is written again by DOT's rule. An id that
  // holds `\\" [URL=...]` stays one id rather than end early and leave the
  // rest as attributes.
  const attack = 'dag {\n  "a\\\\" [URL=<javascript:alert(1)> label=<X>] //" -> b\n  "x\\y" <-> c\n}\n';
  assert.equal(dagToDigraph(attack),
    "digraph causal_dag {\n  rankdir=LR;\n  node [shape=box, style=rounded];\n" +
    '  "a\\\\\\" [URL=<javascript:alert(1)> label=<X>] //" -> b\n  "x\\\\y" -> c [dir=both, style=dashed]\n}\n');
});

test("a figure is inserted as clean nodes, with no script, handler or link, and downloads as shown", async () => {
  const evil = '<?xml version="1.0"?>\n<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "x.dtd">\n' +
    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" onload="alert(1)">' +
    '<script>alert(2)</script><style>body{display:none}</style><foreignObject><div>x</div></foreignObject>' +
    '<g id="node1"><a xlink:href="javascript:alert(3)" xlink:title="CLICK"><polygon points="0,0 1,1" onclick="alert(4)"/>' +
    '<text>CLICK ME</text></a><use href="#node1"/><image href="https://example.org/x.png"/></g>' +
    '<animate attributeName="href" to="javascript:alert(5)"/></svg>';
  const rt = stubRuntime({ async run() { return { raw: { report: { aggregate_score: 80, gate: "pass", n_blockers_failed: 0, maturity: "developing", items: [] }, svg: evil }, code: "#" }; } });
  const { ctx, $ } = await boot({}, rt);
  const downloads = [];
  ctx.URL = { createObjectURL: () => "blob:x", revokeObjectURL() {} };
  ctx.Blob = class { constructor(parts) { downloads.push(parts.join("")); } };
  await $("#runBtn").click();
  const fig = $(".figure");
  const svg = fig.querySelector("svg");
  assert.ok(svg, "the figure holds the SVG");
  assert.equal(fig.innerHTML, "", "the SVG is not inserted as markup");
  for (const tag of ["script", "style", "foreignObject", "a", "animate"]) assert.equal(fig.querySelectorAll(tag).length, 0, tag);
  const attrs = [svg, ...svg.querySelectorAll("*")].flatMap((n) => n.getAttributeNames().map((k) => k + "=" + n.getAttribute(k)));
  assert.ok(!attrs.some((a) => /^on/i.test(a)), "no event handler: " + attrs.join(" "));
  assert.ok(!attrs.some((a) => /javascript:|example\.org/.test(a)), "no link outside the figure: " + attrs.join(" "));
  assert.ok(attrs.includes("href=#node1"), "a reference inside the figure stays");
  assert.match(fig.textContent, /CLICK ME/, "a link's text stays as text");
  // The download is the figure as shown, since something was taken out.
  const btn = fig.parentNode.querySelectorAll("button").find((b) => b.textContent === "SVG");
  await btn.click();
  assert.equal(downloads.length, 1);
  assert.doesNotMatch(downloads[0], /script|onload|javascript/);
  // A figure the package wrote cleanly downloads as it wrote it, and text
  // that is no SVG is shown as a note.
  const plain = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect x="0" y="0" width="1" height="1"/></svg>\n';
  rt.run = async () => ({ raw: { report: { aggregate_score: 80, gate: "pass", n_blockers_failed: 0, maturity: "developing", items: [] }, svg: plain }, code: "#" });
  await $("#runBtn").click();
  await $(".figure").parentNode.querySelectorAll("button").find((b) => b.textContent === "SVG").click();
  assert.equal(downloads[1], plain);
  rt.run = async () => ({ raw: { report: { aggregate_score: 80, gate: "pass", n_blockers_failed: 0, maturity: "developing", items: [] }, svg: "<svg><g></svg>" }, code: "#" });
  await $("#runBtn").click();
  assert.equal($(".figure"), null);
  assert.match($("#output").textContent, /The figure could not be shown/);
});

test("a failed restore of an example falls back to the first example and says so", async () => {
  const saved = { "tf-app-py": JSON.stringify({ opId: "check", params: {}, ran: false, input: { mode: "example", path: EXAMPLES[1].path } }) };
  const rt = stubRuntime({ badExamples: [EXAMPLES[1].path] });
  const { $ } = await boot({ stored: saved }, rt);
  assert.equal($("#exampleSel").value, EXAMPLES[0].path);
  assert.match($(".toast").textContent, /Could not restore Theory B/);
  assert.match($("#summaryWrap").textContent, /Title a\.theory\.yaml/);
});

// ---- honest operations and text ------------------------------------------

// Examples with the lineage the real ones carry. The amended panic network
// names v1 of the panic network as its parent, the weak theory records no
// version, and every other example is version v1 with no parent.
const LINEAGE = [
  { name: "Panic network", path: "fixtures/panic-network.theory.yaml", desc: "",
    lineage: { id: "panic-network-2026", title: "Panic", version: { id: "v1", parent_id: "" } } },
  { name: "Panic network, amended v2", path: "fixtures/panic-network-2026-v2.theory.yaml", desc: "",
    lineage: { id: "panic-network-2026-v2", title: "Panic v2", version: { id: "v2", parent_id: "v1" } } },
  { name: "Happy vowel", path: "examples/happy-vowel-manchester.theory.yaml", desc: "",
    lineage: { id: "happy-vowel-manchester-2026", title: "Happy vowel", version: { id: "v1", parent_id: "" } } },
];

// A runtime whose loads report the example's lineage, which records each call
// it runs and which answers each operation with `answers[op]`, or with what
// `answers[op]` gives for the call's parameters when it is a function.
function lineageRuntime(answers) {
  return stubRuntime({
    calls: [], priorLoads: [],
    hasCorpus() { return true; },
    async init() {
      const summary = await this.loadExample(LINEAGE[0].path);
      return { examples: LINEAGE, version: "Python 3", pkgVersion: "0.0", summary };
    },
    async loadExample(p) {
      const l = LINEAGE.find((e) => e.path === p).lineage;
      this.active = p;
      return { id: l.id, title: l.title, version: l.version, counts: {}, validation: { ok: true } };
    },
    // An uploaded prior reads its id and version from `id:` and `version:`
    // lines, and a top-level list is refused.
    async loadPriorText(text, name) {
      this.priorLoads.push(name);
      if (text.startsWith("- ")) throw new Error("ValueError: Theory data must be a mapping");
      const line = (k) => ((text.match(new RegExp("^" + k + ": (.*)$", "m")) || [])[1] || "");
      return { id: line("id"), title: "", version: { id: line("version"), parent_id: "" } };
    },
    async run(op, params) {
      this.calls.push({ op, params });
      const a = answers && answers[op];
      const raw = (typeof a === "function" ? a(params) : a) || { verdict: "neutral" };
      return { raw, code: "# " + op };
    },
  });
}
const opButton = (ctx, id) => ctx.document.querySelectorAll(".op").find((b) => b.getAttribute("data-op") === id);
const choose = (sel, value) => sel.dispatch("change", { target: { value } });
const lastCall = (rt) => rt.calls[rt.calls.length - 1];

test("the appraisal's prior defaults to the declared parent, and to none for any other theory", async () => {
  const { ctx, $, rt } = await boot({}, lineageRuntime());
  await opButton(ctx, "appraise").click();
  // Version v1 of the panic network declares no parent.
  assert.equal($("#param-prior").value, "");
  await choose($("#exampleSel"), LINEAGE[1].path);
  assert.equal($("#param-prior").value, LINEAGE[0].path, "the amended network defaults to its parent");
  assert.doesNotMatch($("#priorNote").className, /caution/);
  await $("#runBtn").click();
  assert.equal(lastCall(rt).op, "appraise");
  assert.equal(lastCall(rt).params.prior, LINEAGE[0].path);
  // Happy vowel declares no parent, so nothing is chosen for it and Run waits.
  await choose($("#exampleSel"), LINEAGE[2].path);
  assert.equal($("#param-prior").value, "");
  const before = rt.calls.length;
  await $("#runBtn").click();
  assert.equal(rt.calls.length, before, "Run computes nothing without a prior");
  assert.match($(".toast").textContent, /Choose a prior version/);
});

test("a prior that is not the declared parent carries a caution", async () => {
  const { ctx, $, rt } = await boot({}, lineageRuntime({ appraise: { verdict: "progressive", new_predictions: ["pred1"] } }));
  await choose($("#exampleSel"), LINEAGE[2].path);
  await opButton(ctx, "appraise").click();
  await choose($("#param-prior"), LINEAGE[0].path);
  assert.match($("#priorNote").className, /caution/);
  assert.match($("#priorNote").textContent, /not the declared parent/);
  assert.match($("#priorNote").textContent, /matched by id/);
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.prior, LINEAGE[0].path);
  assert.match($("#output").textContent, /not the declared parent/);
});

test("the note under the prior says whether the theory names a parent at all", async () => {
  // Happy vowel names no parent version, so nothing marks it as an amendment,
  // and the note must not take for granted that some version is amended.
  const rt = lineageRuntime();
  rt.loadTheoryText = async function (text, name) {
    this.active = name;
    return { id: "panic-network-2026-v3", title: "Panic v3", version: { id: "v3", parent_id: "v2.1" }, counts: {}, validation: { ok: true } };
  };
  const { ctx, $ } = await boot({}, rt);
  await choose($("#exampleSel"), LINEAGE[2].path);
  await opButton(ctx, "appraise").click();
  assert.equal($("#param-prior").value, "");
  assert.match($("#priorNote").textContent, /names no parent version\. To appraise it as an amendment,/);
  // An upload whose declared parent is not listed has that parent named.
  await upload($("#fileInput"), "panic-v3.theory.yaml", "id: panic-network-2026-v3\n");
  assert.equal($("#param-prior").value, "");
  assert.match($("#priorNote").textContent, /names version v2\.1 as its parent/);
});

test("a prior version can be uploaded, and the result names its file", async () => {
  const { ctx, $, rt } = await boot({}, lineageRuntime({ appraise: { verdict: "neutral" } }));
  await choose($("#exampleSel"), LINEAGE[2].path);
  await opButton(ctx, "appraise").click();
  assert.equal($("#priorFile"), null, "the file field appears only once upload is chosen");
  await choose($("#param-prior"), "upload");
  assert.ok($("#priorFile"), "a file field for the prior");
  const before = rt.calls.length;
  await $("#runBtn").click();
  assert.equal(rt.calls.length, before, "Run waits for the upload");
  // A file that cannot be read is reported, and nothing is uploaded.
  await upload($("#priorFile"), "broken.yaml", "- id: x\n");
  assert.match($("#paramsWrap").textContent, /Could not load broken\.yaml/);
  await $("#runBtn").click();
  assert.equal(rt.calls.length, before);
  await upload($("#priorFile"), "happy-v0.theory.yaml", "id: happy-vowel-manchester-2026\nversion: v0\n");
  assert.deepEqual(rt.priorLoads, ["broken.yaml", "happy-v0.theory.yaml"]);
  assert.match($("#paramsWrap").textContent, /happy-v0\.theory\.yaml/);
  await $("#runBtn").click();
  assert.equal(lastCall(rt).op, "appraise");
  assert.equal(lastCall(rt).params.prior, "upload");
  assert.match($("#output").textContent, /happy-v0\.theory\.yaml/);
});

test("Implied independencies is offered with its cycles choice, and a refusal reads as a result", async () => {
  const refusal = "implications requires an acyclic causal graph; cycle found: c_a -> c_b -> c_a; set cycles to 'sigma' to derive sigma-separation statements";
  const rt = lineageRuntime({ implications: { ok: false, message: refusal } });
  const { ctx, $ } = await boot({}, rt);
  const btn = opButton(ctx, "implications");
  assert.ok(btn, "the operation is offered");
  assert.match(btn.textContent, /Implied independencies/);
  await btn.click();
  assert.equal($("#param-cycles").value, "refuse");
  assert.deepEqual($("#param-cycles").children.map((o) => o.textContent), ["refuse", "sigma"]);
  assert.match($("#opHelp").textContent, /no direct effect/);
  assert.match($("#opHelp").textContent, /common cause/);
  assert.match($("#opHelp").textContent, /unique equilibrium/);
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.cycles, "refuse");
  assert.equal($("#output .error"), null, "a refusal is not shown as an error");
  assert.match($("#output").textContent, /cycle found: c_a -> c_b -> c_a/);
  assert.match($("#output .ri-interp").textContent, /sigma/);
  assert.notEqual($("#codePanel").style.display, "none", "the code that reproduces the refusal is shown");
});

test("implied independencies are listed with their conditioning sets", async () => {
  const result = {
    theory_id: "t", criterion: "m", acyclic: true, constructs: ["c_a", "c_b", "c_c"],
    n_edges: 2, n_bidirected: 0, feedback: [],
    implications: [{ a: "c_a", b: "c_c", given: ["c_b"], statement: "c_a _||_ c_c | c_b" }],
    n_implications: 1, inseparable: [],
  };
  const rt = lineageRuntime({ implications: { result } });
  const { ctx, $ } = await boot({}, rt);
  await opButton(ctx, "implications").click();
  await $("#runBtn").click();
  assert.match($("#output").textContent, /c_a _\|\|_ c_c \| c_b/);
  assert.match($("#output .ri-interp").textContent, /1 independence statement/);
});

test("a feedback loop is reported, and its proviso only where statements are derived", async () => {
  const sigma = (implications) => ({ result: {
    theory_id: "t", criterion: "sigma", acyclic: false, constructs: ["c_a", "c_b", "c_c"],
    n_edges: 3, n_bidirected: 0, feedback: [["c_a", "c_b"]], implications,
    n_implications: implications.length, inseparable: implications.length ? [] : [{ a: "c_a", b: "c_c" }],
  } });
  const stated = [{ a: "c_a", b: "c_c", given: ["c_b"], statement: "c_a _||_ c_c | c_b" }];
  for (const implications of [[], stated]) {
    const { ctx, $ } = await boot({}, lineageRuntime({ implications: sigma(implications) }));
    await opButton(ctx, "implications").click();
    await choose($("#param-cycles"), "sigma");
    await $("#runBtn").click();
    const interp = $("#output .ri-interp").textContent;
    assert.match(interp, /1 feedback loop \(c_a, c_b\)/);
    if (implications.length) assert.match(interp, /so the statements hold only if each loop has a unique equilibrium/);
    else assert.doesNotMatch(interp, /the statements hold only if/, "no statement, so no proviso on one");
  }
});

test("the example is saved by its path, and a saved index is mapped once", async () => {
  // The app used to save the example's position in the list, which an added
  // example would shift. A prior saved then may never have been chosen: that
  // app defaulted every theory to the first example.
  const saved = { "tf-app-py": JSON.stringify({ opId: "check", params: { prior: EXAMPLES[0].path }, ran: false, input: { mode: "example", index: 1 } }) };
  const { ctx, $ } = await boot({ stored: saved });
  assert.equal($("#exampleSel").value, EXAMPLES[1].path);
  assert.match($("#summaryWrap").textContent, /Title b\.theory\.yaml/);
  const now = JSON.parse(ctx.localStorage.getItem("tf-app-py"));
  assert.deepEqual(now.input, { mode: "example", path: EXAMPLES[1].path });
  assert.equal(now.params.prior, undefined, "the old default prior is dropped");
  // A path saved by this version is restored as it is.
  const again = await boot({ stored: { "tf-app-py": JSON.stringify(now) } });
  assert.equal(again.$("#exampleSel").value, EXAMPLES[1].path);
});

test("a session saved before the path format drops its prior, an uploaded theory's too", async () => {
  // Restoring the prior that app chose by default would run the appraisal
  // against an unrelated version again, as soon as the page loads.
  const saved = { "tf-app-py": JSON.stringify({ opId: "appraise", params: { prior: LINEAGE[0].path }, ran: true,
    input: { mode: "upload", name: "mine.theory.yaml", text: "id: mine\n" } }) };
  const rt = lineageRuntime();
  const { ctx, $ } = await boot({ stored: saved }, rt);
  assert.match($("#summaryWrap").textContent, /mine\.theory\.yaml/);
  assert.equal($("#param-prior").value, "", "the old default is gone");
  assert.equal(rt.calls.length, 0, "the appraisal is not run against it");
  // A prior chosen in this version's format is kept.
  const now = JSON.parse(ctx.localStorage.getItem("tf-app-py"));
  now.params.prior = LINEAGE[0].path;
  const again = await boot({ stored: { "tf-app-py": JSON.stringify(now) } }, lineageRuntime());
  assert.equal(again.$("#param-prior").value, LINEAGE[0].path);
});

test("the checklist's guide and reading say what pass, blocked and advisory mean", async () => {
  const report = {
    aggregate_score: 12, coverage: 1, gate: "advisory", n_blockers_failed: 2, maturity: "draft",
    items: [
      { id: "falsifiability", status: "fail", score: 0, weight: 1, severity_if_fail: "blocker" },
      { id: "precision", status: "fail", score: 0, weight: 1, severity_if_fail: "warning" },
      { id: "derivation_chain", status: "fail", score: 0, weight: 1, severity_if_fail: "blocker" },
    ],
  };
  const { $ } = await boot({}, lineageRuntime({ check: { report: Object.assign({ checklist_version: "3.1" }, report), svg: "<svg></svg>" } }));
  await $("#runBtn").click();
  const about = $("#output .ri-about").textContent, interp = $("#output .ri-interp").textContent;
  // The guide opens with what the score describes, for the checklist's own
  // version, and says to read the item statuses first.
  assert.ok(about.startsWith("The checklist score describes how completely the file states what checklist 3.1 asks for. " +
    "Most items read whether a field is filled in or how a prediction is labelled, and stated claims are checked against the causal graph. " +
    "Test outcomes are read only by the parsimony item, the weights are conventions, and no study has established what difference between two scores is meaningful. " +
    "The score does not show that the theory is true or well reasoned. Read the item statuses first"), about);
  assert.match(about, /The gate reports whether either blocking item failed: at least one prediction is typed point, interval or directional, and every prediction cites declared propositions whose graph entails any claim it states, with no stated phenomenon contradicted\. The labels are the author's and are not checked against the statements\./);
  assert.match(about, /The derivation chain reads each stated claim against the causal graph, diagnosticity sets a claim against a rival's propositions where both are stated, precision asks for two finite bounds and non-redundancy compares the words of the construct definitions\./);
  assert.match(about, /At draft maturity, the gate is advisory/);
  assert.doesNotMatch(about, /rigour|facets|quality/i);
  assert.match(interp, /^The checklist score is 12\./);
  assert.match(interp, /draft maturity/);
  assert.match(interp, /falsifiability and derivation_chain/);
  assert.doesNotMatch(interp, /clears the gate|out of 100/);
  // A blocked gate is read as what the blocking items give.
  const blocked = Object.assign({}, report, { gate: "blocked", maturity: "developing" });
  const b = await boot({}, lineageRuntime({ check: { report: blocked, svg: "<svg></svg>" } }));
  await b.$("#runBtn").click();
  assert.match(b.$("#output .ri-interp").textContent, /The blocking items falsifiability and derivation_chain fail, so the gate is blocked\./);
  // Without a version, the statement names no number.
  assert.match(b.$("#output .ri-about").textContent, /^The checklist score describes how completely the file states what the checklist asks for\./);
});

test("the checklist names the predictions it could not read, and a run under sigma shows no grid", async () => {
  const report = {
    aggregate_score: 85.9, aggregate_range: [82.1, 87.9], coverage: 0.92, gate: "pass", n_blockers_failed: 0, maturity: "developing",
    checklist_version: "3.1",
    items: [{ id: "derivation_chain", status: "warn", score: 0.75, weight: 0.08, severity_if_fail: "blocker", not_checked: ["pred3"] }],
  };
  const rt = lineageRuntime({ check: (params) => ({ report, svg: params.cycles === "sigma" ? null : "<svg></svg>" }) });
  const { ctx, $ } = await boot({}, rt);
  await opButton(ctx, "check").click();
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.cycles, "refuse");
  assert.match($("#output .ri-interp").textContent, /1 prediction \(pred3\) was not checked, since the causal graph has a feedback loop\. Set cycles to sigma/);
  assert.match($("#output").textContent, /Not checked \(feedback loop\)pred3/);
  assert.match($("#output").textContent, /Checklist grid/);
  await $("#param-cycles").dispatch("change", { target: { value: "sigma" } });
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.cycles, "sigma");
  assert.match($("#output").textContent, /The package draws the grid with cycles refuse, its default, so it is not drawn for cycles sigma\./);
  assert.match($("#output").textContent, /Cyclessigma/);
  // A package whose check() takes no cycles reads the default whatever was
  // asked, and the runtime says so: the grid is drawn and the reading named.
  const old = lineageRuntime({ check: () => ({ report, svg: "<svg></svg>", cycles: "refuse" }) });
  const o = await boot({}, old);
  await opButton(o.ctx, "check").click();
  await o.$("#param-cycles").dispatch("change", { target: { value: "sigma" } });
  await o.$("#runBtn").click();
  assert.match(o.$("#output").textContent, /Checklist grid/);
  assert.match(o.$("#output").textContent, /Cyclesrefuse/);
  assert.doesNotMatch(o.$("#output").textContent, /not drawn for cycles sigma/);
});

test("whole-number parameters are rounded before they are run", async () => {
  const sim = { result: { states: ["c_a"], steps: 3, dt: 0.15, method: "exact", trajectory: [[1], [1], [1], [1]] } };
  const lit = { result: { n_records: 0, keywords: [], themes: [], keyword_cooccurrence: [], co_citation: [] }, dots: {} };
  const rt = lineageRuntime({ simulate: sim, litmap: lit });
  const { ctx, $ } = await boot({}, rt);
  await opButton(ctx, "simulate").click();
  await $("#param-steps").dispatch("input", { target: { value: "2.6" } });
  await $("#param-dt").dispatch("input", { target: { value: "0.15" } });
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.steps, 3);
  assert.equal(lastCall(rt).params.dt, 0.15);
  await opButton(ctx, "litmap").click();
  await $("#param-min_link").dispatch("input", { target: { value: "2.4" } });
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.min_link, 2);
});

// ---- the test record ------------------------------------------------------

test("the preregistration is a hypotheses section to complete, and its reading counts the tested ones", async () => {
  // The guide called the output ready to timestamp before data collection,
  // and the reading said it preregistered every hypothesis, those a test had
  // already met included.
  const text = (records) => "# Preregistration: T\n\n## Hypotheses\n" +
    records.map((r, i) => (i + 1) + ". [point] Claim. (derives from: p1)\n   - Test record: " + r + "\n").join("") +
    "\n## Severity (pre-data rubric of claim form)\n";
  const cases = [
    [["untested", "untested"], "The document lists 2 hypotheses, none of them tested yet."],
    [["already tested: passed (2026-05-01, registered osf.io/abcde)", "untested"],
      "The document lists 2 hypotheses, of which one has already been tested."],
    [["already tested: passed", "already tested: failed"], "The document lists 2 hypotheses, all of them already tested."],
    [[], "The theory states no prediction, so the document lists no hypothesis."],
  ];
  for (const [records, reading] of cases) {
    const { ctx, $ } = await boot({}, lineageRuntime({ preregister: { text: text(records) } }));
    await opButton(ctx, "preregister").click();
    assert.match($("#opHelp").textContent, /theory and hypotheses sections of a preregistration/);
    await $("#runBtn").click();
    const about = $("#output .ri-about").textContent;
    assert.match(about, /design, sampling plan, analysis plan and inference criteria/);
    assert.doesNotMatch(about, /ready to timestamp/);
    assert.equal($("#output .ri-interp").textContent, reading);
  }
});

test("the pipeline's reading gives each recorded outcome a node of its own", async () => {
  // The diagram now draws every outcome of a replicated prediction, where the
  // reading spoke of one outcome per prediction. An SVG answer needs no
  // Graphviz, so the reading can be checked here.
  const { ctx, $ } = await boot({}, lineageRuntime({ diagram: { ir: "<svg></svg>" } }));
  await opButton(ctx, "diagram").click();
  await choose($("#param-type"), "pipeline");
  await $("#runBtn").click();
  assert.equal($("#output .ri-interp").textContent,
    "Each prediction linked to its recorded test outcomes, one node for each.");
});

test("the code panel says the code reproduces the result with the installed package", async () => {
  const { $ } = await boot();
  assert.equal($("#codePanel .note").textContent, "Paste into Python to reproduce this result with the installed package.");
});

test("the help lists each operation as 'Label: description' and the title names the language", async () => {
  const { ctx, $ } = await boot();
  assert.equal(ctx.document.title, "theoryforge (Python): interactive app");
  await $("#helpBtn").click();
  const items = ctx.document.querySelectorAll("#tfModal ul.help-ops li");
  assert.ok(items.length > 0, "the help lists the operations");
  for (const li of items) {
    assert.match(li.textContent, /^[^:]+: \S/);
    assert.equal(li.querySelector("b"), null, "no label is set in bold");
  }
  assert.match(items[0].textContent, /^Checklist: Reads the file against the 12 items of the checklist/);
  for (const li of items) assert.doesNotMatch(li.textContent, /rigour checklist|Audit dossier|Severity rubric/i);
});

test("the help lists every work that the help texts and the result guides cite", async () => {
  const { ctx, $ } = await boot();
  await $("#helpBtn").click();
  const refs = [...ctx.document.querySelectorAll("#tfModal ul.help-refs li")].map((li) => li.textContent);
  assert.ok(refs.length > 0, "the help lists the works cited");
  // Each author-year citation in the source, such as (Lakatos, 1970) or, for a
  // work republished later, (Verma & Pearl, 1990/2022).
  const CITE = /\(([A-Z][A-Za-z'-]+)( et al\.| & [A-Z][A-Za-z -]+)?, (\d{4})(?:\/(\d{4}))?/;
  const cites = readFileSync(CORE, "utf8").match(new RegExp(CITE.source, "g")) || [];
  assert.ok(cites.length >= 6, "the help texts cite works");
  for (const c of cites) {
    const [, author, , year, reprint] = c.match(CITE);
    const listed = refs.filter((r) => r.startsWith(author + ", "));
    assert.ok(listed.some((r) => reprint
      ? r.includes("(" + reprint + ")") && r.includes("Original work published " + year)
      : r.includes("(" + year + ")") && !r.includes("Original work published")), c + " has an entry");
  }
  for (const r of refs) assert.match(r, / https:\/\/doi\.org\/10\.\S+( \(Original work published \d{4}\))?$/);
});

// ---- groups, chips, the selector, errors and the status region -------------

test("the operations stand in groups, each with a plain-language subtitle", async () => {
  const { ctx } = await boot();
  const groups = ctx.document.querySelectorAll(".opgroup");
  assert.equal(groups.length, ctx.TF.GROUPS.length);
  for (const g of groups) {
    assert.ok(g.querySelector("h3").textContent.length > 0);
    assert.match(g.querySelector(".gs").textContent, /^[A-Z].*\.$/);
  }
  const inGroups = groups.flatMap((g) => g.querySelectorAll(".op").map((b) => b.getAttribute("data-op")));
  const plain = (v) => JSON.parse(JSON.stringify(v));
  assert.deepEqual(plain(inGroups.slice().sort()), plain(ctx.TF.OPS.map((o) => o.id).sort()));
  for (const op of ctx.TF.OPS) assert.ok(ctx.TF.GROUPS.some((g) => g.id === op.group), op.id);
});

test("the summary counts in the singular when there is one", async () => {
  const rt = stubRuntime({
    async loadExample(p) {
      this.active = p;
      return { id: "one", title: "One", counts: { constructs: 1, propositions: 1, predictions: 2, alternatives: 0, assumptions: 1, phenomena: 1 },
        validation: { ok: true }, check: { score: 41.5, gate: "pass" }, hash: "sha256:" + "ab".repeat(32) };
    },
  });
  const { $ } = await boot({}, rt);
  // The stand-in DOM keeps innerHTML as written.
  const text = $("#summaryWrap .chips").textContent.replace(/<\/?b>/g, "");
  assert.match(text, /1 construct(?!s)/);
  assert.match(text, /1 assumption(?!s)/);
  assert.match(text, /1 phenomenon/);
  assert.match(text, /2 predictions/);
  assert.match(text, /checklist 41\.5 · gate pass/);
  assert.doesNotMatch(text, /\/ 100/);
  // The chip's title gives the first and the last sentence of what the score
  // describes.
  assert.equal($("#summaryScore").getAttribute("title"),
    "The checklist score describes how completely the file states what the checklist asks for. The score does not show that the theory is true or well reasoned.");
  assert.match($("#summaryWrap .hash").textContent, /sha256:abababababab…ababab/);
});

test("after an upload the selector names it, and the example shown before can be loaded again", async () => {
  const { $, rt } = await boot();
  await upload($("#fileInput"), "mine.theory.yaml", "id: mine\n");
  assert.equal($("#exampleSel").value, "");
  assert.equal($("#exampleOwn").textContent, "Uploaded: mine.theory.yaml");
  assert.equal($("#exampleOwn").hasAttribute("hidden"), false);
  await $("#exampleSel").dispatch("change", { target: { value: EXAMPLES[0].path } });
  assert.equal(rt.active, EXAMPLES[0].path);
  assert.equal($("#exampleOwn").hasAttribute("hidden"), true);
});

test("an error's headline names the error and the user's file, not a caret or an in-browser path", async () => {
  const yamlError = "PythonError: Traceback (most recent call last):\n  File \"/pkg/_app.py\", line 80, in load\n" +
    "yaml.scanner.ScannerError: mapping values are not allowed here\n  in \"/pkg/input.yaml\", line 2, column 9:\n    foo: bar: baz\n            ^";
  const rt = stubRuntime({
    fileNames: { "/pkg/input.yaml": "my theory.yaml" },
    async loadTheoryText() { throw new Error(yamlError); },
  });
  const { $ } = await boot({}, rt);
  await upload($("#fileInput"), "my theory.yaml", "foo: bar: baz\n");
  assert.equal($("#summaryWrap .error .last").textContent,
    "yaml.scanner.ScannerError: mapping values are not allowed here (line 2, column 9)");
  const full = $("#summaryWrap .error details").textContent;
  assert.match(full, /in "my theory\.yaml", line 2/);
  assert.doesNotMatch(full, /\/pkg\/input/);
  const { headline } = (await boot()).ctx.TF.util;
  assert.equal(headline(["Error in tf_read(p) :", "(input.yaml) Scanner error: mapping values are not allowed in this context at line 2, column 9"]),
    "Error in tf_read(p) : (input.yaml) Scanner error: mapping values are not allowed in this context at line 2, column 9");
  assert.equal(headline(["something went wrong", "^"]), "something went wrong");
  // webR words a condition raised with call. = FALSE as "Error in unknown
  // source: ", where R prints "Error: ", which the headline still finds on a
  // message of several lines.
  const { cleanMessage } = (await boot()).ctx.TF.util;
  const parse = cleanMessage("Error in unknown source: parse error: invalid object key (must be a string)\n  {\"a\": 1,}\n  (right here) ------^");
  assert.equal(headline(parse.split("\n").map((l) => l.trim())), "Error: parse error: invalid object key (must be a string)");
  assert.equal(cleanMessage("Error in unknown source: check requires boolean test outcomes"), "Error: check requires boolean test outcomes");
});

test("a run is announced in a status region, and the result panel is no live region", async () => {
  const { $ } = await boot();
  assert.equal($("#output").getAttribute("aria-live"), null);
  assert.equal($("#liveStatus").getAttribute("role"), "status");
  await $("#runBtn").click();
  await until(() => $("#liveStatus").textContent === "Checklist finished", "the announcement");
  assert.equal($("#liveStatus").textContent, "Checklist finished");
});

test("a fetch that is not ok is refused with the file's name, and Graphviz points convert to pixels", async () => {
  const ctx = makeWindow();
  runScript(ctx, CORE);
  ctx.fetch = async () => ({ ok: false, status: 404, json: async () => ({}), arrayBuffer: async () => new ArrayBuffer(0) });
  await assert.rejects(ctx.TF.util.fetchJson("vendor/manifest.json"), /Could not fetch vendor\/manifest\.json \(HTTP 404\)/);
  await assert.rejects(ctx.TF.util.fetchBytes("vendor/R/core.R"), /HTTP 404/);
  // A request that fails before any answer names the file too.
  ctx.fetch = async () => { throw new TypeError("Failed to fetch"); };
  await assert.rejects(ctx.TF.util.fetchJson("vendor/manifest.json"), /^Error: Could not fetch vendor\/manifest\.json \(Failed to fetch\)$/);
  const { cssPx } = ctx.TF.util;
  assert.equal(cssPx("72pt"), 96);
  assert.equal(cssPx("1in"), 96);
  assert.equal(cssPx("100"), 100);
  assert.equal(cssPx("12.5px"), 12.5);
  assert.equal(cssPx("auto"), 0);
});

// ---- the new operations ------------------------------------------------------

test("the check view shows the checklist score and its range, unpadded, where the checklist gives one", async () => {
  const report = { aggregate_score: 87.1, aggregate_range: [83.5, 89.2], coverage: 1, gate: "pass", n_blockers_failed: 0, maturity: "testing", items: [] };
  const { $ } = await boot({}, lineageRuntime({ check: { report, svg: "<svg></svg>" } }));
  await $("#runBtn").click();
  assert.match($("#output").textContent, /Checklist score87\.1 \(83\.5 to 89\.2 with equal weights or one weight halved or doubled\)/);
  assert.match($("#output .ri-interp").textContent, /^The checklist score is 87\.1\. .*No blocking item fails, so the gate passes\./);
  assert.doesNotMatch($("#output").textContent, /87\.10|83\.50|89\.20|\/ 100|Aggregate score|Rigour/);
});

test("post-data severity reads each outcome in words and writes a value that rounds to 1 as a bound", async () => {
  const rows = [{ prediction_id: "pred2", outcome: 0, lower: 20, upper: 60, estimate: 41, se: 6, severity: 1 },
    { prediction_id: "pred3", outcome: 1, lower: 0.2, upper: null, estimate: 0.1, se: 0.1, severity: 0.159 }];
  const { ctx, $ } = await boot({}, lineageRuntime({ post_severity: { result: rows } }));
  await opButton(ctx, "post_severity").click();
  await $("#runBtn").click();
  const text = $("#output").textContent;
  assert.match(text, /> 0\.999/);
  assert.match(text, /more than 999 times in 1,000/);
  assert.match(text, /Had the true value lain at the lower bound of 0\.2, an estimate lower than 0\.1 would have come up 15\.9 times in 100\./);
  assert.match(text, /outside the region the claim allows/);
  assert.match($("#output .ri-interp").textContent, /^2 test outcomes carry an estimate, a standard error and a prediction with bounds\./);
});

test("what the graph entails lists each claim with its verdict", async () => {
  const result = { theory_id: "t", criterion: "m", acyclic: true, feedback: [], counts: { entailed: 1, contradicted: 1, undetermined: 0, not_evaluated: 0 },
    claims: [
      { source: "prediction", id: "pred1", kind: "effect", x: "a", y: "b", given: [], sign: "positive", derived: "positive", verdict: "entailed", basis: "paths_agree", faithfulness: false, via: ["p1"], identified: true, adjustment: [] },
      { source: "phenomenon", id: "ph1", kind: "association", x: "a", y: "c", given: "b", sign: "zero", derived: "nonzero", verdict: "contradicted", basis: "connected", faithfulness: true, via: [], identified: null, adjustment: null },
    ] };
  const { ctx, $ } = await boot({}, lineageRuntime({ entailments: { result } }));
  await opButton(ctx, "entailments").click();
  assert.deepEqual($("#param-cycles").children.map((o) => o.textContent), ["refuse", "sigma"]);
  await $("#runBtn").click();
  const text = $("#output").textContent;
  assert.match(text, /effect of a on b: positive/);
  assert.match(text, /association of a and c given b: zero \(assumes no exact cancellation\)/);
  assert.match($("#output .ri-interp").textContent, /state 2 claims\. The causal graph entails 1 and contradicts 1\./);
});

test("Compare with a rival offers the alternatives that state propositions, and an upload otherwise", async () => {
  const rt = lineageRuntime({ discriminate: { result: { rival_id: "alt_b", criterion: "m", evaluated: true, shared: ["a", "b"], only_theory: [], only_rival: [],
    markov_equivalent: false, independencies: [], effects: [{ x: "a", y: "b", theory: "positive", rival: "negative", decisive: true }], associations: [],
    claims: [{ source: "prediction", id: "pred1", theory: "entailed", rival: "contradicted", discriminates: true }],
    counts: { discriminating_claims: 1, independencies: 0, decisive_effects: 1, decisive_associations: 0 } } } });
  const base = rt.loadExample;
  rt.loadExample = async function (p) {
    const s = await base.call(this, p);
    s.alternatives = p === LINEAGE[0].path ? [{ id: "alt_a", label: "A", propositions: 0 }, { id: "alt_b", label: "B", propositions: 2 }] : [];
    return s;
  };
  const { ctx, $ } = await boot({}, rt);
  await opButton(ctx, "discriminate").click();
  assert.deepEqual($("#param-rival").children.map((o) => o.getAttribute("value")), ["", "alt_b", "upload"]);
  assert.equal($("#param-rival").value, "alt_b");
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.rival, "alt_b");
  assert.match($("#output").textContent, /The theory's claims under each graph/);
  assert.match($("#output .ri-interp").textContent, /read 1 claim of the theory in opposite ways/);
  // A theory with no such alternative waits for an uploaded rival.
  await choose($("#exampleSel"), LINEAGE[2].path);
  assert.equal($("#param-rival").value, "");
  // Back on a theory with rivals, the first of them is chosen again.
  await choose($("#exampleSel"), LINEAGE[0].path);
  assert.equal($("#param-rival").value, "alt_b");
  await choose($("#exampleSel"), LINEAGE[2].path);
  const before = rt.calls.length;
  await $("#runBtn").click();
  assert.equal(rt.calls.length, before);
  assert.match($(".toast").textContent, /Upload a rival theory/);
});

test("an impulse starts in a construct of the theory, and the uniform start's value is hidden for it", async () => {
  const rt = lineageRuntime({ simulate: { result: { states: ["a", "b"], steps: 2, dt: 0.1, method: "exact", initial_state: [1, 0],
    assumed_positive: ["p2"], ignored: [], opposed: [], trajectory: [[1, 0], [0.9, 0.1], [0.8, 0.2]] } } });
  const base = rt.loadExample;
  rt.loadExample = async function (p) { const s = await base.call(this, p); s.constructs = [{ id: "a", label: "A" }, { id: "b", label: "B" }]; return s; };
  const { ctx, $ } = await boot({}, rt);
  await opButton(ctx, "simulate").click();
  assert.ok($("#param-init"));
  assert.equal($("#param-impulse"), null);
  await choose($("#param-start"), "impulse");
  assert.equal($("#param-init"), null);
  assert.equal($("#param-impulse").value, "a");
  await choose($("#param-impulse"), "b");
  await $("#runBtn").click();
  assert.equal(lastCall(rt).params.start, "impulse");
  assert.equal(lastCall(rt).params.impulse, "b");
  assert.match($("#output").textContent, /Assumed positivep2/);
  assert.match($("#output .ri-interp").textContent, /from an impulse in b/);
});

test("the literature operations offer both bundled corpora and an upload", async () => {
  const rt = lineageRuntime({ litmap: { result: { n_records: 0, keywords: [], themes: [], keyword_cooccurrence: [], co_citation: [] }, dots: {} } });
  rt.corpora = [{ key: "demo", name: "Demo corpus", path: "fixtures/d.yaml" }, { key: "openalex", name: "OpenAlex corpus", path: "fixtures/o.yaml", desc: "Frozen." }];
  const base = rt.init;
  rt.init = async function () { const i = await base.call(this); i.corpora = this.corpora; return i; };
  const { ctx, $ } = await boot({}, rt);
  await opButton(ctx, "litmap").click();
  assert.deepEqual($("#param-corpus").children.map((o) => o.textContent), ["Demo corpus", "OpenAlex corpus", "Upload a corpus…"]);
  assert.equal($("#param-method").value, "simple_centres");
  await choose($("#param-corpus"), "openalex");
  assert.match($("#corpusMore").textContent, /Frozen\./);
  await $("#runBtn").click();
  assert.deepEqual([lastCall(rt).params.corpus, lastCall(rt).params.min_df, lastCall(rt).params.max_df], ["openalex", 1, 1]);
  await choose($("#param-corpus"), "upload");
  assert.ok($("#corpusFile"));
  const before = rt.calls.length;
  await $("#runBtn").click();
  assert.equal(rt.calls.length, before, "Run waits for the upload");
});

// ---- links, the content hash, figures that fail and small numbers -----------

const SHARE = path.join(here, "..", "shared", "share.js");
async function bootWithLink(state, opts, rt) {
  const enc = makeWindow();
  runScript(enc, SHARE);
  const hash = "#s=" + await enc.__tfShare.encode(state);
  const ctx = makeWindow(Object.assign({ hash }, opts || {}));
  runScript(ctx, CORE);
  runScript(ctx, SHARE);
  rt = rt || stubRuntime();
  await ctx.TF.start(rt);
  return { ctx, rt, $: (s) => ctx.document.querySelector(s), enc: (st) => enc.__tfShare.encode(st) };
}
const runsOf = (rt) => { rt.ran = []; const run = rt.run.bind(rt); rt.run = async (op, p) => { rt.ran.push(op); return run(op, p); }; return rt; };

test("a link whose theory cannot be used, or of a newer format, says so and runs nothing", async () => {
  for (const [theory, note] of [
    [{ name: "x.yaml", text: 5 }, /Could not restore x\.yaml; showing Theory A instead/],
    [{}, /Could not restore your theory/],
    [{ example: "" }, /Could not restore your theory/],
    [{ name: "x.yaml", text: null }, /Could not restore x\.yaml/],
  ]) {
    const rt = runsOf(stubRuntime({ async editText() { throw new Error("cannot read"); } }));
    const { ctx, $ } = await bootWithLink({ v: 1, op: "check", run: true, theory }, {}, rt);
    assert.match($(".toast").textContent, note, JSON.stringify(theory));
    assert.deepEqual(rt.ran, [], "nothing runs on the default example");
    assert.equal(ctx.location.hash, "", "the link is taken out of the address");
  }
  const rt = runsOf(stubRuntime());
  const { $ } = await bootWithLink({ v: 2, op: "check", run: true, theory: { example: EXAMPLES[1].path } }, {}, rt);
  assert.equal($(".toast").textContent, "This link was made by a newer version of the app, so the saved session is shown instead");
  assert.deepEqual(rt.ran, []);
});

test("a link asks before it replaces an edited theory, and a reload of the tab's own link does not", async () => {
  const edited = { v: 2, opId: "check", params: {}, ran: false, input: { mode: "edited", name: "mine.yaml", format: "yaml", text: "id: mine\n" } };
  const stored = { "tf-app-py": JSON.stringify(edited) };
  const rt = stubRuntime({ async editText(text, f, name) { this.active = name; return Object.assign(summaryOf("mine", { ok: true }), { texts: {} }); },
    async writeText() { return "id: mine\n"; } });
  const questions = [];
  const { ctx, $ } = await bootWithLink({ v: 1, op: "check", run: false, theory: { example: EXAMPLES[1].path } },
    { stored, confirm: (q) => { questions.push(q); return false; } }, rt);
  assert.equal(questions[0], "This link opens Theory B. Edits to mine.yaml that you have not saved will be lost. Open the link?");
  assert.equal($(".toast").textContent, "The link was not opened, so your edited theory is shown");
  assert.equal(rt.active, "mine.yaml");
  assert.equal(JSON.parse(ctx.localStorage.getItem("tf-app-py")).input.text, "id: mine\n", "the saved edits are kept");
  assert.equal(ctx.location.hash, "");
  // The tab's own link holds the saved text, so a reload asks nothing.
  const again = [];
  const rt2 = stubRuntime({ async editText(text, f, name) { this.active = name; return Object.assign(summaryOf("mine", { ok: true }), { texts: {} }); },
    async writeText() { return "id: mine\n"; } });
  await bootWithLink({ v: 1, op: "check", run: false, theory: { name: "mine.yaml", format: "yaml", text: "id: mine\n" } },
    { stored, confirm: (q) => { again.push(q); return false; } }, rt2);
  assert.deepEqual(again, []);
  assert.equal(rt2.active, "mine.yaml");
});

test("a link pasted into an open tab opens there, and the skip link leaves the address alone", async () => {
  const { ctx, rt, $, enc } = await bootWithLink({ v: 1, op: "check", run: false, theory: { example: EXAMPLES[0].path } });
  runsOf(rt);
  const pasted = "#s=" + await enc({ v: 1, op: "validate", run: true, theory: { example: EXAMPLES[1].path } });
  ctx.location.hash = pasted;
  await ctx.__fire("hashchange");
  assert.equal(rt.active, EXAMPLES[1].path);
  assert.equal($("#exampleSel").value, EXAMPLES[1].path);
  assert.equal(ctx.document.querySelectorAll(".op.active")[0].getAttribute("data-op"), "validate");
  assert.deepEqual(rt.ran, ["validate"]);
  // A fragment the app wrote itself opens nothing.
  await until(() => ctx.location.hash !== pasted && ctx.location.hash.startsWith("#s="), "the app's own link");
  const own = ctx.location.hash;
  rt.ran = [];
  await ctx.__fire("hashchange");
  assert.equal(ctx.location.hash, own);
  assert.deepEqual(rt.ran, []);
  // The skip link moves the focus and keeps the link in the address.
  let prevented = false;
  await $(".skip-link").dispatch("click", { preventDefault() { prevented = true; } });
  assert.ok(prevented);
  assert.equal(ctx.document.activeElement, $("#main"));
  assert.equal(ctx.location.hash, own);
});

test("the content hash arrives after the load, from a call of its own, and an error is shown", async () => {
  const rt = stubRuntime({ hashes: 0, async contentHash() { this.hashes++; return this.active === EXAMPLES[1].path ? { error: "MemoryError" } : { hash: "sha256:" + "cd".repeat(32) }; } });
  const { ctx, $ } = await boot({}, rt);
  await until(() => rt.hashes === 1 && /sha256/.test($("#summaryHash").textContent), "the hash");
  assert.match($("#summaryHash").textContent, /sha256:cdcdcdcdcdcd…cdcdcd/);
  await choose($("#exampleSel"), EXAMPLES[1].path);
  await until(() => /not computed/.test($("#summaryHash").textContent), "the hash's error");
  assert.equal($("#summaryHash").textContent, "Content hash not computed: MemoryError");
  assert.ok(ctx);
});

test("a figure Graphviz cannot draw leaves the rest of the result and says why", async () => {
  const rt = stubRuntime({ async run() { return { raw: { ir: "digraph nomological_net {\n}\n" }, code: "#" }; } });
  const { ctx, $ } = await boot({}, rt);
  opButton(ctx, "diagram").click();
  await $("#runBtn").click();
  const out = $("#output").textContent;
  assert.match(out, /The figure could not be drawn: .*Run the operation again to try once more\./);
  assert.match(out, /Intermediate representation \(Graphviz DOT\)/, "the IR is still shown");
  assert.doesNotMatch(out, /Operation failed/);
});

test("problems are counted from the packages' list, so a value with a semicolon stays one problem", async () => {
  const one = { ok: false, message: "invalid theory object: proposition[0] to 'a; b' is not a known construct",
    problems: ["proposition[0] to 'a; b' is not a known construct"] };
  const rt = stubRuntime({ async loadExample(p) { this.active = p; return summaryOf("a", one); },
    async run(op) { return { raw: op === "validate" ? one : {}, code: "#" }; } });
  const { ctx, $ } = await boot({}, rt);
  assert.equal($("#summaryWrap .chip.invalid").textContent, "1 problem");
  opButton(ctx, "validate").click();
  await $("#runBtn").click();
  assert.deepEqual($("#output .err-list").querySelectorAll("li").map((li) => li.textContent), ["proposition[0] to 'a; b' is not a known construct"]);
  // Without a list, the message is split at "; " only, so "x;y" stays whole.
  assert.deepEqual([...ctx.TF.util.problemList("invalid theory object: duplicate construct id: x;y; construct[1] missing/empty label")],
    ["duplicate construct id: x;y", "construct[1] missing/empty label"]);
});

test("the help dialog has one banner, an h2 title and headings that follow it", async () => {
  const { $ } = await boot();
  await $("#helpBtn").click();
  const modal = $("#tfModal .modal");
  assert.equal(modal.querySelectorAll("header").length, 0, "the dialog's head is no banner landmark");
  assert.equal($("#tfModalTitle").tagName, "H2");
  assert.equal(modal.querySelectorAll("h4").length, 6, "the groups are h4 under the h3 sections");
  assert.equal(modal.querySelectorAll("h3").length, 4);
  assert.equal(modal.querySelectorAll("h5").length, 0);
});

test("a small negative value is written 0, not -0", async () => {
  const rt = stubRuntime({ async run() {
    return { raw: { result: { states: ["a", "b"], trajectory: [[1, 0], [0.951, -0.000159]], steps: 1, dt: 0.1, method: "exact", initial_state: [-0.004, 0] } }, code: "#" };
  } });
  const { ctx, $ } = await boot({}, rt);
  opButton(ctx, "simulate").click();
  await $("#runBtn").click();
  const cells = ctx.document.querySelectorAll("td").map((td) => td.textContent);
  assert.ok(!cells.includes("-0"), cells.join("|"));
  // Values are written as the card writes the score, so -0.004 keeps its
  // sign and its digits, and a value that rounds to zero is 0.
  assert.match($("#output").textContent, /a -0\.004, b 0/);
  assert.doesNotMatch($("#output .figure").textContent, /-0(\.0+)?(?![.\d])/);
});

// ---- the card's score and hash, reloads, links while busy, refusals, figures --

const tick = (ms) => new Promise((r) => setTimeout(r, ms || 5));

// A runtime whose score waits until the test releases it, and which records
// the theory each score and each hash was asked for. An upload whose text
// holds "large" counts 4,000 constructs and takes 200,000 characters as JSON.
function slowScoreRuntime(extra) {
  const rt = stubRuntime(Object.assign({
    scored: [], hashed: [], waiting: [],
    async contentHash() { this.hashed.push(this.active); return { hash: "sha256:" + "ef".repeat(32) }; },
    async score() {
      this.scored.push(this.active);
      await new Promise((r) => this.waiting.push(r));
      return { score: 61.5, gate: "pass", failed: [], warned: ["precision"] };
    },
    release() { for (const r of this.waiting.splice(0)) r(); },
    async loadTheoryText(text, name) {
      this.active = name;
      return Object.assign(summaryOf(name, { ok: true }), { counts: { constructs: /large/.test(text) ? 4000 : 3 }, chars: /large/.test(text) ? 200000 : 900 });
    },
  }, extra || {}));
  return rt;
}
const scoreChipText = ($) => ($("#summaryScore") ? $("#summaryScore").textContent.replace(/<\/?b>/g, "") : "");

test("the card shows before the checklist has run, and each text is scored once", async () => {
  const rt = slowScoreRuntime();
  const { ctx, $ } = await boot({}, rt);
  assert.ok($("#boot").classList.contains("hidden"), "the start did not wait for the score");
  assert.match($("#summaryWrap .ttl").textContent, /Title a\.theory\.yaml/);
  assert.equal(scoreChipText($), "scoring…");
  await until(() => rt.waiting.length > 0, "the score call");
  assert.deepEqual(rt.scored, [EXAMPLES[0].path], "the score is asked once the card is shown");
  rt.release();
  await until(() => scoreChipText($) === "checklist 61.5 · gate pass" && rt.hashed.length === 1, "the first score and hash");
  await choose($("#exampleSel"), EXAMPLES[1].path);
  await until(() => rt.waiting.length > 0, "the second score call");
  rt.release();
  await until(() => scoreChipText($) === "checklist 61.5 · gate pass" && rt.hashed.length === 2, "the second score and hash");
  assert.deepEqual(rt.scored, [EXAMPLES[0].path, EXAMPLES[1].path]);
  // Back on the first example, its score is known.
  await choose($("#exampleSel"), EXAMPLES[0].path);
  await tick(100);
  assert.deepEqual(rt.scored, [EXAMPLES[0].path, EXAMPLES[1].path], "no second score for the same text");
  assert.equal(scoreChipText($), "checklist 61.5 · gate pass");
  assert.deepEqual(rt.hashed, [EXAMPLES[0].path, EXAMPLES[1].path], "no second hash either");
  assert.match($("#summaryHash").textContent, /sha256:efefefefefef…efefef/);
  assert.ok(ctx);
});

test("a large theory is scored only on request, and its last operation is not run again as it opens", async () => {
  const rt = runsOf(slowScoreRuntime());
  const { ctx, $ } = await boot({}, rt);
  await until(() => rt.waiting.length > 0, "the first score call");
  rt.release();
  await until(() => scoreChipText($) === "checklist 61.5 · gate pass" && rt.hashed.length === 1, "the first score and hash");
  await upload($("#fileInput"), "large.theory.yaml", "id: large\n");
  await tick(100);
  assert.deepEqual(rt.scored, [EXAMPLES[0].path], "the large theory is not scored unasked");
  assert.deepEqual(rt.hashed, [EXAMPLES[0].path], "nor hashed");
  assert.equal(scoreChipText($), "not scored score it");
  assert.match($("#summaryScore").getAttribute("title"), /4,000 constructs, propositions and predictions, more than the 300/);
  assert.equal($("#summaryHash").textContent, "Content hash not computed for a theory this long compute it");
  assert.match($("#summaryHash .hk").getAttribute("title"), /^Written as JSON, this theory takes 200,000 characters, more than the 50,000/);
  // Pressed, the button is replaced, and the focus moves to what replaced it.
  const compute = $("#summaryHash button");
  compute.focus();
  await compute.click();
  await until(() => $("#liveStatus").textContent === "Content hash computed", "the announcement of the hash");
  assert.deepEqual(rt.hashed, [EXAMPLES[0].path, "large.theory.yaml"]);
  assert.match($("#summaryHash").textContent, /^Content hash sha256:efef/);
  assert.equal(ctx.document.activeElement, $("#summaryHash button"), "the focus is on the hash's copy button");
  assert.equal($("#liveStatus").textContent, "Content hash computed");
  const button = $("#summaryScore button");
  button.focus();
  await button.click();
  assert.equal(scoreChipText($), "scoring…");
  assert.equal(ctx.document.activeElement, $("#summaryScore"), "the focus stays on the card");
  assert.match($(".toast").textContent, /^Scoring Title large\.theory\.yaml with the checklist/);
  await until(() => rt.waiting.length > 0, "the requested score call");
  assert.deepEqual(rt.scored, [EXAMPLES[0].path, "large.theory.yaml"]);
  rt.release();
  await until(() => $("#liveStatus").textContent === "Checklist score 61.5, gate pass", "the announcement of the score");
  assert.equal(scoreChipText($), "checklist 61.5 · gate pass");
  assert.equal(ctx.document.activeElement, $("#summaryScore"));
  assert.equal($("#liveStatus").textContent, "Checklist score 61.5, gate pass");
  // A session saved with a large theory and a run does not run it as it opens.
  const stored = { "tf-app-py": JSON.stringify({ v: 2, opId: "check", params: {}, ran: true,
    input: { mode: "upload", name: "large.theory.yaml", text: "id: large\n" } }) };
  const rt2 = runsOf(slowScoreRuntime());
  const again = await boot({ stored }, rt2);
  assert.deepEqual(rt2.ran, []);
  assert.equal(again.$(".toast").textContent, "The theory is large, so the Checklist operation was not run. Press Run to run it");
  await tick(100);
  assert.deepEqual(rt2.scored, []);
});

test("a user who moves on while a requested score or hash is computed keeps the focus", async () => {
  const rt = slowScoreRuntime();
  const { ctx, $ } = await boot({}, rt);
  await until(() => rt.waiting.length > 0, "the first score call");
  rt.release();
  await until(() => scoreChipText($) === "checklist 61.5 · gate pass" && rt.hashed.length === 1, "the first score and hash");
  await upload($("#fileInput"), "large.theory.yaml", "id: large\n");
  const button = $("#summaryScore button");
  button.focus();
  await button.click();
  await until(() => rt.waiting.length > 0, "the requested score call");
  // The user goes on to the example selector before the score arrives.
  $("#exampleSel").focus();
  rt.release();
  await until(() => $("#liveStatus").textContent === "Checklist score 61.5, gate pass", "the announcement of the score");
  assert.equal(ctx.document.activeElement, $("#exampleSel"), "the focus stays where the user put it");
  const compute = $("#summaryHash button");
  compute.focus();
  await compute.click();
  $("#runBtn").focus();
  await until(() => $("#liveStatus").textContent === "Content hash computed", "the announcement of the hash");
  assert.equal(ctx.document.activeElement, $("#runBtn"));
});

test("a Checklist run gives the card its score, and the score names an error without a message", async () => {
  const rt = slowScoreRuntime({ async score() { this.scored.push(this.active); return { error: "" }; } });
  const { $ } = await boot({}, rt);
  await until(() => scoreChipText($) === "not scored", "the refused score");
  assert.equal($("#summaryScore").getAttribute("title"), "the checklist stopped without a message");
  await upload($("#fileInput"), "large.theory.yaml", "id: large\n");
  await $("#runBtn").click();
  assert.equal(scoreChipText($), "checklist 80 · gate pass", "the run's report scores the card");
  assert.deepEqual(rt.scored, [EXAMPLES[0].path]);
});

async function bootAt(hash, opts, rt) {
  const ctx = makeWindow(Object.assign({ hash }, opts || {}));
  runScript(ctx, CORE);
  runScript(ctx, SHARE);
  rt = rt || stubRuntime();
  await ctx.TF.start(rt);
  return { ctx, rt, $: (s) => ctx.document.querySelector(s) };
}
async function encodeLink(state) {
  const enc = makeWindow();
  runScript(enc, SHARE);
  return "#s=" + await enc.__tfShare.encode(state);
}
const editedRuntime = () => stubRuntime({
  texts: [],
  async editText(text, f, name) { this.active = name; this.texts.push(text); return Object.assign(summaryOf("mine", { ok: true }), { texts: {} }); },
  async writeText() { return this.texts[this.texts.length - 1] || ""; },
});

test("a reload soon after an edit opens the latest edit and asks nothing", async () => {
  // The tab wrote the link of its first edit, and its own record of the
  // session already holds a second edit that has not reached the address.
  const first = await encodeLink({ v: 1, op: "check", params: {}, run: false, theory: { name: "mine.yaml", text: "title: First edit\n", format: "yaml" } });
  const record = { v: 2, opId: "check", params: {}, ran: false, input: { mode: "edited", name: "mine.yaml", format: "yaml", text: "title: Second edit\n" } };
  const session = JSON.stringify(record);
  const questions = [];
  const rt = editedRuntime();
  const { ctx } = await bootAt(first, { stored: { "tf-app-py": session }, session: { "tf-app-py-tab": JSON.stringify(Object.assign({ link: first }, record)) },
    confirm: (q) => { questions.push(q); return true; } }, rt);
  assert.deepEqual(questions, []);
  assert.deepEqual(rt.texts, ["title: Second edit\n"]);
  // The address then catches up with the session, and the tab records it as its own.
  await until(() => ctx.location.hash !== first && ctx.location.hash.startsWith("#s="), "the app's own link");
  assert.equal(JSON.parse(ctx.sessionStorage.getItem("tf-app-py-tab")).link, ctx.location.hash);
  // The same fragment, not written by this tab, is a link like any other and asks first.
  const rt2 = editedRuntime();
  const asked = [];
  await bootAt(first, { stored: { "tf-app-py": session }, confirm: (q) => { asked.push(q); return true; } }, rt2);
  assert.equal(asked.length, 1);
  assert.deepEqual(rt2.texts, ["title: First edit\n"]);
});

test("a reload of one tab opens its own theory, whatever another tab has saved since", async () => {
  // Two tabs share the browser's storage, and each keeps its own record.
  const A = await bootAt("", {}, stubRuntime());
  await A.$("#exampleSel").dispatch("change", { target: { value: EXAMPLES[1].path } });
  const record = () => JSON.parse(A.ctx.sessionStorage.getItem("tf-app-py-tab") || "{}");
  await until(() => record().input && record().input.path === EXAMPLES[1].path && record().link && record().link === A.ctx.location.hash,
    "tab A's record of its link");
  const linkA = A.ctx.location.hash;
  assert.ok(linkA.startsWith("#s="));
  const B = makeWindow({});
  B.__storage = A.ctx.__storage;
  runScript(B, CORE); runScript(B, SHARE);
  await B.TF.start(stubRuntime());
  await upload(B.document.querySelector("#fileInput"), "other.theory.yaml", "id: other\n");
  await tick(100);
  // Tab A is reloaded: same address, same tab record, the shared session now B's.
  const asked = [];
  const A2 = makeWindow({ hash: linkA, confirm: (q) => { asked.push(q); return true; } });
  A2.__storage = A.ctx.__storage;
  A2.__session = A.ctx.__session;
  runScript(A2, CORE); runScript(A2, SHARE);
  const rt = stubRuntime();
  await A2.TF.start(rt);
  assert.equal(rt.active, EXAMPLES[1].path);
  assert.deepEqual(asked, []);
});

test("a link pasted while the start panel restores a session opens once the app has started", async () => {
  const stored = { "tf-app-py": JSON.stringify({ v: 2, opId: "check", params: {}, ran: false, input: { mode: "upload", name: "mine.yaml", text: "id: mine\n" } }) };
  const ctx = makeWindow({ stored, confirm: () => true });
  runScript(ctx, CORE); runScript(ctx, SHARE);
  let release;
  const gate = new Promise((r) => (release = r));
  const rt = stubRuntime({ restoring: false,
    async loadTheoryText(text, name) { this.restoring = true; await gate; this.active = name; return summaryOf(name, { ok: true }); } });
  const started = ctx.TF.start(rt);
  await until(() => rt.restoring, "the start panel to restore the session");
  const pasted = await encodeLink({ v: 1, op: "validate", run: false, theory: { example: EXAMPLES[1].path } });
  ctx.location.hash = pasted;
  await ctx.__fire("hashchange");
  release();
  await started;
  await until(() => rt.active === EXAMPLES[1].path, "the pasted link to open");
  // The app writes its own link again after the next change.
  await until(() => !ctx.document.querySelector("#runBtn").disabled, "the app to be idle");
  await ctx.document.querySelector("#exampleSel").dispatch("change", { target: { value: EXAMPLES[0].path } });
  const record = () => JSON.parse(ctx.sessionStorage.getItem("tf-app-py-tab") || "{}");
  await until(() => ctx.location.hash !== pasted && ctx.location.hash.startsWith("#s=") && record().link === ctx.location.hash
    && record().input && record().input.path === EXAMPLES[0].path, "the app's own link");
});

test("an operation the user starts goes ahead of the card's score and hash", async () => {
  const order = [];
  const rt = stubRuntime({
    async score() { order.push("score"); return { score: 50, gate: "pass", failed: [], warned: [] }; },
    async contentHash() { order.push("hash"); return { hash: "sha256:" + "12".repeat(32) }; },
  });
  const run = rt.run;
  rt.run = async function (op, p) { order.push("run " + op); return run.call(this, op, p); };
  const { $ } = await boot({}, rt);
  // The card's calls wait for an idle engine, so a Run pressed at once goes first.
  await $("#runBtn").click();
  await until(() => order.length >= 2, "the card's hash");
  assert.deepEqual(order, ["run check", "hash"], "the run went first, and gave the card its score");
});

test("the hash waits for a request when the theory is long, whatever its counts", async () => {
  const rt = stubRuntime({
    hashed: 0,
    async contentHash() { this.hashed++; return { hash: "sha256:" + "34".repeat(32) }; },
    async score() { return { score: 50, gate: "pass", failed: [], warned: [] }; },
    async loadTheoryText(text, name) {
      this.active = name;
      const chars = /long/.test(text) ? 150000 : /unmeasured/.test(text) ? null : 900;
      return Object.assign(summaryOf(name, { ok: true }), { counts: { constructs: 3, outcomes: 1000 }, chars });
    },
  });
  const { $ } = await boot({}, rt);
  await until(() => rt.hashed === 1 && scoreChipText($) === "checklist 50 · gate pass", "the first score and hash");
  await upload($("#fileInput"), "long.theory.yaml", "id: long\n");
  await until(() => scoreChipText($) === "checklist 50 · gate pass", "the score, since the theory's counts are small");
  await tick(100);
  assert.equal(rt.hashed, 1, "a theory longer than the runtime's limit is not hashed unasked");
  assert.match($("#summaryHash").textContent, /^Content hash not computed for a theory this long/);
  await upload($("#fileInput"), "unmeasured.theory.yaml", "id: unmeasured\n");
  await tick(100);
  assert.equal(rt.hashed, 1);
  assert.equal($("#summaryHash .hk").getAttribute("title"),
    "This theory holds more than 20,000 values, more than the app measures as it loads, so its hash is computed only when you ask.");
  // A runtime with a higher limit hashes the same theory unasked.
  const roomy = stubRuntime(Object.assign({}, rt, { limits: { score: 300, hashChars: 1000000 }, hashed: 0 }));
  const again = await boot({}, roomy);
  await until(() => roomy.hashed === 1, "the first hash");
  await upload(again.$("#fileInput"), "long.theory.yaml", "id: long\n");
  await until(() => roomy.hashed === 2, "the long theory's hash");
});

test("a link pasted while an operation runs opens once the run has finished", async () => {
  const { ctx, rt, $, enc } = await bootWithLink({ v: 1, op: "check", run: false, theory: { example: EXAMPLES[0].path } });
  runsOf(rt);
  let release;
  const run = rt.run;
  rt.run = async (op, p) => { if (op === "check") await new Promise((r) => (release = r)); return run(op, p); };
  const running = $("#runBtn").click();
  await until(() => typeof release === "function", "the run to start");
  const pasted = "#s=" + await enc({ v: 1, op: "validate", run: true, theory: { example: EXAMPLES[1].path } });
  ctx.location.hash = pasted;
  await ctx.__fire("hashchange");
  assert.equal(rt.active, EXAMPLES[0].path, "nothing opens while the run goes on");
  await tick(800);
  assert.equal(ctx.location.hash, pasted, "the app's own state leaves the pasted link alone");
  release();
  await running;
  await until(() => rt.ran.length === 2 && /Opened the theory/.test($(".toast").textContent), "the pasted link to open and run");
  assert.equal(rt.active, EXAMPLES[1].path);
  assert.equal($("#exampleSel").value, EXAMPLES[1].path);
  assert.deepEqual(rt.ran, ["check", "validate"]);
  assert.match($(".toast").textContent, /Opened the theory and operation from the link/);
});

test("a refused link says why, in the note and under the card", async () => {
  const refusal = "PythonError: Traceback (most recent call last):\n  File \"/pkg/_app.py\", line 140, in edit\n" +
    "ValueError: (/pkg/edit.yaml) the document holds more than 1000000 values once its aliases are expanded";
  const rt = stubRuntime({ fileNames: { "/pkg/edit.yaml": "laughs.theory.yaml" }, async editText() { throw new Error(refusal); } });
  const { ctx, $ } = await bootWithLink({ v: 1, op: "check", run: false, theory: { name: "laughs.theory.yaml", text: "a: &a [x]\n", format: "yaml" } }, {}, rt);
  assert.equal($(".toast").textContent, "Could not restore laughs.theory.yaml; showing Theory A instead: " +
    "ValueError: (laughs.theory.yaml) the document holds more than 1000000 values once its aliases are expanded");
  assert.match($("#summaryWrap .error .et").textContent, /^Could not restore laughs\.theory\.yaml; showing Theory A instead$/);
  assert.match($("#summaryWrap .error .last").textContent, /holds more than 1000000 values/);
  assert.ok($("#summaryWrap .summary"), "the card of the theory shown stays");
  assert.equal(ctx.location.hash, "");
  // A link too long to read says so too.
  const long = await bootAt("#s=" + "A".repeat(16001));
  assert.equal(long.$(".toast").textContent, "The link could not be read (the link is longer than 16000 characters), so the saved session is shown instead");
});

test("a figure Graphviz refuses says so, and only a failed load asks for another run", async () => {
  const cases = [
    [async () => ({ Graphviz: { load: async () => ({ dot: () => { throw new Error("syntax error in line 1 near 'x'"); } }) } }),
      /Graphviz could not draw this figure: syntax error in line 1 near 'x'$/],
    [async () => { throw new TypeError("Failed to fetch dynamically imported module"); },
      /The figure could not be drawn: Failed to fetch dynamically imported module\. Run the operation again to try once more\./],
  ];
  for (const [load, want] of cases) {
    const ctx = makeWindow();
    let swapped = false;
    runScript(ctx, CORE, (src) => src.replace("await import(GRAPHVIZ_URL)", () => { swapped = true; return "await __graphvizModule()"; }));
    assert.ok(swapped, "the test reaches the Graphviz import");
    ctx.__graphvizModule = load;
    const rt = stubRuntime({ async run() { return { raw: { ir: "digraph nomological_net {\n}\n" }, code: "#" }; } });
    await ctx.TF.start(rt);
    const $ = (s) => ctx.document.querySelector(s);
    opButton(ctx, "diagram").click();
    await $("#runBtn").click();
    const note = $("#output .caution").textContent;
    assert.match(note, want);
    if (!/Run the operation again/.test(String(want))) assert.doesNotMatch(note, /Run the operation again/);
  }
});

test("a figure whose text holds a character XML cannot hold is shown without it", async () => {
  const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><text>Panic\u0001 attack&#2;</text></svg>';
  const rt = stubRuntime({ async run() { return { raw: { report: { aggregate_score: 80, gate: "pass", n_blockers_failed: 0, maturity: "developing", items: [] }, svg }, code: "#" }; } });
  const { ctx, $ } = await boot({}, rt);
  const downloads = [];
  ctx.URL = { createObjectURL: () => "blob:x", revokeObjectURL() {} };
  ctx.Blob = class { constructor(parts) { downloads.push(parts.join("")); } };
  await $("#runBtn").click();
  const fig = $(".figure");
  assert.ok(fig, "the figure is shown");
  assert.equal(fig.querySelector("text").textContent, "Panic attack");
  await fig.parentNode.querySelectorAll("button").find((b) => b.textContent === "SVG").click();
  assert.equal(downloads.length, 1);
  assert.doesNotMatch(downloads[0], /\u0001|&#2;/, "the download is the figure as shown");
});

test("the entailments table says when no adjustment suffices, and why a claim was not evaluated", async () => {
  const result = { theory_id: "t", criterion: "m", acyclic: true, feedback: [], counts: { entailed: 1, contradicted: 0, undetermined: 0, not_evaluated: 1 },
    claims: [
      { source: "prediction", id: "pred1", kind: "effect", x: "a", y: "b", given: [], sign: "positive", derived: "positive", verdict: "entailed", basis: "paths_agree", faithfulness: false, via: ["p1"], identified: false, adjustment: null },
      { source: "prediction", id: "pred2", kind: "effect", x: "a", y: "z", given: [], sign: "positive", derived: null, verdict: "not_evaluated", basis: "not_in_graph", faithfulness: false, via: [], identified: null, adjustment: null },
    ] };
  const { ctx, $ } = await boot({}, lineageRuntime({ entailments: { result } }));
  await opButton(ctx, "entailments").click();
  await $("#runBtn").click();
  const rows = ctx.document.querySelectorAll("#output table.grid tbody tr").filter((tr) => /pred1|pred2/.test(tr.textContent));
  const cell = (tr, i) => tr.querySelectorAll("td")[i].textContent;
  assert.equal(cell(rows[0], 5), "none suffices");
  assert.equal(cell(rows[1], 4), "not in graph");
  assert.match($("#output .ri-interp").textContent, /One claim was not evaluated, since it names a construct that no proposition relates to another\./);
});

test("the appraisal's help says how assumptions are compared", async () => {
  const { ctx, $ } = await boot({}, lineageRuntime());
  await opButton(ctx, "appraise").click();
  assert.match($("#opHelp").textContent, /Assumptions are compared by statement, so one rewritten under its id is appraised as a new one is, and one moved unchanged to another id is not\./);
  await $("#helpBtn").click();
  assert.match(ctx.document.querySelector("#tfModal").textContent, /Assumptions are compared by statement/);
  assert.match(ctx.TF.OPS.find((o) => o.id === "appraise").help, /moved unchanged to another id is not/);
});

// ---- what each result says it computes ----------------------------------------

test("the appraisal says what its verdict is to be read with, and leaves out keys an older package lacks", async () => {
  const full = {
    verdict: "progressive", new_predictions: ["h3", "h4", "h5"], corroborated_new: ["h3", "h5"], ad_hoc_assumptions: [], articulated: [],
    underived: [], corroborated_new_registered: ["h3"], renamed: [], dropped: [], dropped_corroborated: [], content_lost: ["h2"],
    new_anomalies: ["h1"], assumptions: [{ id: "a1", added_for: "h1", class: "pending", independent: [{ id: "h4", status: "untested" }], added_for_inferred: false, change: "new" }],
    theoretically_progressive: true, empirically_progressive: true, revised: [], weakened_refuted: [], unresolved: [], implications_compared: true,
    implications_lost: [], implications_lost_unrefuted: [], implications_gained: [],
    entailments_lost: [{ id: "h2", prior: "entailed", new: "undetermined" }], signs_lost: ["effect of a on b: positive"],
    protected_only: ["h5"], refuted_new: ["h4"], corroborated_new_severity: [{ id: "h3", severity: 0.0012 }, { id: "h5", severity: null }],
  };
  const { ctx, $ } = await boot({}, lineageRuntime({ appraise: full }));
  await choose($("#exampleSel"), LINEAGE[1].path);
  await opButton(ctx, "appraise").click();
  await $("#runBtn").click();
  const about = $("#output .ri-about").textContent, interp = $("#output .ri-interp").textContent, text = $("#output").textContent;
  assert.match(about, /^The verdict applies fixed rules that borrow Lakatos's terms to what the two files declare/);
  assert.match(about, /the prior must be the version before the new predictions were stated/);
  assert.match(about, /A prediction that only changed its id is a rename\. One derived only from the prior's own propositions is an articulation unless a new or revised assumption lists it in protects, and so is one whose claim the prior's graph entails\. Neither a rename nor an articulation counts as new content\./);
  assert.match(interp, /^The amendment is progressive by fixed rules that borrow Lakatos's terms, applied to what the two files declare\./);
  assert.match(interp, /One prediction the prior held now fails a test: h1\./);
  assert.match(interp, /One new prediction failed a test: h4\./);
  assert.match(interp, /The lowest post-data severity of each corroborated new prediction's passes is 0\.001 for h3, and it is not computed for h5, whose passes record no estimate and standard error for a claim with bounds\./);
  assert.match(interp, /The novelty of h5 rests on an assumption that lists it in protects\./);
  assert.match(interp, /The assumption a1 is pending, since its independent predictions are not yet tested\./);
  assert.match(text, /Corroborations with a registration recordedh3/);
  assert.match(text, /Lowest post-data severity of their passesh3 \(0\.001\), h5 \(not computed\)/);
  assert.match(text, /New predictions that failed a testh4/);
  assert.match(text, /New only through protectsh5/);
  assert.match(text, /Entailments losth2 \(entailed → undetermined\)/);
  assert.match(text, /Signs losteffect of a on b: positive/);
  assert.match(text, /Appraised assumptionsa1: pending \(independent prediction not yet tested\)/);
  assert.doesNotMatch(text, /Preregistered|in Lakatos's sense/);
  // An older package's result has none of the new keys, and no row claims
  // that it found none.
  const old = { verdict: "neutral", new_predictions: [], corroborated_new: [], ad_hoc_assumptions: [], assumptions: [] };
  const o = await boot({}, lineageRuntime({ appraise: old }));
  await choose(o.$("#exampleSel"), LINEAGE[1].path);
  await opButton(o.ctx, "appraise").click();
  await o.$("#runBtn").click();
  const otext = o.$("#output").textContent;
  for (const row of ["Signs lost", "Entailments lost", "New predictions that failed a test", "New only through protects", "Lowest post-data severity"]) {
    assert.doesNotMatch(otext, new RegExp(row), row);
  }
  assert.doesNotMatch(o.$("#output .ri-interp").textContent, /failed a test|post-data severity|pending/);
});

test("a caution on the prior says it must be the version before the new predictions were stated", async () => {
  const { ctx, $ } = await boot({}, lineageRuntime());
  await choose($("#exampleSel"), LINEAGE[2].path);
  await opButton(ctx, "appraise").click();
  await choose($("#param-prior"), LINEAGE[0].path);
  assert.match($("#priorNote").textContent, /The prior must be the version before the new predictions were stated\.$/);
});

test("the simulation says that k and the damping decide its course, and its chart carries axis titles and a caption", async () => {
  const run = (trajectory) => ({ result: { states: ["a", "b"], steps: trajectory.length - 1, dt: 0.1, k: 1, damping: 0.5, method: "exact",
    initial_state: trajectory[0], assumed_positive: [], ignored: [], opposed: [], trajectory } });
  const cases = [
    [[[1, 1], [1.5, 1.6], [2, 2.2]], /At k = 1 and damping = 0\.5, the values grow over this run\. Other settings can reverse this\./],
    [[[1, 1], [0.6, 0.7], [0.3, 0.2]], /At k = 1 and damping = 0\.5, the values settle over this run\. Other settings can reverse this\./],
    [[[1, 1], [1, 1], [1, 1]], /At k = 1 and damping = 0\.5, the values change too little over this run to tell whether they grow or settle\./],
    [[[1, 1]], /change too little over this run to tell/],
  ];
  for (const [traj, want] of cases) {
    const { ctx, $ } = await boot({}, lineageRuntime({ simulate: run(traj) }));
    await opButton(ctx, "simulate").click();
    await $("#runBtn").click();
    assert.match($("#output .ri-interp").textContent, want);
    const fig = $("#output .figure").textContent;
    assert.match(fig, /value \(no unit\)/);
    assert.match(fig, /step \(dt = 0\.1\)/);
    assert.match(fig, /Linear system, k = 1, damping = 0\.5, exact method\. Not fitted to data\./);
    assert.match($("#output .ri-about").textContent, /The theory states no parameter values\. The gain k and the damping are free settings that together decide whether a feedback loop grows or settles, unsigned relations are taken as positive, the values have no unit and the trajectory is not fitted to data\. A linear system cannot show bistability\.$/);
    // The method the run used is the exact solution unless the user chose Euler steps.
    assert.equal(ctx.TF.OPS.find((o) => o.id === "simulate").params.find((p) => p.id === "method").default, "exact");
  }
});

test("the verdicts of the causal readings and the landscape's statuses are neutral pills", async () => {
  const entail = { result: { theory_id: "t", criterion: "m", acyclic: true, feedback: [], counts: { entailed: 1, contradicted: 1, undetermined: 1, not_evaluated: 0 },
    claims: ["entailed", "contradicted", "undetermined"].map((v, i) => ({ source: "prediction", id: "pred" + i, kind: "effect", x: "a", y: "b", given: [], sign: "positive",
      derived: "positive", verdict: v, basis: "paths_agree", faithfulness: false, via: ["p1"], identified: true, adjustment: [] })) } };
  const disc = { result: { rival_id: "alt_b", criterion: "m", evaluated: true, shared: ["a", "b"], only_theory: [], only_rival: [], markov_equivalent: false,
    independencies: [], effects: [], associations: [], claims: [{ source: "prediction", id: "pred1", theory: "entailed", rival: "contradicted", discriminates: true }],
    counts: { discriminating_claims: 1, independencies: 0, decisive_effects: 0, decisive_associations: 0 } } };
  const equiv = { result: { computed: true, edges: [{ from: "a", to: "b", propositions: ["p1"], status: "compelled" }, { from: "b", to: "c", propositions: ["p2"], status: "reversible" }],
    v_structures: [], n_compelled: 1, n_reversible: 1 } };
  const land = { result: { themes: [{ id: "t1", status: "under_theorised", focal: false, keywords: ["x"], alternatives: [], focal_terms: [] },
    { id: "t2", status: "covered", focal: true, keywords: ["y"], alternatives: [], focal_terms: ["y"] },
    { id: "t3", status: "crowded", focal: true, keywords: ["z"], alternatives: ["alt"], focal_terms: ["z"] }],
    under_theorised_fronts: ["t1"], redundancy_risk: ["t3"] } };
  const red = { rows: [{ a: "a", b: "b", similarity: 0.9, overlap: 0.9, flag: "review", reason: "near-duplicate" }, { a: "a", b: "c", similarity: 0.1, overlap: 0.2, flag: "ok", reason: "" }] };
  const rt = lineageRuntime({ entailments: entail, discriminate: disc, equivalent: equiv, landscape: land, redundancy: red });
  const base = rt.loadExample;
  rt.loadExample = async function (p) { const s = await base.call(this, p); s.alternatives = [{ id: "alt_b", label: "B", propositions: 1 }]; return s; };
  const { ctx, $ } = await boot({}, rt);
  const pills = () => ctx.document.querySelectorAll("#output .pill").map((p) => [p.textContent, p.className]);
  const runOp = async (id) => { await opButton(ctx, id).click(); await $("#runBtn").click(); };
  await runOp("entailments");
  assert.deepEqual(pills(), [["entailed", "pill plain"], ["contradicted", "pill plain"], ["undetermined", "pill plain"]]);
  assert.equal(ctx.document.querySelectorAll("#output table.grid tbody tr").filter((tr) => /pred0/.test(tr.textContent))[0].querySelectorAll("td")[5].textContent, "none needed");
  assert.match($("#output .ri-about").textContent, /Entailed means the claim follows from the propositions as written, a check of the theory's internal consistency, not evidence that the claim is true\. A claim that restates one proposition is entailed by that proposition alone\./);
  assert.match($("#output .ri-about").textContent, /each loop settles to a unique equilibrium, also once the construct whose effect is read is held fixed/);
  await runOp("discriminate");
  assert.deepEqual(pills(), [["entailed", "pill plain"], ["contradicted", "pill plain"]]);
  assert.match($("#output .ri-about").textContent, /The comparison shows which results would favour one account over the other\. It does not say which account the data favour\.$/);
  await runOp("equivalent");
  assert.deepEqual(pills(), [["compelled", "pill plain"], ["reversible", "pill plain"]]);
  assert.match($("#output .ri-interp").textContent, /No test of conditional independence can tell the direction of a reversible edge\. An intervention, a temporal order or distributional assumptions such as non-Gaussian errors can\./);
  assert.match($("#output .ri-about").textContent, /The function does not know which constructs a study manipulates/);
  assert.doesNotMatch($("#output").textContent, /whatever the sample size|Observational data cannot/);
  await runOp("landscape");
  assert.deepEqual(pills(), [["no account shares a word", "pill plain"], ["one account shares a word", "pill plain"], ["several accounts share a word", "pill plain"]]);
  assert.match($("#output").textContent, /Themes no account shares a word witht1/);
  assert.match($("#output").textContent, /Themes several accounts share a word witht3/);
  assert.match($("#output .ri-about").textContent, /does not show that the account explains what the theme's records report, nor that a theme without a match is unexplained/);
  assert.doesNotMatch($("#output").textContent, /nder-theorised|Crowded/);
  assert.match($("#output .ri-about").textContent, /The figure, like the JSON, keeps the package's names for the three statuses: under_theorised for a theme no account shares a word with, covered for one and crowded for several\. The JSON also keeps the package's names for the two lists, under_theorised_fronts and redundancy_risk\.$/);
  await runOp("redundancy");
  assert.deepEqual(pills(), [["review", "pill review"], ["not flagged", "pill plain"]]);
  assert.match($("#output .ri-about").textContent, /when the two carry the same label or when every measure of one is listed for the other/);
});

test("the claim-form rubric names every claim at the highest value", async () => {
  const rows = (vals) => ({ rows: vals.map((v, i) => ({ prediction_id: "p" + (i + 1), type: "directional", risk_score: v, computed_severity: v })), svg: "<svg></svg>" });
  const cases = [
    [[0.4, 0.4, 0.3], /the rubric value runs from 0\.3 to 0\.4 \(mean 0\.367\)\. The riskiest claim forms, at 0\.4, are those of p1 and p2\./],
    [[0.9, 0.4], /The riskiest claim form, at 0\.9, is that of p1\./],
    [[0.4, 0.4], /Every prediction's claim form has the same value\./],
    [[0.3], /^The one prediction, p1, has a rubric value of 0\.3\.$/],
  ];
  for (const [vals, want] of cases) {
    const { ctx, $ } = await boot({}, lineageRuntime({ severity: rows(vals) }));
    await opButton(ctx, "severity").click();
    await $("#runBtn").click();
    assert.match($("#output .ri-interp").textContent, want);
    assert.match($("#output").textContent, /risk scorerubric value/);
    assert.match($("#output .ri-about").textContent, /predictions that name a registered rival they are declared to discriminate from \(the declaration is not checked\)/);
  }
  const { ctx } = await boot({}, lineageRuntime());
  const op = ctx.TF.OPS.find((o) => o.id === "severity");
  assert.equal(op.label, "Claim-form rubric");
  assert.equal(op.desc, "Pre-data riskiness of each claim's form");
});

test("the dossier, validation, post-data severity and start panel say what they rest on", async () => {
  const { ctx, $ } = await boot({}, lineageRuntime({ dossier: { text: "# Dossier\n", hash: null }, validate: { ok: true }, post_severity: { result: [] } }));
  const dossier = ctx.TF.OPS.find((o) => o.id === "dossier");
  assert.equal(dossier.label, "Dossier");
  assert.equal(dossier.desc, "The file and its checks, for reviewers");
  assert.match($("#output").textContent, /theoryforge reads a theory written as structured data and checks what the file states: which fields are filled in, what its propositions imply as a causal graph, how it differs from a rival or from an earlier version and whether an amendment meets fixed rules that borrow Lakatos's terms\. None of these checks shows that a theory is true or well reasoned, and the checklist's weights and thresholds have not been validated against expert judgement\./);
  await opButton(ctx, "dossier").click();
  await $("#runBtn").click();
  assert.equal($("#outTitle").textContent, "Dossier");
  assert.match($("#output .ri-about").textContent, /^The dossier gathers what the theory file records and what the package derives from it\. The score, gate and verdicts describe the file by fixed rules\. Test outcomes, evidence, registrations and declared severities are as the author entered them, and the package checks only whether a recorded estimate agrees with its pass or failure and whether a declared severity is more than 0\.2 above the rubric\. It is not an independent audit\.$/);
  await opButton(ctx, "validate").click();
  await $("#runBtn").click();
  assert.match($("#output").textContent, /✓ Well-formed\. Full validation found no problem in the file's structure or references\./);
  assert.match($("#output .ri-about").textContent, /Validate first: other operations run on an invalid file, but their results may not mean what they say\.$/);
  await opButton(ctx, "post_severity").click();
  await $("#runBtn").click();
  assert.match($("#output .ri-about").textContent, /post-data severity of Mayo and Spanos \(2006\)\. With two finite bounds, the package takes the smaller of the two one-sided values, its own extension, which equals 1 minus the p value of the two one-sided z-tests of equivalence \(Lakens, 2017\)\./);
  assert.match($("#output .ri-about").textContent, /It treats the standard error as known, so in small samples it overstates the severity of an estimate inside the region, and it does not account for a subgroup or analysis chosen after seeing the data\. A high value does not show that the claim is true\.$/);
  for (const op of ctx.TF.OPS) assert.doesNotMatch(op.label + " " + op.desc + " " + (op.help || ""), /rigour checklist|Audit|in Lakatos's sense/i, op.id);
});

test("a toast about one operation goes when the operation changes or a run starts", async () => {
  const { ctx, $ } = await boot({}, lineageRuntime());
  await choose($("#exampleSel"), LINEAGE[2].path);
  await opButton(ctx, "appraise").click();
  await $("#runBtn").click();
  assert.ok($(".toast").classList.contains("show"), "the appraisal waits for a prior and says so");
  await opButton(ctx, "check").click();
  assert.ok(!$(".toast").classList.contains("show"), "a change of operation takes the toast away");
  await opButton(ctx, "appraise").click();
  await $("#runBtn").click();
  assert.ok($(".toast").classList.contains("show"));
  ctx.TF.util.toast("A message about something else");
  await opButton(ctx, "appraise").click();
  assert.ok($(".toast").classList.contains("show"), "choosing the same operation again keeps it");
  await opButton(ctx, "check").click();
  ctx.TF.util.toast("A message about the last operation");
  await $("#runBtn").click();
  assert.ok(!$(".toast").classList.contains("show"), "a run takes the toast away");
});
