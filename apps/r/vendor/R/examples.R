#' Access to the example theories shipped inside the package.
#'
#' Thin wrappers over \code{system.file()}, so that the two twins name the
#' examples the same way: the Python package exposes \code{example_path()} and
#' \code{example_names()} over the same files. The copies under
#' \code{inst/fixtures/} are written by \code{scripts/gen_golden.py} and gated in
#' CI, so they cannot drift from the originals at the repository root.
#' @name examples
#' @keywords internal
NULL

#' Names of the packaged example files
#'
#' The bundled set is four example theories and one literature corpus,
#' \code{panic-corpus.yaml}, which [tf_read_corpus()] reads.
#'
#' @return A sorted character vector of the \code{.yaml} file names. The Python
#'   twin's \code{example_names()} applies the same extension filter, so the two
#'   list the same set.
#' @examples
#' tf_example_names()
#' @export
tf_example_names <- function() {
  dir <- system.file("fixtures", package = "theoryforge")
  if (!nzchar(dir)) {
    stop("could not locate the packaged example theories", call. = FALSE)
  }
  sort(list.files(dir, pattern = "\\.yaml$"))
}

#' Path to a packaged example file
#'
#' @param name File name, e.g. \code{"panic-network.theory.yaml"}. See
#'   [tf_example_names()].
#' @return The path to the installed file.
#' @examples
#' tf_read(tf_example_path("panic-network.theory.yaml"))$id
#' @export
tf_example_path <- function(name) {
  path <- system.file("fixtures", name, package = "theoryforge")
  if (!nzchar(path)) {
    stop("no packaged example named '", name, "'; available: ",
         paste(tf_example_names(), collapse = ", "), call. = FALSE)
  }
  path
}
