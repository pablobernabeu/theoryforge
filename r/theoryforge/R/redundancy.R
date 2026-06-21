#' Deterministic lexical redundancy screen.
#'
#' Tokenization and Jaccard similarity per API_SPEC.md section 6.
#' @name redundancy
#' @keywords internal
NULL

.tf_STOPWORDS <- c(
  "the", "and", "for", "that", "with", "from", "are", "was", "its", "our", "their",
  "this", "these", "those", "towards", "toward", "into", "onto", "per", "via"
)

#' Tokenize a string into a set of content tokens
#'
#' Lowercases, replaces every run of non-\code{[a-z0-9]} characters with a
#' single space, splits, drops tokens shorter than 3 characters and the
#' canonical stopwords, then returns the unique set. See API_SPEC.md section 6.
#'
#' @param s A single string (or \code{NULL}, treated as "").
#' @return A character vector of unique tokens (possibly empty).
#' @examples
#' tf_tokens("The physiological arousal response to a threat")
#' @export
tf_tokens <- function(s) {
  if (is.null(s) || length(s) == 0L) {
    s <- ""
  } else {
    s <- as.character(s[[1L]])
    if (is.na(s)) s <- ""
  }
  s <- tolower(s)
  s <- gsub("[^a-z0-9]+", " ", s)
  parts <- strsplit(s, " ", fixed = TRUE)[[1L]]
  parts <- parts[nzchar(parts)]
  keep <- nchar(parts) >= 3L & !(parts %in% .tf_STOPWORDS)
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
  toks <- lapply(cons, function(c) tf_tokens(.tf_get(c, "definition", "")))

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
