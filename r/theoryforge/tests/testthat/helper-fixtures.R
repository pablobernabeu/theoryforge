# The example theories and corpora the tests read are the ones the package
# installs, which tf_example_path() reaches. The golden outputs live in
# goldens/ beside these tests, so that R CMD check finds them and an installed
# package does not carry them. scripts/gen_golden.py writes both copies from the
# repository's fixtures/ and CI fails on any difference.

tf_fixtures_dir <- function() {
  dirname(tf_example_path("panic-network.theory.yaml"))
}

tf_fixture_path <- function(...) {
  file.path(tf_fixtures_dir(), ...)
}

tf_expected_path <- function(...) {
  testthat::test_path("goldens", ...)
}

# Read a file as raw bytes -> string, exactly as the golden comparison requires.
# The goldens are UTF-8, and the string is marked so. Unmarked, it would be read
# in the session's charset, and in a Latin-9 session, as on CRAN's Debian clang
# flavour, it would no longer equal the package's UTF-8 output.
tf_read_golden <- function(f) {
  text <- readChar(f, file.info(f)$size, useBytes = TRUE)
  Encoding(text) <- "UTF-8"
  text
}
