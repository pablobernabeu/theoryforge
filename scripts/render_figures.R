#!/usr/bin/env Rscript
# Render the Graphviz diagram artifacts (fixtures/expected/*.dot) to PNG for the
# manuscript, using DiagrammeR's bundled viz.js engine (no system Graphviz needed)
# plus webshot2. The dagitty *.dag files are left as code listings.
#
# Usage: Rscript scripts/render_figures.R <repo_root>
suppressWarnings(suppressMessages({
  library(DiagrammeR); library(webshot2)
  args <- commandArgs(trailingOnly = TRUE)
  root <- if (length(args) >= 1) args[[1]] else "."
  expected <- file.path(root, "fixtures", "expected")
  outdir <- file.path(root, "manuscript", "figures")
  if (!dir.exists(outdir)) dir.create(outdir, recursive = TRUE)

  dots <- list.files(expected, pattern = "\\.dot$", full.names = TRUE)
  for (f in dots) {
    dot <- readChar(f, file.info(f)$size, useBytes = TRUE)
    Encoding(dot) <- "UTF-8"
    name <- sub("\\.dot$", "", basename(f))
    html <- file.path(tempdir(), paste0(name, ".html"))
    png <- file.path(outdir, paste0(name, ".png"))
    g <- grViz(dot)
    htmlwidgets::saveWidget(g, html, selfcontained = FALSE)
    webshot2::webshot(html, png, vwidth = 900, vheight = 560, delay = 0.5, zoom = 2)
    cat("rendered", basename(png), "->", if (file.exists(png)) file.info(png)$size else 0, "bytes\n")
  }
}))
