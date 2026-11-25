/* theoryforge interactive app: R runtime (webR).
 *
 * Boots webR, installs jsonlite + yaml, vendors the live R package source into
 * the in-browser filesystem, sources it, and pre-seeds the schema, checklist
 * and fold-table caches, so the real package functions run unmodified and
 * entirely client-side.
 */
// webR 0.6.1 runs R 4.6.0. The release is pinned, as Pyodide's is in
// py-runtime.js, because the "latest" address serves webR's development build,
// which can change the R under the app with nothing changed here. The two
// engines are updated deliberately (apps/README.md, "Runtimes").
const WEBR_URL = "https://webr.r-wasm.org/v0.6.1/webr.mjs";

// The engine is imported inside init rather than at the top of this module.
// A module whose static import fails never runs, so the page would stay blank,
// where a failure inside init reaches the app's panel with a Reload button.
const loadEngine = (what, host, url) => import(url).catch((e) => {
  throw new Error(`Could not download ${what} from ${host}. Check that your network allows it, then reload. (${(e && e.message) || e})`);
});

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
.tf_app$corpora <- list()

# The value of a parameter that stands for a file the user uploaded: a prior
# version, a rival theory or a corpus, each held apart from the theory.
.tf_UPLOADED <- "upload"
# The literature figures draw the strongest links only, as many as this.
.tf_MAX_EDGES <- 60L

.tf_json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null"))

# The id, title and version record of a theory, each read as text, so a
# missing field is "". The app takes a candidate prior for the declared parent
# of the loaded theory when the candidate's version id is the theory's
# parent_id and the theory's id begins with the candidate's.
.tf_lineage_of <- function(t) {
  v <- .tf_get(t, "version")
  list(id = .tf_str(t, "id"), title = .tf_str(t, "title"),
       version = list(id = .tf_str(v, "id"), parent_id = .tf_str(v, "parent_id")))
}

# The length of the theory as jsonlite writes it, from which the app tells a
# theory too long to hash as it loads. Python's json module writes some
# numbers differently, so the two glues can differ by a few characters. A
# theory with more values than .tf_MEASURED_VALUES is not measured, and its
# length is NULL.
.tf_MEASURED_VALUES <- 20000L
.tf_chars <- function(t) {
  if (length(unlist(unclass(t), use.names = FALSE)) > .tf_MEASURED_VALUES) return(NULL)
  tryCatch(nchar(jsonlite::toJSON(unclass(t), auto_unbox = TRUE, null = "null", digits = NA), type = "chars"),
           error = function(e) NULL)
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
      assumptions = length(.tf_list(t, "auxiliary_assumptions")),
      phenomena = length(.tf_list(t, "phenomena")),
      outcomes = length(.tf_list(t, "test_outcomes"))
    ),
    chars = .tf_chars(t),
    # The constructs an impulse can start from and the rivals that state
    # propositions of their own, which the app offers as choices.
    constructs = lapply(.tf_list(t, "constructs"), function(c) {
      list(id = .tf_str(c, "id"), label = .tf_str(c, "label"))
    }),
    alternatives = lapply(.tf_list(t, "alternatives"), function(a) {
      list(id = .tf_str(a, "id"), label = .tf_str(a, "label"),
           propositions = length(.tf_list(a, "propositions")))
    }))
}

# Full validation, with the problems as a list as well as the package's joined
# message: a message may quote a value of the theory that holds "; " itself, so
# the app counts and lists the problems from the list. as.list() keeps a single
# problem an array in the JSON.
.tf_validation <- function(t) {
  tryCatch({
    p <- .tf_validation_problems(t, TRUE)
    if (!length(p)) list(ok = TRUE) else
      list(ok = FALSE, message = paste0("invalid theory object: ", paste(p, collapse = "; ")),
           problems = as.list(p))
  }, error = function(e) list(ok = FALSE, message = conditionMessage(e)))
}

# The checklist's score and gate, which the card and the editor show, or the
# message of a theory the checklist refuses. An error without a message is
# named by its class.
.tf_score <- function(t) {
  tryCatch({
    r <- tf_check(t)
    ids <- function(status) {
      as.character(unlist(lapply(r$items, function(i) if (identical(i$status, status)) i$id)))
    }
    list(score = r$aggregate_score, gate = r$gate, failed = I(ids("fail")), warned = I(ids("warn")))
  }, error = function(e) {
    msg <- conditionMessage(e)
    list(error = if (nzchar(msg)) msg else class(e)[[1L]])
  })
}

# The score of the loaded theory. It is a call of its own, which the app makes
# once the theory card has been drawn, so that the checklist, whose time grows
# faster than the theory, never holds up a load, a restore or the start.
.tf_score_call <- function() .tf_json(.tf_score(.tf_app$theory))

.tf_hash <- function(t) tryCatch(tf_content_hash(t), error = function(e) NULL)

# The content hash of the loaded theory, or the message of the error that
# stopped it. It is a call of its own, which the app makes once a load has
# finished, so that a slow hash never holds up a load or the start.
.tf_hash_call <- function() {
  .tf_json(tryCatch(list(hash = tf_content_hash(.tf_app$theory)),
                    error = function(e) list(error = conditionMessage(e))))
}

.tf_loaded <- function(t) {
  .tf_app$theory <- t
  out <- .tf_summary(t)
  out$validation <- .tf_validation(t)
  out
}

# A file that cannot be read stops, and the previous theory stays loaded. One
# that reads but fails validation is loaded, and the summary says so, so the
# app can flag it before an operation trips over it.
.tf_load <- function(path) .tf_json(.tf_loaded(tf_read(path)))

# The theory as the package's own writer writes it, as YAML or as JSON.
.tf_written <- function(t, fmt) {
  f <- tempfile(fileext = if (identical(fmt, "json")) ".json" else ".yaml")
  on.exit(unlink(f), add = TRUE)
  tf_write(t, f)
  out <- rawToChar(readBin(f, "raw", file.info(f)$size))
  Encoding(out) <- "UTF-8"
  out
}
.tf_write_text <- function(fmt) {
  if (is.null(.tf_app$theory)) stop("No theory loaded", call. = FALSE)
  .tf_written(.tf_app$theory, fmt)
}

.tf_read_call <- function() {
  jsonlite::fromJSON(
    readChar("/tf/call.json", file.info("/tf/call.json")$size, useBytes = TRUE),
    simplifyVector = TRUE)
}

# The editor's call: the theory in the file at path replaces the loaded one,
# and the result carries the summary and the theory written in each format
# asked for. A file that cannot be read stops and leaves the theory as it was.
.tf_edit <- function(path, formats) {
  out <- .tf_loaded(tf_read(path))
  texts <- list()
  for (fmt in formats) texts[[fmt]] <- .tf_written(.tf_app$theory, fmt)
  out$texts <- if (length(texts)) texts else structure(list(), names = character(0))
  .tf_json(out)
}
.tf_edit_call <- function() {
  call <- .tf_read_call()
  .tf_edit(call$path, as.character(call$formats))
}

# The theory the package's DAGitty reader makes of the model code in the file
# the call names replaces the loaded one. The settings the user gives, id,
# title and the relation an arrow reads as, are passed on, and any other is
# the package's default. A model the reader refuses stops and leaves the
# theory as it was.
.tf_import_dagitty <- function(path, opts) {
  model <- rawToChar(readBin(path, "raw", file.info(path)$size))
  Encoding(model) <- "UTF-8"
  args <- list(model)
  for (k in c("id", "title", "relation")) {
    if (is.character(opts[[k]]) && length(opts[[k]]) == 1L && nzchar(opts[[k]])) args[[k]] <- opts[[k]]
  }
  out <- .tf_loaded(do.call(tf_read_dagitty, args))
  texts <- list()
  for (fmt in as.character(opts$formats)) texts[[fmt]] <- .tf_written(.tf_app$theory, fmt)
  out$texts <- if (length(texts)) texts else structure(list(), names = character(0))
  .tf_json(out)
}
.tf_import_dagitty_call <- function() {
  call <- .tf_read_call()
  .tf_import_dagitty(call$path, call)
}

# A bundled corpus is read once, when an operation first asks for it, and an
# uploaded one is held under "upload". A file that cannot be read stops, and
# the corpus uploaded before it stays.
.tf_load_corpus <- function(path, key = path) {
  corpus <- tf_read_corpus(path)
  .tf_app$corpora[[key]] <- corpus
  .tf_json(list(id = .tf_str(corpus, "id"), n_records = length(.tf_list(corpus, "records"))))
}
.tf_corpus <- function(p) {
  key <- if (is.null(p$corpus)) "" else p$corpus
  if (identical(key, .tf_UPLOADED)) {
    if (is.null(.tf_app$corpora[[key]])) stop("No corpus uploaded", call. = FALSE)
    return(.tf_app$corpora[[key]])
  }
  if (is.null(.tf_app$corpora[[key]])) .tf_app$corpora[[key]] <- tf_read_corpus(key)
  .tf_app$corpora[[key]]
}

# The lineage of each candidate prior, read without loading it. A file that
# cannot be read has none, so it is never taken for a declared parent.
.tf_lineage <- function(paths) {
  out <- lapply(unname(paths), function(p) {
    tryCatch(.tf_lineage_of(tf_read(p)), error = function(e) NULL)
  })
  .tf_json(out)
}
.tf_lineage_call <- function() .tf_lineage(.tf_read_call()$paths)

# An uploaded prior is held apart from the theory. A file that cannot be read
# stops, and the prior uploaded before it stays.
.tf_load_prior <- function(path) {
  .tf_app$prior <- tf_read(path)
  .tf_json(.tf_lineage_of(.tf_app$prior))
}

# An uploaded rival theory, held apart from the theory as a prior is.
.tf_load_rival <- function(path) {
  .tf_app$rival <- tf_read(path)
  out <- .tf_lineage_of(.tf_app$rival)
  out$constructs <- length(.tf_list(.tf_app$rival, "constructs"))
  .tf_json(out)
}

# A refusal is the package's answer for the theory, so the app shows it as a
# result with the package's message. expr gives the result's envelope.
.tf_answer <- function(expr) {
  tryCatch(expr, error = function(e) list(ok = FALSE, message = conditionMessage(e)))
}

# A run whose warning comes back with the result: the Euler run's departure
# from the exact solution, or litmap's warning that one theme holds most of
# the keywords.
.tf_warned <- function(expr) {
  warned <- NULL
  res <- withCallingHandlers(expr, warning = function(w) {
    if (is.null(warned)) warned <<- conditionMessage(w)
    invokeRestart("muffleWarning")
  })
  if (!is.null(warned) && !identical(res$ok, FALSE)) res$warning <- warned
  res
}

.tf_run <- function(op, p) {
  t <- .tf_app$theory
  env <- .tf_json
  cycles <- if (is.null(p$cycles)) "refuse" else p$cycles
  if (op == "check")      return(env(list(report = tf_check(t), svg = tf_diagram(t, "rigour"))))
  if (op == "validate")   return(env(.tf_validation(t)))
  if (op == "severity")   return(env(list(rows = tf_severity(t), svg = tf_diagram(t, "severity"))))
  if (op == "post_severity") return(env(.tf_answer(list(result = tf_post_data_severity(t)))))
  if (op == "redundancy") return(env(list(rows = tf_redundancy_check(t))))
  if (op == "appraise") {
    prior <- if (identical(p$prior, .tf_UPLOADED)) .tf_app$prior else tf_read(p$prior)
    if (is.null(prior)) stop("No prior version uploaded", call. = FALSE)
    return(env(tf_appraise_amendment(t, prior)))
  }
  if (op == "discriminate") {
    if (identical(p$rival, .tf_UPLOADED)) {
      rival <- .tf_app$rival
      if (is.null(rival)) stop("No rival theory uploaded", call. = FALSE)
    } else if (is.character(p$rival) && length(p$rival) == 1L && nzchar(p$rival)) {
      rival <- p$rival
    } else {
      stop("No rival chosen", call. = FALSE)
    }
    return(env(.tf_answer(list(result = tf_discriminate(t, rival, cycles = cycles)))))
  }
  # A refusal, a feedback loop under the default or a relation the graph
  # cannot be built from, is a result the app shows with its message.
  if (op == "implications") return(env(.tf_answer(list(result = tf_implications(t, cycles = cycles)))))
  if (op == "entailments")  return(env(.tf_answer(list(result = tf_entailments(t, cycles = cycles)))))
  if (op == "equivalent")   return(env(.tf_answer(list(result = tf_equivalent_models(t)))))
  if (op == "diagram")    return(env(list(ir = tf_diagram(t, p$type))))
  if (op == "sem")        return(env(list(text = tf_compile_sem(t))))
  if (op == "preregister") return(env(list(text = tf_preregister(t, cycles = cycles), hash = .tf_hash(t))))
  if (op == "dossier")    return(env(list(text = tf_dossier(t, cycles = cycles), hash = .tf_hash(t))))
  # steps is passed as given, so a fractional value is refused as the package
  # refuses it, not truncated. A refusal or a divergence comes back as a
  # message for the app to show, as in the Python runtime. An impulse starts
  # the chosen construct at 1 and every other at 0, through the mapping form
  # of init.
  if (op == "simulate") {
    method <- if (is.null(p$method)) "exact" else p$method
    init <- if (identical(p$start, "impulse")) stats::setNames(1, p$impulse) else as.numeric(p$init)
    return(env(.tf_warned(.tf_answer(list(result = tf_simulate(t,
      steps = p$steps, dt = as.numeric(p$dt), k = as.numeric(p$k),
      damping = as.numeric(p$damping), init = init, method = method))))))
  }
  if (op == "litmap") {
    corpus <- .tf_corpus(p)
    method <- if (is.null(p$method)) "components" else p$method
    min_df <- if (is.null(p$min_df)) 1L else as.integer(p$min_df)
    max_df <- if (is.null(p$max_df)) 1 else as.numeric(p$max_df)
    return(env(.tf_warned(.tf_answer({
      lm <- tf_litmap(corpus, min_link = as.integer(p$min_link), method = method,
                      min_df = min_df, max_df = max_df)
      list(result = lm, dots = list(
        keyword_cooccurrence = tf_lit_diagram(lm, "keyword_cooccurrence", max_edges = .tf_MAX_EDGES),
        co_citation = tf_lit_diagram(lm, "co_citation", max_edges = .tf_MAX_EDGES)))
    }))))
  }
  if (op == "landscape") {
    corpus <- .tf_corpus(p)
    method <- if (is.null(p$method)) "components" else p$method
    return(env(.tf_warned(.tf_answer({
      ls <- tf_landscape(t, corpus, min_link = as.integer(p$min_link), method = method)
      list(result = ls, dot = tf_lit_diagram(ls, "theme_landscape"))
    }))))
  }
  stop(paste("unknown operation:", op))
}

# Dispatch from a JSON call file, avoiding any interpolation of data into R source.
.tf_run_call <- function() {
  call <- .tf_read_call()
  .tf_run(call$op, call$params)
}
`;

const RT = {
  lang: "r",
  // The size above which the card's score and hash wait for the user to ask
  // (apps/README.md, "Runtimes"). In webR, the checklist took up to 2.7 s on
  // 300 constructs, propositions and predictions, and the hash up to 2.5 s on
  // 48,000 characters of JSON made mostly of test outcomes, whose numbers cost
  // the canonical writer most.
  limits: { score: 300, hashChars: 50000 },
  langLabel: "R",
  engineLabel: "webR (WebAssembly)",
  accent: "#276DC3",
  accentInk: "#ffffff",
  // Text in the accent colour, lighter in the dark theme, where the fill
  // colour above reads at less than 4.5:1 on the panels.
  accentText: { light: "#2563b0", dark: "#8ab8f0" },
  docsUrl: "https://pablobernabeu.github.io/theoryforge/r/",
  examples: [],
  corpora: [],
  version: "",     // interpreter version (R.version.string), set at boot
  pkgVersion: "",  // this package's version (DESCRIPTION), which build.mjs stamps into the manifest
  _webR: null,
  _theoryFile: "your-theory.yaml",
  // Whether the package ships the theory's file, which the code then reads
  // through tf_example_path(). An upload or an edited theory never is.
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
    const engine = loadEngine("the R engine (webR)", "webr.r-wasm.org", WEBR_URL);
    engine.catch(() => {});   // a failure is reported where it is awaited
    onProgress("Fetching package manifest…");
    const manifest = await window.TF.util.fetchJson("vendor/manifest.json");

    // The package files are fetched while the engine downloads.
    const files = [...manifest.rFiles.map((f) => [f, "/tf/" + f]),
      [manifest.schema.theory, "/tf/schema/theory.schema.json"],
      [manifest.schema.checklist, "/tf/schema/rigor_checklist.yaml"],
      [manifest.schema.fold, "/tf/schema/fold.json"],
      ...manifest.examples.map((e) => [e.path, "/tf/" + e.path]),
      ...manifest.corpora.map((c) => [c.path, "/tf/" + c.path])];
    const fetched = Promise.all(files.map(([rel, dest]) => window.TF.util.fetchBytes("vendor/" + rel).then((buf) => [dest, buf])));
    fetched.catch(() => {});   // a failure is reported where it is awaited

    onProgress("Downloading the R runtime (webR)… this can take ~20s the first time.");
    const { WebR } = await engine;
    const webR = new WebR();
    this._webR = webR;
    await webR.init();

    onProgress("Installing R dependencies (jsonlite, yaml)…");
    await webR.installPackages(["jsonlite", "yaml"]);
    // installPackages() only warns when the repository cannot be reached, and
    // the first error would then name a package R cannot find, so what was
    // installed is checked here.
    const missing = [];
    for (const p of ["jsonlite", "yaml"]) {
      if (!await webR.evalRBoolean(`requireNamespace("${p}", quietly = TRUE)`)) missing.push(p);
    }
    if (missing.length) {
      throw new Error("Could not install the R package" + (missing.length > 1 ? "s " : " ") + missing.join(" and ") +
        " from repo.r-wasm.org. Check the connection and reload.");
    }
    // repo.r-wasm.org serves its current builds of the two, which are not
    // pinned, so the console records the versions this session installed.
    try {
      console.info("theoryforge R app: " + await webR.evalRString(
        'paste(vapply(c("jsonlite", "yaml"), function(p) paste(p, format(packageVersion(p))), ""), collapse = ", ")'));
    } catch (e) { /* a missing record never stops the app */ }

    onProgress("Vendoring the theoryforge R source into the browser…");
    await this._mkdirp(["/tf", "/tf/R", "/tf/schema", "/tf/fixtures"]);
    const enc = new TextEncoder();
    await Promise.all((await fetched).map(([dest, buf]) => webR.FS.writeFile(dest, buf)));
    this._fixtures = {};
    for (const e of [...manifest.examples, ...manifest.corpora]) this._fixtures[e.path] = "/tf/" + e.path;

    onProgress("Loading the package…");
    await webR.FS.writeFile("/tf/boot.R", enc.encode(BOOT_R));
    await webR.evalRVoid('source("/tf/boot.R")');
    this.canImportDagitty = await webR.evalRBoolean('exists("tf_read_dagitty", mode = "function")');

    this.version = (await webR.evalRString("R.version.string")) || "R";
    // The version of the R package, shown in the footer. build.mjs stamps it
    // into the manifest from DESCRIPTION, after checking that pyproject.toml
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

  async _mkdirp(dirs) {
    for (const d of dirs) { try { await this._webR.FS.mkdir(d); } catch (e) { /* exists */ } }
  },

  // A call's arguments travel as a JSON file rather than as R source.
  async _call(fn, args) {
    await this._webR.FS.writeFile("/tf/call.json", new TextEncoder().encode(JSON.stringify(args)));
    return this._webR.evalRString(fn + "()");
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

  // Write text the user gave the app to the in-browser file `stem`.ext and
  // record the user's name for it.
  async _put(stem, text, filename, format) {
    const ext = format || (/\.json$/i.test(filename || "") ? "json" : "yaml");
    const dest = "/tf/" + stem + "." + ext;
    await this._webR.FS.writeFile(dest, new TextEncoder().encode(text));
    this.fileNames[dest] = filename || stem + "." + ext;
    return dest;
  },

  async loadTheoryText(text, filename) {
    const dest = await this._put("input", text, filename);
    const json = await this._webR.evalRString(`.tf_load("${dest}")`);
    this._theoryFile = filename || "your-theory." + dest.split(".").pop();
    this._theoryShipped = false;
    return JSON.parse(json);
  },

  // The editor's call. `text`, in `format` ("yaml" or "json"), replaces the
  // loaded theory, and the result carries the theory as the package's writer
  // writes it in each of `formats`. `filename` is the name the code panel
  // reads the theory from, the name Save gives the file.
  async editText(text, format, filename, formats) {
    const dest = await this._put("edit", text, filename, format === "json" ? "json" : "yaml");
    const json = await this._call(".tf_edit_call", { path: dest, formats: formats || [] });
    this._theoryFile = filename || "your-theory." + dest.split(".").pop();
    this._theoryShipped = false;
    return JSON.parse(json);
  },

  // Whether this package version has a DAGitty reader, read at start-up.
  canImportDagitty: false,

  // The theory the package's DAGitty reader makes of `model` replaces the
  // loaded one. `opts` holds the id, title and relation the user chose.
  async importDagitty(model, opts, formats) {
    const dest = await this._put("dagitty", model, "DAGitty model code", "txt");
    const json = await this._call(".tf_import_dagitty_call", Object.assign({}, opts, { path: dest, formats: formats || [] }));
    const out = JSON.parse(json);
    this._theoryFile = (out.id || "dagitty-import") + ".theory.yaml";
    this._theoryShipped = false;
    return out;
  },
  // The code that makes the same theory with the installed package.
  importCode(opts) {
    const args = ["id", "title", "relation"].filter((k) => opts[k]).map((k) => `, ${k} = ${JSON.stringify(String(opts[k]))}`).join("");
    return `library(theoryforge)\nmodel <- paste(readLines("model.dag", encoding = "UTF-8"), collapse = "\\n")   # the DAGitty model code\ntheory <- tf_read_dagitty(model${args})\ntf_write(theory, ${JSON.stringify(opts.file || (opts.id || "dagitty-import") + ".theory.yaml")})`;
  },

  // The name the code panel reads the theory from, when the app renames it.
  renameTheory(filename) { this._theoryFile = filename; },

  // The content hash of the loaded theory, as { hash } or { error }.
  async contentHash() { return JSON.parse(await this._webR.evalRString(".tf_hash_call()")); },

  // The checklist's score of the loaded theory, as { score, gate, failed,
  // warned } or { error }.
  async score() { return JSON.parse(await this._webR.evalRString(".tf_score_call()")); },

  // The loaded theory as the package's writer writes it ("yaml" or "json").
  async writeText(format) {
    return this._webR.evalRString(`.tf_write_text("${format === "json" ? "json" : "yaml"}")`);
  },

  // An uploaded prior has a file of its own and is held apart from the theory.
  // Its name is recorded for the code panel only once the engine has read it.
  async loadPriorText(text, filename) {
    const dest = await this._put("prior", text, filename);
    const json = await this._webR.evalRString(`.tf_load_prior("${dest}")`);
    this._priorFile = filename || "prior." + dest.split(".").pop();
    return JSON.parse(json);
  },

  async loadRivalText(text, filename) {
    const dest = await this._put("rival", text, filename);
    const json = await this._webR.evalRString(`.tf_load_rival("${dest}")`);
    this._rivalFile = filename || "rival." + dest.split(".").pop();
    return JSON.parse(json);
  },

  async loadCorpusText(text, filename) {
    const dest = await this._put("corpus", text, filename);
    const json = await this._webR.evalRString(`.tf_load_corpus("${dest}", "upload")`);
    this._corpusUpload = filename || "corpus." + dest.split(".").pop();
    return JSON.parse(json);
  },

  // The lineage of each file in `paths` (in-FS paths), null for one that
  // cannot be read. Nothing is loaded. The paths travel as a JSON call file,
  // as an operation's parameters do.
  async lineageOf(paths) {
    return JSON.parse(await this._call(".tf_lineage_call", { paths }));
  },

  _shipped(list, path) {
    const e = (list || []).find((x) => x.path === path);
    return !!(e && e.shipped);
  },

  async run(opId, params) {
    // Pass the call as a JSON file rather than interpolating data into R source.
    const json = await this._call(".tf_run_call", { op: opId, params: this._mapParams(opId, params) || {} });
    return { raw: JSON.parse(json), code: this.code(opId, params) };
  },

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

  // The corpus line of the literature operations.
  _corpusLine(key) {
    if (key === "upload") return this._read("corpus", "tf_read_corpus", this._corpusUpload || "corpus.yaml", false);
    const c = this.corpora.find((x) => x.key === key) || this.corpora[0] || { path: "corpus.yaml" };
    return this._read("corpus", "tf_read_corpus", c.path.split("/").pop(), !!c.shipped);
  },

  code(opId, p) {
    p = p || {};
    const head = "library(theoryforge)\n" +
      this._read("theory", "tf_read", this._theoryFile, this._theoryShipped, " (View source or Save in the app offers a download).");
    const cycles = `cycles = "${p.cycles || "refuse"}"`;
    switch (opId) {
      case "check":
        return `${head}\n\nreport <- tf_check(theory)\nreport$aggregate_score   # overall 0-100\nreport$gate              # pass / blocked / advisory\n\n# Visualise the rigour grid (SVG):\nwriteLines(tf_diagram(theory, "rigour"), "rigour.svg")`;
      case "validate":
        return `${head}\n\ntf_validate(theory, full = TRUE)   # structural + referential integrity; stops, listing every problem`;
      case "appraise": {
        const uploaded = p.prior === "upload";
        const pf = uploaded ? this._priorFile || "prior.theory.yaml" : String(p.prior || "prior.theory.yaml").split("/").pop();
        const prior = this._read("prior", "tf_read", pf, !uploaded && this._shipped(this.examples, p.prior));
        return `${head}\n${prior}\n\nappr <- tf_appraise_amendment(theory, prior)\nappr$verdict                      # progressive / degenerating / neutral\nstr(appr)`;
      }
      case "discriminate": {
        const uploaded = p.rival === "upload";
        const rival = uploaded ? this._read("rival", "tf_read", this._rivalFile || "rival.theory.yaml", false) + "\n" : "";
        const arg = uploaded ? "rival" : JSON.stringify(String(p.rival || ""));
        return `${head}\n${rival}\n# A refusal stops with the message the app shows.\nres <- tf_discriminate(theory, ${arg}, ${cycles})\nstr(res)`;
      }
      case "diagram": {
        const t = p.type;
        if (window.TF.DIAG_SVG.includes(t)) {
          return `${head}\n\nir <- tf_diagram(theory, "${t}")\n# '${t}' is emitted directly as SVG:\nwriteLines(ir, "${t}.svg")`;
        }
        if (t === "causal_dag") {
          return `${head}\n\nir <- tf_diagram(theory, "causal_dag")\ncat(ir)\n# This is dagitty model code, which Graphviz cannot read. The dagitty\n# package draws it:\nif (requireNamespace("dagitty", quietly = TRUE)) {\n  plot(dagitty::graphLayout(dagitty::dagitty(ir)))\n}`;
        }
        return `${head}\n\nir <- tf_diagram(theory, "${t}")   # Graphviz DOT\ncat(ir)\n# Draw it with the package's renderer, which needs DiagrammeR:\nif (requireNamespace("DiagrammeR", quietly = TRUE)) {\n  print(tf_render_diagram(theory, "${t}"))\n}`;
      }
      case "severity":
        return `${head}\n\nsev <- tf_severity(theory)        # per-prediction risk & computed severity\nstr(sev)\nwriteLines(tf_diagram(theory, "severity"), "severity.svg")`;
      case "post_severity":
        return `${head}\n\n# One record per test outcome with an estimate and an SE whose prediction\n# declares bounds. A refusal stops with the message the app shows.\nstr(tf_post_data_severity(theory))`;
      case "redundancy":
        return `${head}\n\nstr(tf_redundancy_check(theory))  # pairwise Jaccard and overlap of construct definitions`;
      case "sem":
        return `${head}\n\ncat(tf_compile_sem(theory))       # lavaan model syntax`;
      case "implications":
        return `${head}\n\n# A refusal stops with the message the app shows.\nimplied <- tf_implications(theory, ${cycles})\nvapply(implied$implications, function(s) s$statement, character(1))`;
      case "entailments":
        return `${head}\n\n# A refusal stops with the message the app shows.\nres <- tf_entailments(theory, ${cycles})\nvapply(res$claims, function(c) paste(c$source, c$id, c$verdict), character(1))\nstr(res$counts)`;
      case "equivalent":
        return `${head}\n\nstr(tf_equivalent_models(theory))`;
      case "preregister":
        return `${head}\n\ncat(tf_preregister(theory, ${cycles}))   # Markdown`;
      case "dossier":
        return `${head}\n\ncat(tf_dossier(theory, ${cycles}))       # Markdown`;
      case "simulate": {
        const init = p.start === "impulse" ? `c(${JSON.stringify(String(p.impulse || ""))} = 1)` : String(p.init);
        return `${head}\n\nsim <- tf_simulate(theory, steps = ${p.steps}, dt = ${p.dt}, k = ${p.k}, damping = ${p.damping}, init = ${init}, method = "${p.method || "exact"}")\nsim$assumed_positive              # causes and mediates, coupled at +k by assumption\nstr(sim)                          # list(states, dt, steps, k, damping, init, initial_state, method, ignored, assumed_positive, opposed, trajectory)`;
      }
      case "litmap":
        return `${head}\n${this._corpusLine(p.corpus)}\n\nlm <- tf_litmap(corpus, min_link = ${p.min_link}, method = "${p.method || "components"}", min_df = ${p.min_df === undefined ? 1 : p.min_df}, max_df = ${p.max_df === undefined ? 1 : p.max_df})\nstr(lm$themes)\ncat(tf_lit_diagram(lm, "keyword_cooccurrence", max_edges = 60))`;
      case "landscape":
        return `${head}\n${this._corpusLine(p.corpus)}\n\nland <- tf_landscape(theory, corpus, min_link = ${p.min_link}, method = "${p.method || "components"}")\nland$under_theorised_fronts\nland$redundancy_risk\ncat(tf_lit_diagram(land, "theme_landscape"))`;
      default:
        return head;
    }
  },
};

window.TF.start(RT);
