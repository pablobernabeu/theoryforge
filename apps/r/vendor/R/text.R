#' Text normalisation shared by every consumer.
#'
#' The two languages disagree on what whitespace is and on how to lowercase:
#' R's trimws() and Python's str.strip() trim different characters, and
#' Python's str.lower() turns the Turkish dotted capital I into two code points
#' where tolower() gives one, while ?tolower calls tolower() platform-dependent.
#' These helpers pin one reading (API_SPEC.md sections 3, 6, 10, 18 and 19),
#' and the Python twin's _text.py mirrors each of them. The file is ASCII, as
#' CRAN asks, so every other character is written as an escape.
#'
#' @keywords internal
#' @noRd
NULL

# Unicode's White_Space property, 25 code points, written out because R's
# default trims only space, tab, CR and LF, and PCRE's [\h\v] adds U+180E. The
# class holds the characters themselves, not \x{...} escapes: R runs PCRE in
# UTF mode only when the pattern or the text is non-ASCII, and outside it an
# escape above \x{FF} is an invalid pattern.
.tf_WS_CODE_POINTS <- c(0x09:0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000:0x200A,
                        0x2028, 0x2029, 0x202F, 0x205F, 0x3000)
.tf_WS_CLASS <- paste0("[", intToUtf8(.tf_WS_CODE_POINTS), "]")

# `x` without leading or trailing characters of the whitespace set.
.tf_trim <- function(x) {
  trimws(enc2utf8(x), whitespace = .tf_WS_CLASS)
}

# `x` trimmed, with each run of whitespace-set characters inside it made one
# space. Mirrors Python's _text.squish.
.tf_squish <- function(x) {
  .tf_trim(gsub(paste0(.tf_WS_CLASS, "+"), " ", enc2utf8(x), perl = TRUE))
}

# `x` with A-Z lowercased and every other character kept.
.tf_ascii_lower <- function(x) {
  chartr("ABCDEFGHIJKLMNOPQRSTUVWXYZ", "abcdefghijklmnopqrstuvwxyz", x)
}

# `x` folded through schema/fold.json: the one-character entries with chartr,
# the longer ones (such as the sharp s to "ss") with a fixed gsub, then the
# combining marks deleted. No entry's output is folded again, so applying them
# in turn gives what Python's single str.translate gives. iconv()'s
# transliteration is avoided because its output differs between platforms.
.tf_fold <- function(x) {
  f <- tf_fold_table()
  x <- enc2utf8(x)
  x <- chartr(f$old, f$new, x)
  for (k in names(f$multi)) x <- gsub(k, f$multi[[k]], x, fixed = TRUE)
  gsub(f$delete, "", x, perl = TRUE)
}

# The fold, then ASCII lowercasing: what tokens and SEM names are built from.
.tf_normalise_words <- function(x) {
  .tf_ascii_lower(.tf_fold(x))
}

# A DOI as Crossref matches one, with explicit ASCII classes: PCRE and Python's
# re give \d, \S and \v different meanings.
.tf_DOI_PATTERN <- "10\\.[0-9]{4,9}/[^\\x{09}-\\x{0D}\\x{20}]+"

.tf_DOI_PREFIXES <- c("https://doi.org/", "http://doi.org/", "https://dx.doi.org/",
                      "http://dx.doi.org/", "doi:")

# The form two DOIs are compared in (API_SPEC.md section 18): trimmed and
# lowercased (ASCII letters only, as the DOI Handbook prescribes), with every
# percent escape of a printable ASCII character decoded, then the first run that
# looks like a DOI, less any trailing full stops, commas or semicolons. Text with
# no such run keeps the 0.6.0 rule: one known prefix is removed and the rest
# trimmed again. Mirrors Python's _text.normalise_doi.
.tf_normalize_doi <- function(doi) {
  if (is.null(doi) || length(doi) == 0L || is.na(doi)) doi <- ""
  d <- .tf_ascii_lower(.tf_trim(as.character(doi)))
  m <- gregexpr("%[0-9a-f]{2}", d, perl = TRUE)
  esc <- regmatches(d, m)[[1L]]
  if (length(esc) > 0L) {
    v <- strtoi(substring(esc, 2L), 16L)
    printable <- v >= 0x21 & v <= 0x7E
    esc[printable] <- vapply(v[printable], intToUtf8, character(1))
    regmatches(d, m) <- list(esc)
  }
  pos <- regexpr(.tf_DOI_PATTERN, d, perl = TRUE)
  if (pos > 0L) {
    return(sub("[.,;]+$", "", regmatches(d, pos), perl = TRUE))
  }
  for (prefix in .tf_DOI_PREFIXES) {
    if (startsWith(d, prefix)) {
      return(.tf_trim(substr(d, nchar(prefix) + 1L, nchar(d))))
    }
  }
  d
}
