// apps/shared/app-core.js under a stub DOM and a stub runtime: start-up with
// blocked storage, failed uploads and restores, the validity chip and how a
// change of theory or a failed operation is reported. The later tests cover the
// appraisal's prior, the implied-independencies operation, the saved example,
// the checklist's wording and whole-number parameters.
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
});

test("a failed restore of an example falls back to the first example and says so", async () => {
  const saved = { "tf-app-py": JSON.stringify({ opId: "check", params: {}, ran: false, input: { mode: "example", path: EXAMPLES[1].path } }) };
  const rt = stubRuntime({ badExamples: [EXAMPLES[1].path] });
  const { $ } = await boot({ stored: saved }, rt);
  assert.equal($("#exampleSel").value, EXAMPLES[0].path);
  assert.match($(".toast").textContent, /Could not restore Theory B/);
  assert.match($("#summaryWrap").textContent, /Title a\.theory\.yaml/);
});

// ---- CS28: honest operations and text ------------------------------------

// Examples with the lineage the real ones carry. Every theory but the amended
// panic network is version v1 with no parent, and the amended one names v1 of
// the panic network as its parent.
const LINEAGE = [
  { name: "Panic network", path: "fixtures/panic-network.theory.yaml", desc: "",
    lineage: { id: "panic-network-2026", title: "Panic", version: { id: "v1", parent_id: "" } } },
  { name: "Panic network, amended v2", path: "fixtures/panic-network-2026-v2.theory.yaml", desc: "",
    lineage: { id: "panic-network-2026-v2", title: "Panic v2", version: { id: "v2", parent_id: "v1" } } },
  { name: "Happy vowel", path: "examples/happy-vowel-manchester.theory.yaml", desc: "",
    lineage: { id: "happy-vowel-manchester-2026", title: "Happy vowel", version: { id: "v1", parent_id: "" } } },
];

// A runtime whose loads report the example's lineage, which records each call
// it runs and which answers each operation with `answers[op]`.
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
      const raw = (answers && answers[op]) || { verdict: "neutral" };
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
  const { $ } = await boot({}, lineageRuntime({ check: { report, svg: "<svg></svg>" } }));
  await $("#runBtn").click();
  const about = $("#output .ri-about").textContent, interp = $("#output .ri-interp").textContent;
  assert.match(about, /Pass means neither blocking item failed, and blocked means at least one did\./);
  assert.match(about, /At draft maturity, the gate is always advisory/);
  assert.doesNotMatch(about, /usable with the noted gaps/);
  assert.match(interp, /draft maturity/);
  assert.match(interp, /falsifiability and derivation_chain/);
  assert.doesNotMatch(interp, /clears the gate/);
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

test("the code panel says the code reproduces the result with the installed package", async () => {
  const { $ } = await boot();
  assert.equal($("#codePanel .note").textContent, "Paste into Python to reproduce this result with the installed package.");
});
