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
  # NULL is excluded twice over: length(NULL) is 0, and is.atomic(NULL) is FALSE
  # from R 4.4 (it was TRUE up to 4.3, and DESCRIPTION declares R >= 4.1). The
  # line therefore reads a missing key as an absent array on every supported R.
  (is.atomic(v) && !is.null(v)) && length(v) >= 1L
}

# Mirror Python `T.get(key)` returning a list when present, else [].
# tf_read() returns every YAML or JSON sequence as a list and every mapping as a
# named list, and a missing key is absent.
.tf_list <- function(d, key) {
  v <- d[[key]]
  if (is.null(v)) return(list())
  if (is.list(v)) return(v)
  # An atomic value: a scalar string from natural YAML such as
  # `derives_from: p1`, or a vector in a theory built in memory, such as
  # `derives_from = c("p1", "p2")`. Either is read as the list of its elements.
  as.list(v)
}

# Mirror Python dict.get(key, default): NULL when absent.
.tf_get <- function(d, key, default = NULL) {
  if (is.null(d) || !is.list(d)) return(default)
  v <- d[[key]]
  if (is.null(v)) default else v
}

# Get a scalar string field, returning "" when absent/NULL (mirrors `str(x or "")`).
# A reader for fields the schema types as a scalar, and deliberately lenient: a
# YAML sequence where a scalar belongs is read as its first element, so an id or a
# label still prints somewhere. Refusing such a file is tf_validate()'s job. Do not
# add validation here, or the reader and the validator would disagree about the
# same document.
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
    # 100 MB is a ceiling on what a mistaken or hostile URL can pull into memory
    # in a session. It is far above any OpenAlex page (200 records at most), so
    # a truncated read here means something other than the documented API
    # answered, and the JSON parse that follows will say so.
    body <- readBin(con, "raw", n = 1e8L)
  }
  text <- rawToChar(body)
  Encoding(text) <- "UTF-8"
  text
}  # nocov end

# Does a parsed document look like a mapping, as Python's isinstance(data, dict)
# asks? A YAML or JSON sequence also parses to an R list, so `is.list` alone lets
# one through and every collection then reads as empty, scoring nonsense instead
# of refusing it. A mapping parses to a named list and a sequence to an unnamed
# one, the empty `{}` and `[]` included, so requiring names refuses `[]` as
# Python does and accepts `{}` as Python does.
.tf_is_mapping <- function(data) {
  is.list(data) && !is.null(names(data))
}

# -- Reading and writing files ----------------------------------------------
#
# One reading of a file in both twins (API_SPEC.md section 3, "Reading and
# writing files"). The Python twin's _load.py follows the same rules.

# The text of a file as UTF-8. The bytes are read whole, so no connection warns
# about a missing final newline or re-encodes for the session locale. A UTF-8
# byte-order mark is dropped, as Python's "utf-8-sig" codec drops it. jsonlite
# warned about one, and Python's json module refused one.
.tf_read_text <- function(path) {
  con <- file(path, open = "rb")
  on.exit(close(con))
  bytes <- readBin(con, "raw", n = file.size(path))
  if (length(bytes) >= 3L && identical(bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf)))) {
    bytes <- bytes[-(1:3)]
  }
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  text
}

# Handlers that make the yaml package read a document as PyYAML does under the
# Python twin's loader. A sequence is always a list, so `maturity: [draft]` stays
# a one-element list where yaml would collapse it to the string "draft" and let
# it validate. YAML 1.1 lists y, Y, n and N as booleans and PyYAML reads them as
# text, so they stay text, while the other boolean words keep their meaning. R's
# own missing-value forms (.na, .na.real, .na.integer, .na.character) stay text
# too, as Python reads them.
.tf_yaml_handlers <- list(
  seq = function(x) as.list(x),
  "bool#yes" = function(x) if (x %in% c("y", "Y")) x else TRUE,
  "bool#no" = function(x) if (x %in% c("n", "N")) x else FALSE,
  "bool#na" = function(x) x,
  "int#na" = function(x) x,
  "float#na" = function(x) x,
  "str#na" = function(x) x
)

# yaml takes for a number some plain scalars that it then cannot convert, and
# reads NA with a warning: a comma between digits (1,000, from YAML 1.0), a dot
# with no digit (.) and an integer beyond R's range (2147483648). The Python
# twin reads the first two as text and the third as an integer. These handlers
# read them the same way, the large integer as a double, and leave every other
# number as yaml converts it. A float is handed back to yaml for that, because
# as.numeric() rounds a few decimals (-527.867953 among them) one unit in the
# last place away from the value yaml and Python read.
.tf_yaml_int <- function(base) {
  function(x) {
    if (grepl(",", x, fixed = TRUE)) return(x)
    digits <- sub("^[-+]?(0x)?", "", x)
    value <- strtoi(digits, base)
    if (is.na(value)) {
      # The value is beyond R's integer range. A decimal goes through the float
      # reading, which rounds correctly, and octal and hexadecimal are summed
      # digit by digit, exact up to 2^53.
      value <- if (base == 10L) {
        .tf_yaml_float(paste0(digits, ".0"))
      } else {
        Reduce(function(acc, d) acc * base + d, strtoi(strsplit(digits, "")[[1L]], base), 0)
      }
    }
    if (startsWith(x, "-")) -value else value
  }
}

.tf_yaml_float <- function(x) {
  if (grepl(",", x, fixed = TRUE) || !grepl("[0-9]", sub("[eE].*$", "", x))) return(x)
  value <- suppressWarnings(yaml::yaml.load(x))
  # NA only when the value is beyond the range of a double: +/-Inf or 0, as in Python.
  if (is.na(value)) as.numeric(x) else value
}

.tf_yaml_number_handlers <- list(
  "int" = .tf_yaml_int(10L),
  "int#oct" = .tf_yaml_int(8L),
  "int#hex" = .tf_yaml_int(16L),
  "float#fix" = .tf_yaml_float,
  "float#exp" = .tf_yaml_float
)

# Parse a YAML file. merge.precedence = "override" lets a mapping's own key win
# over a merged one (yaml's default keeps the merged value), and a repeated key
# stops with "(<path>) Duplicate map key: '<key>'", which the Python twin copies.
# The number handlers cost a callback for every number, so they are used only
# when yaml warned on the first reading. Any warning left after that is the
# caller's to see.
.tf_read_yaml <- function(path) {
  text <- .tf_read_text(path)
  parse <- function(handlers) {
    yaml::yaml.load(text, handlers = handlers, merge.precedence = "override", error.label = path)
  }
  warned <- FALSE
  data <- withCallingHandlers(parse(.tf_yaml_handlers), warning = function(w) {
    warned <<- TRUE
    invokeRestart("muffleWarning")
  })
  if (warned) data <- parse(c(.tf_yaml_handlers, .tf_yaml_number_handlers))
  data
}

# Parse a JSON file. jsonlite keeps both entries of a repeated name, so the
# document is checked afterwards and refused with the YAML reader's message.
.tf_read_json <- function(path) {
  data <- jsonlite::fromJSON(.tf_read_text(path), simplifyVector = FALSE)
  key <- .tf_first_duplicate_key(data)
  if (!is.null(key)) {
    stop(sprintf("(%s) Duplicate map key: '%s'", path, key), call. = FALSE)
  }
  data
}

# The first repeated name in a parsed document, or NULL. Children are checked
# before their parent, the order in which the objects close, because that is the
# order Python's json module (and R's yaml package, for YAML) meets them in.
.tf_first_duplicate_key <- function(x) {
  if (!is.list(x)) return(NULL)
  for (child in x) {
    key <- .tf_first_duplicate_key(child)
    if (!is.null(key)) return(key)
  }
  nms <- names(x)
  dup <- which(duplicated(nms))
  if (length(dup) > 0L) nms[[dup[[1L]]]] else NULL
}

# Parse the file at `path`: JSON when the extension is .json, otherwise YAML.
.tf_read_file <- function(path) {
  if (identical(tolower(tools::file_ext(path)), "json")) .tf_read_json(path) else .tf_read_yaml(path)
}

# The paths of the schema's array-of-strings fields, such as
# c("predictions", "[]", "derives_from"), where "[]" stands for every entry of a
# collection. They are read from theory.schema.json, so a field added there is
# boxed by tf_write() without a change here.
.tf_string_array_paths <- function() {
  if (is.null(.tf_cache$string_array_paths)) {
    .tf_cache$string_array_paths <- .tf_schema_string_arrays(tf_theory_schema(), character(0))
  }
  .tf_cache$string_array_paths
}

.tf_schema_string_arrays <- function(node, path) {
  if (identical(node[["type"]], "array")) {
    items <- node[["items"]]
    if (identical(items[["type"]], "string")) return(list(path))
    if (is.list(items)) return(.tf_schema_string_arrays(items, c(path, "[]")))
    return(list())
  }
  out <- list()
  props <- node[["properties"]]
  for (name in names(props)) {
    out <- c(out, .tf_schema_string_arrays(props[[name]], c(path, name)))
  }
  out
}

# Hold every array-of-strings field of a theory as a list. jsonlite (under
# auto_unbox) and yaml write a one-element character vector as a scalar, which
# fails the package's own schema, while a list is always written as an array.
.tf_box_string_arrays <- function(theory) {
  for (path in .tf_string_array_paths()) theory <- .tf_box_path(theory, path)
  theory
}

.tf_box_path <- function(x, path) {
  if (!is.list(x)) return(x)
  head <- path[[1L]]
  rest <- path[-1L]
  if (identical(head, "[]")) {
    for (i in seq_along(x)) {
      if (!is.null(x[[i]])) x[[i]] <- .tf_box_path(x[[i]], rest)
    }
    return(x)
  }
  value <- x[[head]]
  if (is.null(value)) return(x)
  if (length(rest) > 0L) {
    x[[head]] <- .tf_box_path(value, rest)
  } else if (is.atomic(value)) {
    x[[head]] <- as.list(unname(value))
  }
  x
}

# Replace every missing value (NA, of any type) with NULL, which both formats
# write as null and both readers return as NULL and None. yaml would write R's
# own .na forms, which both readers take for text, and jsonlite would write the
# string "NA" for a number. NaN is a number and is kept.
.tf_na_as_null <- function(x) {
  if (!is.list(x)) return(x)
  for (i in seq_along(x)) {
    v <- x[[i]]
    if (is.list(v)) {
      x[[i]] <- .tf_na_as_null(v)
    } else if (is.atomic(v) && length(v) > 0L) {
      absent <- if (is.double(v)) is.na(v) & !is.nan(v) else is.na(v)
      if (!any(absent)) next
      if (length(v) == 1L) {
        x[i] <- list(NULL)
      } else {
        # unname() keeps a vector an array: a named list is written as a mapping.
        v <- as.list(unname(v))
        v[absent] <- list(NULL)
        x[[i]] <- v
      }
    }
  }
  x
}

# The yaml handler that writes doubles. yaml's own precision argument counts
# decimal places, so 15 of them would write 21.3 as 21.300000000000001 and keep
# fewer than 15 significant digits of a small number. Each double is written with
# 15 significant digits instead, as jsonlite's digits = NA writes JSON, with the
# decimal point both readers need to take it for a float (5.0, 1.0e+20).
.tf_yaml_double <- function(x) {
  out <- sub("^([-+]?[0-9]+)(e|$)", "\\1.0\\2", sprintf("%.15g", x))
  out[is.nan(x)] <- ".nan"
  out[is.infinite(x) & x > 0] <- ".inf"
  out[is.infinite(x) & x < 0] <- "-.inf"
  out[is.na(x) & !is.nan(x)] <- "~"
  names(out) <- names(x)
  structure(out, class = "verbatim")
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
# so results are identical on every platform. Vectorised in x (sign/floor/abs).
# Do not replace with base round(), which is banker's rounding and diverges
# across platforms at exact decimal half-boundaries.
.tf_rnd <- function(x, n) {
  s <- 10^n
  sign(x) * floor(abs(x) * s + 0.5 + 1e-6) / s
}
