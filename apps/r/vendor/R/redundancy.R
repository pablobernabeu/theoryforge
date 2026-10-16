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

# The overlap coefficient flags a pair only when both definitions hold at least
# this many tokens. One or two content words contained in a longer definition
# are too few to call the two constructs the same.
.tf_MIN_OVERLAP_TOKENS <- 3L

# The overlap coefficient, |A and B| / min(|A|, |B|), rounded to 3 decimals, or
# 0 when either set is empty.
.tf_overlap <- function(a, b) {
  if (length(a) == 0L || length(b) == 0L) return(0.0)
  .tf_rnd(length(intersect(a, b)) / min(length(a), length(b)), 3)
}

# The screen's record of every unordered construct pair, in construct order, as
# a data frame. A pair is flagged "review" when its Jaccard similarity reaches
# redundancy_similarity_max, a near-duplicate, or when both definitions hold at
# least three tokens and their overlap coefficient reaches
# redundancy_overlap_max, one definition contained in the other. The
# checklist's non_redundancy item reads the same flags.
.tf_redundancy_pairs <- function(theory, thr) {
  cons <- .tf_list(theory, "constructs")
  ids <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  toks <- lapply(cons, function(c) tf_tokens(.tf_str(c, "definition")))

  a <- character(0)
  b <- character(0)
  sim <- numeric(0)
  overlap <- numeric(0)
  flag <- character(0)
  n <- length(cons)
  if (n >= 2L) {
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        s <- tf_jaccard(toks[[i]], toks[[j]])
        ov <- .tf_overlap(toks[[i]], toks[[j]])
        contained <- length(toks[[i]]) >= .tf_MIN_OVERLAP_TOKENS &&
          length(toks[[j]]) >= .tf_MIN_OVERLAP_TOKENS &&
          ov >= thr$redundancy_overlap_max
        a <- c(a, ids[[i]])
        b <- c(b, ids[[j]])
        sim <- c(sim, s)
        overlap <- c(overlap, ov)
        flag <- c(flag, if (s >= thr$redundancy_similarity_max || contained) "review" else "ok")
      }
    }
  }
  data.frame(a = a, b = b, similarity = sim, overlap = overlap, flag = flag,
             stringsAsFactors = FALSE)
}

#' Pairwise lexical similarity of construct definitions
#'
#' Compares the definitions of every unordered pair of constructs and returns
#' a data frame with one row per pair, sorted by descending similarity then
#' \code{(a, b)} ascending. \code{similarity} is the Jaccard index of the two
#' definitions' token sets and \code{overlap} their overlap coefficient, the
#' shared tokens over the tokens of the shorter definition. \code{flag} is
#' \code{"review"} for a near-duplicate, a similarity at or above the
#' checklist's \code{redundancy_similarity_max}, and for a definition contained
#' in the other, an overlap at or above \code{redundancy_overlap_max} when both
#' definitions hold at least three tokens. It is \code{"ok"} otherwise.
#'
#' The screen compares words, so it cannot detect empirical redundancy, two
#' differently defined constructs that correlate almost perfectly once
#' measurement error is corrected for (Le et al., 2010). Sibling constructs
#' (Lawson & Robins, 2021) may share vocabulary without being redundant.
#'
#' @param theory A theory object (named list).
#' @return A data frame with columns \code{a}, \code{b}, \code{similarity},
#'   \code{overlap}, \code{flag}.
#' @references
#' Le, H., Schmidt, F. L., Harter, J. K., & Lauver, K. J. (2010). The problem of
#'   empirical redundancy of constructs in organizational research: An empirical
#'   investigation. \emph{Organizational Behavior and Human Decision Processes},
#'   112(2), 112-125. \doi{10.1016/j.obhdp.2010.02.003}
#'
#' Lawson, K. M., & Robins, R. W. (2021). Sibling constructs: What are they, why
#'   do they matter, and how should you handle them? \emph{Personality and
#'   Social Psychology Review}, 25(4), 344-366. \doi{10.1177/10888683211047101}
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal",
#'                    "Bodily activation in response to a stressor.") |>
#'   tf_add_construct("c_threat", "Perceived threat",
#'                    "Appraised danger in response to a stressor.")
#' tf_redundancy_check(theory)
#' @export
tf_redundancy_check <- function(theory) {
  df <- .tf_redundancy_pairs(theory, tf_checklist()$thresholds)
  if (nrow(df) > 0L) {
    ord <- order(-df$similarity, df$a, df$b, method = "radix")
    df <- df[ord, , drop = FALSE]
    rownames(df) <- NULL
  }
  df
}
