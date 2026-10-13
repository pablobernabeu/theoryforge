# Two test files evaluate chunks of the pkgdown articles, which sit in
# vignettes/articles. .Rbuildignore leaves that folder out of the built package,
# so each of those tests is skipped wherever its article is absent.

# The lines of one knitr chunk, found by its label.
chunk_code <- function(path, label) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  start <- grep(sprintf("^```\\{r %s[,}]", label), lines)
  if (length(start) != 1L) {
    stop(sprintf("expected one `%s` chunk in %s, found %d",
                 label, basename(path), length(start)), call. = FALSE)
  }
  fences <- grep("^```\\s*$", lines)
  end <- fences[fences > start][1L]
  lines[(start + 1L):(end - 1L)]
}
