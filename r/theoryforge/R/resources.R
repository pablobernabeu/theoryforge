#' Access to the vendored shared schema and rigour checklist.
#'
#' These read the files vendored under \code{inst/schema/} at runtime via
#' \code{system.file()}. Results are cached in a package-private environment so
#' repeated calls are cheap.
#'
#' @keywords internal
#' @noRd

.tf_cache <- new.env(parent = emptyenv())

#' The JSON Schema for a theory object (source of truth, vendored).
#' @keywords internal
#' @noRd
tf_schema <- function() {
  if (is.null(.tf_cache$schema)) {
    path <- system.file("schema", "theory.schema.json", package = "theoryforge")
    if (!nzchar(path)) {
      stop("could not locate vendored theory.schema.json", call. = FALSE)
    }
    text <- readChar(path, file.info(path)$size, useBytes = TRUE)
    .tf_cache$schema <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  }
  .tf_cache$schema
}

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
