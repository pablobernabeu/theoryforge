#' Access to the example theories shipped inside the package.
#'
#' Functions that find the example files installed with the package, through
#' \code{system.file()}. The Python package offers the same files through
#' \code{example_path()} and \code{example_names()}.
#' @name examples
#' @noRd
#' @keywords internal
NULL

#' Names of the packaged example files
#'
#' The bundled set is four example theories and two literature corpora, which
#' [tf_read_corpus()] reads. \code{panic-corpus.yaml} is a small corpus designed
#' to fall into four themes, and \code{openalex-panic-2026.corpus.yaml} holds
#' 150 works fetched from OpenAlex and saved.
#'
#' @return A sorted character vector of the \code{.yaml} file names. The Python
#'   package's \code{example_names()} lists the same files.
#' @examples
#' tf_example_names()
#' @export
tf_example_names <- function() {
  dir <- system.file("extdata", package = "theoryforge")
  if (!nzchar(dir)) {
    stop("could not locate the packaged example theories", call. = FALSE)
  }
  sort(list.files(dir, pattern = "\\.yaml$"))
}

#' Path to a packaged example file
#'
#' @param name File name, for example \code{"panic-network.theory.yaml"}. See
#'   [tf_example_names()].
#' @return The path to the installed file. A \code{name} that matches no
#'   installed file stops with an error that lists the names
#'   [tf_example_names()] returns.
#' @examples
#' tf_read(tf_example_path("panic-network.theory.yaml"))$id
#' @export
tf_example_path <- function(name) {
  # Only a listed name is looked up, so that no other file or folder of the
  # installed package can be reached through this function.
  listed <- is.character(name) && length(name) == 1L && name %in% tf_example_names()
  path <- if (listed) system.file("extdata", name, package = "theoryforge") else ""
  if (!nzchar(path)) {
    stop("no packaged example named '", name, "'; available: ",
         paste(tf_example_names(), collapse = ", "), call. = FALSE)
  }
  path
}
