#' Internal helpers mirroring the Python reference implementation.
#'
#' @keywords internal
#' @noRd
NULL

# A field is "nonempty" if it is a single non-NA string of trimmed length >= 1.
.tf_ne_str <- function(v) {
  is.character(v) && length(v) == 1L && !is.na(v) && nzchar(trimws(v))
}

# A list/array field is "nonempty" if it is a list/vector of length >= 1.
# yaml: `[]` parses to list() (length 0); a missing key is NULL (length 0).
.tf_ne_list <- function(v) {
  (is.list(v) || (is.atomic(v) && !is.null(v))) && length(v) >= 1L
}

# Mirror Python `T.get(key)` returning a list when present, else [].
# yaml::read_yaml gives a list for sequences/mappings; missing keys are absent.
.tf_list <- function(d, key) {
  v <- d[[key]]
  if (is.null(v)) return(list())
  if (is.list(v)) return(v)
  # An atomic vector (e.g. a YAML sequence of scalars) -> coerce to list of items.
  as.list(v)
}

# Mirror Python dict.get(key, default): NULL when absent.
.tf_get <- function(d, key, default = NULL) {
  if (is.null(d) || !is.list(d)) return(default)
  v <- d[[key]]
  if (is.null(v)) default else v
}

# Get a scalar string field, returning "" when absent/NULL (mirrors `str(x or "")`).
.tf_str <- function(d, key) {
  v <- .tf_get(d, key, "")
  if (is.null(v) || length(v) == 0L) return("")
  if (length(v) > 1L) v <- v[[1L]]
  if (is.na(v)) return("")
  as.character(v)
}
