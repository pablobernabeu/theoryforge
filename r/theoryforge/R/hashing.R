# The content hash of a theory (API_SPEC.md section 34). The Python twin's
# hashing.py writes the same canonical form, byte for byte.

# A number as ECMAScript's Number.prototype.toString writes it, with the fewest
# digits that read back as the same double (RFC 8785).
.tf_canonical_number <- function(x) {
  x <- as.numeric(x)
  if (is.nan(x)) return("NaN")
  if (is.infinite(x)) return(if (x > 0) "Infinity" else "-Infinity")
  if (x == 0) return("0")
  sign <- if (x < 0) "-" else ""
  x <- abs(x)
  # The fewest significant digits, up to 17, that read back as x, and of two
  # such the nearer (.tf_shortest_e() in utils.R).
  s <- .tf_shortest_e(x)
  parts <- strsplit(s, "e", fixed = TRUE)[[1]]
  digits <- sub("0+$", "", gsub(".", "", parts[[1]], fixed = TRUE))
  if (!nzchar(digits)) digits <- "0"
  k <- nchar(digits)
  n <- as.integer(parts[[2]]) + 1L
  out <- if (k <= n && n <= 21L) {
    paste0(digits, strrep("0", n - k))
  } else if (0L < n && n <= 21L) {
    paste0(substr(digits, 1L, n), ".", substr(digits, n + 1L, k))
  } else if (-6L < n && n <= 0L) {
    paste0("0.", strrep("0", -n), digits)
  } else {
    e <- n - 1L
    paste0(substr(digits, 1L, 1L), if (k > 1L) paste0(".", substr(digits, 2L, k)),
           if (e >= 0L) "e+" else "e-", abs(e))
  }
  paste0(sign, out)
}

# A JSON string: quotation mark, backslash and control characters escaped, the
# rest as it is.
.tf_canonical_string <- function(s) {
  cps <- utf8ToInt(enc2utf8(s))
  pieces <- vapply(cps, function(cp) {
    switch(as.character(cp),
           "34" = "\\\"", "92" = "\\\\", "8" = "\\b", "12" = "\\f", "10" = "\\n",
           "13" = "\\r", "9" = "\\t",
           if (cp < 32L) sprintf("\\u%04x", cp) else intToUtf8(cp))
  }, character(1))
  paste0("\"", paste(pieces, collapse = ""), "\"")
}

# A key's sort order: its UTF-16 code units, each as four hexadecimal digits,
# so that sorting the strings bytewise sorts the keys as RFC 8785 asks.
.tf_utf16_key <- function(k) {
  cps <- utf8ToInt(enc2utf8(k))
  units <- unlist(lapply(cps, function(cp) {
    if (cp < 0x10000) cp else c(0xD800 + (cp - 0x10000) %/% 0x400, 0xDC00 + (cp - 0x10000) %% 0x400)
  }))
  paste(sprintf("%04x", as.integer(units)), collapse = "")
}

# `v` as canonical JSON: keys sorted, no whitespace, an empty container written
# as []. A vector of two or more values, which only a theory built in memory
# holds, is a sequence, and a missing value is null.
.tf_canonical <- function(v) {
  if (is.null(v)) return("null")
  if (is.list(v)) {
    if (length(v) == 0L) return("[]")
    if (.tf_is_mapping(v)) {
      keys <- names(v)
      order_keys <- order(vapply(keys, .tf_utf16_key, character(1)), method = "radix")
      body <- vapply(order_keys, function(i) {
        paste0(.tf_canonical_string(keys[[i]]), ":", .tf_canonical(v[[i]]))
      }, character(1))
      return(paste0("{", paste(body, collapse = ","), "}"))
    }
    return(paste0("[", paste(vapply(v, .tf_canonical, character(1)), collapse = ","), "]"))
  }
  if (length(v) != 1L) {
    return(paste0("[", paste(vapply(as.list(v), .tf_canonical, character(1)), collapse = ","), "]"))
  }
  if (is.na(v) && !(is.double(v) && is.nan(v))) return("null")
  if (is.logical(v)) return(if (v) "true" else "false")
  if (is.numeric(v)) return(.tf_canonical_number(v))
  if (is.character(v)) return(.tf_canonical_string(v))
  if (is.factor(v)) return(.tf_canonical_string(as.character(v)))
  stop("content_hash cannot write a value of class ", class(v)[[1]], call. = FALSE)
}

# SHA-256 of a raw vector, as 64 lowercase hexadecimal digits (FIPS 180-4).
# Base R has no SHA-256 before R 4.5, so it is computed here. Words are held as
# doubles from 0 to 2^32 - 1, and the bitwise operations work on their two
# 16-bit halves, since an R integer cannot hold 2^31.
.tf_sha256 <- function(bytes) {
  w32 <- 4294967296
  half <- function(x) list(hi = as.integer(x %/% 65536), lo = as.integer(x %% 65536))
  join <- function(h) h$hi * 65536 + h$lo
  xor <- function(a, b) {
    a <- half(a)
    b <- half(b)
    join(list(hi = bitwXor(a$hi, b$hi), lo = bitwXor(a$lo, b$lo)))
  }
  and <- function(a, b) {
    a <- half(a)
    b <- half(b)
    join(list(hi = bitwAnd(a$hi, b$hi), lo = bitwAnd(a$lo, b$lo)))
  }
  not <- function(a) w32 - 1 - a
  rotr <- function(x, n) (x %/% 2^n) + (x %% 2^n) * 2^(32 - n)
  shr <- function(x, n) x %/% 2^n
  add <- function(...) sum(...) %% w32
  k <- c(
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2)
  h <- c(0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19)
  b <- as.integer(bytes)
  len_bits <- length(b) * 8
  b <- c(b, 0x80L)
  b <- c(b, rep(0L, (56 - length(b) %% 64) %% 64))
  len_bytes <- vapply(7:0, function(i) as.integer((len_bits %/% 256^i) %% 256), integer(1))
  b <- c(b, len_bytes)
  for (start in seq(1L, length(b), by = 64L)) {
    chunk <- b[start:(start + 63L)]
    w <- numeric(64)
    for (t in 1:16) {
      i <- (t - 1L) * 4L
      w[[t]] <- chunk[[i + 1L]] * 16777216 + chunk[[i + 2L]] * 65536 + chunk[[i + 3L]] * 256 + chunk[[i + 4L]]
    }
    for (t in 17:64) {
      s0 <- xor(xor(rotr(w[[t - 15L]], 7), rotr(w[[t - 15L]], 18)), shr(w[[t - 15L]], 3))
      s1 <- xor(xor(rotr(w[[t - 2L]], 17), rotr(w[[t - 2L]], 19)), shr(w[[t - 2L]], 10))
      w[[t]] <- add(w[[t - 16L]], s0, w[[t - 7L]], s1)
    }
    a <- h[[1]]; bb <- h[[2]]; cc <- h[[3]]; d <- h[[4]]
    e <- h[[5]]; f <- h[[6]]; g <- h[[7]]; hh <- h[[8]]
    for (t in 1:64) {
      s1 <- xor(xor(rotr(e, 6), rotr(e, 11)), rotr(e, 25))
      ch <- xor(and(e, f), and(not(e), g))
      t1 <- add(hh, s1, ch, k[[t]], w[[t]])
      s0 <- xor(xor(rotr(a, 2), rotr(a, 13)), rotr(a, 22))
      maj <- xor(xor(and(a, bb), and(a, cc)), and(bb, cc))
      t2 <- add(s0, maj)
      hh <- g; g <- f; f <- e; e <- add(d, t1)
      d <- cc; cc <- bb; bb <- a; a <- add(t1, t2)
    }
    h <- c(add(h[[1]], a), add(h[[2]], bb), add(h[[3]], cc), add(h[[4]], d),
           add(h[[5]], e), add(h[[6]], f), add(h[[7]], g), add(h[[8]], hh))
  }
  paste(sprintf("%04x%04x", as.integer(h %/% 65536), as.integer(h %% 65536)), collapse = "")
}

#' Compute the content hash of a theory
#'
#' Returns the SHA-256 digest of the theory's canonical form, as
#' \code{sha256:} followed by 64 hexadecimal digits. The canonical form is the
#' theory as JSON with every mapping's keys sorted by their UTF-16 code units,
#' no whitespace, strings escaped only where JSON requires it and numbers
#' written with the fewest digits that read back as the same double, as RFC
#' 8785 specifies (Rundgren et al., 2020). Three conventions make it the same
#' in R and Python: an empty mapping is written as an empty sequence, an
#' infinity or a missing number as \code{Infinity}, \code{-Infinity} or
#' \code{NaN} and a single value in a field that the schema types as an array
#' of strings, such as \code{measurement} or \code{derives_from}, as a
#' one-element array, since a reader takes \code{derives_from: p1} for
#' \code{[p1]}. [tf_write()] writes such a field as an array, so a theory keeps
#' its hash when R writes it. The theory's own \code{version$content_hash} is
#' left out, so that a file can record the hash of its content.
#'
#' Two theory files with the same content therefore have the same hash
#' whatever their layout, comments, key order or format, and any change to a
#' value changes it. [tf_validate()] with \code{full = TRUE} checks a recorded
#' hash against the content, and [tf_preregister()] and [tf_dossier()] give the
#' hash, so that a reader can check that the theory file in hand is the one
#' they describe.
#'
#' @param theory A theory object (named list).
#' @return The hash as a single string.
#' @references
#' Rundgren, A., Jordan, B., & Erdtman, S. (2020). \emph{JSON Canonicalization
#' Scheme (JCS)} (RFC 8785). RFC Editor. \doi{10.17487/RFC8785}
#' @examples
#' tf_content_hash(tf_read(tf_example_path("modality-switching.theory.yaml")))
#' @export
tf_content_hash <- function(theory) {
  data <- theory
  if (.tf_is_mapping(data) && .tf_is_mapping(data[["version"]])) {
    data[["version"]] <- data[["version"]][names(data[["version"]]) != "content_hash"]
  }
  # A single value in a field the schema types as an array of strings is
  # written as a one-element array, as the singleton rule reads it and as
  # tf_write() writes it. NA becomes null first, so that it is not boxed.
  data <- .tf_box_string_arrays(.tf_na_as_null(data))
  bytes <- charToRaw(enc2utf8(.tf_canonical(data)))
  paste0("sha256:", .tf_sha256(bytes))
}
