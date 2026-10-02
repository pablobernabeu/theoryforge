#!/usr/bin/env Rscript
# Emit the R package's deterministic-core outputs as raw LF bytes, so the
# Python-side parity checker can diff them against Python's.
#
# Usage: Rscript scripts/parity_emit.R <mode> <src_dir> <out_dir> [<pkg_dir>]
#
#   golden    the golden set: the per-theory artefacts of every
#             <src_dir>/*.theory.yaml, the amendment appraisal, the DOI screen
#             and the literature artefacts (src_dir is fixtures/)
#   theories  the per-theory artefacts only, for every <src_dir>/*.theory.yaml
#             (parity_check.py runs it on apps/examples/)
#   edge      one outcome record per <src_dir>/*.theory.yaml|json, mirroring
#             edge_outcome() in scripts/gen_golden.py (src_dir is fixtures/edge/)
#   roundtrip tf_read() then tf_write() for every <src_dir>/*.theory.yaml|json,
#             each written to <out_dir> under its own name and format
#             (parity_check.py runs it on the files the Python twin wrote)
suppressWarnings(suppressMessages({
  usage <- "usage: Rscript scripts/parity_emit.R <golden|theories|edge|roundtrip> <src_dir> <out_dir> [<pkg_dir>]"
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 3L || !(args[[1]] %in% c("golden", "theories", "edge", "roundtrip"))) {
    stop(usage, call. = FALSE)
  }
  mode <- args[[1]]
  src_dir <- args[[2]]
  out_dir <- args[[3]]
  pkg_dir <- if (length(args) >= 4) args[[4]] else "r/theoryforge"

  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

  # The source tree wins over an installed copy whenever there is one to load.
  #
  # This used to be the other way round, and it made the gate test the wrong
  # thing. Any machine with theoryforge installed had its parity checked against
  # that copy rather than against the working tree, silently: the two share a
  # version number long after their contents diverge, so nothing announced it.
  # Locally that showed up as sixteen false failures for fields the working tree
  # had gained and the installed copy lacked. The dangerous direction is the
  # other one: an installed copy that happens to satisfy the comparison while
  # the tree it is standing in for does not, which is a green parity check over
  # code nobody ran.
  #
  # CI was right only by accident of ordering: it runs R CMD INSTALL on this very
  # directory immediately beforehand, so its installed copy was the working tree.
  # It no longer has to be, and the R distribution itself is covered by six
  # R CMD check cells elsewhere in this workflow; what this gate is for is
  # whether the two languages agree on the code in the repository.
  loaded_from <- NULL
  if (dir.exists(pkg_dir) && requireNamespace("pkgload", quietly = TRUE)) {
    pkgload::load_all(pkg_dir, quiet = TRUE)
    loaded_from <- paste0("source: ", pkg_dir)
  } else if (requireNamespace("theoryforge", quietly = TRUE)) {
    library(theoryforge)
    loaded_from <- paste0("installed package ",
                          as.character(utils::packageVersion("theoryforge")))
  } else {
    stop("theoryforge is neither loadable from ", pkg_dir, " nor installed.",
         call. = FALSE)
  }

  write_raw <- function(s, path) writeBin(charToRaw(enc2utf8(s)), path)

  diagram_ext <- c(
    nomological_net = "dot", provenance = "dot", causal_dag = "dag",
    development_roadmap = "dot", pipeline = "dot",
    context = "dot", workflow = "dot", venn = "svg",
    rigour = "svg", severity = "svg"
  )

  # The per-theory artefact set, as emit_theory() in scripts/gen_golden.py.
  emit_theory <- function(t, out_dir) {
    id <- t$id
    write_raw(paste0(tf_report(t, format = "json"), "\n"),
              file.path(out_dir, paste0(id, ".report.json")))
    for (type in names(diagram_ext)) {
      write_raw(tf_diagram(t, type = type),
                file.path(out_dir, paste0(id, ".", type, ".", diagram_ext[[type]])))
    }
    sev <- tf_severity(t)
    write_raw(paste0(jsonlite::toJSON(sev, dataframe = "rows", auto_unbox = TRUE, pretty = TRUE), "\n"),
              file.path(out_dir, paste0(id, ".severity.json")))
    write_raw(tf_preregister(t), file.path(out_dir, paste0(id, ".prereg.md")))
    write_raw(tf_compile_sem(t), file.path(out_dir, paste0(id, ".sem.lavaan")))
    write_raw(tf_dossier(t), file.path(out_dir, paste0(id, ".dossier.md")))
    write_raw(paste0(jsonlite::toJSON(tf_simulate(t), auto_unbox = TRUE, digits = 10, pretty = TRUE), "\n"),
              file.path(out_dir, paste0(id, ".simulate.json")))
  }

  # The message of a condition as an edge outcome records it: a leading
  # "(<path>) " is dropped, up to the first ") ", because the path differs
  # between machines and between the twins (error_text() in gen_golden.py).
  error_text <- function(e) sub("^\\(.*?\\) ", "", conditionMessage(e), perl = TRUE)
  attempt <- function(expr) {
    tryCatch(expr, error = function(e) list(error = error_text(e)))
  }
  check_summary <- function(rep) {
    list(
      aggregate_score = rep$aggregate_score,
      gate = rep$gate,
      n_blockers_failed = rep$n_blockers_failed,
      items = lapply(rep$items, function(it) {
        list(id = it$id, status = it$status, score = it$score)
      })
    )
  }
  # One record per edge case, keys in call order, as edge_outcome() in
  # scripts/gen_golden.py. A failed read leaves the record holding read alone.
  edge_outcome <- function(path) {
    t <- tryCatch(tf_read(path), error = function(e) e)
    if (inherits(t, "error")) return(list(read = list(error = error_text(t))))
    list(
      read = "ok",
      validate = attempt(isTRUE(tf_validate(t))),
      validate_full = attempt(isTRUE(tf_validate(t, full = TRUE))),
      check = attempt(check_summary(tf_check(t))),
      severity = attempt(tf_severity(t)),
      implications = attempt(tf_implications(t)),
      compile_sem = attempt(tf_compile_sem(t)),
      simulate = attempt(tf_simulate(t, steps = 3)),
      preregister = attempt(tf_preregister(t))
    )
  }

  theory_files <- function(dir) {
    sort(list.files(dir, pattern = "\\.theory\\.yaml$", full.names = TRUE))
  }

  if (mode == "edge") {
    inputs <- sort(list.files(src_dir, pattern = "\\.theory\\.(yaml|json)$", full.names = TRUE))
    for (path in inputs) {
      name <- sub("\\.theory\\.(yaml|json)$", "", basename(path))
      rec <- edge_outcome(path)
      write_raw(paste0(jsonlite::toJSON(rec, auto_unbox = TRUE, dataframe = "rows",
                                        null = "null", na = "null", digits = NA,
                                        pretty = TRUE), "\n"),
                file.path(out_dir, paste0(name, ".outcome.json")))
    }
    cat(sprintf("emitted R edge outcomes for %d theory file(s) to %s [R engine from %s]\n",
                length(inputs), out_dir, loaded_from))
  } else if (mode == "roundtrip") {
    inputs <- sort(list.files(src_dir, pattern = "\\.theory\\.(yaml|json)$", full.names = TRUE))
    for (path in inputs) tf_write(tf_read(path), file.path(out_dir, basename(path)))
    cat(sprintf("rewrote %d theory file(s) with tf_read() and tf_write() to %s [R engine from %s]\n",
                length(inputs), out_dir, loaded_from))
  } else {
    fixtures <- theory_files(src_dir)
    for (fx in fixtures) emit_theory(tf_read(fx), out_dir)

    if (mode == "golden") {
      fixtures_dir <- src_dir
      # amendment appraisal for the v2-vs-v1 pair
      v1 <- tf_read(file.path(fixtures_dir, "panic-network.theory.yaml"))
      v2 <- tf_read(file.path(fixtures_dir, "panic-network-2026-v2.theory.yaml"))
      ap <- tf_appraise_amendment(v2, v1)
      write_raw(paste0(jsonlite::toJSON(ap, auto_unbox = TRUE, pretty = TRUE), "\n"),
                file.path(out_dir, "panic-network-2026-v2.appraisal.json"))

      # new_evidence_dois (P2): candidate DOIs against the panic-network theory's
      # existing evidence and alternatives (two already cited, two new, one duplicate)
      new_evidence_candidates <- c(
        "10.1016/j.brat.2015.10.002",
        "https://doi.org/10.1016/0005-7967(86)90011-2",
        "10.1176/AJP.146.2.148",
        "10.1037/0033-2909.99.1.20",
        "10.1037/0033-2909.99.1.20",
        "10.1016/j.cpr.2011.09.005",
        # Spellings of the cited DOIs that the normaliser of API_SPEC.md
        # section 18 recognises, so the output is the same as without them.
        "doi: 10.1016/j.brat.2015.10.002",
        "DOI 10.1016/j.brat.2015.10.002",
        "doi.org/10.1016/j.brat.2015.10.002",
        "dx.doi.org/10.1016/j.brat.2015.10.002",
        "https://www.doi.org/10.1016/j.brat.2015.10.002",
        "info:doi/10.1016/j.brat.2015.10.002",
        "urn:doi:10.1016/j.brat.2015.10.002",
        "https://doi.org/10.1016/0005-7967%2886%2990011-2",
        "10.1016/j.brat.2015.10.002.",
        "10.1016/J.BRAT.2015.10.002\u00a0"
      )
      new_dois <- tf_new_evidence_dois(v1, new_evidence_candidates)
      write_raw(paste0(jsonlite::toJSON(new_dois, auto_unbox = FALSE, pretty = TRUE), "\n"),
                file.path(out_dir, "panic-network-2026.new_evidence_dois.json"))

      # bibliometric layer (P2)
      corpus <- tf_read_corpus(file.path(fixtures_dir, "panic-corpus.yaml"))
      cid <- corpus$id
      lm <- tf_litmap(corpus)
      write_raw(paste0(jsonlite::toJSON(lm, auto_unbox = TRUE, pretty = TRUE), "\n"),
                file.path(out_dir, paste0(cid, ".litmap.json")))
      write_raw(tf_lit_diagram(lm, "keyword_cooccurrence"),
                file.path(out_dir, paste0(cid, ".keyword_cooccurrence.dot")))
      write_raw(tf_lit_diagram(lm, "co_citation"),
                file.path(out_dir, paste0(cid, ".co_citation.dot")))
      panic <- tf_read(file.path(fixtures_dir, "panic-network.theory.yaml"))
      ls <- tf_landscape(panic, corpus)
      write_raw(paste0(jsonlite::toJSON(ls, auto_unbox = TRUE, pretty = TRUE), "\n"),
                file.path(out_dir, paste0(cid, ".landscape.json")))
      write_raw(tf_lit_diagram(ls, "theme_landscape"),
                file.path(out_dir, paste0(cid, ".theme_landscape.dot")))
    }

    # Name what was loaded. A parity result means nothing without it: the same
    # command over the same fixtures reports on the working tree or on some
    # installed copy depending only on what happens to be on the library path.
    cat(sprintf("emitted R outputs (%s) for %d theory file(s) to %s [R engine from %s]\n",
                mode, length(fixtures), out_dir, loaded_from))
  }
}))
