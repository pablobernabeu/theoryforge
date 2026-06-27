/* theoryforge interactive app — R runtime (webR).
 *
 * Boots webR, installs jsonlite + yaml, vendors the live R package source into
 * the in-browser filesystem, sources it, and pre-seeds the schema/checklist
 * cache so the real package functions run unmodified — entirely client-side.
 */
import { WebR } from "https://webr.r-wasm.org/latest/webr.mjs";

const DIAG_SVG = new Set(["venn", "rigor", "severity"]);

// R bootstrap, sourced once into the global environment so all definitions and
// persistent state (.tf_app) survive across calls.
const BOOT_R = String.raw`
.tf_app_files <- list.files("/tf/R", pattern = "[.][Rr]$", full.names = TRUE)
invisible(lapply(.tf_app_files, source))

# Pre-seed the resource cache from the vendored schema, so the package never
# needs system.file() (which only resolves for an installed package).
.tf_cache$schema <- jsonlite::fromJSON(
  readChar("/tf/schema/theory.schema.json", file.info("/tf/schema/theory.schema.json")$size, useBytes = TRUE),
  simplifyVector = FALSE)
.tf_cache$checklist <- yaml::read_yaml("/tf/schema/rigor_checklist.yaml")

.tf_app <- new.env(parent = emptyenv())

.tf_summary <- function(t) {
  list(
    id = .tf_get(t, "id"), title = .tf_get(t, "title"),
    maturity = .tf_get(t, "maturity"), form = .tf_get(t, "theory_form"),
    counts = list(
      constructs = length(.tf_list(t, "constructs")),
      propositions = length(.tf_list(t, "propositions")),
      predictions = length(.tf_list(t, "predictions")),
      alternatives = length(.tf_list(t, "alternatives")),
      assumptions = length(.tf_list(t, "auxiliary_assumptions"))
    ))
}

.tf_load <- function(path) {
  .tf_app$theory <- tf_read(path)
  jsonlite::toJSON(.tf_summary(.tf_app$theory), auto_unbox = TRUE, null = "null")
}
.tf_load_corpus <- function(path) {
  .tf_app$corpus <- tf_read_corpus(path)
  "ok"
}

.tf_run <- function(op, params_json) {
  p <- if (nzchar(params_json)) jsonlite::fromJSON(params_json) else list()
  t <- .tf_app$theory
  env <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null"))
  if (op == "check")      return(env(list(report = tf_check(t), svg = tf_diagram(t, "rigor"))))
  if (op == "severity")   return(env(list(rows = tf_severity(t), svg = tf_diagram(t, "severity"))))
  if (op == "redundancy") return(env(list(rows = tf_redundancy_check(t))))
  if (op == "diagram")    return(env(list(ir = tf_diagram(t, p$type))))
  if (op == "sem")        return(env(list(text = tf_compile_sem(t))))
  if (op == "preregister")return(env(list(text = tf_preregister(t))))
  if (op == "dossier")    return(env(list(text = tf_dossier(t))))
  if (op == "simulate")   return(env(list(result = tf_simulate(t, steps = p$steps, dt = p$dt, k = p$k, damping = p$damping, init = p$init))))
  if (op == "litmap") {
    lm <- tf_litmap(.tf_app$corpus, min_link = p$min_link)
    return(env(list(result = lm, dots = list(
      keyword_cooccurrence = tf_lit_diagram(lm, "keyword_cooccurrence"),
      co_citation = tf_lit_diagram(lm, "co_citation")))))
  }
  if (op == "landscape") {
    ls <- tf_landscape(t, .tf_app$corpus, min_link = p$min_link)
    return(env(list(result = ls, dot = tf_lit_diagram(ls, "theme_landscape"))))
  }
  stop(paste("unknown operation:", op))
}
`;

const RT = {
  lang: "r",
  langLabel: "R",
  engineLabel: "webR (WebAssembly)",
  accent: "#276DC3",
  accentInk: "#ffffff",
  docsUrl: "https://pablobernabeu.github.io/theoryforge/r/",
  examples: [],
  corpora: [],
  version: "",
  _webR: null,
  _corpusFile: null,
  _theoryFile: "your-theory.yaml",

  hasCorpus() { return this.corpora.length > 0; },

  async init(onProgress) {
    onProgress("Fetching package manifest…");
    const manifest = await (await fetch("vendor/manifest.json")).json();

    onProgress("Downloading the R runtime (webR)… this can take ~20s the first time.");
    const webR = new WebR();
    this._webR = webR;
    await webR.init();

    onProgress("Installing R dependencies (jsonlite, yaml)…");
    await webR.installPackages(["jsonlite", "yaml"]);

    onProgress("Vendoring the theoryforge R source into the browser…");
    await this._mkdirp(["/tf", "/tf/R", "/tf/schema", "/tf/fixtures"]);
    const enc = new TextEncoder();
    const writeVendor = async (rel, dest) => {
      const text = await (await fetch("vendor/" + rel)).text();
      await webR.FS.writeFile(dest, enc.encode(text));
    };
    for (const f of manifest.rFiles) await writeVendor(f, "/tf/" + f);
    await writeVendor(manifest.schema.theory, "/tf/schema/theory.schema.json");
    await writeVendor(manifest.schema.checklist, "/tf/schema/rigor_checklist.yaml");
    this._fixtures = {};
    for (const e of manifest.examples) { const dest = "/tf/" + e.path; await writeVendor(e.path, dest); this._fixtures[e.path] = dest; }
    for (const c of manifest.corpora) { const dest = "/tf/" + c.path; await writeVendor(c.path, dest); this._fixtures[c.path] = dest; }

    onProgress("Loading the package…");
    await webR.FS.writeFile("/tf/boot.R", enc.encode(BOOT_R));
    await webR.evalRVoid('source("/tf/boot.R")');

    this.version = (await webR.evalRString("R.version.string")) || "R";
    this.examples = manifest.examples;
    this.corpora = manifest.corpora;

    // Load a corpus (for the literature operations) and the first example.
    if (manifest.corpora.length) {
      this._corpusFile = manifest.corpora[0].path;
      await webR.evalRVoid(`.tf_load_corpus("${this._fixtures[this._corpusFile]}")`);
    }
    const summary = await this.loadExample(manifest.examples[0].path);
    return { version: this.version, examples: this.examples, corpora: this.corpora, summary };
  },

  async _mkdirp(dirs) {
    for (const d of dirs) { try { await this._webR.FS.mkdir(d); } catch (e) { /* exists */ } }
  },

  async loadExample(path) {
    this._theoryFile = path.split("/").pop();
    const json = await this._webR.evalRString(`.tf_load("${this._fixtures[path]}")`);
    return JSON.parse(json);
  },

  async loadTheoryText(text, filename) {
    const ext = /\.json$/i.test(filename) ? "json" : "yaml";
    const dest = "/tf/input." + ext;
    await this._webR.FS.writeFile(dest, new TextEncoder().encode(text));
    this._theoryFile = filename || "your-theory." + ext;
    const json = await this._webR.evalRString(`.tf_load("${dest}")`);
    return JSON.parse(json);
  },

  async run(opId, params) {
    const pj = JSON.stringify(params || {}).replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    const json = await this._webR.evalRString(`.tf_run("${opId}", "${pj}")`);
    const raw = JSON.parse(json);
    return { raw, code: this.code(opId, params) };
  },

  // ---- reproducible R code ------------------------------------------------
  code(opId, p) {
    const f = this._theoryFile;
    const head = `library(theoryforge)\ntheory <- tf_read("${f}")`;
    const corpus = `corpus <- tf_read_corpus("${(this._corpusFile || "corpus.yaml").split("/").pop()}")`;
    switch (opId) {
      case "check":
        return `${head}\n\nreport <- tf_check(theory)\nreport$aggregate_score   # overall 0-100\nreport$gate              # pass / blocked / advisory\n\n# Visualise the rigour grid (SVG):\nwriteLines(tf_diagram(theory, "rigor"), "rigor.svg")`;
      case "diagram": {
        const t = p.type;
        const isSvg = DIAG_SVG.has(t);
        return `${head}\n\nir <- tf_diagram(theory, "${t}")\ncat(ir)\n` + (isSvg
          ? `# '${t}' is emitted directly as SVG:\nwriteLines(ir, "${t}.svg")`
          : `# '${t}' is ${t === "causal_dag" ? "dagitty" : "Graphviz DOT"}; render with e.g.\n# DiagrammeR::grViz(ir)   or   write to a file and run Graphviz.`);
      }
      case "severity":
        return `${head}\n\nsev <- tf_severity(theory)        # per-prediction risk & computed severity\nsev\nwriteLines(tf_diagram(theory, "severity"), "severity.svg")`;
      case "redundancy":
        return `${head}\n\ntf_redundancy_check(theory)       # pairwise Jaccard overlap of construct definitions`;
      case "sem":
        return `${head}\n\ncat(tf_compile_sem(theory))       # lavaan model syntax`;
      case "preregister":
        return `${head}\n\ncat(tf_preregister(theory))       # preregistration document (Markdown)`;
      case "dossier":
        return `${head}\n\ncat(tf_dossier(theory))           # reviewer-facing audit bundle (Markdown)`;
      case "simulate":
        return `${head}\n\nsim <- tf_simulate(theory, steps = ${p.steps}, dt = ${p.dt}, k = ${p.k}, damping = ${p.damping}, init = ${p.init})\nstr(sim)                          # list(states, dt, steps, trajectory)`;
      case "litmap":
        return `${head}\n${corpus}\n\nlm <- tf_litmap(corpus, min_link = ${p.min_link})\nlm$themes\ncat(tf_lit_diagram(lm, "keyword_cooccurrence"))`;
      case "landscape":
        return `${head}\n${corpus}\n\nland <- tf_landscape(theory, corpus, min_link = ${p.min_link})\nland$under_theorized_fronts\ncat(tf_lit_diagram(land, "theme_landscape"))`;
      default:
        return head;
    }
  },
};

window.TF.start(RT);
