/* theoryforge interactive app: Python runtime (Pyodide).
 *
 * Boots Pyodide, loads PyYAML, vendors the live theoryforge package source into
 * the in-browser filesystem, imports it, and runs the real package functions —
 * entirely client-side. importlib.resources resolves the bundled schema/.
 */
import { loadPyodide } from "https://cdn.jsdelivr.net/pyodide/v0.27.7/full/pyodide.mjs";

const PYODIDE_INDEX = "https://cdn.jsdelivr.net/pyodide/v0.27.7/full/";
const DIAG_SVG = new Set(window.TF.DIAG_SVG);

const APP_PY = String.raw`
import json
import theoryforge as tf
from theoryforge import litmap, lit_diagram, read_corpus

_state = {}

def _summary(t):
    d = t.data
    def n(k):
        v = d.get(k)
        return len(v) if isinstance(v, list) else 0
    return {
        "id": d.get("id"), "title": d.get("title"),
        "maturity": d.get("maturity"), "form": d.get("theory_form"),
        "counts": {
            "constructs": n("constructs"), "propositions": n("propositions"),
            "predictions": n("predictions"), "alternatives": n("alternatives"),
            "assumptions": n("auxiliary_assumptions"),
        },
    }

def load(path):
    t = tf.read(path)
    _state["theory"] = t
    return json.dumps(_summary(t))

def load_corpus(path):
    _state["corpus"] = read_corpus(path)
    return "ok"

def run(op, params_json):
    p = json.loads(params_json) if params_json else {}
    t = _state.get("theory")
    if t is None:
        raise RuntimeError("No theory loaded")
    if op == "check":
        return json.dumps({"report": t.check(), "svg": t.diagram("rigour")})
    if op == "validate":
        try:
            t.validate(full=True)
            return json.dumps({"ok": True})
        except ValueError as e:
            return json.dumps({"ok": False, "message": str(e)})
    if op == "severity":
        return json.dumps({"rows": t.severity(), "svg": t.diagram("severity")})
    if op == "redundancy":
        return json.dumps({"rows": t.redundancy_check()})
    if op == "implications":
        return json.dumps({"result": t.implications()})
    if op == "appraise":
        prior = tf.read(p["prior"])
        return json.dumps(t.appraise_amendment(prior))
    if op == "diff":
        return json.dumps({"result": t.diff(tf.read(p["prior"]))})
    if op == "fair":
        return json.dumps({"files": t.fair_export()})
    if op == "diagram":
        return json.dumps({"ir": t.diagram(p["type"])})
    if op == "sem":
        return json.dumps({"text": t.compile_sem()})
    if op == "preregister":
        return json.dumps({"text": t.preregister()})
    if op == "dossier":
        return json.dumps({"text": t.dossier()})
    if op == "simulate":
        return json.dumps({"result": t.simulate(
            steps=int(p["steps"]), dt=float(p["dt"]), k=float(p["k"]),
            damping=float(p["damping"]), init=float(p["init"]))})
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
  version: "",
  _py: null,
  _app: null,
  _corpusFile: null,
  _theoryFile: "your-theory.yaml",

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
    this.examples = manifest.examples;
    this.corpora = manifest.corpora;

    if (manifest.corpora.length) {
      this._corpusFile = manifest.corpora[0].path;
      this._app.load_corpus(this._fixtures[this._corpusFile]);
    }
    const summary = await this.loadExample(manifest.examples[0].path);
    return { version: this.version, examples: this.examples, corpora: this.corpora, summary };
  },

  async loadExample(path) {
    this._theoryFile = path.split("/").pop();
    return JSON.parse(this._str(this._app.load(this._fixtures[path])));
  },

  async loadTheoryText(text, filename) {
    const ext = /\.json$/i.test(filename) ? "json" : "yaml";
    const dest = "/pkg/input." + ext;
    this._py.FS.writeFile(dest, new TextEncoder().encode(text));
    this._theoryFile = filename || "your-theory." + ext;
    return JSON.parse(this._str(this._app.load(dest)));
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
    if ((opId === "appraise" || opId === "diff") && params && params.prior) {
      return Object.assign({}, params, { prior: this._fixtures[params.prior] || params.prior });
    }
    return params;
  },

  // ---- reproducible Python code -------------------------------------------
  code(opId, p) {
    const f = this._theoryFile;
    const head = `import theoryforge as tf\ntheory = tf.read("${f}")`;
    const corpus = `corpus = tf.read_corpus("${(this._corpusFile || "corpus.yaml").split("/").pop()}")`;
    switch (opId) {
      case "check":
        return `${head}\n\nreport = theory.check()\nreport["aggregate_score"]   # overall 0-100\nreport["gate"]              # pass / blocked / advisory\n\n# Visualise the rigour grid (SVG):\nopen("rigour.svg", "w").write(theory.diagram("rigour"))`;
      case "validate":
        return `${head}\n\ntheory.validate(full=True)        # structural + referential integrity; raises listing every problem`;
      case "appraise": {
        const pf = (p.prior || "prior.theory.yaml").split("/").pop();
        return `${head}\nprior = tf.read("${pf}")\n\nappr = theory.appraise_amendment(prior)\nappr["verdict"]                   # progressive / degenerating / neutral`;
      }
      case "diagram": {
        const t = p.type;
        const isSvg = DIAG_SVG.has(t);
        return `${head}\n\nir = theory.diagram("${t}")\nprint(ir)\n` + (isSvg
          ? `# '${t}' is emitted directly as SVG:\nopen("${t}.svg", "w").write(ir)`
          : `# '${t}' is ${t === "causal_dag" ? "dagitty" : "Graphviz DOT"}; render with e.g.\n# graphviz.Source(ir).render("${t}", format="svg")`);
      }
      case "severity":
        return `${head}\n\nsev = theory.severity()           # per-prediction risk & computed severity\nopen("severity.svg", "w").write(theory.diagram("severity"))`;
      case "redundancy":
        return `${head}\n\ntheory.redundancy_check()         # pairwise Jaccard overlap of construct definitions`;
      case "implications":
        return `${head}\n\nimp = theory.implications()\nimp["acyclic"]                    # causal graph acyclic?\nimp["feedback_loops"]             # every simple cycle\nimp["implications"]               # implied conditional independencies (acyclic graphs)`;
      case "diff": {
        const pf = (p.prior || "prior.theory.yaml").split("/").pop();
        return `${head}\nprior = tf.read("${pf}")\n\nd = theory.diff(prior)\nd["changed_fields"]               # changed top-level fields\nd["summary"]                      # totals across the collections`;
      }
      case "fair":
        return `${head}\n\nbundle = theory.fair_export(authors=["Family, Given"])\nprint(bundle["CITATION.cff"])\n# write everything (plus theory.yaml) to a directory:\n# theory.fair_export(path="archive/", authors=["Family, Given"])`;
      case "sem":
        return `${head}\n\nprint(theory.compile_sem())       # lavaan model syntax`;
      case "preregister":
        return `${head}\n\nprint(theory.preregister())       # preregistration document (Markdown)`;
      case "dossier":
        return `${head}\n\nprint(theory.dossier())           # reviewer-facing audit bundle (Markdown)`;
      case "simulate":
        return `${head}\n\nsim = theory.simulate(steps=${p.steps}, dt=${p.dt}, k=${p.k}, damping=${p.damping}, init=${p.init})\nsim["trajectory"]                 # list of states per step`;
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
