/* theoryforge interactive app: Python runtime (Pyodide).
 *
 * Boots Pyodide, loads PyYAML, vendors the live theoryforge package source into
 * the in-browser filesystem, imports it, and runs the real package functions
 * entirely client-side. importlib.resources resolves the bundled schema/.
 */
import { loadPyodide } from "https://cdn.jsdelivr.net/pyodide/v0.27.7/full/pyodide.mjs";

const PYODIDE_INDEX = "https://cdn.jsdelivr.net/pyodide/v0.27.7/full/";
const DIAG_SVG = new Set(window.TF.DIAG_SVG);

const APP_PY = String.raw`
import json
import warnings
import theoryforge as tf
from theoryforge import litmap, lit_diagram, read_corpus
from theoryforge._access import field, text

_state = {}

# The prior the app's "Upload a prior version" option stands for, which
# load_prior() holds in _state["prior"].
UPLOADED_PRIOR = "upload"

# The id, title and version record of a theory, each read as text, so a
# missing field is "". The app takes a candidate prior for the declared parent
# of the loaded theory when the candidate's version id is the theory's
# parent_id and the theory's id begins with the candidate's.
def _lineage(d):
    v = field(d, "version")
    return {"id": text(field(d, "id")), "title": text(field(d, "title")),
            "version": {"id": text(field(v, "id")), "parent_id": text(field(v, "parent_id"))}}

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
            "assumptions": n("auxiliary_assumptions"),
        },
    }

def _validation(t):
    try:
        t.validate(full=True)
        return {"ok": True}
    except ValueError as e:
        return {"ok": False, "message": str(e)}

# A file that cannot be read raises, and the previous theory stays loaded. One
# that reads but fails validation is loaded, and the summary says so, so the
# app can flag it before an operation trips over it.
def load(path):
    t = tf.read(path)
    _state["theory"] = t
    out = _summary(t)
    out["validation"] = _validation(t)
    return json.dumps(out)

def load_corpus(path):
    _state["corpus"] = read_corpus(path)
    return "ok"

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

def run(op, params_json):
    p = json.loads(params_json) if params_json else {}
    t = _state.get("theory")
    if t is None:
        raise RuntimeError("No theory loaded")
    if op == "check":
        return json.dumps({"report": t.check(), "svg": t.diagram("rigour")})
    if op == "validate":
        return json.dumps(_validation(t))
    if op == "severity":
        return json.dumps({"rows": t.severity(), "svg": t.diagram("severity")})
    if op == "redundancy":
        return json.dumps({"rows": t.redundancy_check()})
    if op == "appraise":
        if p.get("prior") == UPLOADED_PRIOR:
            prior = _state.get("prior")
            if prior is None:
                raise RuntimeError("No prior version uploaded")
        else:
            prior = tf.read(p["prior"])
        return json.dumps(t.appraise_amendment(prior))
    if op == "implications":
        # A refusal, a feedback loop under the default or a relation the graph
        # cannot be built from, is a result the app shows with its message.
        try:
            res = t.implications(cycles=p.get("cycles", "refuse"))
        except ValueError as e:
            return json.dumps({"ok": False, "message": str(e)})
        return json.dumps({"result": res})
    if op == "diagram":
        return json.dumps({"ir": t.diagram(p["type"])})
    if op == "sem":
        return json.dumps({"text": t.compile_sem()})
    if op == "preregister":
        return json.dumps({"text": t.preregister()})
    if op == "dossier":
        return json.dumps({"text": t.dossier()})
    if op == "simulate":
        # steps is passed as given, so a fractional value is refused as the
        # package refuses it, not truncated. A refusal or a divergence comes
        # back as a message for the app to show, as in the R runtime. The
        # Euler run's departure warning comes back with the result.
        try:
            with warnings.catch_warnings(record=True) as caught:
                warnings.simplefilter("always")
                res = t.simulate(
                    steps=p["steps"], dt=float(p["dt"]), k=float(p["k"]),
                    damping=float(p["damping"]), init=float(p["init"]),
                    method=p.get("method", "exact"))
        except ValueError as e:
            return json.dumps({"ok": False, "message": str(e)})
        out = {"result": res}
        said = [str(w.message) for w in caught if issubclass(w.category, UserWarning)]
        if said:
            out["warning"] = said[0]
        return json.dumps(out)
    if op == "litmap":
        lm = litmap(_state["corpus"], min_link=int(p["min_link"]))
        return json.dumps({"result": lm, "dots": {
            "keyword_cooccurrence": lit_diagram(lm, "keyword_cooccurrence"),
            "co_citation": lit_diagram(lm, "co_citation")}})
    if op == "landscape":
        ls = t.landscape(_state["corpus"], min_link=int(p["min_link"]))
        return json.dumps({"result": ls, "dot": lit_diagram(ls, "theme_landscape")})
    raise ValueError("unknown operation: " + op)
`;

const RT = {
  lang: "py",
  langLabel: "Python",
  engineLabel: "Pyodide (WebAssembly)",
  accent: "#3776AB",
  accentInk: "#ffffff",
  docsUrl: "https://pablobernabeu.github.io/theoryforge/python/",
  examples: [],
  corpora: [],
  version: "",     // interpreter version ("Python x.y.z"), set at boot
  pkgVersion: "",  // theoryforge release, stamped into the manifest by build.mjs
  _py: null,
  _app: null,
  _corpusFile: null,
  _theoryFile: "your-theory.yaml",
  // Whether the package ships the theory's file, which the code then reads
  // through example_path(). An upload never is.
  _theoryShipped: false,
  // The uploaded prior's file name, set once the engine has read it.
  _priorFile: null,

  hasCorpus() { return this.corpora.length > 0; },

  async init(onProgress) {
    onProgress("Fetching package manifest…");
    const manifest = await (await fetch("vendor/manifest.json")).json();

    onProgress("Downloading the Python runtime (Pyodide)… this can take ~20s the first time.");
    const pyodide = await loadPyodide({ indexURL: PYODIDE_INDEX });
    this._py = pyodide;

    onProgress("Loading PyYAML…");
    await pyodide.loadPackage("pyyaml");

    onProgress("Vendoring the theoryforge package into the browser…");
    const enc = new TextEncoder();
    const writeVendor = async (rel, dest) => {
      const slash = dest.lastIndexOf("/");
      if (slash > 0) pyodide.FS.mkdirTree(dest.slice(0, slash));
      const buf = new Uint8Array(await (await fetch("vendor/" + rel)).arrayBuffer());
      pyodide.FS.writeFile(dest, buf);
    };
    for (const f of manifest.pyFiles) await writeVendor(f, "/pkg/" + f);
    this._fixtures = {};
    for (const e of manifest.examples) { const dest = "/pkg/" + e.path; await writeVendor(e.path, dest); this._fixtures[e.path] = dest; }
    for (const c of manifest.corpora) { const dest = "/pkg/" + c.path; await writeVendor(c.path, dest); this._fixtures[c.path] = dest; }

    onProgress("Importing the package…");
    pyodide.runPython("import sys\nif '/pkg' not in sys.path: sys.path.insert(0, '/pkg')");
    pyodide.FS.writeFile("/pkg/_app.py", enc.encode(APP_PY));
    pyodide.runPython("import _app");
    this._app = pyodide.pyimport("_app");

    this.version = "Python " + pyodide.runPython("import platform; platform.python_version()");
    // The theoryforge release shown in the footer. build.mjs stamps it into the
    // manifest from pyproject.toml (after checking DESCRIPTION agrees), so the
    // app cannot drift from the packaged version.
    this.pkgVersion = manifest.pkgVersion || "";
    // Each example's lineage, read once, lets the appraisal default to the
    // version the loaded theory declares as its parent.
    onProgress("Reading the examples' versions…");
    const lineage = await this.lineageOf(manifest.examples.map((e) => this._fixtures[e.path]));
    this.examples = manifest.examples.map((e, i) => Object.assign({}, e, { lineage: lineage[i] }));
    this.corpora = manifest.corpora;

    if (manifest.corpora.length) {
      this._corpusFile = manifest.corpora[0].path;
      this._app.load_corpus(this._fixtures[this._corpusFile]);
    }
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

  async loadTheoryText(text, filename) {
    const ext = /\.json$/i.test(filename) ? "json" : "yaml";
    const dest = "/pkg/input." + ext;
    this._py.FS.writeFile(dest, new TextEncoder().encode(text));
    const summary = JSON.parse(this._str(this._app.load(dest)));
    this._theoryFile = filename || "your-theory." + ext;
    this._theoryShipped = false;
    return summary;
  },

  // An uploaded prior has a file of its own and is held apart from the theory.
  // Its name is recorded for the code panel only once the engine has read it.
  async loadPriorText(text, filename) {
    const ext = /\.json$/i.test(filename) ? "json" : "yaml";
    const dest = "/pkg/prior." + ext;
    this._py.FS.writeFile(dest, new TextEncoder().encode(text));
    const lineage = JSON.parse(this._str(this._app.load_prior(dest)));
    this._priorFile = filename || "prior." + ext;
    return lineage;
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

  // The 'prior' param arrives as a manifest path; map it to its in-FS path.
  _mapParams(opId, params) {
    if (opId === "appraise" && params && params.prior) {
      return Object.assign({}, params, { prior: this._fixtures[params.prior] || params.prior });
    }
    return params;
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

  code(opId, p) {
    const head = "import theoryforge as tf\n" +
      this._read("theory", "tf.read", this._theoryFile, this._theoryShipped, " (View source in the app offers a download).");
    const cf = this._corpusFile || "corpus.yaml";
    const corpus = this._read("corpus", "tf.read_corpus", cf.split("/").pop(), this._shipped(this.corpora, cf));
    switch (opId) {
      case "check":
        return `${head}\n\nreport = theory.check()\nreport["aggregate_score"]   # overall 0-100\nreport["gate"]              # pass / blocked / advisory\n\n# Visualise the rigour grid (SVG):\nopen("rigour.svg", "w", encoding="utf-8").write(theory.diagram("rigour"))`;
      case "validate":
        return `${head}\n\ntheory.validate(full=True)        # structural + referential integrity; raises listing every problem`;
      case "appraise": {
        const uploaded = p.prior === "upload";
        const pf = uploaded ? this._priorFile || "prior.theory.yaml" : String(p.prior || "prior.theory.yaml").split("/").pop();
        const prior = this._read("prior", "tf.read", pf, !uploaded && this._shipped(this.examples, p.prior));
        return `${head}\n${prior}\n\nappr = theory.appraise_amendment(prior)\nappr["verdict"]                   # progressive / degenerating / neutral`;
      }
      case "diagram": {
        const t = p.type;
        const isSvg = DIAG_SVG.has(t);
        return `${head}\n\nir = theory.diagram("${t}")\nprint(ir)\n` + (isSvg
          ? `# '${t}' is emitted directly as SVG:\nopen("${t}.svg", "w", encoding="utf-8").write(ir)`
          : `# '${t}' is ${t === "causal_dag" ? "dagitty" : "Graphviz DOT"}; render with e.g.\n# graphviz.Source(ir).render("${t}", format="svg")`);
      }
      case "severity":
        return `${head}\n\nsev = theory.severity()           # per-prediction risk & computed severity\nopen("severity.svg", "w", encoding="utf-8").write(theory.diagram("severity"))`;
      case "redundancy":
        return `${head}\n\ntheory.redundancy_check()         # pairwise Jaccard and overlap of construct definitions`;
      case "sem":
        return `${head}\n\nprint(theory.compile_sem())       # lavaan model syntax`;
      case "implications":
        return `${head}\n\n# A refusal raises ValueError with the message the app shows.\nimplied = theory.implications(cycles="${p.cycles || "refuse"}")\nfor s in implied["implications"]:\n    print(s["statement"])`;
      case "preregister":
        return `${head}\n\nprint(theory.preregister())       # preregistration document (Markdown)`;
      case "dossier":
        return `${head}\n\nprint(theory.dossier())           # reviewer-facing audit bundle (Markdown)`;
      case "simulate":
        return `${head}\n\nsim = theory.simulate(steps=${p.steps}, dt=${p.dt}, k=${p.k}, damping=${p.damping}, init=${p.init}, method="${p.method || "exact"}")\nsim["trajectory"]                 # list of states per step`;
      case "litmap":
        return `${head}\n${corpus}\n\nlm = tf.litmap(corpus, min_link=${p.min_link})\nlm["themes"]\nprint(tf.lit_diagram(lm, "keyword_cooccurrence"))`;
      case "landscape":
        return `${head}\n${corpus}\n\nland = theory.landscape(corpus, min_link=${p.min_link})\nland["under_theorised_fronts"]\nprint(tf.lit_diagram(land, "theme_landscape"))`;
      default:
        return head;
    }
  },
};

window.TF.start(RT);
