// apps/shared/app-core.js under a stub DOM and a stub runtime: start-up with
// blocked storage, failed uploads and restores, the validity chip and how a
// change of theory or a failed operation is reported. The later tests cover the
// appraisal's prior, the implied-independencies operation, the saved example,
// the checklist's wording, whole-number parameters, the help's list of
// operations and the page title.
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
  assert.match(items[0].textContent, /^Rigour checklist: Scores the theory against the 12-item rigour checklist/);
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
  assert.match(text, /41\.5 \/ 100 · pass/);
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
  await new Promise((r) => setTimeout(r, 60));
  assert.equal($("#liveStatus").textContent, "Rigour checklist finished");
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

test("the check view shows the range of the aggregate where the checklist gives one", async () => {
  const report = { aggregate_score: 87.1, aggregate_range: [83.5, 89.2], coverage: 1, gate: "pass", n_blockers_failed: 0, maturity: "testing", items: [] };
  const { $ } = await boot({}, lineageRuntime({ check: { report, svg: "<svg></svg>" } }));
  await $("#runBtn").click();
  assert.match($("#output").textContent, /87\.1 \/ 100 \(83\.50 to 89\.20 under other weightings\)|87\.1 \/ 100 \(83\.5 to 89\.2 under other weightings\)/);
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
  assert.match(text, /Had the true value lain at the lower bound of 0\.20, an estimate lower than 0\.10 would have come up 15\.9 times in 100\./);
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
  ctx.location.hash = "#s=" + await enc({ v: 1, op: "validate", run: true, theory: { example: EXAMPLES[1].path } });
  await ctx.__fire("hashchange");
  assert.equal(rt.active, EXAMPLES[1].path);
  assert.equal($("#exampleSel").value, EXAMPLES[1].path);
  assert.equal(ctx.document.querySelectorAll(".op.active")[0].getAttribute("data-op"), "validate");
  assert.deepEqual(rt.ran, ["validate"]);
  // A fragment the app wrote itself opens nothing.
  await new Promise((r) => setTimeout(r, 800));
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
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(rt.hashes, 1);
  assert.match($("#summaryHash").textContent, /sha256:cdcdcdcdcdcd…cdcdcd/);
  await choose($("#exampleSel"), EXAMPLES[1].path);
  await new Promise((r) => setTimeout(r, 20));
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
  assert.equal(modal.querySelectorAll("h3").length, 3);
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
  assert.match($("#output").textContent, /a 0\.00, b 0/);
});

// ---- the card's score and hash, reloads, links while busy, refusals, figures --

const tick = (ms) => new Promise((r) => setTimeout(r, ms || 5));

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
  // The tab wrote the link of its first edit, and its session already holds a
  // second edit that has not reached the address.
  const first = await encodeLink({ v: 1, op: "check", params: {}, run: false, theory: { name: "mine.yaml", text: "title: First edit\n", format: "yaml" } });
  const session = JSON.stringify({ v: 2, opId: "check", params: {}, ran: false, input: { mode: "edited", name: "mine.yaml", format: "yaml", text: "title: Second edit\n" } });
  const questions = [];
  const rt = editedRuntime();
  const { ctx } = await bootAt(first, { stored: { "tf-app-py": session, "tf-app-py-link": first }, confirm: (q) => { questions.push(q); return true; } }, rt);
  assert.deepEqual(questions, []);
  assert.deepEqual(rt.texts, ["title: Second edit\n"]);
  assert.equal(ctx.localStorage.getItem("tf-app-py") === session || JSON.parse(ctx.localStorage.getItem("tf-app-py")).input.text === "title: Second edit\n", true);
  // The address then catches up with the session, and the tab records it as its own.
  await tick(800);
  assert.notEqual(ctx.location.hash, first);
  assert.equal(ctx.localStorage.getItem("tf-app-py-link"), ctx.location.hash);
  // The same fragment, not written by this tab, is a link like any other and asks first.
  const rt2 = editedRuntime();
  const asked = [];
  await bootAt(first, { stored: { "tf-app-py": session }, confirm: (q) => { asked.push(q); return true; } }, rt2);
  assert.equal(asked.length, 1);
  assert.deepEqual(rt2.texts, ["title: First edit\n"]);
});

test("a link pasted while an operation runs opens once the run has finished", async () => {
  const { ctx, rt, $, enc } = await bootWithLink({ v: 1, op: "check", run: false, theory: { example: EXAMPLES[0].path } });
  runsOf(rt);
  let release;
  const run = rt.run;
  rt.run = async (op, p) => { if (op === "check") await new Promise((r) => (release = r)); return run(op, p); };
  const running = $("#runBtn").click();
  await tick();
  const pasted = "#s=" + await enc({ v: 1, op: "validate", run: true, theory: { example: EXAMPLES[1].path } });
  ctx.location.hash = pasted;
  await ctx.__fire("hashchange");
  assert.equal(rt.active, EXAMPLES[0].path, "nothing opens while the run goes on");
  await tick(800);
  assert.equal(ctx.location.hash, pasted, "the app's own state leaves the pasted link alone");
  release();
  await running;
  await tick(20);
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

