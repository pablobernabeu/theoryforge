#' Access to the vendored rigour checklist and theory schema.
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

#' The theory JSON Schema, read for its enumeration of recognised fields.
#'
#' No JSON-Schema engine is involved (API_SPEC.md section 2); \code{tf_validate}
#' only needs the \code{properties} key set, so the schema stays the single
#' source of truth for which top-level fields exist.
#' @keywords internal
#' @noRd
tf_theory_schema <- function() {
  if (is.null(.tf_cache$theory_schema)) {
    path <- system.file("schema", "theory.schema.json", package = "theoryforge")
    if (!nzchar(path)) {
      stop("could not locate vendored theory.schema.json", call. = FALSE)
    }
    .tf_cache$theory_schema <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  }
  .tf_cache$theory_schema
}
