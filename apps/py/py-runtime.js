/* theoryforge interactive app: Python runtime (Pyodide).
 *
 * Boots Pyodide, loads PyYAML, vendors the live theoryforge package source into
 * the in-browser filesystem, imports it, and runs the real package functions
 * entirely client-side. importlib.resources resolves the bundled schema/.
 */
// Pyodide 314.0.8 runs Python 3.14.2 and ships PyYAML 6.0.3. The release is
// pinned, as webR's is in r-runtime.js, and the two engines are updated
// together and on purpose (apps/README.md, "Runtimes").
const PYODIDE_INDEX = "https://cdn.jsdelivr.net/pyodide/v314.0.8/full/";

// The engine is imported inside init rather than at the top of this module.
// A module whose static import fails never runs, so the page would stay blank,
// where a failure inside init reaches the app's panel with a Reload button.
const loadEngine = (what, host, url) => import(url).catch((e) => {
  throw new Error(`Could not download ${what} from ${host}. Check that your network allows it, then reload. (${(e && e.message) || e})`);
});

const APP_PY = String.raw`
import json
import os
import tempfile
import warnings

import theoryforge as tf
from theoryforge import lit_diagram, litmap, read_corpus
from theoryforge._access import field, items, text

_state = {"corpora": {}}

# The literature figures draw the strongest links only, as many as this.
MAX_EDGES = 60

# The value of a parameter that stands for a file the user uploaded: a prior
# version, a rival theory or a corpus, each held apart from the theory.
UPLOADED = "upload"

# The id, title and version record of a theory, each read as text, so a
# missing field is "". The app takes a candidate prior for the declared parent
# of the loaded theory when the candidate's version id is the theory's
# parent_id and the theory's id begins with the candidate's.
def _lineage(d):
    v = field(d, "version")
    return {"id": text(field(d, "id")), "title": text(field(d, "title")),
            "version": {"id": text(field(v, "id")), "parent_id": text(field(v, "parent_id"))}}

# The length of the theory as the json module writes it, from which the app
# tells a theory too long to hash as it loads. R's jsonlite writes some
# numbers differently, so the two glues can differ by a few characters. A
# theory with more values than MEASURED_VALUES is not measured, and its length
# is None.
MEASURED_VALUES = 20000

def _chars(d):
    n, stack = 0, [d]
    while stack:
        v = stack.pop()
        if isinstance(v, dict):
            stack.extend(v.values())
        elif isinstance(v, list):
            stack.extend(v)
        elif v is not None:
            n += 1
            if n > MEASURED_VALUES:
                return None
    try:
        return len(json.dumps(d, ensure_ascii=False, separators=(",", ":"), default=str))
    except (TypeError, ValueError):
        return None

def _summary(t):
    d = t.data
    def n(k):
        v = d.get(k)
        return len(v) if isinstance(v, list) else 0
    return {
        "id": d.get("id"), "title": d.get("title"),
        "maturity": d.get("maturity"), "form": d.get("theory_form"),
        "version": _lineage(d)["version"],
        "counts": {
            "constructs": n("constructs"), "propositions": n("propositions"),
            "predictions": n("predictions"), "alternatives": n("alternatives"),
            "assumptions": n("auxiliary_assumptions"), "phenomena": n("phenomena"),
            "outcomes": n("test_outcomes"),
        },
        "chars": _chars(d),
        # The constructs an impulse can start from and the rivals that state
        # propositions of their own, which the app offers as choices.
        "constructs": [{"id": text(field(c, "id")), "label": text(field(c, "label"))}
                       for c in items(d, "constructs")],
        "alternatives": [{"id": text(field(a, "id")), "label": text(field(a, "label")),
                          "propositions": len(items(a, "propositions"))}
                         for a in items(d, "alternatives")],
    }

# Full validation, with the problems as a list as well as the package's joined
# message: a message may quote a value of the theory that holds "; " itself, so
# the app counts and lists the problems from the list.
def _validation(t):
    try:
        problems = t._problems(full=True)
    except ValueError as e:
        return {"ok": False, "message": str(e)}
    if not problems:
        return {"ok": True}
    return {"ok": False, "message": "invalid theory object: " + "; ".join(problems), "problems": problems}

# The checklist with the app's cycles setting. The result says which reading it
# gives. The package draws the grid with the default, so the grid is drawn only
# for that reading.
def _check(t, cycles="refuse"):
    return {"report": t.check(cycles=cycles),
            "svg": t.diagram("rigour") if cycles == "refuse" else None, "cycles": cycles}

# The checklist's score and gate, which the card and the editor show, or the
# message of a theory the checklist refuses. An error without a message, such
# as a MemoryError, is named by its type. The card reads the graph with the
# default cycles.
def _score(t):
    try:
        r = t.check()
    except Exception as e:
        return {"error": str(e) or type(e).__name__}
    return {"score": r["aggregate_score"], "gate": r["gate"],
            "failed": [i["id"] for i in r["items"] if i["status"] == "fail"],
            "warned": [i["id"] for i in r["items"] if i["status"] == "warn"],
            "version": r.get("checklist_version")}

# The score of the loaded theory. It is a call of its own, which the app makes
# once the theory card has been drawn, so that the checklist, whose time grows
# faster than the theory, never holds up a load, a restore or the start.
def score():
    return json.dumps(_score(_state["theory"]))

def _hash(t):
    try:
        return t.content_hash()
    except Exception:
        return None

# The content hash of the loaded theory, or the message of the error that
# stopped it. It is a call of its own, which the app makes once a load has
# finished, so that a slow hash never holds up a load or the start.
def content_hash():
    try:
        return json.dumps({"hash": _state["theory"].content_hash()})
    except Exception as e:
        return json.dumps({"error": str(e) or type(e).__name__})

def _loaded(t):
    _state["theory"] = t
    out = _summary(t)
    out["validation"] = _validation(t)
    return out

# A file that cannot be read raises, and the previous theory stays loaded. One
# that reads but fails validation is loaded, and the summary says so, so the
# app can flag it before an operation trips over it.
def load(path):
    return json.dumps(_loaded(tf.read(path)))

# The theory as the package's own writer writes it, as YAML or as JSON.
def _written(t, fmt):
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "theory." + ("json" if fmt == "json" else "yaml"))
        t.write(path)
        with open(path, encoding="utf-8") as fh:
            return fh.read()

def write_text(fmt):
    t = _state.get("theory")
    if t is None:
        raise RuntimeError("No theory loaded")
    return _written(t, fmt)

# The editor's call: the theory in the file at path replaces the loaded one,
# and the result carries the summary and the theory written in each format
# asked for. A file that cannot be read raises and leaves the theory as it was.
def edit(path, formats_json):
    out = _loaded(tf.read(path))
    out["texts"] = {fmt: _written(_state["theory"], fmt) for fmt in json.loads(formats_json)}
    return json.dumps(out)

# The theory the package's DAGitty reader makes of the model code in the file
# at path replaces the loaded one. The settings the user gives, id, title and
# the relation an arrow reads as, are passed on, and any other is the
# package's default. A model the reader refuses raises and leaves the theory
# as it was.
def import_dagitty(path, opts_json):
    o = json.loads(opts_json)
    with open(path, encoding="utf-8") as fh:
        model = fh.read()
    kw = {k: o[k] for k in ("id", "title", "relation") if o.get(k)}
    out = _loaded(tf.read_dagitty(model, **kw))
    out["texts"] = {fmt: _written(_state["theory"], fmt) for fmt in o.get("formats", [])}
    return json.dumps(out)

def can_import_dagitty():
    return hasattr(tf, "read_dagitty")

# A bundled corpus is read once, when an operation first asks for it, and an
# uploaded one is held under "upload". A file that cannot be read raises, and
# the corpus uploaded before it stays.
def load_corpus(path, key=None):
    corpus = read_corpus(path)
    _state["corpora"][key or path] = corpus
    recs = corpus.get("records")
    return json.dumps({"id": text(corpus.get("id")), "n_records": len(recs) if isinstance(recs, list) else 0})

def _corpus(p):
    key = p.get("corpus") or ""
    if key == UPLOADED:
        if UPLOADED not in _state["corpora"]:
            raise RuntimeError("No corpus uploaded")
        return _state["corpora"][UPLOADED]
    if key not in _state["corpora"]:
        _state["corpora"][key] = read_corpus(key)
    return _state["corpora"][key]

# The lineage of each candidate prior, read without loading it. A file that
# cannot be read has none, so it is never taken for a declared parent.
def lineage(paths_json):
    out = []
    for path in json.loads(paths_json):
        try:
            out.append(_lineage(tf.read(path).data))
        except Exception:
            out.append(None)
    return json.dumps(out)

# An uploaded prior is held apart from the theory. A file that cannot be read
# raises, and the prior uploaded before it stays.
def load_prior(path):
    prior = tf.read(path)
    _state["prior"] = prior
    return json.dumps(_lineage(prior.data))

# An uploaded rival theory, held apart from the theory as a prior is.
def load_rival(path):
    rival = tf.read(path)
    _state["rival"] = rival
    out = _lineage(rival.data)
    out["constructs"] = len(items(rival.data, "constructs"))
    return json.dumps(out)

# A refusal is the package's answer for the theory, so the app shows it as a
# result with the package's message. fn returns the result's envelope.
def _answer(fn):
    try:
        return fn()
    except ValueError as e:
        return {"ok": False, "message": str(e)}

# A run whose UserWarning comes back with the result: the Euler run's
# departure from the exact solution, or litmap's warning that one theme holds
# most of the keywords.
def _warned(fn):
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        out = fn()
    said = [str(w.message) for w in caught if issubclass(w.category, UserWarning)]
    if said and out.get("ok") is not False:
        out["warning"] = said[0]
    return out

def run(op, params_json):
    p = json.loads(params_json) if params_json else {}
    t = _state.get("theory")
    if t is None:
        raise RuntimeError("No theory loaded")
    cycles = p.get("cycles", "refuse")
    if op == "check":
        return json.dumps(_check(t, cycles))
    if op == "validate":
        return json.dumps(_validation(t))
    if op == "severity":
        return json.dumps({"rows": t.severity(), "svg": t.diagram("severity")})
    if op == "post_severity":
        return json.dumps(_answer(lambda: {"result": t.post_data_severity()}))
    if op == "redundancy":
        return json.dumps({"rows": t.redundancy_check()})
    if op == "appraise":
        if p.get("prior") == UPLOADED:
            prior = _state.get("prior")
            if prior is None:
                raise RuntimeError("No prior version uploaded")
        else:
            prior = tf.read(p["prior"])
        return json.dumps(t.appraise_amendment(prior))
    if op == "discriminate":
        if p.get("rival") == UPLOADED:
            rival = _state.get("rival")
            if rival is None:
                raise RuntimeError("No rival theory uploaded")
        elif p.get("rival"):
            rival = p["rival"]
        else:
            raise RuntimeError("No rival chosen")
        return json.dumps(_answer(lambda: {"result": t.discriminate(rival, cycles=cycles)}))
    if op == "implications":
        # A refusal, a feedback loop under the default or a relation the graph
        # cannot be built from, is a result the app shows with its message.
        return json.dumps(_answer(lambda: {"result": t.implications(cycles=cycles)}))
    if op == "entailments":
        return json.dumps(_answer(lambda: {"result": t.entailments(cycles=cycles)}))
    if op == "equivalent":
        return json.dumps(_answer(lambda: {"result": t.equivalent_models()}))
    if op == "diagram":
        return json.dumps({"ir": t.diagram(p["type"])})
    if op == "sem":
        return json.dumps({"text": t.compile_sem()})
    if op == "preregister":
        return json.dumps({"text": tf.preregister(t, cycles=cycles), "hash": _hash(t)})
    if op == "dossier":
        return json.dumps({"text": tf.dossier(t, cycles=cycles), "hash": _hash(t)})
    if op == "simulate":
        # steps is passed as given, so a fractional value is refused as the
        # package refuses it, not truncated. A refusal or a divergence comes
        # back as a message for the app to show, as in the R runtime. An
        # impulse starts the chosen construct at 1 and every other at 0,
        # through the mapping form of init.
        init = {p["impulse"]: 1.0} if p.get("start") == "impulse" else float(p["init"])
        return json.dumps(_warned(lambda: _answer(lambda: {"result": t.simulate(
            steps=p["steps"], dt=float(p["dt"]), k=float(p["k"]),
            damping=float(p["damping"]), init=init, method=p.get("method", "exact"))})))
    if op == "litmap":
        corpus = _corpus(p)
        def go():
            lm = litmap(corpus, min_link=int(p["min_link"]), method=p.get("method", "components"),
                        min_df=int(p.get("min_df", 1)), max_df=float(p.get("max_df", 1.0)))
            return {"result": lm, "dots": {
                "keyword_cooccurrence": lit_diagram(lm, "keyword_cooccurrence", max_edges=MAX_EDGES),
                "co_citation": lit_diagram(lm, "co_citation", max_edges=MAX_EDGES)}}
        return json.dumps(_warned(lambda: _answer(go)))
    if op == "landscape":
        corpus = _corpus(p)
        def go():
            ls = t.landscape(corpus, min_link=int(p["min_link"]), method=p.get("method", "components"))
            return {"result": ls, "dot": lit_diagram(ls, "theme_landscape")}
        return json.dumps(_warned(lambda: _answer(go)))
    raise ValueError("unknown operation: " + op)
`;

const RT = {
  lang: "py",
  // The size above which the card's score and hash wait for the user to ask
  // (apps/README.md, "Runtimes"). In Pyodide, the checklist took up to 0.3 s on
  // 300 constructs, propositions and predictions and 1.4 s on 899, and the hash
  // up to 0.2 s on theories of up to 235,000 characters of JSON.
  limits: { score: 300, hashChars: 1000000 },
  langLabel: "Python",
  engineLabel: "Pyodide (WebAssembly)",
  accent: "#3776AB",
  accentInk: "#ffffff",
  // Text in the accent colour, lighter in the dark theme, where the fill
  // colour above reads at less than 4.5:1 on the panels.
  accentText: { light: "#2f6796", dark: "#8fbfe6" },
  docsUrl: "https://pablobernabeu.github.io/theoryforge/python/",
  examples: [],
  corpora: [],
  version: "",     // interpreter version ("Python x.y.z"), set at boot
  pkgVersion: "",  // this package's version (pyproject.toml), which build.mjs stamps into the manifest
  _py: null,
  _app: null,
  _theoryFile: "your-theory.yaml",
  // Whether the package ships the theory's file, which the code then reads
  // through example_path(). An upload or an edited theory never is.
  _theoryShipped: false,
  // The names of the uploaded prior, rival and corpus, set once the engine
  // has read each.
  _priorFile: null,
  _rivalFile: null,
  _corpusUpload: null,
  // The in-browser files that hold what the user gave the app, each named as
  // the user named it, so an error message names the user's file.
  fileNames: {},

  hasCorpus() { return this.corpora.length > 0; },

  async init(onProgress) {
    // The engine downloads while the manifest and the package files are fetched.
    const engine = loadEngine("the Python engine (Pyodide)", "cdn.jsdelivr.net", PYODIDE_INDEX + "pyodide.mjs");
    engine.catch(() => {});   // a failure is reported where it is awaited
    onProgress("Fetching package manifest…");
    const manifest = await window.TF.util.fetchJson("vendor/manifest.json");

    // The package files are fetched while the engine downloads.
    onProgress("Downloading the Python runtime (Pyodide)… this can take ~20s the first time.");
    const files = [...manifest.pyFiles.map((f) => [f, "/pkg/" + f]),
      ...manifest.examples.map((e) => [e.path, "/pkg/" + e.path]),
      ...manifest.corpora.map((c) => [c.path, "/pkg/" + c.path])];
    const fetched = Promise.all(files.map(([rel, dest]) => window.TF.util.fetchBytes("vendor/" + rel).then((buf) => [dest, buf])));
    fetched.catch(() => {});   // a failure is reported where it is awaited
    const { loadPyodide } = await engine;
    const pyodide = await loadPyodide({ indexURL: PYODIDE_INDEX });
    this._py = pyodide;

    onProgress("Loading PyYAML…");
    // loadPackage() resolves even when the download fails, and the failure
    // would surface later as a traceback about a missing module, so the
    // package is checked here.
    const yamlErrors = [];
    await pyodide.loadPackage("pyyaml", { errorCallback: (m) => yamlErrors.push(m) });
    if (!pyodide.loadedPackages.pyyaml) {
      throw new Error("Could not load PyYAML from cdn.jsdelivr.net" +
        (yamlErrors.length ? " (" + yamlErrors[yamlErrors.length - 1] + ")" : "") + ". Check the connection and reload.");
    }

    onProgress("Vendoring the theoryforge package into the browser…");
    const enc = new TextEncoder();
    for (const [dest, buf] of await fetched) {
      const slash = dest.lastIndexOf("/");
      if (slash > 0) pyodide.FS.mkdirTree(dest.slice(0, slash));
      pyodide.FS.writeFile(dest, buf);
    }
    this._fixtures = {};
    for (const e of [...manifest.examples, ...manifest.corpora]) this._fixtures[e.path] = "/pkg/" + e.path;

    onProgress("Importing the package…");
    pyodide.runPython("import sys\nif '/pkg' not in sys.path: sys.path.insert(0, '/pkg')");
    pyodide.FS.writeFile("/pkg/_app.py", enc.encode(APP_PY));
    pyodide.runPython("import _app");
    this._app = pyodide.pyimport("_app");
    this.canImportDagitty = !!this._app.can_import_dagitty();

    this.version = "Python " + pyodide.runPython("import platform; platform.python_version()");
    // The version of the Python package, shown in the footer. build.mjs stamps
    // it into the manifest from pyproject.toml, after checking that DESCRIPTION
    // agrees with it, so the app cannot drift from the packaged version.
    this.pkgVersion = manifest.pkgVersion || "";
    // Each example's lineage, read once, lets the appraisal default to the
    // version the loaded theory declares as its parent.
    onProgress("Reading the examples' versions…");
    const lineage = await this.lineageOf(manifest.examples.map((e) => this._fixtures[e.path]));
    this.examples = manifest.examples.map((e, i) => Object.assign({}, e, { lineage: lineage[i] }));
    this.corpora = manifest.corpora;

    const summary = await this.loadExample(manifest.examples[0].path);
    return { version: this.version, pkgVersion: this.pkgVersion, examples: this.examples, corpora: this.corpora, summary };
  },

  // The code panel names _theoryFile, so it changes only once the engine holds
  // the new theory. A load that fails leaves the previous theory in the engine
  // and its name here.
  async loadExample(path) {
    const summary = JSON.parse(this._str(this._app.load(this._fixtures[path])));
    this._theoryFile = path.split("/").pop();
    this._theoryShipped = this._shipped(this.examples, path);
    return summary;
  },

  // Write text the user gave the app to the in-browser file `stem`.ext and
  // record the user's name for it.
  _put(stem, text, filename, format) {
    const ext = format || (/\.json$/i.test(filename || "") ? "json" : "yaml");
    const dest = "/pkg/" + stem + "." + ext;
    this._py.FS.writeFile(dest, new TextEncoder().encode(text));
    this.fileNames[dest] = filename || stem + "." + ext;
    return dest;
  },

  async loadTheoryText(text, filename) {
    const dest = this._put("input", text, filename);
    const summary = JSON.parse(this._str(this._app.load(dest)));
    this._theoryFile = filename || "your-theory." + dest.split(".").pop();
    this._theoryShipped = false;
    return summary;
  },

  // The editor's call. `text`, in `format` ("yaml" or "json"), replaces the
  // loaded theory, and the result carries the theory as the package's writer
  // writes it in each of `formats`. `filename` is the name the code panel
  // reads the theory from, the name Save gives the file.
  async editText(text, format, filename, formats) {
    const dest = this._put("edit", text, filename, format === "json" ? "json" : "yaml");
    const out = JSON.parse(this._str(this._app.edit(dest, JSON.stringify(formats || []))));
    this._theoryFile = filename || "your-theory." + dest.split(".").pop();
    this._theoryShipped = false;
    return out;
  },

  // Whether this package version has a DAGitty reader, read at start-up.
  canImportDagitty: false,

  // The theory the package's DAGitty reader makes of `model` replaces the
  // loaded one. `opts` holds the id, title and relation the user chose.
  async importDagitty(model, opts, formats) {
    const dest = this._put("dagitty", model, "DAGitty model code", "txt");
    const out = JSON.parse(this._str(this._app.import_dagitty(dest, JSON.stringify(Object.assign({}, opts, { formats: formats || [] })))));
    this._theoryFile = (out.id || "dagitty-import") + ".theory.yaml";
    this._theoryShipped = false;
    return out;
  },
  // The code that makes the same theory with the installed package.
  importCode(opts) {
    const args = ["id", "title", "relation"].filter((k) => opts[k]).map((k) => `, ${k}=${JSON.stringify(String(opts[k]))}`).join("");
    return `import theoryforge as tf\n\nwith open("model.dag", encoding="utf-8") as fh:   # the DAGitty model code\n    theory = tf.read_dagitty(fh.read()${args})\ntheory.write(${JSON.stringify(opts.file || (opts.id || "dagitty-import") + ".theory.yaml")})`;
  },

  // The name the code panel reads the theory from, when the app renames it.
  renameTheory(filename) { this._theoryFile = filename; },

  // The content hash of the loaded theory, as { hash } or { error }.
  async contentHash() { return JSON.parse(this._str(this._app.content_hash())); },

  // The checklist's score of the loaded theory, as { score, gate, failed,
  // warned, version } or { error }.
  async score() { return JSON.parse(this._str(this._app.score())); },

  // The loaded theory as the package's writer writes it ("yaml" or "json").
  async writeText(format) { return this._str(this._app.write_text(format)); },

  // An uploaded prior has a file of its own and is held apart from the theory.
  // Its name is recorded for the code panel only once the engine has read it.
  async loadPriorText(text, filename) {
    const dest = this._put("prior", text, filename);
    const lineage = JSON.parse(this._str(this._app.load_prior(dest)));
    this._priorFile = filename || "prior." + dest.split(".").pop();
    return lineage;
  },

  async loadRivalText(text, filename) {
    const dest = this._put("rival", text, filename);
    const out = JSON.parse(this._str(this._app.load_rival(dest)));
    this._rivalFile = filename || "rival." + dest.split(".").pop();
    return out;
  },

  async loadCorpusText(text, filename) {
    const dest = this._put("corpus", text, filename);
    const out = JSON.parse(this._str(this._app.load_corpus(dest, "upload")));
    this._corpusUpload = filename || "corpus." + dest.split(".").pop();
    return out;
  },

  // The lineage of each file in `paths` (in-FS paths), null for one that
  // cannot be read. Nothing is loaded.
  async lineageOf(paths) {
    return JSON.parse(this._str(this._app.lineage(JSON.stringify(paths))));
  },

  _shipped(list, path) {
    const e = (list || []).find((x) => x.path === path);
    return !!(e && e.shipped);
  },

  async run(opId, params) {
    const out = this._app.run(opId, JSON.stringify(this._mapParams(opId, params) || {}));
    return { raw: JSON.parse(this._str(out)), code: this.code(opId, params) };
  },

  // _app functions return JSON strings (Pyodide auto-converts Python str -> JS string).
  // Assert that contract so a future dict/list return fails loudly, not as "[object Object]".
  _str(out) { if (typeof out !== "string") throw new Error("Python runtime returned a non-string result"); return out; },

  // The prior arrives as a manifest path and the corpus as its key in the
  // manifest; each is mapped to its in-browser path.
  _mapParams(opId, params) {
    const p = Object.assign({}, params || {});
    if (opId === "appraise" && p.prior) p.prior = this._fixtures[p.prior] || p.prior;
    if (p.corpus && p.corpus !== "upload") {
      const c = this.corpora.find((x) => x.key === p.corpus);
      if (c) p.corpus = this._fixtures[c.path];
    }
    return p;
  },

  // ---- reproducible Python code -------------------------------------------
  // A file the package ships is read through example_path(), so the code runs
  // wherever the package is installed. Any other file, an app-only example or
  // an upload, has to be saved beside the script first. `note` ends that
  // comment. The name is a JSON string literal in the code, which Python
  // reads as written. In the comment, a line feed or carriage return in an
  // uploaded file's name would end the comment and leave the rest of the
  // name as code, so every control character is shown as "?".
  _read(name, fn, file, shipped, note) {
    const lit = JSON.stringify(file);
    const shown = String(file).replace(/[\u0000-\u001f\u007f]/g, "?");
    return shipped
      ? `${name} = ${fn}(tf.example_path(${lit}))`
      : `# Save ${shown} beside this script first${note || "."}\n${name} = ${fn}(${lit})`;
  },

  // The corpus line of the literature operations.
  _corpusLine(key) {
    if (key === "upload") return this._read("corpus", "tf.read_corpus", this._corpusUpload || "corpus.yaml", false);
    const c = this.corpora.find((x) => x.key === key) || this.corpora[0] || { path: "corpus.yaml" };
    return this._read("corpus", "tf.read_corpus", c.path.split("/").pop(), !!c.shipped);
  },

  code(opId, p) {
    p = p || {};
    const head = "import json\n\nimport theoryforge as tf\n\n" +
      this._read("theory", "tf.read", this._theoryFile, this._theoryShipped, " (View source or Save in the app offers a download).");
    const show = (expr) => `print(json.dumps(${expr}, indent=2))`;
    const cycles = `cycles="${p.cycles || "refuse"}"`;
    switch (opId) {
      case "check": {
        const c = p.cycles || "refuse";
        const call = `theory.check(${cycles})`;
        const grid = c === "refuse" ? `\n\n# The checklist grid as SVG:\nwith open("rigour.svg", "w", encoding="utf-8") as fh:\n    fh.write(theory.diagram("rigour"))\nprint("Wrote rigour.svg")` : "";
        return `${head}\n\nreport = ${call}\nprint("Checklist score:", report["aggregate_score"])   # 0-100\nprint("Gate:", report["gate"])                        # pass / blocked / advisory${grid}`;
      }
      case "validate":
        return `${head}\n\n# Raises ValueError listing every problem, or passes:\ntheory.validate(full=True)\nprint("The theory passes full validation.")`;
      case "appraise": {
        const uploaded = p.prior === "upload";
        const pf = uploaded ? this._priorFile || "prior.theory.yaml" : String(p.prior || "prior.theory.yaml").split("/").pop();
        const prior = this._read("prior", "tf.read", pf, !uploaded && this._shipped(this.examples, p.prior));
        return `${head}\n${prior}\n\nappr = theory.appraise_amendment(prior)\nprint("Verdict:", appr["verdict"])   # progressive / degenerating / neutral\n${show("appr")}`;
      }
      case "discriminate": {
        const uploaded = p.rival === "upload";
        const rival = uploaded
          ? this._read("rival", "tf.read", this._rivalFile || "rival.theory.yaml", false) + "\n"
          : "";
        const arg = uploaded ? "rival" : JSON.stringify(String(p.rival || ""));
        return `${head}\n${rival}\n# A refusal raises ValueError with the message the app shows.\nres = theory.discriminate(${arg}, ${cycles})\n${show("res")}`;
      }
      case "diagram": {
        const t = p.type;
        if (window.TF.DIAG_SVG.includes(t)) {
          return `${head}\n\nir = theory.diagram("${t}")\n# '${t}' is emitted directly as SVG:\nwith open("${t}.svg", "w", encoding="utf-8") as fh:\n    fh.write(ir)\nprint("Wrote ${t}.svg")`;
        }
        if (t === "causal_dag") {
          return `${head}\n\nir = theory.diagram("causal_dag")\nprint(ir)\n# This is dagitty model code, which Graphviz cannot read. Paste it into\n# https://dagitty.net to draw the graph and examine it there.`;
        }
        return `${head}\n\nir = theory.diagram("${t}")   # Graphviz DOT\nprint(ir)\n\n# Draw it with the package's renderer, which needs the render extra\n# (pip install "theoryforge[render]") and the Graphviz programs:\ntry:\n    print("Wrote", theory.render_diagram("${t}").render("${t}", format="svg"))\nexcept Exception as err:\n    print("Not drawn here:", err)`;
      }
      case "severity":
        return `${head}\n\nsev = theory.severity()           # per-prediction risk and computed severity\n${show("sev")}\nwith open("severity.svg", "w", encoding="utf-8") as fh:\n    fh.write(theory.diagram("severity"))\nprint("Wrote severity.svg")`;
      case "post_severity":
        return `${head}\n\n# One record per test outcome with an estimate and an SE whose prediction\n# declares bounds. A refusal raises ValueError with the message the app shows.\n${show("theory.post_data_severity()")}`;
      case "redundancy":
        return `${head}\n\n# Pairwise Jaccard and overlap of the construct definitions:\n${show("theory.redundancy_check()")}`;
      case "sem":
        return `${head}\n\nprint(theory.compile_sem())       # lavaan model syntax`;
      case "implications":
        return `${head}\n\n# A refusal raises ValueError with the message the app shows.\nimplied = theory.implications(${cycles})\nfor s in implied["implications"]:\n    print(s["statement"])\nprint(len(implied["implications"]), "statements")`;
      case "entailments":
        return `${head}\n\n# A refusal raises ValueError with the message the app shows.\nres = theory.entailments(${cycles})\nfor c in res["claims"]:\n    print(c["source"], c["id"], c["verdict"])\n${show('res["counts"]')}`;
      case "equivalent":
        return `${head}\n\nres = theory.equivalent_models()\n${show("res")}`;
      case "preregister":
        return `${head}\n\nprint(tf.preregister(theory, ${cycles}))   # Markdown`;
      case "dossier":
        return `${head}\n\nprint(tf.dossier(theory, ${cycles}))       # Markdown`;
      case "simulate": {
        const init = p.start === "impulse" ? `{${JSON.stringify(String(p.impulse || ""))}: 1.0}` : String(p.init);
        return `${head}\n\nsim = theory.simulate(steps=${p.steps}, dt=${p.dt}, k=${p.k}, damping=${p.damping}, init=${init}, method="${p.method || "exact"}")\nprint("States:", sim["states"])\nprint("Assumed positive:", sim["assumed_positive"])\nfor step, row in enumerate(sim["trajectory"]):\n    print(step, row)`;
      }
      case "litmap":
        return `${head}\n${this._corpusLine(p.corpus)}\n\nlm = tf.litmap(corpus, min_link=${p.min_link}, method="${p.method || "components"}", min_df=${p.min_df === undefined ? 1 : p.min_df}, max_df=${p.max_df === undefined ? 1 : p.max_df})\n${show('lm["themes"]')}\nprint(tf.lit_diagram(lm, "keyword_cooccurrence", max_edges=60))`;
      case "landscape":
        return `${head}\n${this._corpusLine(p.corpus)}\n\nland = theory.landscape(corpus, min_link=${p.min_link}, method="${p.method || "components"}")\nprint("Themes no account shares a word with:", land["under_theorised_fronts"])\nprint("Themes several accounts share a word with:", land["redundancy_risk"])\nprint(tf.lit_diagram(land, "theme_landscape"))`;
      default:
        return head;
    }
  },
};

window.TF.start(RT);
