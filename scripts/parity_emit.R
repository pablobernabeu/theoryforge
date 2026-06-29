#!/usr/bin/env Rscript
# Emit the R package's deterministic-core outputs as raw LF bytes, so the
# Python-side parity checker can diff them against the goldens.
#
# Usage: Rscript scripts/parity_emit.R <fixtures_dir> <out_dir> [<pkg_dir>]
suppressWarnings(suppressMessages({
  args <- commandArgs(trailingOnly = TRUE)
  fixtures_dir <- args[[1]]
  out_dir <- args[[2]]
  pkg_dir <- if (length(args) >= 3) args[[3]] else "r/theoryforge"

  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  if (requireNamespace("theoryforge", quietly = TRUE)) {
    library(theoryforge)
  } else {
    devtools::load_all(pkg_dir, quiet = TRUE)
  }

  write_raw <- function(s, path) writeBin(charToRaw(enc2utf8(s)), path)

  diagram_ext <- c(
    nomological_net = "dot", provenance = "dot", causal_dag = "dag",
    development_roadmap = "dot", pipeline = "dot",
    context = "dot", workflow = "dot", venn = "svg",
    rigour = "svg", severity = "svg"
  )

  fixtures <- sort(list.files(fixtures_dir, pattern = "\\.theory\\.yaml$", full.names = TRUE))
  for (fx in fixtures) {
    t <- tf_read(fx)
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

  # amendment appraisal for the v2-vs-v1 pair
  v1 <- tf_read(file.path(fixtures_dir, "panic-network.theory.yaml"))
  v2 <- tf_read(file.path(fixtures_dir, "panic-network-2026-v2.theory.yaml"))
  ap <- tf_appraise_amendment(v2, v1)
  write_raw(paste0(jsonlite::toJSON(ap, auto_unbox = TRUE, pretty = TRUE), "\n"),
            file.path(out_dir, "panic-network-2026-v2.appraisal.json"))

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

  cat(sprintf("emitted R outputs for %d fixture(s) to %s\n", length(fixtures), out_dir))
}))
