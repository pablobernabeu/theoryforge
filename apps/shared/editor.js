/* theoryforge interactive apps: the theory editor.
 *
 * A researcher builds or edits a theory in forms, one card for each entry,
 * kept in step with a source pane that holds the same theory as YAML or JSON
 * text and can be edited directly. The editor holds the theory as data and
 * hands every version to the engine, which reads it with the package's own
 * reader, validates it in full and scores it with the checklist, so the
 * problems and the score shown are the package's. The engine's writer gives
 * the source text after a change in the forms, and the forms are rebuilt from
 * the engine's reading after a change in the source.
 *
 * Import DAGitty hands model code to the package's own DAGitty reader
 * (read_dagitty() in Python, tf_read_dagitty() in R), whose theory replaces
 * the one in the editor, so the app has no reader of its own. The pure
 * helpers at the top need no page and are tested on their own
 * (apps/tests/editor.test.mjs).
 */
(function () {
  "use strict";

  // ---- pure helpers --------------------------------------------------------
  const isMap = (v) => v !== null && typeof v === "object" && !Array.isArray(v);
  const list = (v) => (Array.isArray(v) ? v : []);

  // The collection each validation message prefix names.
  const PREFIX = {
    construct: "constructs", proposition: "propositions", prediction: "predictions",
    assumption: "auxiliary_assumptions", alternative: "alternatives", evidence: "evidence",
    test_outcome: "test_outcomes", phenomenon: "phenomena", provenance: "provenance",
  };
  const COLLECTION_KEYS = ["constructs", "propositions", "phenomena", "predictions", "auxiliary_assumptions",
    "alternatives", "evidence", "test_outcomes", "provenance"];

  // The field a full-validation problem concerns, as a path such as
  // "predictions.2.claim", or "" when it concerns the theory as a whole. The
  // messages follow API_SPEC.md section 2, the same in R and in Python.
  function problemPath(msg, doc) {
    const m = String(msg || "").trim();
    let r;
    if ((r = /^missing\/empty required field: (\w+)/.exec(m))) return r[1];
    if ((r = /^(maturity|theory_form|schema_version|boundary_conditions)\b/.exec(m))) return r[1];
    if ((r = /^version (id|parent_id|content_hash)\b/.exec(m))) return "version." + r[1];
    if (/^version\b/.test(m)) return "version.id";
    if ((r = /^formal_model(?: (type|spec_ref))?\b/.exec(m))) return "formal_model." + (r[1] || "type");
    if ((r = /^(\w+) must be a list$/.exec(m)) && COLLECTION_KEYS.includes(r[1])) return r[1];
    if ((r = /^duplicate (construct|proposition|prediction|alternative|assumption|phenomenon) id: (.*)$/.exec(m))) {
      const key = PREFIX[r[1]];
      const items = list(doc && doc[key]);
      let seen = 0;
      for (let i = 0; i < items.length; i++) {
        if (isMap(items[i]) && items[i].id === r[2] && ++seen === 2) return key + "." + i + ".id";
      }
      return key;
    }
    r = /^(construct|proposition|prediction|assumption|alternative|evidence|test_outcome|phenomenon|provenance)\[(\d+)\](?: proposition\[(\d+)\])?\s*(.*)$/.exec(m);
    if (r) {
      let base = PREFIX[r[1]] + "." + r[2];
      if (r[3] != null) base += ".propositions." + r[3];
      const rest = r[4];
      let f;
      if ((f = /^missing\/empty (\w+)/.exec(rest))) return base + "." + f[1];
      if (/^duplicate proposition id/.test(rest)) return base + ".propositions";
      if ((f = /^(\w+)\b/.exec(rest))) return base + "." + f[1];
      return base;
    }
    return "";
  }

  // A theory to start from, which validates and has nothing in it yet.
  function templateTheory() {
    return {
      schema_version: "1.1", id: "new-theory", title: "Untitled theory", maturity: "draft", theory_form: "network",
      version: { id: "v1", parent_id: null },
      constructs: [], propositions: [], predictions: [],
    };
  }

  // A fresh id with `prefix` and the first free number.
  function nextId(prefix, taken) {
    let n = 1;
    for (const t of taken) {
      const m = new RegExp("^" + prefix.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "(\\d+)$").exec(String(t));
      if (m) n = Math.max(n, Number(m[1]) + 1);
    }
    while (taken.has(prefix + n)) n++;
    return prefix + n;
  }
  // ---- paths into the theory ----------------------------------------------
  const segs = (path) => String(path).split(".").map((s) => (/^\d+$/.test(s) ? Number(s) : s));
  function getAt(doc, path) {
    let v = doc;
    for (const s of segs(path)) { if (v == null || typeof v !== "object") return undefined; v = v[s]; }
    return v;
  }
  // The mappings that exist only to hold their fields, which go when emptied.
  const HOLDERS = ["version", "formal_model", "bounds", "claim"];
  function setAt(doc, path, value) {
    const ss = segs(path);
    let v = doc;
    for (let i = 0; i < ss.length - 1; i++) {
      if (!isMap(v[ss[i]]) && !Array.isArray(v[ss[i]])) v[ss[i]] = {};
      v = v[ss[i]];
    }
    v[ss[ss.length - 1]] = value;
  }
  function delAt(doc, path) {
    const ss = segs(path);
    const parents = [doc];
    let v = doc;
    for (let i = 0; i < ss.length - 1; i++) { if (v == null || typeof v !== "object") return; v = v[ss[i]]; parents.push(v); }
    if (!isMap(v)) return;
    delete v[ss[ss.length - 1]];
    for (let i = ss.length - 2; i >= 0; i--) {
      const holder = parents[i + 1];
      if (HOLDERS.includes(ss[i]) && isMap(holder) && !Object.keys(holder).length) delete parents[i][ss[i]];
      else break;
    }
  }

  // ---- the forms -----------------------------------------------------------
  const RELATIONS = ["increases", "decreases", "causes", "mediates", "moderates", "associates"];
  const PROP_FIELDS = [
    { k: "id", label: "Id", type: "text", required: true },
    { k: "from", label: "From", type: "ref", of: "constructs", required: true },
    { k: "relation", label: "Relation", type: "enum", options: RELATIONS, required: true },
    { k: "to", label: "To", type: "ref", of: "constructs", required: true },
    { k: "mechanism", label: "Mechanism (why the relation holds)", type: "textarea", wide: true },
  ];
  const HEADER = [
    { k: "id", label: "Id", type: "text", required: true },
    { k: "title", label: "Title", type: "text", required: true, wide: true },
    { k: "maturity", label: "Maturity", type: "enum", options: ["draft", "building", "developing", "testing"], required: true },
    { k: "theory_form", label: "Form", type: "enum", options: ["variance", "network", "typology", "process"] },
    { k: "schema_version", label: "Schema version", type: "text", required: true },
    { k: "version.id", label: "Version", type: "text" },
    { k: "version.parent_id", label: "Parent version", type: "text" },
    { k: "version.content_hash", label: "Recorded content hash", type: "hash", wide: true },
    { k: "formal_model.type", label: "Formal model", type: "enum", options: ["ode", "abm", "network", "sem", "none"] },
    { k: "formal_model.spec_ref", label: "Formal model file or reference", type: "text" },
    { k: "boundary_conditions", label: "Boundary conditions of the theory (one per line)", type: "lines", wide: true },
  ];
  const SECTIONS = [
    { key: "constructs", title: "Constructs", item: "construct", idPrefix: "c_new",
      help: "The entities the theory is about. Each has an id that the propositions use, a label, a definition, the measures that index it and the conditions under which it is claimed to hold.",
      blank: (id) => ({ id, label: "", definition: "" }),
      fields: [
        { k: "id", label: "Id", type: "text", required: true },
        { k: "label", label: "Label", type: "text", required: true },
        { k: "definition", label: "Definition", type: "textarea", required: true, wide: true },
        { k: "measurement", label: "Measures (one per line)", type: "lines" },
        { k: "boundary_conditions", label: "Boundary conditions (one per line)", type: "lines" },
      ] },
    { key: "propositions", title: "Propositions", item: "proposition", idPrefix: "p",
      help: "Relations between constructs. increases and decreases state a sign, causes and mediates a direction without one, moderates that one construct changes another's effect, and associates a covariance the theory leaves unexplained. The mechanism says why the relation holds.",
      blank: (id) => ({ id, from: "", to: "", relation: "" }),
      fields: PROP_FIELDS.concat([{ k: "functional_form", label: "Functional form", type: "text" }]) },
    { key: "phenomena", title: "Phenomena", item: "phenomenon", idPrefix: "ph",
      help: "The robust regularities the theory sets out to explain. A claim in machine-readable form lets 'What the graph entails' read the phenomenon against the propositions.",
      blank: (id) => ({ id, statement: "" }),
      fields: [
        { k: "id", label: "Id", type: "text", required: true },
        { k: "source_doi", label: "Source DOI", type: "text" },
        { k: "statement", label: "Statement", type: "textarea", required: true, wide: true },
        { k: "claim", label: "Claim", type: "claim", wide: true },
      ] },
    { key: "predictions", title: "Predictions", item: "prediction", idPrefix: "pred",
      help: "What the theory forbids. The type ranks how much a claim risks, from existence to point. derives_from names the propositions it follows from, diagnostic_vs the rivals it tells the theory apart from, the bounds the region of the quantity the claim allows and the claim the two constructs and the sign it concerns.",
      blank: (id) => ({ id, statement: "", type: "", derives_from: [], diagnostic_vs: [] }),
      fields: [
        { k: "id", label: "Id", type: "text", required: true },
        { k: "type", label: "Type", type: "enum", options: ["existence", "directional", "interval", "point"], required: true },
        { k: "severity", label: "Declared severity (0 to 1)", type: "number", min: 0, max: 1 },
        { k: "statement", label: "Statement", type: "textarea", required: true, wide: true },
        { k: "derives_from", label: "Derives from (propositions)", type: "refs", of: "propositions", wide: true },
        { k: "diagnostic_vs", label: "Diagnostic against (alternatives)", type: "refs", of: "alternatives", wide: true },
        { k: "bounds", label: "Bounds of the quantity the claim allows", type: "bounds", wide: true },
        { k: "claim", label: "Claim", type: "claim", wide: true },
      ] },
    { key: "auxiliary_assumptions", title: "Auxiliary assumptions", item: "assumption", idPrefix: "aux",
      help: "Assumptions a prediction needs besides the propositions. A core assumption is added for no prediction. One added in answer to a failed prediction names it, and the checklist treats it as ad hoc unless another prediction it protects is corroborated.",
      blank: (id) => ({ id, statement: "", added_for: null, protects: [] }),
      fields: [
        { k: "id", label: "Id", type: "text", required: true },
        { k: "added_for", label: "Added for", type: "ref", of: "predictions", none: "no prediction (core)" },
        { k: "statement", label: "Statement", type: "textarea", required: true, wide: true },
        { k: "protects", label: "Protects (predictions)", type: "refs", of: "predictions", wide: true },
      ] },
    { key: "alternatives", title: "Alternatives", item: "alternative", idPrefix: "alt",
      help: "Rival accounts of the same phenomena. Propositions written over this theory's constructs let 'Compare with a rival' set the rival's causal graph against the theory's.",
      blank: (id) => ({ id, label: "" }),
      fields: [
        { k: "id", label: "Id", type: "text", required: true },
        { k: "label", label: "Label", type: "text", required: true },
        { k: "source_doi", label: "Source DOI", type: "text" },
        { k: "key_constructs", label: "Key constructs (one per line)", type: "lines" },
        { k: "propositions", label: "The rival's propositions", type: "nested", wide: true },
      ] },
    { key: "evidence", title: "Evidence", item: "evidence entry", idPrefix: "",
      help: "Published findings for or against a prediction, each with its DOI.",
      blank: () => ({ supports: "", direction: "" }),
      fields: [
        { k: "supports", label: "Supports (prediction)", type: "ref", of: "predictions", required: true },
        { k: "direction", label: "Direction", type: "enum", options: ["corroborates", "refutes", "mixed"], required: true },
        { k: "source_doi", label: "Source DOI", type: "text" },
      ] },
    { key: "test_outcomes", title: "Test outcomes", item: "test outcome", idPrefix: "",
      help: "The record of each test of a prediction. An estimate and its standard error, on the scale of the prediction's bounds, let 'Post-data severity' compute how severely the claim passed.",
      blank: () => ({ prediction_id: "" }),
      fields: [
        { k: "prediction_id", label: "Prediction", type: "ref", of: "predictions", required: true },
        { k: "passed", label: "Passed", type: "bool", required: true },
        { k: "date", label: "Date", type: "text" },
        { k: "registered", label: "Registered at", type: "text" },
        { k: "estimate", label: "Estimate", type: "number" },
        { k: "se", label: "Standard error", type: "number", min: 0 },
        { k: "observed", label: "Observed", type: "textarea", wide: true },
      ] },
  ];

  const short = (s, n) => { s = String(s == null ? "" : s); return s.length > n ? s.slice(0, n - 1) + "…" : s; };

  function create(host, panel) {
    const { el } = host;
    let doc = null, stale = true, built = false, loading = null;
    let format = "yaml", view = null, srcError = null;
    let timer = null, origin = null, inflight = null, again = false;
    let fieldIndex = new Map(), inputIndex = new Map(), problems = [];
    const openSecs = new Set(["theory", "constructs", "propositions", "predictions"]);
    let formsEl, srcArea, lintEl, srcNote, srcLabel, bodyEl;

    const visible = () => !panel.hasAttribute("hidden");

    // ---- building ----------------------------------------------------------
    function build() {
      if (built) return;
      built = true;
      view = (typeof window !== "undefined" && window.innerWidth >= 1280) ? "both" : "forms";
      const seg = (label, on, pressed) => el("button", { class: "btn ghost sm seg", "aria-pressed": pressed ? "true" : "false", onclick: on }, label);
      const viewBtns = [["Forms", "forms"], ["Source", "source"], ["Side by side", "both"]].map(([l, v]) => {
        const b = seg(l, () => setView(v), v === view);
        b.setAttribute("data-view", v);
        return b;
      });
      const fmtBtns = [["YAML", "yaml"], ["JSON", "json"]].map(([l, v]) => {
        const b = seg(l, () => setFormat(v), v === format);
        b.setAttribute("data-format", v);
        return b;
      });
      const toolbar = el("div", { class: "ed-toolbar" }, [
        el("button", { class: "btn sm", id: "edNew", onclick: () => newTheory() }, "New theory"),
        el("button", { class: "btn ghost sm", id: "edImport", onclick: openImport, disabled: host.canImportDagitty() ? null : "",
          title: host.canImportDagitty() ? "Make a new theory of DAGitty model code with the package's reader" : "This version of the package has no DAGitty reader" }, "Import DAGitty…"),
        el("button", { class: "btn ghost sm", id: "edSave", onclick: save }, "Save YAML"),
        el("span", { class: "grow" }),
        el("span", { class: "segwrap", role: "group", "aria-label": "Editor view" }, viewBtns),
      ]);
      lintEl = el("div", { class: "ed-lint", id: "edLint" });
      formsEl = el("div", { class: "ed-forms", id: "edForms" });
      srcLabel = el("label", { for: "edSource", id: "edSourceLabel" }, "Source (YAML)");
      srcArea = el("textarea", { id: "edSource", class: "ed-src", spellcheck: "false", autocomplete: "off", autocapitalize: "off", wrap: "off", rows: "30",
        oninput: () => schedule("source") });
      srcNote = el("p", { class: "note ed-srcnote", id: "edSrcNote" }, "Changes made in the forms rewrite this text in the package's own layout, which keeps no comments. Changes typed here are read by the package as you type.");
      const srcPane = el("div", { class: "ed-source" }, [
        el("div", { class: "ed-srchead" }, [srcLabel, el("span", { class: "grow" }), el("span", { class: "segwrap", role: "group", "aria-label": "Source format" }, fmtBtns)]),
        srcArea, srcNote,
      ]);
      bodyEl = el("div", { class: "ed-body view-" + view }, [formsEl, srcPane]);
      panel.replaceChildren(el("div", { class: "panel editor" }, [
        el("div", { class: "outhead" }, [el("h2", null, "Theory editor"), el("span", { class: "grow" })]),
        el("p", { class: "note ed-intro" }, "Build or edit the theory in the forms or in the source. The package reads each change, validates it in full and scores it with the rigour checklist, and the problems appear beside the fields they concern. Save writes the theory as YAML with the package's own writer."),
        toolbar, lintEl, bodyEl,
      ]));
    }
    function setView(v) {
      view = v;
      bodyEl.className = "ed-body view-" + v;
      for (const b of panel.querySelectorAll(".seg")) if (b.getAttribute("data-view")) b.setAttribute("aria-pressed", b.getAttribute("data-view") === v ? "true" : "false");
    }
    async function setFormat(f) {
      if (f === format) return;
      await flush();
      if (srcError) { host.toast("Correct the source first: it cannot be read as " + format.toUpperCase()); return; }
      try {
        const text = await host.writeText(f);
        format = f;
        setSource(text);
        host.setSource(text);
      } catch (err) { host.toast("The theory could not be written as " + f.toUpperCase()); return; }
      for (const b of panel.querySelectorAll(".seg")) if (b.getAttribute("data-format")) b.setAttribute("aria-pressed", b.getAttribute("data-format") === f ? "true" : "false");
      srcLabel.textContent = "Source (" + f.toUpperCase() + ")";
    }
    function setSource(text) { srcArea.value = text; }

    // ---- loading the active theory -----------------------------------------
    async function load() {
      stale = false;
      try {
        const data = await host.theoryData();
        doc = isMap(data) ? data : {};
      } catch (err) {
        doc = null;
        formsEl.replaceChildren(host.errorBox("The theory could not be read into the forms", err));
        return;
      }
      const name = host.sourceName() || "";
      let text = host.sourceOf();
      const fmt = /\.json$/i.test(name) ? "json" : "yaml";
      if (text == null) { text = await host.writeText(format); }
      else if (fmt !== format) { format = fmt; srcLabel.textContent = "Source (" + fmt.toUpperCase() + ")"; }
      for (const b of panel.querySelectorAll(".seg")) if (b.getAttribute("data-format")) b.setAttribute("aria-pressed", b.getAttribute("data-format") === format ? "true" : "false");
      srcError = null;
      setSource(text);
      render();
      lint(host.summary());
    }
    async function open() {
      build();
      if (stale) { loading = load(); await loading; }
    }
    // A new theory has been loaded, so a change still waiting for the timer
    // belongs to the theory before it and is dropped rather than applied to
    // the new one.
    function reload() {
      clearTimeout(timer); timer = null; origin = null; again = false;
      unlock();
      stale = true;
      if (built && visible()) open();
    }

    // ---- syncing with the engine -------------------------------------------
    // The forms and the source are two views of one theory, and a change in
    // one reaches the other only once the engine has read it. Until then, the
    // other pane takes no input, so that an edit there cannot be overwritten by
    // the change still on its way, or overwrite it: the forms are inert while
    // a change typed in the source waits or is being read, and the source is
    // read-only while a change made in the forms does.
    function lockFor(from) {
      if (!formsEl || !srcArea) return;
      if (from === "source") { formsEl.inert = true; formsEl.setAttribute("aria-busy", "true"); }
      else srcArea.readOnly = true;
    }
    function unlock() {
      if (timer || inflight || again || !formsEl || !srcArea) return;
      formsEl.inert = false; formsEl.removeAttribute("aria-busy"); srcArea.readOnly = false;
    }
    function schedule(from) {
      origin = from;
      lockFor(from);
      clearTimeout(timer);
      timer = setTimeout(() => { timer = null; sync(); }, 450);
    }
    async function sync() {
      if (inflight) { again = true; return inflight; }
      const from = origin || "forms";
      origin = null;
      inflight = (async () => {
        if (from === "source") {
          const text = srcArea.value;
          const res = await host.apply(text, format, ["json"], {});
          if (res.ok) {
            srcError = null;
            try { doc = JSON.parse(res.texts.json); } catch (e) { /* keep the forms as they are */ }
            render();
            host.setSource(text);
            lint(res.summary);
          } else {
            srcError = res.error;
            lint(host.summary());
          }
        } else if (doc) {
          const res = await host.apply(JSON.stringify(doc, null, 2), "json", [format], { doc });
          if (res.ok) {
            srcError = null;
            const t = res.texts[format];
            // A source with the focus is rewritten too while it is read-only,
            // since nothing can have been typed into it, and the caret stays
            // where it was.
            if (typeof t === "string" && (srcArea.readOnly || document.activeElement !== srcArea)) {
              const a = srcArea.selectionStart, b = srcArea.selectionEnd;
              setSource(t); host.setSource(t);
              if (document.activeElement === srcArea && typeof srcArea.setSelectionRange === "function") {
                try { srcArea.setSelectionRange(Math.min(a, t.length), Math.min(b, t.length)); } catch (e) { /* no selection */ }
              }
            }
            lint(res.summary);
          } else {
            lint(host.summary(), res.error);
          }
        }
      })();
      try { await inflight; }
      catch (e) { again = false; throw e; }
      finally { inflight = null; unlock(); }
      if (again) { again = false; await sync(); }
    }
    async function flush() {
      if (loading) await loading;
      if (timer) { clearTimeout(timer); timer = null; await sync(); }
      else if (inflight) await inflight;
    }
    function changed(structural) {
      if (structural) render();
      updateHeads();
      schedule("forms");
    }

    // ---- new theory, import and save --------------------------------------
    async function newTheory() {
      build();
      await flush();
      if (host.mayDiscard && !host.mayDiscard("Start a new theory")) return;
      doc = templateTheory();
      stale = false;
      srcError = null;
      const res = await host.apply(JSON.stringify(doc, null, 2), "json", [format], { fresh: true, isNew: true, doc });
      if (res.ok) { setSource(res.texts[format] || ""); host.setSource(srcArea.value); }
      render();
      lint(res.ok ? res.summary : host.summary(), res.ok ? null : res.error);
      host.toast("Started a new theory. Give it an id and a title, then add its constructs.");
      const first = inputIndex.get("id");
      if (first) first.focus();
    }
    async function save() {
      await flush();
      let text;
      try { text = await host.writeText("yaml"); }
      catch (err) { host.toast("The theory could not be written"); return; }
      const name = host.saveName ? host.saveName(doc) : "theory.yaml";
      host.download(name, text, "application/yaml");
      const s = host.summary(), v = s && s.validation;
      const n = v && !v.ok ? host.problemList(v).length : 0;
      host.toast(srcError ? "Saved " + name + " as the package last read it: the source as typed cannot be read."
        : n ? "Saved " + name + ". The theory has " + host.plural(n, "problem") + ", which the file keeps." : "Saved " + name + ".");
    }

    function openImport() {
      build();
      if (!host.canImportDagitty()) { host.toast("This version of the package has no DAGitty reader"); return; }
      const area = el("textarea", { class: "ed-src", id: "dagText", rows: "10", spellcheck: "false",
        placeholder: 'dag {\n  "Physiological arousal" -> "Perceived threat" -> Avoidance\n  "Physiological arousal" <-> Mood\n}' });
      const id = el("input", { type: "text", id: "dagId", placeholder: "dagitty-import" });
      const title = el("input", { type: "text", id: "dagTitle", placeholder: "Causal diagram imported from DAGitty" });
      const relation = el("select", { id: "dagRelation" }, [
        el("option", { value: "causes" }, "causes (a direction without a sign)"),
        el("option", { value: "increases" }, "increases"),
        el("option", { value: "decreases" }, "decreases"),
      ]);
      const opts = () => ({ id: id.value.trim(), title: title.value.trim(), relation: relation.value });
      const code = el("pre", { class: "text", id: "dagCode" });
      const showCode = () => { code.textContent = host.importCode(opts()); };
      for (const x of [id, title]) x.addEventListener("input", showCode);
      relation.addEventListener("change", showCode);
      showCode();
      const status = el("div", { id: "dagStatus", role: "status" });
      const go = el("button", { class: "btn", id: "dagImport", onclick: async () => {
        if (!area.value.trim()) { host.toast("Paste the model code first"); return; }
        await flush();
        go.disabled = true;
        const res = await host.importDagitty(area.value, opts(), [format, "json"]);
        go.disabled = false;
        if (!res.ok) { status.replaceChildren(host.errorBox("The package's DAGitty reader refused the model", res.error)); return; }
        try { doc = JSON.parse(res.texts.json); } catch (e) { doc = {}; }
        stale = false;
        srcError = null;
        setSource(res.texts[format] || "");
        host.setSource(srcArea.value);
        host.closeModal();
        render();
        lint(res.summary);
        const c = res.summary.counts || {};
        host.toast("Imported " + host.plural(c.constructs || 0, "construct") + " and " + host.plural(c.propositions || 0, "proposition") + ". Give each construct a definition.");
      } }, "Import");
      host.openModal("Import a DAGitty model", el("div", { class: "help" }, [
        el("p", null, "The package's DAGitty reader makes a new theory of the model, which replaces the theory in the editor, so save that one first if you want to keep it. Each variable becomes a construct, with its name as its id and label, and each edge a proposition. A -> B reads as B depending on A, and A <- B the other way round. A <-> B, an association that a common cause would explain, becomes associates. Attributes in square brackets and settings such as bb are ignored, and an undirected edge, which no proposition states, is refused."),
        el("label", { class: "field" }, [el("span", null, "DAGitty model code"), area]),
        el("div", { class: "efrow" }, [
          el("label", { class: "field sub" }, [el("span", null, "Read A -> B as"), relation]),
          el("label", { class: "field sub" }, [el("span", null, "Id of the new theory"), id]),
          el("label", { class: "field sub" }, [el("span", null, "Title"), title]),
        ]),
        status,
        el("details", null, [el("summary", null, "The same import in " + host.lang()), code]),
        el("div", { class: "modal-actions" }, [el("button", { class: "btn ghost", onclick: host.closeModal }, "Cancel"), go]),
      ]), { wide: true, focus: area });
    }

    // ---- rendering the forms -----------------------------------------------
    const ids = (key) => list(doc && doc[key]).filter(isMap).map((x) => x.id).filter((x) => typeof x === "string" && x);

    function fieldWrap(path, label, input, spec) {
      const probs = el("ul", { class: "fp", id: "fp-" + path.replace(/\./g, "-") });
      const w = el("div", { class: "ef" + (spec && spec.wide ? " wide" : "") + (spec && spec.required ? " req" : "") }, [
        el("span", { class: "efl", id: lblId(path) }, label + (spec && spec.required ? " *" : "")), input, probs]);
      fieldIndex.set(path, w);
      return w;
    }
    const lblId = (path) => "lbl-" + path.replace(/\./g, "-");
    // Record an input under its path, so focus can return to it after the
    // forms are rebuilt. `labelled` names it by its field's label, which an
    // input inside a label element of its own does not need.
    function track(path, input, labelled) {
      input.setAttribute("data-k", path);
      if (labelled !== false) input.setAttribute("aria-labelledby", labelled || lblId(path));
      inputIndex.set(path, input);
      return input;
    }
    const textValue = (v) => (typeof v === "string" ? v : v == null ? "" : typeof v === "object" ? JSON.stringify(v) : String(v));

    // One field of the theory at `path`, described by `spec`.
    function field(spec, path) {
      const v = getAt(doc, path);
      const req = !!spec.required;
      const set = (val) => setAt(doc, path, val);
      const del = () => delAt(doc, path);
      let input;
      switch (spec.type) {
        case "text":
        case "textarea": {
          input = el(spec.type === "text" ? "input" : "textarea", spec.type === "text" ? { type: "text", value: textValue(v) } : { rows: "2" });
          if (spec.type === "textarea") input.value = textValue(v);
          input.addEventListener("input", () => {
            const s = input.value;
            if (s === "" && !req) del(); else set(s);
            changed(false);
          });
          // A new id changes the choices other fields offer, so the forms are
          // rebuilt, once the focus has reached the field the user moved to,
          // which the rebuild then focuses again.
          if (spec.k === "id") input.addEventListener("change", () => setTimeout(() => changed(true), 0));
          break;
        }
        case "hash": {
          const box = el("input", { type: "text", value: textValue(v), placeholder: "none recorded" });
          track(path, box);
          box.addEventListener("input", () => { if (box.value === "") del(); else set(box.value); changed(false); });
          const use = el("button", { class: "btn ghost sm", type: "button", onclick: () => {
            const s = host.summary();
            if (!s || !s.hash) { host.toast("The current hash is not known yet"); return; }
            box.value = s.hash; set(s.hash); changed(false);
          } }, "Record the current hash");
          return fieldWrap(path, spec.label, el("div", { class: "efrow" }, [box, use]), spec);
        }
        case "lines": {
          input = el("textarea", { rows: "2" });
          input.value = Array.isArray(v) ? v.map(textValue).join("\n") : textValue(v);
          input.addEventListener("input", () => {
            const arr = input.value.split("\n").map((s) => s.trim()).filter(Boolean);
            if (arr.length) set(arr); else del();
            changed(false);
          });
          break;
        }
        case "enum": {
          const opts = (req ? [["", "Choose…"]] : [["", "—"]]).concat(spec.options.map((o) => [o, o]));
          if (v != null && v !== "" && !spec.options.includes(v)) opts.push([textValue(v), textValue(v) + " (not allowed)"]);
          input = el("select", null, opts.map(([val, l]) => el("option", { value: val }, l)));
          input.value = v == null ? "" : textValue(v);
          input.addEventListener("change", () => { if (input.value === "") { if (req) set(""); else del(); } else set(input.value); changed(false); });
          break;
        }
        case "ref": {
          const known = ids(spec.of);
          const opts = [["", spec.none || "Choose…"]].concat(known.map((x) => [x, x]));
          if (typeof v === "string" && v && !known.includes(v)) opts.push([v, v + " (not declared)"]);
          input = el("select", null, opts.map(([val, l]) => el("option", { value: val }, l)));
          input.value = typeof v === "string" ? v : "";
          input.addEventListener("change", () => {
            if (input.value === "") { if (spec.none) set(null); else if (req) set(""); else del(); }
            else set(input.value);
            changed(false);
          });
          break;
        }
        case "refs": {
          const known = ids(spec.of);
          const cur = Array.isArray(v) ? v.filter((x) => typeof x === "string") : typeof v === "string" && v ? [v] : [];
          const all = known.concat(cur.filter((x) => !known.includes(x)));
          if (!all.length) {
            input = el("span", { class: "note", text: "No " + spec.of + " declared yet." });
            return fieldWrap(path, spec.label, input, spec);
          }
          const boxes = all.map((x) => {
            const cb = el("input", { type: "checkbox", value: x });
            cb.checked = cur.includes(x);
            cb.addEventListener("change", () => {
              const now = boxes.filter((b) => b.checked).map((b) => b.value);
              set(now);
              changed(false);
            });
            track(path + "#" + x, cb, false);
            return cb;
          });
          // The group is named by the field's label, so a screen reader says
          // which relation a box sets as well as the id beside it.
          input = el("div", { class: "checks", role: "group", "aria-labelledby": lblId(path) }, all.map((x, i) =>
            el("label", { class: "check" }, [boxes[i], " " + x + (known.includes(x) ? "" : " (not declared)")])));
          return fieldWrap(path, spec.label, input, spec);
        }
        case "number": {
          input = el("input", { type: "number", step: "any", value: typeof v === "number" ? String(v) : textValue(v), min: spec.min, max: spec.max });
          input.addEventListener("input", () => {
            const s = input.value.trim();
            if (s === "") del();
            else { const n = Number(s); if (Number.isFinite(n)) set(n); }
            changed(false);
          });
          break;
        }
        case "bool": {
          input = el("select", null, [el("option", { value: "" }, "Choose…"), el("option", { value: "true" }, "yes"), el("option", { value: "false" }, "no")]);
          input.value = v === true ? "true" : v === false ? "false" : "";
          input.addEventListener("change", () => { if (input.value === "") del(); else set(input.value === "true"); changed(false); });
          break;
        }
        case "bounds": {
          const b = isMap(v) ? v : {};
          const one = (side) => {
            const inp = el("input", { type: "number", step: "any", placeholder: "open", value: typeof b[side] === "number" ? String(b[side]) : "",
              "aria-label": spec.label + ", " + side });
            track(path + "#" + side, inp, false);
            inp.addEventListener("input", () => {
              const cur = isMap(getAt(doc, path)) ? getAt(doc, path) : {};
              const s = inp.value.trim();
              const n = s === "" ? null : Number(s);
              const next = Object.assign({ lower: null, upper: null }, cur, { [side]: Number.isFinite(n) ? n : null });
              if (next.lower == null && next.upper == null) del(); else set(next);
              changed(false);
            });
            return el("label", { class: "sub" }, [el("span", null, side === "lower" ? "lower" : "upper"), inp]);
          };
          return fieldWrap(path, spec.label, el("div", { class: "efrow" }, [one("lower"), one("upper"),
            el("span", { class: "note", text: "Leave a side empty for an open bound." })]), spec);
        }
        case "claim": return claimField(spec, path);
        case "nested": return nestedField(spec, path);
        default: input = el("span", { text: textValue(v) });
      }
      track(path, input);
      return fieldWrap(path, spec.label, input, spec);
    }

    // A claim about two constructs: the kind, x, y, the sign and, for an
    // association, the constructs held fixed.
    function claimField(spec, path) {
      const c = isMap(getAt(doc, path)) ? getAt(doc, path) : null;
      const kind = c ? c.kind : "";
      const sub = (k, label, spec2) => {
        const w = field(Object.assign({ k }, spec2), path + "." + k);
        w.classList.add("sub");
        w.querySelector(".efl").textContent = label;
        // A field of boxes registers no input under its own path, so its
        // group takes the claim's label in the input's place.
        const inp = inputIndex.get(path + "." + k) || w.querySelector(".checks");
        if (inp) inp.setAttribute("aria-labelledby", lblId(path) + " " + lblId(path + "." + k));
        return w;
      };
      const kindSel = el("select", null, [el("option", { value: "" }, "no claim"), el("option", { value: "effect" }, "effect of x on y"), el("option", { value: "association" }, "association of x and y")]);
      kindSel.value = kind === "effect" || kind === "association" ? kind : "";
      track(path + ".kind", kindSel, lblId(path) + " " + lblId(path + ".kind"));
      kindSel.addEventListener("change", () => {
        if (!kindSel.value) delAt(doc, path);
        else {
          const cur = isMap(getAt(doc, path)) ? getAt(doc, path) : {};
          const next = Object.assign({ kind: "", x: "", y: "", sign: "" }, cur, { kind: kindSel.value });
          if (next.kind === "effect") delete next.given;
          setAt(doc, path, next);
        }
        changed(true);
      });
      const kids = [el("label", { class: "sub" }, [el("span", { id: lblId(path + ".kind") }, "kind"), kindSel])];
      if (c) {
        kids.push(sub("x", "x", { type: "ref", of: "constructs", required: true }));
        kids.push(sub("y", "y", { type: "ref", of: "constructs", required: true }));
        kids.push(sub("sign", "sign", { type: "enum", options: ["positive", "negative", "zero", "nonzero"], required: true }));
        if (kind === "association") kids.push(sub("given", "given (held fixed)", { type: "refs", of: "constructs" }));
      }
      return fieldWrap(path, spec.label, el("div", { class: "efrow claim" }, kids), spec);
    }

    // The propositions of an alternative, each a small card.
    function nestedField(spec, path) {
      const v = getAt(doc, path);
      if (v != null && !Array.isArray(v)) return fieldWrap(path, spec.label, el("p", { class: "note", text: "This field holds something other than a list. Correct it in the source." }), spec);
      const rows = list(v).map((p, j) => {
        const pp = path + "." + j;
        if (!isMap(p)) return el("p", { class: "note", text: "Entry " + (j + 1) + " is not a mapping. Correct it in the source." });
        const del = el("button", { class: "btn ghost sm rm", type: "button", "aria-label": "Remove the rival's proposition " + (p.id || j + 1),
          onclick: () => { list(getAt(doc, path)).splice(j, 1); if (!list(getAt(doc, path)).length) delAt(doc, path); changed(true); focusAfterRemove(path, j); } }, "Remove");
        const card = el("div", { class: "ecard nested" }, [el("div", { class: "eh" }, [el("span", { class: "et", text: p.id || "(no id)" }), el("span", { class: "grow" }), del]),
          el("div", { class: "efgrid" }, PROP_FIELDS.map((f) => field(f, pp + "." + f.k)))]);
        fieldIndex.set(pp, card);
        return card;
      });
      const add = el("button", { class: "btn ghost sm nestadd", type: "button", onclick: () => {
        const cur = Array.isArray(getAt(doc, path)) ? getAt(doc, path) : [];
        const taken = new Set(cur.filter(isMap).map((p) => p.id));
        const altId = String((getAt(doc, path.replace(/\.propositions$/, "")) || {}).id || "r");
        // The rival's own letters, so that alt_reinforcement's propositions
        // are rei1, rei2, ..., and an id with none, such as alt1, gives r1.
        const prefix = altId.replace(/^alt_?/, "").replace(/[^A-Za-z]/g, "").slice(0, 3) || "r";
        cur.push({ id: nextId(prefix, taken), from: "", to: "", relation: "" });
        setAt(doc, path, cur);
        changed(true);
      } }, "Add a proposition of this rival");
      return fieldWrap(path, spec.label, el("div", { class: "nestwrap" }, rows.concat([add])), spec);
    }

    function itemTitle(sec, it) {
      if (!isMap(it)) return "(not a mapping)";
      if (sec.key === "evidence") return (it.supports || "?") + " · " + (it.direction || "");
      if (sec.key === "test_outcomes") return (it.prediction_id || "?") + " · " + (it.passed === true ? "passed" : it.passed === false ? "failed" : "no result");
      if (sec.key === "propositions") return (it.id || "(no id)") + " · " + (it.from || "?") + " " + (it.relation || "?") + " " + (it.to || "?");
      return (it.id || "(no id)") + (it.label || it.statement ? " · " + short(it.label || it.statement, 60) : "");
    }

    function sectionEl(sec) {
      const raw = doc[sec.key];
      const items = list(raw);
      const det = el("details", { class: "ed-sec", "data-sec": sec.key, open: openSecs.has(sec.key) ? "" : null });
      det.addEventListener("toggle", () => { if (det.open) openSecs.add(sec.key); else openSecs.delete(sec.key); });
      const head = el("summary", null, [el("span", { class: "st", text: sec.title }), el("span", { class: "cnt", text: String(items.length) }),
        el("span", { class: "sp", id: "sp-" + sec.key })]);
      const kids = [head, el("p", { class: "note ed-help", text: sec.help })];
      if (raw != null && !Array.isArray(raw) && !(isMap(raw) && !Object.keys(raw).length)) {
        kids.push(el("p", { class: "caution", text: "This field holds something other than a list. Correct it in the source." }));
        det.append(...kids);
        fieldIndex.set(sec.key, det);
        return det;
      }
      items.forEach((it, i) => {
        const path = sec.key + "." + i;
        const rm = el("button", { class: "btn ghost sm rm", type: "button", "aria-label": "Remove " + sec.item + " " + (isMap(it) && it.id ? it.id : i + 1),
          onclick: () => { doc[sec.key].splice(i, 1); changed(true); focusAfterRemove(sec.key, i); } }, "Remove");
        const card = el("div", { class: "ecard", id: "card-" + path.replace(/\./g, "-") }, [
          el("div", { class: "eh" }, [el("span", { class: "et", text: itemTitle(sec, it) }), el("span", { class: "grow" }), rm]),
          isMap(it) ? el("div", { class: "efgrid" }, sec.fields.map((f) => field(f, path + "." + f.k)))
            : el("p", { class: "caution", text: "This entry is not a mapping. Correct it in the source." }),
          el("ul", { class: "fp", id: "fp-" + path.replace(/\./g, "-") }),
        ]);
        fieldIndex.set(path, card);
        kids.push(card);
      });
      kids.push(el("button", { class: "btn ghost sm add", type: "button", onclick: () => {
        if (!Array.isArray(doc[sec.key])) doc[sec.key] = [];
        const taken = new Set(doc[sec.key].filter(isMap).map((x) => x.id));
        doc[sec.key].push(sec.blank(sec.idPrefix ? nextId(sec.idPrefix, taken) : ""));
        openSecs.add(sec.key);
        changed(true);
        const k = sec.key + "." + (doc[sec.key].length - 1) + "." + sec.fields[sec.fields[0].k === "id" ? 1 : 0].k;
        const inp = inputIndex.get(k);
        if (inp) inp.focus();
      } }, "Add " + sec.item));
      det.append(...kids);
      fieldIndex.set(sec.key, det);
      return det;
    }

    // A removal rebuilds the forms, so the Remove button that had the focus
    // is gone. The focus goes to the Remove button of the entry now in the
    // same place, or of the last entry, or else to the list's Add button.
    // changed(true) rebuilds the forms at once, so the new cards are indexed.
    function focusAfterRemove(path, i) {
      const n = list(getAt(doc, path)).length;
      const card = n ? fieldIndex.get(path + "." + Math.min(i, n - 1)) : null;
      const wrap = fieldIndex.get(path);
      const target = card ? card.querySelector(".rm")
        : wrap && (wrap.querySelector(".add") || wrap.querySelector(".nestadd"));
      if (target) target.focus();
    }

    function render() {
      if (!formsEl) return;
      const active = typeof document !== "undefined" ? document.activeElement : null;
      const key = active && active.getAttribute ? active.getAttribute("data-k") : null;
      const sel = key && typeof active.selectionStart === "number" ? [active.selectionStart, active.selectionEnd] : null;
      fieldIndex = new Map(); inputIndex = new Map();
      if (!isMap(doc)) { formsEl.replaceChildren(el("p", { class: "note", text: "No theory to edit." })); return; }
      const banner = el("div", { id: "edBanner", class: "caution", hidden: "" });
      const header = el("details", { class: "ed-sec", "data-sec": "theory", open: openSecs.has("theory") ? "" : null }, [
        el("summary", null, [el("span", { class: "st", text: "Theory" }), el("span", { class: "sp", id: "sp-theory" })]),
        el("p", { class: "note ed-help", text: "The theory's identity and status. Maturity sets how the checklist's gate applies: at draft it is advisory and blocks nothing. A recorded content hash lets full validation confirm that the file holds the content it was recorded for." }),
        el("div", { class: "ecard" }, el("div", { class: "efgrid" }, HEADER.map((f) => field(f, f.k)))),
      ]);
      header.addEventListener("toggle", () => { if (header.open) openSecs.add("theory"); else openSecs.delete("theory"); });
      formsEl.replaceChildren(banner, header, ...SECTIONS.map(sectionEl));
      showProblems();
      if (key && inputIndex.has(key)) {
        const inp = inputIndex.get(key);
        inp.focus();
        if (sel && typeof inp.setSelectionRange === "function") { try { inp.setSelectionRange(sel[0], sel[1]); } catch (e) { /* not a text field */ } }
      }
    }
    // The card titles and counts follow the fields as they are typed.
    function updateHeads() {
      for (const sec of SECTIONS) {
        list(doc && doc[sec.key]).forEach((it, i) => {
          const card = fieldIndex.get(sec.key + "." + i);
          const t = card && card.querySelector(".et");
          if (t) t.textContent = itemTitle(sec, it);
        });
      }
    }

    // ---- problems and the checklist ----------------------------------------
    function lint(summary, applyErr) {
      if (!lintEl) return;
      const s = summary || {};
      const v = s.validation;
      problems = v && !v.ok ? host.problemList(v) : [];
      const kids = [];
      const chips = el("div", { class: "chips" });
      if (srcError) chips.append(el("span", { class: "chip invalid", text: "source unreadable" }));
      if (v) chips.append(v.ok ? el("span", { class: "chip valid", text: "valid" }) : el("span", { class: "chip invalid", text: host.plural(problems.length, "problem") }));
      // The score arrives after the theory, from a call of its own, and a
      // theory too large to be scored as it loads is scored on request.
      const ck = s.check;
      const refused = !!ck && "error" in ck;
      if (ck && !refused) {
        chips.append(el("span", { class: "chip score", html: "checklist <b>" + host.esc(String(ck.score)) + "</b> / 100 · gate " + host.esc(ck.gate) }));
        const failed = host.asArr(ck.failed), warned = host.asArr(ck.warned);
        if (failed.length) chips.append(el("span", { class: "chip", text: "fails: " + failed.join(", ") }));
        if (warned.length) chips.append(el("span", { class: "chip", text: "warns: " + warned.join(", ") }));
      } else if (refused) chips.append(el("span", { class: "chip", title: ck.error, text: "not scored" }));
      else if (s.scoreWait === "asked") {
        chips.append(el("span", { class: "chip unscored", title: host.largeNote ? host.largeNote(s) : "" }, ["not scored ",
          el("button", { class: "linklike sm", type: "button", onclick: () => host.score && host.score(), "aria-label": "Score the theory with the rigour checklist" }, "score it")]));
      } else if (s.scoreWait === "queued") chips.append(el("span", { class: "chip scoring", text: "scoring…" }));
      kids.push(chips);
      if (srcError) kids.push(host.errorBox("The source cannot be read, so the forms and the score show the last version that could", srcError));
      else if (applyErr) kids.push(host.errorBox("The package could not read the theory", applyErr));
      if (refused) kids.push(el("p", { class: "caution", text: "The checklist refuses this theory: " + ck.error }));
      if (problems.length) {
        const items = problems.map((p) => {
          const path = problemPath(p, doc);
          const go = path ? el("button", { class: "linklike sm", type: "button", onclick: () => goTo(path) }, "show field") : null;
          return el("li", null, [p, go ? " " : null, go]);
        });
        kids.push(el("details", { class: "ed-plist", open: problems.length <= 6 ? "" : null }, [
          el("summary", null, "Full validation: " + host.plural(problems.length, "problem")), el("ul", { class: "err-list" }, items)]));
      }
      lintEl.replaceChildren(...kids);
      showProblems();
      const banner = formsEl && formsEl.querySelector("#edBanner");
      if (banner) {
        if (srcError) { banner.textContent = "The source cannot be read as it stands, so the forms show the last version the package could read. Correct the source, or edit a field here to replace the source with this version."; banner.removeAttribute("hidden"); }
        else banner.setAttribute("hidden", "");
      }
    }
    // Each problem beside its field, or failing that beside the nearest card
    // or section that holds it.
    function showProblems() {
      for (const w of fieldIndex.values()) {
        const fp = w.querySelector(":scope > .fp") || null;
        if (fp) fp.replaceChildren();
        w.classList.remove("has-problem");
        for (const i of w.querySelectorAll("[aria-invalid]")) i.removeAttribute("aria-invalid");
      }
      const counts = {};
      for (const p of problems) {
        let path = problemPath(p, doc);
        const top = path.split(".")[0];
        if (path) counts[HEADER.some((h) => h.k.split(".")[0] === top) ? "theory" : top] = (counts[HEADER.some((h) => h.k.split(".")[0] === top) ? "theory" : top] || 0) + 1;
        while (path && !fieldIndex.has(path)) path = path.includes(".") ? path.slice(0, path.lastIndexOf(".")) : "";
        const w = path && fieldIndex.get(path);
        if (!w) continue;
        w.classList.add("has-problem");
        const fp = w.querySelector(":scope > .fp");
        if (fp) {
          fp.append(el("li", null, p));
          const inp = w.querySelector("input, select, textarea");
          if (inp && w.classList.contains("ef")) {
            inp.setAttribute("aria-invalid", "true");
            inp.setAttribute("aria-describedby", fp.id);
          }
        }
      }
      for (const key of ["theory"].concat(SECTIONS.map((s) => s.key))) {
        const sp = formsEl && formsEl.querySelector("#sp-" + key);
        if (sp) sp.textContent = counts[key] ? host.plural(counts[key], "problem") : "";
      }
    }
    function goTo(path) {
      setView(view === "source" ? "forms" : view);
      let p = path;
      while (p && !fieldIndex.has(p)) p = p.includes(".") ? p.slice(0, p.lastIndexOf(".")) : "";
      const w = fieldIndex.get(p);
      if (!w) return;
      let d = w.closest ? w.closest("details") : null;
      while (d) { d.open = true; d = d.parentElement && d.parentElement.closest ? d.parentElement.closest("details") : null; }
      if (w.scrollIntoView) w.scrollIntoView({ block: "center", behavior: "smooth" });
      const inp = w.querySelector("input, select, textarea");
      if (inp) inp.focus({ preventScroll: true });
    }

    return {
      open, reload, newTheory, flush,
      onSummary(s) { if (built && !inflight) lint(s); },
      sourceText: () => (built && srcArea ? srcArea.value : null),
    };
  }

  const api = { create, problemPath, templateTheory, nextId, getAt, setAt, delAt, SECTIONS, HEADER };
  if (typeof window !== "undefined" && window.TF) window.TF.editor = api;
  if (typeof globalThis !== "undefined") globalThis.__tfEditor = api;
})();
