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
