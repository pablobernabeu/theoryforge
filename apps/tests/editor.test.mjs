// apps/shared/editor.js: the field a validation problem points to, the paths
// the forms write through, the template of a new theory and the fields the
// forms offer. These helpers need no page, so they run without the stub DOM.
// The editor reads DAGitty model code with the package's own reader, so it
// holds no reader to test here.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const ctx = { console };
ctx.globalThis = ctx;
vm.createContext(ctx);
vm.runInContext(readFileSync(path.join(here, "..", "shared", "editor.js"), "utf8"), ctx);
const E = ctx.__tfEditor;
const plain = (v) => JSON.parse(JSON.stringify(v));

test("each validation problem points to the field it concerns", () => {
  const doc = { constructs: [{ id: "a" }, { id: "a" }], alternatives: [{ id: "alt", propositions: [{}, {}] }] };
  const cases = [
    ["missing/empty required field: title", "title"],
    ["maturity must be one of building, developing, draft, testing", "maturity"],
    ["version content_hash does not match the theory's content", "version.content_hash"],
    ["formal_model type 'xyz' not allowed", "formal_model.type"],
    ["schema_version must match major.minor (for example \"1.0\")", "schema_version"],
    ["construct[0] missing/empty definition", "constructs.0.definition"],
    ["proposition[2] from 'c_x' is not a known construct", "propositions.2.from"],
    ["prediction[1] derives_from 'p9' is not a known proposition", "predictions.1.derives_from"],
    ["prediction[0] claim x 'c_q' is not a known construct", "predictions.0.claim"],
    ["prediction[0] bounds lower exceeds upper", "predictions.0.bounds"],
    ["assumption[0] protects 'pred9' is not a known prediction", "auxiliary_assumptions.0.protects"],
    ["test_outcome[3] passed must be true or false", "test_outcomes.3.passed"],
    ["test_outcome[0] estimate and se must be given together", "test_outcomes.0.estimate"],
    ["phenomenon[0] missing/empty statement", "phenomena.0.statement"],
    ["evidence[1] supports 'x' is not a known prediction", "evidence.1.supports"],
    ["alternative[0] proposition[1] to 'c_z' is not a known construct", "alternatives.0.propositions.1.to"],
    ["alternative[0] duplicate proposition id: g1", "alternatives.0.propositions"],
    ["duplicate construct id: a", "constructs.1.id"],
    ["constructs must be a list", "constructs"],
    ["unknown top-level field: predicitions", ""],
  ];
  for (const [msg, want] of cases) assert.equal(E.problemPath(msg, doc), want, msg);
});

test("the paths the forms write through create and tidy the mappings that hold a field", () => {
  const doc = { predictions: [{ id: "p" }] };
  E.setAt(doc, "predictions.0.bounds", { lower: 1, upper: null });
  E.setAt(doc, "version.id", "v2");
  assert.equal(E.getAt(doc, "predictions.0.bounds.lower"), 1);
  assert.equal(E.getAt(doc, "version.id"), "v2");
  E.delAt(doc, "version.id");
  assert.equal("version" in doc, false, "an emptied version block goes");
  E.setAt(doc, "predictions.0.claim", { kind: "effect" });
  E.delAt(doc, "predictions.0.claim.kind");
  assert.deepEqual(plain(doc.predictions[0]), { id: "p", bounds: { lower: 1, upper: null } });
  assert.equal(E.getAt(doc, "nothing.here.at.all"), undefined);
});

test("a new theory starts from a template with no content, and fresh ids take the next number", () => {
  const t = E.templateTheory();
  assert.equal(t.schema_version, "1.1");
  assert.equal(t.maturity, "draft");
  assert.deepEqual(plain([t.constructs, t.propositions, t.predictions]), [[], [], []]);
  assert.equal(E.nextId("p", new Set(["p1", "p2", "p7"])), "p8");
  assert.equal(E.nextId("pred", new Set()), "pred1");
});

test("the editor holds no DAGitty reader of its own", () => {
  assert.equal(E.parseDagitty, undefined);
  assert.doesNotMatch(readFileSync(path.join(here, "..", "shared", "editor.js"), "utf8"), /function (parseDagitty|tokenize|mergeDagitty)/);
});

test("every form field is a field of the schema", () => {
  const schema = JSON.parse(readFileSync(path.join(here, "..", "..", "schema", "theory.schema.json"), "utf8"));
  for (const sec of E.SECTIONS) {
    const props = schema.properties[sec.key].items.properties;
    for (const f of sec.fields) assert.ok(f.k in props, `${sec.key}.${f.k} is not in the schema`);
  }
  for (const f of E.HEADER) {
    const [top, sub] = f.k.split(".");
    assert.ok(top in schema.properties, f.k);
    if (sub) assert.ok(sub in schema.properties[top].properties, f.k);
  }
});

// ---- the editor on a page ---------------------------------------------------
// The editor and app-core.js run together under the stub DOM, with a runtime
// whose engine holds the theory as data. Its "YAML" is JSON with a first
// comment line, which tells the two formats apart, and every text it reads is
// recorded with the file name the app gave it.
import { makeWindow, runScript } from "./dom.mjs";
const SHARED = path.join(here, "..", "shared");
const EX = [
  { name: "Theory A", path: "fixtures/a.theory.yaml", desc: "" },
  { name: "Theory B", path: "fixtures/b.theory.yaml", desc: "" },
];
const baseDoc = (id) => ({
  schema_version: "1.1", id, title: "Title " + id, maturity: "draft",
  constructs: [{ id: "c1", label: "One", definition: "D" }, { id: "c2", label: "Two", definition: "D" }, { id: "c3", label: "Three", definition: "D" }],
  propositions: [{ id: "p1", from: "c1", to: "c2", relation: "increases" }],
  predictions: [{ id: "h1", statement: "S", type: "directional", derives_from: ["p1"], diagnostic_vs: [],
    claim: { kind: "association", x: "c1", y: "c2", sign: "positive", given: ["c3"] } }],
  alternatives: [{ id: "alt1", label: "Rival", propositions: [{ id: "r1", from: "c1", to: "c3", relation: "causes" }, { id: "r2", from: "c2", to: "c3", relation: "causes" }] }],
});
function editRuntime(extra) {
  return Object.assign({
    lang: "py", langLabel: "Python", engineLabel: "stub", accent: "#3776AB", docsUrl: "#",
    examples: [], corpora: [], doc: null, reads: [], renamed: [], importOpts: [],
    hasCorpus() { return false; },
    summary(validation) {
      const d = this.doc;
      return { id: d.id, title: d.title, counts: { constructs: (d.constructs || []).length }, validation: validation || { ok: true },
        constructs: (d.constructs || []).map((c) => ({ id: c.id, label: c.label })), alternatives: [] };
    },
    text(fmt) { return (fmt === "json" ? "" : "# yaml\n") + JSON.stringify(this.doc, null, 2); },
    async init() { return { examples: EX, version: "Python 3", pkgVersion: "0.0", summary: await this.loadExample(EX[0].path) }; },
    async loadExample(p) { this.doc = baseDoc(p.split("/").pop().split(".")[0]); this.reads.push(["example", p]); return this.summary(); },
    async loadTheoryText(text, name) { this.doc = JSON.parse(text.replace(/^#.*\n/, "")); this.reads.push(["upload", name]); return this.summary(); },
    async editText(text, format, name, formats) {
      this.doc = JSON.parse(String(text).replace(/^#.*\n/, ""));
      this.reads.push(["edit", name, format]);
      return Object.assign(this.summary(), { texts: Object.fromEntries((formats || []).map((f) => [f, this.text(f)])) });
    },
    async writeText(fmt) { return this.text(fmt); },
    renameTheory(n) { this.renamed.push(n); },
    canImportDagitty: true,
    async importDagitty(model, opts, formats) {
      this.importOpts.push(opts);
      this.doc = { schema_version: "1.1", id: opts.id || "dagitty-import", title: "Imported", maturity: "draft", constructs: [], propositions: [] };
      return Object.assign(this.summary(), { texts: Object.fromEntries((formats || []).map((f) => [f, this.text(f)])) });
    },
    importCode(opts) { return "write " + JSON.stringify(opts.file || (opts.id || "dagitty-import") + ".theory.yaml"); },
    async run(op) { return { raw: { ok: true }, code: "# " + op }; },
  }, extra || {});
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
// Wait until cond() holds, checking every few milliseconds, and fail after a
// generous time, so that a test does not depend on the speed of the machine.
async function until(cond, what, ms = 10000) {
  const t0 = Date.now();
  while (!cond()) {
    if (Date.now() - t0 > ms) throw new Error("timed out waiting for " + (what || "the condition"));
    await wait(5);
  }
}
async function page(opts, rt) {
  const ctx = makeWindow(opts);
  for (const f of ["app-core.js", "share.js", "editor.js"]) runScript(ctx, path.join(SHARED, f));
  rt = rt || editRuntime();
  await ctx.TF.start(rt);
  const $ = (s) => ctx.document.querySelector(s);
  return { ctx, rt, $, $$: (s) => ctx.document.querySelectorAll(s) };
}
async function openEditor(p) {
  await p.$("#tabEditor").click();
  await until(() => p.$("#edForms") && p.$("#edForms").inert === false, "the editor to read the theory");
}
const fieldOf = (p, k) => p.$$("[data-k]").find((x) => x.getAttribute("data-k") === k);
const stored = (p) => JSON.parse(p.ctx.localStorage.getItem("tf-app-py") || "null");

test("while a change waits for the engine, the other pane takes no input, and both edits survive", async () => {
  const p = await page();
  await openEditor(p);
  const src = p.$("#edSource"), forms = p.$("#edForms");
  // A change typed in the source locks the forms until the engine has read it.
  src.value = "# yaml\n" + JSON.stringify(Object.assign({}, p.rt.doc, { title: "Typed in the source" }), null, 2);
  await src.dispatch("input");
  assert.equal(forms.inert, true, "the forms take no input while the source change waits");
  assert.ok(!src.readOnly);
  await until(() => forms.inert === false, "the forms to take input again once the engine has read the change");
  assert.equal(p.rt.doc.title, "Typed in the source");
  // The stub keeps a text field's starting value as its attribute.
  assert.equal(fieldOf(p, "title").getAttribute("value"), "Typed in the source", "the forms show the source change");
  // A change made in the forms makes the source read-only until it is read,
  // and the source then shows it, the source change kept.
  const def = fieldOf(p, "constructs.0.definition");
  def.value = "A definition from the forms";
  await def.dispatch("input");
  assert.equal(src.readOnly, true, "the source takes no input while the forms change waits");
  await until(() => src.readOnly === false, "the source to take input again");
  assert.match(src.value, /A definition from the forms/);
  assert.match(src.value, /Typed in the source/);
  // A box ticked in the forms reaches the source in the same way.
  const box = fieldOf(p, "predictions.0.diagnostic_vs#alt1");
  box.checked = true;
  box.value = box.getAttribute("value");   // a browser reflects the attribute; the stub does not
  await box.dispatch("change");
  assert.equal(src.readOnly, true);
  await until(() => src.readOnly === false, "the source to take input again");
  assert.deepEqual(JSON.parse(JSON.stringify(p.rt.doc.predictions[0].diagnostic_vs)), ["alt1"]);
  assert.match(src.value, /"alt1"/);
  assert.match(src.value, /A definition from the forms/);
});

test("a change waiting for the timer is applied before Copy link, View source or a change of example", async () => {
  let asked = 0;
  const p = await page({ confirm: () => { asked++; return true; } });
  p.ctx.navigator.clipboard = { writeText: async (t) => { p.copied = t; } };
  await openEditor(p);
  const title = fieldOf(p, "title");
  title.value = "Typed before Copy link";
  await title.dispatch("input");
  await p.$("#copyLink").click();
  const link = await p.ctx.TF.share.decode(p.copied.split("#s=")[1]);
  assert.match(link.theory.text, /Typed before Copy link/, "the copied link carries the edit");
  fieldOf(p, "title").value = "Typed before View source";
  await fieldOf(p, "title").dispatch("input");
  await p.$("#viewSrc").click();
  assert.match(p.$("#tfModal pre").textContent, /Typed before View source/);
  p.$("#tfModal").remove();
  // An edit made just before an example is chosen is applied to the theory
  // it was made on, which is edited, so the choice asks first, and the
  // example then loads as itself, not as an edited theory.
  fieldOf(p, "constructs.0.label").value = "Edited label";
  await fieldOf(p, "constructs.0.label").dispatch("input");
  await p.$("#exampleSel").dispatch("change", { target: { value: EX[1].path } });
  await wait(600);
  assert.equal(asked, 1);
  assert.equal(p.$("#exampleSel").value, EX[1].path);
  assert.equal(p.rt.doc.id, "b", "the late edit was not applied to the example");
  assert.equal(stored(p).input.mode, "example");
});

test("choosing an example or uploading a file asks before it replaces an edited theory", async () => {
  let answer = false;
  const questions = [];
  const p = await page({ confirm: (q) => { questions.push(q); return answer; } });
  await openEditor(p);
  fieldOf(p, "title").value = "My unsaved edit";
  await fieldOf(p, "title").dispatch("input");
  await until(() => stored(p) && stored(p).input.mode === "edited" && /My unsaved edit/.test(stored(p).input.text), "the edit to be saved");
  await p.$("#exampleSel").dispatch("change", { target: { value: EX[1].path } });
  assert.match(questions[0], /^Load Theory B\? Edits to My unsaved edit that you have not saved will be lost\.$/);
  assert.equal(p.rt.doc.title, "My unsaved edit", "a refusal keeps the edited theory");
  assert.match(stored(p).input.text, /My unsaved edit/);
  assert.match(p.$("#exampleOwn").textContent, /^Edited: /);
  await p.$("#fileInput").dispatch("change", { target: { files: [{ name: "other.yaml", text: async () => JSON.stringify(baseDoc("o")) }] } });
  assert.match(questions[1], /^Load other\.yaml\?/);
  assert.equal(p.rt.doc.title, "My unsaved edit");
  answer = true;
  await p.$("#exampleSel").dispatch("change", { target: { value: EX[1].path } });
  assert.equal(p.rt.doc.id, "b");
  assert.equal(stored(p).input.mode, "example");
});

test("after New theory or a DAGitty import, every place names the file after the theory's id", async () => {
  const p = await page();
  await openEditor(p);
  await p.$("#edNew").click();
  await until(() => /new-theory/.test(p.$("#exampleOwn").textContent), "the new theory");
  assert.deepEqual(p.rt.reads[p.rt.reads.length - 1].slice(0, 2), ["edit", "new-theory.theory.yaml"]);
  assert.match(p.$("#exampleOwn").textContent, /Edited: new-theory\.theory\.yaml/);
  await p.$("#viewSrc").click();
  assert.match(p.$("#tfModalTitle").textContent, /new-theory\.theory\.yaml/);
  p.$("#tfModal").remove();
  // An id with spaces gives one sanitised name to the code, the selector and
  // the source, and the import dialog's code writes that file.
  await p.$("#edImport").click();
  p.$("#dagId").value = "sleep and mood";
  await p.$("#dagId").dispatch("input");
  assert.equal(p.$("#dagCode").textContent, 'write "sleep-and-mood.theory.yaml"');
  p.$("#dagText").value = "dag { stress -> sleep }";
  await p.$("#dagImport").click();
  await until(() => p.rt.renamed.length > 0, "the import");
  assert.deepEqual(p.rt.renamed, ["sleep-and-mood.theory.yaml"]);
  assert.match(p.$("#exampleOwn").textContent, /Edited: sleep-and-mood\.theory\.yaml/);
  // The link keeps the theory new, so a reload goes on naming it after its id.
  await until(() => stored(p) && stored(p).input.name === "sleep-and-mood.theory.yaml", "the session to be saved");
  const s = stored(p);
  assert.equal(s.input.isNew, true);
  assert.equal(s.input.name, "sleep-and-mood.theory.yaml");
});

test("a theory edited in the forms comes back after a reload as YAML under the YAML label", async () => {
  const doc = baseDoc("a");
  doc.title = "Saved as JSON";
  const session = { v: 2, opId: "check", params: {}, ran: false,
    input: { mode: "edited", name: "a.theory.yaml", format: "json", text: JSON.stringify(doc, null, 2) } };
  const p = await page({ stored: { "tf-app-py": JSON.stringify(session) } });
  await p.$("#viewSrc").click();
  assert.match(p.$("#tfModal pre").textContent, /^# yaml\n/, "View source shows the writer's YAML, not the saved JSON");
  p.$("#tfModal").remove();
  await openEditor(p);
  assert.match(p.$("#edSource").value, /^# yaml\n/);
  assert.equal(p.$("#edSourceLabel").textContent, "Source (YAML)");
});

test("a field of boxes is named by its label, and a claim's given by the claim's", async () => {
  const p = await page();
  await openEditor(p);
  const groups = p.$$(".checks");
  const byPath = (k) => groups.find((g) => g.parentNode && g.parentNode.querySelector(".efl") && g.parentNode.querySelector(".efl").id === "lbl-" + k.replace(/\./g, "-"));
  assert.equal(byPath("predictions.0.derives_from").getAttribute("aria-labelledby"), "lbl-predictions-0-derives_from");
  assert.equal(byPath("predictions.0.claim.given").getAttribute("aria-labelledby"), "lbl-predictions-0-claim lbl-predictions-0-claim-given");
  for (const g of groups) assert.ok(g.getAttribute("aria-labelledby"), "every group of boxes has a name");
});

test("removing an entry puts the focus on the entry now in its place, or on Add", async () => {
  const p = await page();
  await openEditor(p);
  const rm = (label) => p.$$("button").find((b) => b.getAttribute("aria-label") === label);
  await rm("Remove construct c2").click();
  assert.equal(p.ctx.document.activeElement.getAttribute("aria-label"), "Remove construct c3");
  await rm("Remove construct c3").click();
  assert.equal(p.ctx.document.activeElement.getAttribute("aria-label"), "Remove construct c1");
  await rm("Remove construct c1").click();
  assert.equal(p.ctx.document.activeElement.textContent, "Add construct");
  await rm("Remove the rival's proposition r1").click();
  assert.equal(p.ctx.document.activeElement.getAttribute("aria-label"), "Remove the rival's proposition r2");
  await rm("Remove the rival's proposition r2").click();
  assert.equal(p.ctx.document.activeElement.textContent, "Add a proposition of this rival");
});

test("above the limits, Record the current hash computes it, and 'score it' keeps the focus in the editor", async () => {
  // Written as JSON, the theory is longer than the app hashes as it loads,
  // and it has more constructs than it scores.
  const rt = editRuntime({
    hashes: 0, scores: 0,
    summary(validation) {
      return Object.assign(editRuntime().summary.call(this, validation), { counts: { constructs: 400 }, chars: 500000 });
    },
    async contentHash() { this.hashes++; return { hash: "sha256:" + "56".repeat(32) }; },
    async score() { this.scores++; return { score: 42, gate: "advisory", failed: [], warned: [], version: "3.1" }; },
  });
  const p = await page({}, rt);
  await openEditor(p);
  await wait(20);
  assert.equal(rt.hashes, 0);
  assert.equal(rt.scores, 0);
  const record = p.$$("button").find((b) => b.textContent === "Record the current hash");
  await record.click();
  await until(() => fieldOf(p, "version.content_hash").value !== "", "the hash to be recorded");
  assert.equal(rt.hashes, 1, "the hash is computed on request");
  assert.equal(fieldOf(p, "version.content_hash").value, "sha256:" + "56".repeat(32));
  // Recording the hash is an edit, which the engine reads once typing pauses
  // and which gives a new theory to score. The test waits for that read, so
  // that the score asked for below is that of the theory then shown.
  await until(() => rt.reads.some((r) => r[0] === "edit") && p.$("#edSource").readOnly === false && p.$("#edLint button"),
    "the recorded hash to reach the engine");
  // The editor's 'score it' is replaced by the score, and the focus follows.
  const scoreIt = p.$("#edLint button");
  scoreIt.focus();
  await scoreIt.click();
  await until(() => p.$("#liveStatus").textContent === "Checklist score 42, gate advisory", "the announcement of the score");
  assert.equal(rt.scores, 1);
  assert.equal(p.ctx.document.activeElement, p.$("#edScore"));
  assert.match(p.$("#edScore").textContent.replace(/<\/?b>/g, ""), /checklist 42 · gate advisory/);
  // The lint bar's score reads as the card's does, with the same title.
  assert.equal(p.$("#edScore").getAttribute("title"),
    "The checklist score describes how completely the file states what checklist 3.1 asks for. The score does not show that the theory is true or well reasoned.");
  assert.equal(p.$("#liveStatus").textContent, "Checklist score 42, gate advisory");
});

test("Record the current hash records nothing when the theory changes while its hash is computed", async () => {
  // The hash waits until the test lets it go, and is the hash of the title
  // the theory had when it was asked for.
  const rt = editRuntime({
    held: [],
    summary(validation) {
      return Object.assign(editRuntime().summary.call(this, validation), { counts: { constructs: 400 }, chars: 500000 });
    },
    async contentHash() {
      const title = this.doc.title;
      await new Promise((r) => this.held.push(r));
      return { hash: "sha256:" + (title === "Title a" ? "07" : "1d").repeat(32) };
    },
  });
  const p = await page({}, rt);
  await openEditor(p);
  const record = p.$$("button").find((b) => b.textContent === "Record the current hash");
  const pressed = record.click();
  await until(() => rt.held.length === 1, "the hash to be asked for");
  // An edit typed while the hash is computed.
  fieldOf(p, "title").value = "Typed meanwhile";
  await fieldOf(p, "title").dispatch("input");
  rt.held.shift()();
  await pressed;
  assert.equal(p.$(".toast").textContent, "The theory changed while its hash was computed. Press Record again");
  assert.equal(fieldOf(p, "version.content_hash").value, "", "no hash is recorded");
  assert.equal(rt.doc.title, "Typed meanwhile");
});

test("Record the current hash says why it cannot record one, without asking twice", async () => {
  const rt = editRuntime({
    hashes: 0,
    async contentHash() { this.hashes++; return { error: "MemoryError" }; },
  });
  const p = await page({}, rt);
  await openEditor(p);
  await until(() => rt.hashes === 1 && /not computed/.test(p.$("#summaryHash").textContent), "the hash to fail");
  const record = p.$$("button").find((b) => b.textContent === "Record the current hash");
  await record.click();
  assert.equal(p.$(".toast").textContent, "The content hash could not be computed: MemoryError");
  assert.equal(rt.hashes, 1, "a hash that failed is not asked for again");
});

test("while a new theory is read, the forms and the source of the one before take no input", async () => {
  let release = null;
  const rt = editRuntime({
    gate: null,
    async writeText(fmt) { if (this.gate) await this.gate; return this.text(fmt); },
  });
  const p = await page({}, rt);
  await openEditor(p);
  await p.$("#tabResult").click();
  rt.gate = new Promise((r) => (release = r));
  await p.$("#fileInput").dispatch("change", { target: { files: [{ name: "other.yaml", text: async () => JSON.stringify(baseDoc("o")) }] } });
  await p.$("#tabEditor").click();
  const forms = p.$("#edForms"), src = p.$("#edSource");
  assert.equal(forms.inert, true, "the old forms take no input");
  assert.equal(src.readOnly, true, "the old source takes no input");
  // A browser blocks the input, and the stand-in DOM does not, so the change
  // made to the old forms must also be dropped.
  const title = fieldOf(p, "title");
  title.value = "Edit to the theory before";
  await title.dispatch("input");
  release();
  await until(() => forms.inert === false, "the new theory to be read");
  await wait(700);
  assert.equal(rt.doc.id, "o");
  assert.equal(rt.doc.title, "Title o");
  assert.ok(!rt.reads.some((r) => r[0] === "edit"), "nothing was applied to the theory: " + JSON.stringify(rt.reads));
  assert.equal(fieldOf(p, "title").getAttribute("value"), "Title o");
});
