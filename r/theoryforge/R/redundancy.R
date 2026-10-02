#' Deterministic lexical redundancy screen.
#'
#' Tokenisation and Jaccard similarity over construct definitions.
#' @name redundancy
#' @keywords internal
NULL

.tf_STOPWORDS <- c(
  "the", "and", "for", "that", "with", "from", "are", "was", "its", "our", "their",
  "this", "these", "those", "towards", "toward", "into", "onto", "per", "via"
)

#' Tokenise a string into a set of content tokens
#'
#' Folds the text through the package's fold table (accented Latin letters to
#' ASCII, Greek and Cyrillic letters to small unaccented ones) and lowercases
#' ASCII letters, then takes every maximal run of letters, marks and digits in
#' any script (Unicode general categories L, M and N) as a token. Tokens
#' shorter than 3 code points and the canonical English stopwords are dropped,
#' and the unique set is returned. Scripts other than Latin, Greek and Cyrillic
#' are compared as written, and text written without spaces, such as Chinese,
#' gives one token per run.
#'
#' @param s A single string (or \code{NULL}, treated as "").
#' @return A character vector of unique tokens (possibly empty).
#' @examples
#' tf_tokens("The physiological arousal response to a threat")
#' # Accents and case are folded, so these give the same tokens.
#' tf_tokens("Na\u00efve \u00c9motion")
#' tf_tokens("naive emotion")
#' @export
tf_tokens <- function(s) {
  if (is.null(s) || length(s) == 0L) {
    s <- ""
  } else {
    s <- as.character(s[[1L]])
    if (is.na(s)) s <- ""
  }
  s <- .tf_normalise_words(s)
  parts <- regmatches(s, gregexpr("[\\p{L}\\p{M}\\p{N}]+", s, perl = TRUE))[[1L]]
  keep <- nchar(parts, type = "chars") >= 3L & !(parts %in% .tf_STOPWORDS)
  unique(parts[keep])
}

#' Jaccard similarity of two token sets
#'
#' Returns 0.0 if both sets are empty, otherwise the size of the intersection
#' divided by the size of the union, rounded to 3 decimals.
#'
#' @param a,b Character vectors of tokens (treated as sets).
#' @return A numeric similarity in \code{[0, 1]}.
#' @examples
#' tf_jaccard(tf_tokens("arousal threat response"),
#'            tf_tokens("threat appraisal response"))
#' @export
tf_jaccard <- function(a, b) {
  if (length(a) == 0L && length(b) == 0L) {
    return(0.0)
  }
  inter <- length(intersect(a, b))
  union <- length(union(a, b))
  .tf_rnd(inter / union, 3)
}

#' Pairwise lexical similarity of construct definitions
#'
#' Computes Jaccard similarity for every unordered pair of construct
#' definitions. Returns a data frame with one row per pair, sorted by
#' descending similarity then \code{(a, b)} ascending. The \code{flag} column
#' is \code{"review"} when similarity meets or exceeds the configured
#' \code{redundancy_similarity_max} threshold, otherwise \code{"ok"}.
#'
#' @param theory A theory object (named list).
#' @return A data frame with columns \code{a}, \code{b}, \code{similarity},
#'   \code{flag}.
#' @references
#' Le, H., Schmidt, F. L., Harter, J. K., & Lauver, K. J. (2010). The problem of
#'   empirical redundancy of constructs. \emph{Organizational Behavior and Human
#'   Decision Processes}, 112(2), 112-125. \doi{10.1016/j.obhdp.2010.02.003}
#'
#' Lawson, K. M., & Robins, R. W. (2021). Sibling constructs. \emph{Personality
#'   and Social Psychology Review}, 25(4), 344-366. \doi{10.1177/10888683211047101}
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal",
#'                    "Bodily activation in response to a stressor.") |>
#'   tf_add_construct("c_threat", "Perceived threat",
#'                    "Appraised danger in response to a stressor.")
#' tf_redundancy_check(theory)
#' @export
tf_redundancy_check <- function(theory) {
  cons <- .tf_list(theory, "constructs")
  thr <- tf_checklist()$thresholds$redundancy_similarity_max
  ids <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  toks <- lapply(cons, function(c) tf_tokens(.tf_str(c, "definition")))

  a <- character(0)
  b <- character(0)
  sim <- numeric(0)
  n <- length(cons)
  if (n >= 2L) {
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        a <- c(a, ids[[i]])
        b <- c(b, ids[[j]])
        sim <- c(sim, tf_jaccard(toks[[i]], toks[[j]]))
      }
    }
  }
  flag <- ifelse(sim >= thr, "review", "ok")
  df <- data.frame(a = a, b = b, similarity = sim, flag = flag,
                   stringsAsFactors = FALSE)
  if (nrow(df) > 0L) {
    ord <- order(-df$similarity, df$a, df$b, method = "radix")
    df <- df[ord, , drop = FALSE]
    rownames(df) <- NULL
  }
  df
}
