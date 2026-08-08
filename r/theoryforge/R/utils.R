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
# Where the schema expects an array, a nonempty scalar string counts as a
# singleton list (natural YAML such as `derives_from: p1`); an empty or
# whitespace-only scalar counts as absent. Mirrors the Python `_as_list`
# reading (API_SPEC.md section 4).
.tf_ne_list <- function(v) {
  if (is.list(v)) return(length(v) >= 1L)
  if (is.character(v) && length(v) == 1L) {
    return(!is.na(v) && nzchar(trimws(v)))
  }
  (is.atomic(v) && !is.null(v)) && length(v) >= 1L
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

# Seconds every outbound request is allowed before it is abandoned, matching the
# `timeout=30` the Python twin passes to urlopen. Without one a stalled service
# hangs an interactive session indefinitely.
.tf_NET_TIMEOUT <- 30

# Fetch a URL as UTF-8 text under that timeout. curl (Suggests) gives a
# per-request timeout when it is installed; otherwise base R's url() connection
# honours the global `timeout` option, which is restored on exit, so the
# guarantee holds with no hard dependency.
.tf_fetch_url <- function(url, timeout = .tf_NET_TIMEOUT) {
  if (requireNamespace("curl", quietly = TRUE)) {  # nocov start
    handle <- curl::new_handle(timeout = timeout, connecttimeout = timeout)
    body <- curl::curl_fetch_memory(url, handle = handle)$content
  } else {
    old <- options(timeout = timeout)
    on.exit(options(old), add = TRUE)
    con <- base::url(url, open = "rb")
    on.exit(close(con), add = TRUE)
    body <- readBin(con, "raw", n = 1e8L)
  }
  text <- rawToChar(body)
  Encoding(text) <- "UTF-8"
  text
}  # nocov end

# Does a parsed document look like a mapping, as Python's isinstance(data, dict)
# asks? A YAML sequence of mappings also parses to an R list, so `is.list` alone
# lets one through and every collection then reads as empty, scoring nonsense
# instead of refusing it. Requiring names closes that. Zero-length lists are
# exempt because the R reader cannot tell `{}` from `[]`, and refusing them
# would diverge from Python on `{}`, which it accepts.
.tf_is_mapping <- function(data) {
  is.list(data) && (length(data) == 0L || !is.null(names(data)))
}

# The single writer every file-emitting function in the package goes through.
# API_SPEC.md section 3 pins every generated artefact to LF with a single
# trailing newline, so the connection is opened "wb" to bypass the platform's
# newline translation, any CRLF carried in from the theory's own text is folded
# to LF, and the bytes are UTF-8 whatever the session locale. The Python twin's
# `_io.write_lf` does the same three things.
.tf_write_lf <- function(path, text) {
  con <- file(path, open = "wb")
  on.exit(close(con))
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  writeBin(charToRaw(enc2utf8(text)), con)
  invisible(path)
}

# Deterministic, cross-platform half-away-from-zero rounding (API_SPEC.md
# section 3). Mirrors the Python `rnd` byte-for-byte. The `+1e-6` bias is far
# larger than cross-platform ULP jitter yet far smaller than the rounding grid,
# so results are identical on every platform. Vectorized in x (sign/floor/abs).
# Do not replace with base round(), which is banker's rounding and diverges
# across platforms at exact decimal half-boundaries.
.tf_rnd <- function(x, n) {
  s <- 10^n
  sign(x) * floor(abs(x) * s + 0.5 + 1e-6) / s
}
