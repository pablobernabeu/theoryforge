# Locate the directory holding the shared parity fixtures. The same golden
# files are shipped inside the package under inst/fixtures/ (so they are present
# when R CMD check runs the tests against the built tarball) and also live at
# the repo root under fixtures/ (used by the Python twin and by in-source runs).
# Prefer the installed copy via system.file(); fall back to searching upward for
# the repo-level fixtures/ directory. Both copies are byte-identical.

tf_fixtures_dir <- function() {
  installed <- system.file("fixtures", package = "theoryforge")
  if (nzchar(installed) && dir.exists(file.path(installed, "expected"))) {
    return(installed)
  }
  candidates <- c(
    Sys.getenv("THEORYFORGE_REPO_ROOT", unset = ""),
    testthat::test_path("..", ".."),     # r/theoryforge/
    getwd()
  )
  candidates <- candidates[nzchar(candidates)]
  for (start in candidates) {
    dir <- normalizePath(start, winslash = "/", mustWork = FALSE)
    for (i in 1:8) {
      if (dir.exists(file.path(dir, "fixtures", "expected"))) {
        return(file.path(dir, "fixtures"))
      }
      parent <- dirname(dir)
      if (identical(parent, dir)) break
      dir <- parent
    }
  }
  stop("could not locate fixtures/ directory (installed or repo-level)")
}

tf_fixture_path <- function(...) {
  file.path(tf_fixtures_dir(), ...)
}

tf_expected_path <- function(...) {
  file.path(tf_fixtures_dir(), "expected", ...)
}

# Read a file as raw bytes -> string, exactly as the golden comparison requires.
tf_read_golden <- function(f) {
  readChar(f, file.info(f)$size, useBytes = TRUE)
}
