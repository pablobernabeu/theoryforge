#' Access to the vendored rigour checklist.
#'
#' These read the files vendored under \code{inst/schema/} at runtime via
#' \code{system.file()}. Results are cached in a package-private environment so
#' repeated calls are cheap.
#'
#' @keywords internal
#' @noRd

.tf_cache <- new.env(parent = emptyenv())

#' The rigour checklist specification (items, weights, thresholds, citations).
#' @keywords internal
#' @noRd
tf_checklist <- function() {
  if (is.null(.tf_cache$checklist)) {
    path <- system.file("schema", "rigor_checklist.yaml", package = "theoryforge")
    if (!nzchar(path)) {
      stop("could not locate vendored rigor_checklist.yaml", call. = FALSE)
    }
    .tf_cache$checklist <- yaml::read_yaml(path)
  }
  .tf_cache$checklist
}
