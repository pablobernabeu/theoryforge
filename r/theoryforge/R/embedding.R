#' Opt-in embedding-based construct-redundancy screen.
#'
#' Results depend on a user-supplied embedding function whose outputs are not
#' deterministic across model versions or SDKs. This screen is the assistive
#' counterpart to the deterministic lexical screen in
#' \code{tf_redundancy_check}.
#' @name embedding
#' @keywords internal
NULL

# Cosine similarity of two numeric vectors. The caller enforces equal lengths
# and nonzero norms.
.tf_cosine <- function(a, b) {
  a <- as.numeric(a)
  b <- as.numeric(b)
  sum(a * b) / (sqrt(sum(a * a)) * sqrt(sum(b * b)))
}

# Whether an embedding vector holds only finite numbers and has a finite,
# nonzero norm. An empty vector passes here and is refused with its pair's
# lengths. The norm is tested as computed, since one can underflow to 0 or
# overflow to an infinity although every entry is finite.
.tf_usable_vector <- function(v) {
  if (is.list(v)) {
    if (!all(vapply(v, function(x) is.numeric(x) && length(x) == 1L, logical(1)))) return(FALSE)
    v <- unlist(v)
  }
  if (length(v) == 0L) return(TRUE)
  if (!is.numeric(v) || !all(is.finite(v))) return(FALSE)
  norm <- sqrt(sum(as.numeric(v) * as.numeric(v)))
  norm > 0 && is.finite(norm)
}

#' Embedding-based pairwise construct-redundancy screen
#'
#' For every unordered pair of constructs, embeds each definition with the
#' supplied \code{embedder} and computes the cosine similarity (rounded to 6
#' decimals). The vectors of every compared pair must be of equal, nonzero
#' length, or the pair is refused. A vector that holds anything other than
#' finite numbers, or only zeros, which have no direction to compare, is
#' refused with the id of its construct, and so is a threshold outside -1 to 1.
#' Returns a data frame sorted by descending
#' cosine then \code{(a, b)}, flagging pairs at or above \code{threshold} for
#' review. This assistive screen complements the deterministic lexical
#' [tf_redundancy_check()], and its results are only as reproducible as the
#' supplied \code{embedder}.
#'
#' @param theory A theory object (named list), such as one from [tf_read()].
#' @param embedder A function mapping a definition string to a numeric vector.
#' @param threshold Cosine threshold for the \code{"review"} flag. It defaults
#'   to the checklist's \code{embedding_similarity_max} (0.85). How high a cosine
#'   two unrelated definitions reach depends on the embedding model, so a
#'   threshold suited to one model may flag everything or nothing under
#'   another, and the value is best set for the model in use.
#' @return A data frame with columns \code{a}, \code{b}, \code{cosine} and
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
    threshold <- tf_checklist()$thresholds$embedding_similarity_max
  }
  x <- .tf_number(threshold)
  if (is.null(x) || x < -1 || x > 1) {
    stop("embedding_redundancy requires a threshold from -1 to 1", call. = FALSE)
  }
  cons <- .tf_list(T, "constructs")
  ids <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  vecs <- lapply(cons, function(c) embedder(.tf_str(c, "definition")))
  for (i in seq_along(vecs)) {
    if (!.tf_usable_vector(vecs[[i]])) {
      stop("embedding_redundancy requires finite, nonzero embedding vectors; ",
           sprintf("the vector of construct %s is not", ids[[i]]), call. = FALSE)
    }
  }

  a <- character(0)
  b <- character(0)
  cosine <- numeric(0)
  n <- length(cons)
  if (n >= 2L) {
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        # Unequal or empty vectors have no defensible cosine: R's sum(a * b)
        # would recycle the shorter vector and a plain Python zip() truncate
        # the longer, so the same embedder could give two confident, different
        # similarities. Refuse instead of picking a reading.
        la <- length(vecs[[i]])
        lb <- length(vecs[[j]])
        if (la == 0L || lb == 0L || la != lb) {
          stop("embedding_redundancy requires equal-length nonempty embedding vectors; ",
               sprintf("constructs %s and %s have lengths %d and %d",
                       ids[[i]], ids[[j]], la, lb),
               call. = FALSE)
        }
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
