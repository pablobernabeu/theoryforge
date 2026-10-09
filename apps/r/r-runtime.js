/* theoryforge interactive app: R runtime (webR).
 *
 * Boots webR, installs jsonlite + yaml, vendors the live R package source into
 * the in-browser filesystem, sources it, and pre-seeds the schema, checklist
 * and fold-table caches, so the real package functions run unmodified and
 * entirely client-side.
 */
import { WebR } from "https://webr.r-wasm.org/latest/webr.mjs";

const DIAG_SVG = new Set(window.TF.DIAG_SVG);

// R bootstrap, sourced once into the global environment so all definitions and
// persistent state (.tf_app) survive across calls.
const BOOT_R = String.raw`
.tf_app_files <- list.files("/tf/R", pattern = "[.][Rr]$", full.names = TRUE)
invisible(lapply(.tf_app_files, source))

# Pre-seed the resource caches from the vendored files, so the package never
# needs system.file() (which only resolves for an installed package).
.tf_cache$checklist <- yaml::read_yaml("/tf/schema/rigor_checklist.yaml")
.tf_cache$theory_schema <- jsonlite::fromJSON("/tf/schema/theory.schema.json", simplifyVector = FALSE)
.tf_cache$fold <- .tf_fold_compile(jsonlite::fromJSON("/tf/schema/fold.json", simplifyVector = FALSE))

.tf_app <- new.env(parent = emptyenv())

# The prior the app's "Upload a prior version" option stands for, which
# .tf_load_prior() holds in .tf_app$prior.
.tf_UPLOADED_PRIOR <- "upload"

# The id, title and version record of a theory, each read as text, so a
# missing field is "". The app takes a candidate prior for the declared parent
# of the loaded theory when the candidate's version id is the theory's
# parent_id and the theory's id begins with the candidate's.
.tf_lineage_of <- function(t) {
  v <- .tf_get(t, "version")
  list(id = .tf_str(t, "id"), title = .tf_str(t, "title"),
       version = list(id = .tf_str(v, "id"), parent_id = .tf_str(v, "parent_id")))
}

.tf_summary <- function(t) {
  list(
    id = .tf_get(t, "id"), title = .tf_get(t, "title"),
    maturity = .tf_get(t, "maturity"), form = .tf_get(t, "theory_form"),
    version = .tf_lineage_of(t)$version,
    counts = list(
      constructs = length(.tf_list(t, "constructs")),
      propositions = length(.tf_list(t, "propositions")),
      predictions = length(.tf_list(t, "predictions")),
      alternatives = length(.tf_list(t, "alternatives")),
      assumptions = length(.tf_list(t, "auxiliary_assumptions"))
    ))
}

.tf_validation <- function(t) {
  tryCatch({ tf_validate(t, full = TRUE); list(ok = TRUE) },
           error = function(e) list(ok = FALSE, message = conditionMessage(e)))
}

# A file that cannot be read stops, and the previous theory stays loaded. One
# that reads but fails validation is loaded, and the summary says so, so the
# app can flag it before an operation trips over it.
.tf_load <- function(path) {
  .tf_app$theory <- tf_read(path)
  out <- .tf_summary(.tf_app$theory)
  out$validation <- .tf_validation(.tf_app$theory)
  as.character(jsonlite::toJSON(out, auto_unbox = TRUE, digits = NA, null = "null"))
}
.tf_load_corpus <- function(path) {
  .tf_app$corpus <- tf_read_corpus(path)
  "ok"
}

# The lineage of each candidate prior, read without loading it. A file that
# cannot be read has none, so it is never taken for a declared parent.
.tf_lineage <- function(paths) {
  out <- lapply(unname(paths), function(p) {
    tryCatch(.tf_lineage_of(tf_read(p)), error = function(e) NULL)
  })
  as.character(jsonlite::toJSON(out, auto_unbox = TRUE, digits = NA, null = "null"))
}
.tf_lineage_call <- function() {
  call <- jsonlite::fromJSON(
    readChar("/tf/call.json", file.info("/tf/call.json")$size, useBytes = TRUE),
    simplifyVector = TRUE)
  .tf_lineage(call$paths)
}

# An uploaded prior is held apart from the theory. A file that cannot be read
# stops, and the prior uploaded before it stays.
.tf_load_prior <- function(path) {
  .tf_app$prior <- tf_read(path)
  as.character(jsonlite::toJSON(.tf_lineage_of(.tf_app$prior),
                                auto_unbox = TRUE, digits = NA, null = "null"))
}

.tf_run <- function(op, p) {
  t <- .tf_app$theory
  env <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null"))
  if (op == "check")      return(env(list(report = tf_check(t), svg = tf_diagram(t, "rigour"))))
  if (op == "validate")   return(env(.tf_validation(t)))
  if (op == "severity")   return(env(list(rows = tf_severity(t), svg = tf_diagram(t, "severity"))))
  if (op == "redundancy") return(env(list(rows = tf_redundancy_check(t))))
  if (op == "appraise") {
    prior <- if (identical(p$prior, .tf_UPLOADED_PRIOR)) .tf_app$prior else tf_read(p$prior)
    if (is.null(prior)) stop("No prior version uploaded", call. = FALSE)
    return(env(tf_appraise_amendment(t, prior)))
  }
  # A refusal, a feedback loop under the default or a relation the graph
  # cannot be built from, is a result the app shows with its message.
  if (op == "implications") {
    cycles <- if (is.null(p$cycles)) "refuse" else p$cycles
    return(env(tryCatch(list(result = tf_implications(t, cycles = cycles)),
                        error = function(e) list(ok = FALSE, message = conditionMessage(e)))))
  }
  if (op == "diagram")    return(env(list(ir = tf_diagram(t, p$type))))
  if (op == "sem")        return(env(list(text = tf_compile_sem(t))))
  if (op == "preregister")return(env(list(text = tf_preregister(t))))
  if (op == "dossier")    return(env(list(text = tf_dossier(t))))
  # steps is passed as given, so a fractional value is refused as the package
  # refuses it, not truncated. A refusal or a divergence comes back as a
  # message for the app to show, as in the Python runtime. The Euler run's
  # departure warning is caught without stopping the run and comes back with
  # the result.
  if (op == "simulate") {
    warned <- NULL
    method <- if (is.null(p$method)) "exact" else p$method
    res <- tryCatch(withCallingHandlers(
      list(result = tf_simulate(t,
        steps = p$steps, dt = as.numeric(p$dt), k = as.numeric(p$k),
        damping = as.numeric(p$damping), init = as.numeric(p$init), method = method)),
      warning = function(w) {
        if (is.null(warned)) warned <<- conditionMessage(w)
        invokeRestart("muffleWarning")
      }),
      error = function(e) list(ok = FALSE, message = conditionMessage(e)))
    if (!is.null(warned) && !is.null(res$result)) res$warning <- warned
    return(env(res))
  }
  if (op == "litmap") {
    lm <- tf_litmap(.tf_app$corpus, min_link = as.integer(p$min_link))
    return(env(list(result = lm, dots = list(
      keyword_cooccurrence = tf_lit_diagram(lm, "keyword_cooccurrence"),
      co_citation = tf_lit_diagram(lm, "co_citation")))))
  }
  if (op == "landscape") {
    ls <- tf_landscape(t, .tf_app$corpus, min_link = as.integer(p$min_link))
    return(env(list(result = ls, dot = tf_lit_diagram(ls, "theme_landscape"))))
  }
  stop(paste("unknown operation:", op))
}

# Dispatch from a JSON call file, avoiding any interpolation of data into R source.
.tf_run_call <- function() {
  call <- jsonlite::fromJSON(
    readChar("/tf/call.json", file.info("/tf/call.json")$size, useBytes = TRUE),
    simplifyVector = TRUE)
  .tf_run(call$op, call$params)
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
  version: "",     // interpreter version (R.version.string), set at boot
  pkgVersion: "",  // theoryforge release, stamped into the manifest by build.mjs
  _webR: null,
  _corpusFile: null,
  _theoryFile: "your-theory.yaml",
  // Whether the package ships the theory's file, which the code then reads
  // through tf_example_path(). An upload never is.
  _theoryShipped: false,
  // The uploaded prior's file name, set once the engine has read it.
  _priorFile: null,

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
    await writeVendor(manifest.schema.fold, "/tf/schema/fold.json");
    this._fixtures = {};
    for (const e of manifest.examples) { const dest = "/tf/" + e.path; await writeVendor(e.path, dest); this._fixtures[e.path] = dest; }
    for (const c of manifest.corpora) { const dest = "/tf/" + c.path; await writeVendor(c.path, dest); this._fixtures[c.path] = dest; }

    onProgress("Loading the package…");
    await webR.FS.writeFile("/tf/boot.R", enc.encode(BOOT_R));
    await webR.evalRVoid('source("/tf/boot.R")');

    this.version = (await webR.evalRString("R.version.string")) || "R";
    // The theoryforge release shown in the footer. build.mjs stamps it into the
    // manifest from DESCRIPTION (after checking pyproject.toml agrees), so the
    // app cannot drift from the packaged version.
    this.pkgVersion = manifest.pkgVersion || "";
    // Each example's lineage, read once, lets the appraisal default to the
    // version the loaded theory declares as its parent.
    onProgress("Reading the examples' versions…");
    const lineage = await this.lineageOf(manifest.examples.map((e) => this._fixtures[e.path]));
    this.examples = manifest.examples.map((e, i) => Object.assign({}, e, { lineage: lineage[i] }));
    this.corpora = manifest.corpora;

    // Load a corpus (for the literature operations) and the first example.
    if (manifest.corpora.length) {
      this._corpusFile = manifest.corpora[0].path;
      await webR.evalRVoid(`.tf_load_corpus("${this._fixtures[this._corpusFile]}")`);
    }
    const summary = await this.loadExample(manifest.examples[0].path);
    return { version: this.version, pkgVersion: this.pkgVersion, examples: this.examples, corpora: this.corpora, summary };
  },

  async _mkdirp(dirs) {
    for (const d of dirs) { try { await this._webR.FS.mkdir(d); } catch (e) { /* exists */ } }
  },

  // The code panel names _theoryFile, so it changes only once the engine holds
  // the new theory. A load that fails leaves the previous theory in the engine
  // and its name here.
  async loadExample(path) {
    const json = await this._webR.evalRString(`.tf_load("${this._fixtures[path]}")`);
    this._theoryFile = path.split("/").pop();
    this._theoryShipped = this._shipped(this.examples, path);
    return JSON.parse(json);
  },

  async loadTheoryText(text, filename) {
    const ext = /\.json$/i.test(filename) ? "json" : "yaml";
    const dest = "/tf/input." + ext;
    await this._webR.FS.writeFile(dest, new TextEncoder().encode(text));
    const json = await this._webR.evalRString(`.tf_load("${dest}")`);
    this._theoryFile = filename || "your-theory." + ext;
    this._theoryShipped = false;
    return JSON.parse(json);
  },

  // An uploaded prior has a file of its own and is held apart from the theory.
  // Its name is recorded for the code panel only once the engine has read it.
  async loadPriorText(text, filename) {
    const ext = /\.json$/i.test(filename) ? "json" : "yaml";
    const dest = "/tf/prior." + ext;
    await this._webR.FS.writeFile(dest, new TextEncoder().encode(text));
    const json = await this._webR.evalRString(`.tf_load_prior("${dest}")`);
    this._priorFile = filename || "prior." + ext;
    return JSON.parse(json);
  },

  // The lineage of each file in `paths` (in-FS paths), null for one that
  // cannot be read. Nothing is loaded. The paths travel as a JSON call file,
  // as an operation's parameters do.
  async lineageOf(paths) {
    await this._webR.FS.writeFile("/tf/call.json", new TextEncoder().encode(JSON.stringify({ paths })));
    return JSON.parse(await this._webR.evalRString(".tf_lineage_call()"));
  },

  _shipped(list, path) {
    const e = (list || []).find((x) => x.path === path);
    return !!(e && e.shipped);
  },

  async run(opId, params) {
    // Pass the call as a JSON file rather than interpolating data into R source.
    const call = JSON.stringify({ op: opId, params: this._mapParams(opId, params) || {} });
    await this._webR.FS.writeFile("/tf/call.json", new TextEncoder().encode(call));
    const json = await this._webR.evalRString(".tf_run_call()");
    return { raw: JSON.parse(json), code: this.code(opId, params) };
  },

  // The 'prior' param arrives as a manifest path; map it to its in-FS path.
  _mapParams(opId, params) {
    if (opId === "appraise" && params && params.prior) {
      return Object.assign({}, params, { prior: this._fixtures[params.prior] || params.prior });
    }
    return params;
  },

  // ---- reproducible R code ------------------------------------------------
  // A file the package ships is read through tf_example_path(), so the code
  // runs wherever the package is installed. Any other file, an app-only
  // example or an upload, has to be saved beside the script first. `note`
  // ends that comment. The name is a JSON string literal in the code, which R
  // reads as written. In the comment, a line feed or carriage return in an
  // uploaded file's name would end the comment and leave the rest of the
  // name as code, so every control character is shown as "?".
  _read(name, fn, file, shipped, note) {
    const lit = JSON.stringify(file);
    const shown = String(file).replace(/[\u0000-\u001f\u007f]/g, "?");
    return shipped
      ? `${name} <- ${fn}(tf_example_path(${lit}))`
      : `# Save ${shown} beside this script first${note || "."}\n${name} <- ${fn}(${lit})`;
  },

  code(opId, p) {
    const head = "library(theoryforge)\n" +
      this._read("theory", "tf_read", this._theoryFile, this._theoryShipped, " (View source in the app offers a download).");
    const cf = this._corpusFile || "corpus.yaml";
    const corpus = this._read("corpus", "tf_read_corpus", cf.split("/").pop(), this._shipped(this.corpora, cf));
    switch (opId) {
      case "check":
        return `${head}\n\nreport <- tf_check(theory)\nreport$aggregate_score   # overall 0-100\nreport$gate              # pass / blocked / advisory\n\n# Visualise the rigour grid (SVG):\nwriteLines(tf_diagram(theory, "rigour"), "rigour.svg")`;
      case "validate":
        return `${head}\n\ntf_validate(theory, full = TRUE)   # structural + referential integrity; stops, listing every problem`;
      case "appraise": {
        const uploaded = p.prior === "upload";
        const pf = uploaded ? this._priorFile || "prior.theory.yaml" : String(p.prior || "prior.theory.yaml").split("/").pop();
        const prior = this._read("prior", "tf_read", pf, !uploaded && this._shipped(this.examples, p.prior));
        return `${head}\n${prior}\n\nappr <- tf_appraise_amendment(theory, prior)\nappr$verdict                      # progressive / degenerating / neutral`;
      }
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
        return `${head}\n\ntf_redundancy_check(theory)       # pairwise Jaccard and overlap of construct definitions`;
      case "sem":
        return `${head}\n\ncat(tf_compile_sem(theory))       # lavaan model syntax`;
      case "implications":
        return `${head}\n\n# A refusal stops with the message the app shows.\nimplied <- tf_implications(theory, cycles = "${p.cycles || "refuse"}")\nvapply(implied$implications, function(s) s$statement, character(1))`;
      case "preregister":
        return `${head}\n\ncat(tf_preregister(theory))       # preregistration document (Markdown)`;
      case "dossier":
        return `${head}\n\ncat(tf_dossier(theory))           # reviewer-facing audit bundle (Markdown)`;
      case "simulate":
        return `${head}\n\nsim <- tf_simulate(theory, steps = ${p.steps}, dt = ${p.dt}, k = ${p.k}, damping = ${p.damping}, init = ${p.init}, method = "${p.method || "exact"}")\nstr(sim)                          # list(states, dt, steps, k, damping, init, method, ignored, opposed, trajectory)`;
      case "litmap":
        return `${head}\n${corpus}\n\nlm <- tf_litmap(corpus, min_link = ${p.min_link})\nlm$themes\ncat(tf_lit_diagram(lm, "keyword_cooccurrence"))`;
      case "landscape":
        return `${head}\n${corpus}\n\nland <- tf_landscape(theory, corpus, min_link = ${p.min_link})\nland$under_theorised_fronts\ncat(tf_lit_diagram(land, "theme_landscape"))`;
      default:
        return head;
    }
  },
};

window.TF.start(RT);
