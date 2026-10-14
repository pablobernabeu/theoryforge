#!/usr/bin/env Rscript
# Run the R app's glue under R on exactly the files the browser receives.
#
# The webR app (apps/r/r-runtime.js) installs jsonlite and yaml, writes the
# files its manifest lists under /tf, writes its glue code BOOT_R to
# /tf/boot.R and sources it into the global environment. This script does the
# same in a temporary directory. It copies the manifest's files there, writes
# BOOT_R beside them with /tf/ replaced by that directory and sources it in a
# fresh R whose library holds copies of jsonlite and yaml, and nothing else.
# theoryforge is not installed there, so system.file() cannot find a resource
# that BOOT_R fails to pre-seed, just as in the browser.
#
# It calls what the app calls: .tf_lineage_call() over every example and
# .tf_load_corpus() at start-up, then .tf_load() and every operation in
# scripts/app_smoke_cases.json for each example, each operation passed to
# .tf_run_call() as a JSON call file. As in the UI, the appraisal's prior is
# the example the theory declares as its parent when exactly one does.
# Otherwise it is an example uploaded as a prior through .tf_load_prior().
# Last, an invalid theory must load with {"ok": false, "message": ...} and give
# the same from validate. Every result must be a JSON object.
#
# Usage: Rscript scripts/app_smoke.R [<apps_dir>]
#
# apps_dir defaults to apps/ and must hold r/r-runtime.js and the r/vendor/
# tree that `node apps/build.mjs` writes (docs.yml passes the staged
# site/apps). Exit 0 when every call succeeds, 1 when one fails and 2 when the
# tree, jsonlite or yaml is missing. scripts/app_smoke.py does the same for the
# Pyodide app.
#
# Everything below runs inside local(), so the global environment holds only
# what BOOT_R defines there.
local({
  # Readable YAML with a misspelt top-level field, which full validation refuses.
  invalid_theory <- "schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\npredicitions: []\n"
  uploaded_prior <- "upload"

  file_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)[1]
  self <- normalizePath(gsub("~+~", " ", sub("^--file=", "", file_arg), fixed = TRUE), winslash = "/")
  root <- dirname(dirname(self))
  args <- commandArgs(trailingOnly = TRUE)

  # isDeclaredParent() of apps/shared/app-core.js.
  is_declared_parent <- function(theory, cand) {
    one_string <- function(x) is.character(x) && length(x) == 1L
    pid <- theory$version$parent_id
    one_string(pid) && nzchar(pid) && identical(cand$version$id, pid) &&
      one_string(theory$id) && one_string(cand$id) && nzchar(cand$id) &&
      startsWith(theory$id, cand$id)
  }

  # Copy the files the app fetches, BOOT_R, jsonlite and yaml into `work`, and
  # return the path of the plan the child reads, or NULL.
  prepare <- function(apps, work) {
    runtime <- file.path(apps, "r", "r-runtime.js")
    vendor <- file.path(apps, "r", "vendor")
    if (!file.exists(runtime) || !file.exists(file.path(vendor, "manifest.json"))) {
      message(apps, " holds no r/r-runtime.js and r/vendor/manifest.json; run `node apps/build.mjs` first")
      return(NULL)
    }
    pkgs <- c("jsonlite", "yaml")
    found <- find.package(pkgs, quiet = TRUE)
    if (length(found) != length(pkgs)) {
      message("jsonlite and yaml must both be installed for the app's glue to run")
      return(NULL)
    }
    js <- paste(readLines(runtime, encoding = "UTF-8", warn = FALSE), collapse = "\n")
    m <- regmatches(js, regexpr("(?s)const BOOT_R = String\\.raw`(.*?)`;", js, perl = TRUE))
    if (length(m) != 1L) {
      message("no BOOT_R in ", runtime)
      return(NULL)
    }
    boot <- sub("`;$", "", sub("(?s)^const BOOT_R = String\\.raw`", "", m, perl = TRUE))
    manifest <- jsonlite::fromJSON(file.path(vendor, "manifest.json"), simplifyVector = FALSE)
    tree <- file.path(work, "tf")
    # The app makes these four folders and writes every file into one of them.
    for (d in c("", "R", "schema", "fixtures")) dir.create(file.path(tree, d), showWarnings = FALSE)
    put <- function(rel, dest) {
      if (!isTRUE(file.copy(file.path(vendor, rel), dest))) stop("could not write ", dest, call. = FALSE)
    }
    for (f in manifest$rFiles) put(f, file.path(tree, f))
    put(manifest$schema$theory, file.path(tree, "schema", "theory.schema.json"))
    put(manifest$schema$checklist, file.path(tree, "schema", "rigor_checklist.yaml"))
    put(manifest$schema$fold, file.path(tree, "schema", "fold.json"))
    for (e in c(manifest$examples, manifest$corpora)) put(e$path, file.path(tree, e$path))
    writeLines(gsub("\"/tf/", paste0("\"", tree, "/"), boot, fixed = TRUE),
               file.path(tree, "boot.R"), useBytes = TRUE)
    lib <- file.path(work, "lib")
    dir.create(lib)
    file.copy(found, lib, recursive = TRUE)
    plan <- list(
      tree = tree, lib = lib, cases = file.path(root, "scripts", "app_smoke_cases.json"),
      examples = lapply(manifest$examples, function(e) list(name = e$name, path = file.path(tree, e$path))),
      corpus = if (length(manifest$corpora)) file.path(tree, manifest$corpora[[1]]$path) else "")
    path <- file.path(work, "plan.json")
    jsonlite::write_json(plan, path, auto_unbox = TRUE)
    path
  }

  # Source BOOT_R from the copied tree and call it as the app does.
  run_child <- function(plan_path) {
    plan <- jsonlite::fromJSON(plan_path, simplifyVector = FALSE)
    installed <- system.file(package = "theoryforge")
    if (nzchar(installed)) {
      cat("FAIL theoryforge is installed at", installed, "and could stand in for the copied tree\n")
      return(1L)
    }
    booted <- tryCatch({
      source(file.path(plan$tree, "boot.R"), local = globalenv())
      TRUE
    }, error = function(e) {
      cat("FAIL boot: ", conditionMessage(e), "\n", sep = "")
      FALSE
    })
    if (!booted) return(1L)
    cat(R.version.string, ", jsonlite ", format(utils::packageVersion("jsonlite")), " and yaml ",
        format(utils::packageVersion("yaml")), " from ", plan$lib, "\n", sep = "")

    failures <- character()
    calls <- 0L
    fail <- function(label, why) {
      failures <<- c(failures, paste0(label, ": ", why))
      invisible(NULL)
    }
    # The app reads every result as JSON text. A call that fails gives NULL.
    call_json <- function(label, f) {
      calls <<- calls + 1L
      out <- tryCatch(f(), error = function(e) structure(conditionMessage(e), class = "smoke_error"))
      if (inherits(out, "smoke_error")) return(fail(label, unclass(out)))
      if (!is.character(out) || length(out) != 1L || !isTRUE(jsonlite::validate(out))) {
        return(fail(label, "not a JSON string"))
      }
      jsonlite::fromJSON(out, simplifyVector = FALSE)
    }
    # A call reaches the glue as a JSON file, as the app writes it.
    write_call <- function(json) {
      writeBin(charToRaw(enc2utf8(json)), file.path(plan$tree, "call.json"))
    }
    as_json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA))

    examples <- plan$examples
    cases <- jsonlite::fromJSON(plan$cases, simplifyVector = FALSE)$cases
    paths <- vapply(examples, function(e) e$path, "")
    lineage <- call_json("start-up: lineage", function() {
      write_call(as.character(jsonlite::toJSON(list(paths = paths))))
      .tf_lineage_call()
    })
    records <- is.list(lineage) && length(lineage) == length(examples) &&
      all(vapply(lineage, function(x) is.list(x) && !is.null(names(x)), logical(1)))
    if (!records) {
      if (!is.null(lineage)) fail("start-up: lineage", "not one lineage record per example")
      lineage <- vector("list", length(examples))
    }
    if (nzchar(plan$corpus)) {
      calls <- calls + 1L
      tryCatch(.tf_load_corpus(plan$corpus),
               error = function(e) fail("start-up: load_corpus", conditionMessage(e)))
    }
    # An uploaded prior is written to a file of its own, as the app writes it.
    upload <- file.path(plan$tree, "prior.yaml")
    file.copy(examples[[1]]$path, upload)
    up <- call_json("upload a prior", function() .tf_load_prior(upload))
    if (!is.null(up) && (!is.list(up) || is.null(names(up)))) fail("upload a prior", "no lineage record")

    for (i in seq_along(examples)) {
      ex <- examples[[i]]
      summary <- call_json(paste0(ex$name, ": load"), function() .tf_load(ex$path))
      if (!is.list(summary)) next
      parents <- paths[vapply(seq_along(examples), function(j) {
        j != i && is_declared_parent(summary, lineage[[j]])
      }, logical(1))]
      prior <- if (length(parents) == 1L) parents else uploaded_prior
      for (cs in cases) {
        params <- cs$params
        if (identical(cs$op, "appraise")) params$prior <- prior
        params_json <- if (length(params)) as_json(params) else "{}"
        label <- paste0(ex$name, ": ", cs$op, " ", params_json)
        res <- call_json(label, function() {
          write_call(sprintf("{\"op\":%s,\"params\":%s}", as_json(cs$op), params_json))
          .tf_run_call()
        })
        if (!is.null(res) && (!is.list(res) || is.null(names(res)))) {
          fail(label, "the result is not a JSON object")
        }
      }
    }

    invalid <- file.path(plan$tree, "input.yaml")
    writeBin(charToRaw(invalid_theory), invalid)
    summary <- call_json("invalid theory: load", function() .tf_load(invalid))
    v <- if (is.list(summary)) summary$validation else NULL
    if (!(identical(v$ok, FALSE) && is.character(v$message) &&
          startsWith(v$message, "invalid theory object: "))) {
      fail("invalid theory: load", "validation is not ok false with a message")
    }
    res <- call_json("invalid theory: validate", function() {
      write_call("{\"op\":\"validate\",\"params\":{}}")
      .tf_run_call()
    })
    if (!identical(res, v)) fail("invalid theory: validate", "differs from the load's validation")

    for (f in failures) cat("FAIL ", f, "\n", sep = "")
    cat(sprintf(paste0("%d examples x %d operations, with start-up, an uploaded prior and an ",
                       "invalid theory: %d calls, %d failures\n"),
                length(examples), length(cases), calls, length(failures)))
    if (length(failures)) 1L else 0L
  }

  run_parent <- function(apps) {
    work <- tempfile("tf-app-smoke-")
    dir.create(work)
    work <- normalizePath(work, winslash = "/")
    on.exit(unlink(work, recursive = TRUE), add = TRUE)
    plan <- prepare(apps, work)
    if (is.null(plan)) return(2L)
    # The child's library is the copied jsonlite and yaml, then R's own base
    # and recommended packages. --vanilla skips the site and user profiles
    # and Renviron files, and the variables set here leave out the user and
    # site libraries, wherever theoryforge may be installed.
    vars <- c("R_LIBS", "R_LIBS_USER", "R_LIBS_SITE")
    old <- Sys.getenv(vars, unset = NA)
    on.exit(for (v in vars) {
      if (is.na(old[[v]])) Sys.unsetenv(v) else do.call(Sys.setenv, stats::setNames(list(old[[v]]), v))
    }, add = TRUE)
    none <- file.path(work, "none")
    Sys.setenv(R_LIBS = file.path(work, "lib"), R_LIBS_USER = none, R_LIBS_SITE = none)
    rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
    status <- system2(rscript, c("--vanilla", shQuote(self), "--child", shQuote(plan)))
    as.integer(status)
  }

  status <- if (length(args) == 2L && args[[1]] == "--child") {
    run_child(args[[2]])
  } else {
    run_parent(if (length(args)) normalizePath(args[[1]], winslash = "/", mustWork = FALSE) else file.path(root, "apps"))
  }
  quit(save = "no", status = status)
})
