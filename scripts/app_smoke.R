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
# It calls what the app calls: .tf_lineage_call() over every example at
# start-up, an uploaded prior, rival and corpus, then .tf_load() and every
# operation in scripts/app_smoke_cases.json for each example, each operation
# passed to .tf_run_call() as a JSON call file. As in the UI, the appraisal's
# prior is the example the theory declares as its parent when exactly one
# does, and otherwise an example uploaded as a prior through .tf_load_prior().
# The rival is the first alternative that states propositions, and otherwise a
# theory uploaded through .tf_load_rival(). An impulse starts in the first
# construct, and a corpus named by its key is read from its file. Each example
# must have a score from .tf_score_call() and a content hash from
# .tf_hash_call(), and the editor's call, .tf_edit_call(), must read the
# theory back from the JSON the package's writer gives with the same score and
# content hash. Where the package has
# tf_read_dagitty(), .tf_import_dagitty_call() must make the theory a small
# model states. Last, an invalid theory must load with {"ok": false,
# "message": ...} and give the same from validate. Every result must be a
# JSON object.
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
  uploaded <- "upload"

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
      corpora = stats::setNames(lapply(manifest$corpora, function(c) file.path(tree, c$path)),
                                vapply(manifest$corpora, function(c) c$key, "")))
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
    # An uploaded prior, rival or corpus is written to a file of its own, as
    # the app writes it.
    for (kind in c("prior", "rival")) {
      upload <- file.path(plan$tree, paste0(kind, ".yaml"))
      file.copy(examples[[1]]$path, upload)
      fn <- if (kind == "prior") .tf_load_prior else .tf_load_rival
      up <- call_json(paste("upload a", kind), function() fn(upload))
      if (!is.null(up) && (!is.list(up) || is.null(names(up)))) fail(paste("upload a", kind), "no record")
    }
    corpora <- plan$corpora
    if (length(corpora)) {
      upload <- file.path(plan$tree, "corpus.yaml")
      file.copy(corpora[[1]], upload)
      up <- call_json("upload a corpus", function() .tf_load_corpus(upload, uploaded))
      if (!is.null(up) && !(is.list(up) && isTRUE(up$n_records > 0))) fail("upload a corpus", "no records read")
    }

    for (i in seq_along(examples)) {
      ex <- examples[[i]]
      summary <- call_json(paste0(ex$name, ": load"), function() .tf_load(ex$path))
      if (!is.list(summary)) next
      # The score and the hash are calls of their own, made after the load.
      score <- call_json(paste0(ex$name, ": score"), function() .tf_score_call())
      if (!is.null(score) && (is.null(score$score) || is.null(score$gate))) {
        fail(paste0(ex$name, ": score"), paste("no score:", as_json(score)))
      }
      digest <- call_json(paste0(ex$name, ": content hash"), function() .tf_hash_call())
      if (!is.null(digest) && is.null(digest$hash)) {
        fail(paste0(ex$name, ": content hash"), paste("no hash:", as_json(digest)))
      }
      parents <- paths[vapply(seq_along(examples), function(j) {
        j != i && is_declared_parent(summary, lineage[[j]])
      }, logical(1))]
      prior <- if (length(parents) == 1L) parents else uploaded
      rivals <- unlist(lapply(summary$alternatives, function(a) if (isTRUE(a$propositions > 0)) a$id))
      constructs <- unlist(lapply(summary$constructs, function(c) c$id))
      for (cs in cases) {
        params <- cs$params
        if (identical(cs$op, "appraise")) params$prior <- prior
        if (identical(cs$op, "discriminate")) params$rival <- if (length(rivals)) rivals[[1]] else uploaded
        if (identical(params$start, "impulse")) params$impulse <- constructs[[1]]
        if (!is.null(params$corpus) && !identical(params$corpus, uploaded)) params$corpus <- corpora[[params$corpus]]
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
      # The editor reads the theory back from the JSON the writer gives.
      label <- paste0(ex$name, ": edit")
      written <- file.path(plan$tree, "edit.json")
      ok <- tryCatch({ writeBin(charToRaw(enc2utf8(.tf_write_text("json"))), written); TRUE },
                     error = function(e) { fail(label, paste("write_text:", conditionMessage(e))); FALSE })
      if (!ok) next
      edited <- call_json(label, function() {
        write_call(as_json(list(path = written, formats = c("yaml", "json"))))
        .tf_edit_call()
      })
      if (is.list(edited)) {
        same <- identical(call_json(label, function() .tf_hash_call()), digest) &&
          identical(call_json(label, function() .tf_score_call()), score) &&
          identical(edited$validation, summary$validation)
        if (!same) {
          fail(label, "the theory read back differs from the theory loaded")
        }
        if (!setequal(names(edited$texts), c("yaml", "json"))) fail(label, "the writer's texts are missing")
      }
    }

    # The editor's DAGitty import, through the package's reader where this
    # version of the package has one.
    if (exists("tf_read_dagitty", mode = "function")) {
      model <- file.path(plan$tree, "dagitty.txt")
      writeBin(charToRaw("dag {\n  a -> b -> c\n  a <-> c [latent]\n}\n"), model)
      res <- call_json("import a DAGitty model", function() {
        write_call(as_json(list(path = model, id = "dag-demo", relation = "increases", formats = I("yaml"))))
        .tf_import_dagitty_call()
      })
      if (!is.null(res) && !(identical(res$id, "dag-demo") && identical(res$counts$constructs, 3L) &&
                             identical(res$counts$propositions, 3L) && !is.null(res$texts$yaml))) {
        fail("import a DAGitty model", "not the theory of three constructs and three propositions the model states")
      }
    } else {
      cat("This version of the package has no tf_read_dagitty(), so the DAGitty import was not run\n")
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
    cat(sprintf(paste0("%d examples x %d operations, with start-up, the uploads, the editor's call ",
                       "and an invalid theory: %d calls, %d failures\n"),
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
