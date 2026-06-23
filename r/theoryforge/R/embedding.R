#' Opt-in embedding-based construct-redundancy screen.
#'
#' This screen is parity-exempt because its results depend on a user-supplied
#' embedding function whose outputs are not deterministic across model versions
#' or SDKs. It is the assistive counterpart to the deterministic lexical screen
#' in \code{tf_redundancy_check}, and it is excluded from the parity contract
#' and CI.
#' See API_SPEC.md section 23.
#' @name embedding
#' @keywords internal
NULL

# Cosine similarity of two numeric vectors; 0 when either has zero norm.
.tf_cosine <- function(a, b) {
  a <- as.numeric(a)
  b <- as.numeric(b)
  num <- sum(a * b)
  da <- sqrt(sum(a * a))
  db <- sqrt(sum(b * b))
  if (da == 0 || db == 0) {
    return(0.0)
  }
  num / (da * db)
}

#' Embedding-based pairwise construct-redundancy screen
#'
#' For every unordered pair of constructs, embeds each definition with the
#' supplied \code{embedder} and computes the cosine similarity (rounded to 6
#' decimals). Returns a data frame sorted by descending cosine then
#' \code{(a, b)}, flagging pairs at or above \code{threshold} for review. This
#' assistive screen complements the deterministic lexical
#' [tf_redundancy_check()] and is parity-exempt. See API_SPEC.md section 23.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param embedder A function mapping a definition string to a numeric vector.
#' @param threshold Cosine threshold for the \code{"review"} flag; defaults to
#'   the checklist's \code{redundancy_similarity_max}.
#' @return A data frame with columns \code{a}, \code{b}, \code{cosine},
#'   \code{flag}.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "bodily activation") |>
#'   tf_add_construct("c_threat", "Threat", "appraised danger")
#' # A toy deterministic embedder: bag-of-words counts over a fixed vocabulary.
#' vocab <- c("bodily", "activation", "appraised", "danger")
#' embedder <- function(def) {
#'   words <- strsplit(tolower(def), "\\s+")[[1]]
#'   vapply(vocab, function(w) sum(words == w), numeric(1))
#' }
#' tf_embedding_redundancy(theory, embedder)
#' @export
tf_embedding_redundancy <- function(theory, embedder, threshold = NULL) {
  T <- theory
  if (is.null(threshold)) {
    threshold <- tf_checklist()$thresholds$redundancy_similarity_max
  }
  cons <- .tf_list(T, "constructs")
  ids <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  vecs <- lapply(cons, function(c) embedder(.tf_str(c, "definition")))

  a <- character(0)
  b <- character(0)
  cosine <- numeric(0)
  n <- length(cons)
  if (n >= 2L) {
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        a <- c(a, ids[[i]])
        b <- c(b, ids[[j]])
        cosine <- c(cosine, .tf_rnd(.tf_cosine(vecs[[i]], vecs[[j]]), 6))
      }
    }
  }
  flag <- ifelse(cosine >= threshold, "review", "ok")
  df <- data.frame(a = a, b = b, cosine = cosine, flag = flag,
                   stringsAsFactors = FALSE)
  if (nrow(df) > 0L) {
    ord <- order(-df$cosine, df$a, df$b, method = "radix")
    df <- df[ord, , drop = FALSE]
    rownames(df) <- NULL
  }
  df
}
