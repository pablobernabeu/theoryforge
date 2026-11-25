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
#' ASCII, Greek and Cyrillic letters to small unaccented ones) and lower-cases
#' ASCII letters, then takes every maximal run of letters, marks and digits in
#' any script (Unicode general categories L, M and N) as a token. Tokens
#' shorter than 3 code points and the canonical English stopwords are dropped,
#' and the unique set is returned. Scripts other than Latin, Greek and Cyrillic
#' are compared as written, and text written without spaces, such as Chinese,
#' gives one token per run.
#'
#' @param s A single string. \code{NULL} and \code{NA} read as \code{""}, and
#'   anything else is refused.
#' @return A character vector of unique tokens (possibly empty).
#' @examples
#' tf_tokens("The physiological arousal response to a threat")
#' # Accents and case are folded, so these give the same tokens.
#' tf_tokens("Na\u00efve \u00c9motion")
#' tf_tokens("naive emotion")
#' @export
tf_tokens <- function(s) {
  if (is.null(s) || (is.atomic(s) && length(s) == 1L && is.na(s))) {
    s <- ""
  } else if (!is.character(s) || length(s) != 1L) {
    stop("tokens requires a string", call. = FALSE)
  }
  s <- .tf_normalise_words(s)
  parts <- regmatches(s, gregexpr("[\\p{L}\\p{M}\\p{N}]+", s, perl = TRUE))[[1L]]
  keep <- nchar(parts, type = "chars") >= 3L & !(parts %in% .tf_STOPWORDS)
  unique(parts[keep])
}

#' Jaccard similarity of two token sets
#'
#' Returns 0.0 if both sets are empty and otherwise the size of the
#' intersection divided by the size of the union, rounded to 3 decimals.
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

# A label or measure as the screen compares it: folded, lower-cased and
# squished.
.tf_screen_name <- function(x) .tf_squish(.tf_normalise_words(.tf_text(x)))

# What the screen compares of each construct: its id, its definition's tokens,
# its label and its measures, the last two as the screen names them. Tokens
# and measures are also given as integer codes, with for each code the
# constructs that hold it, so that a construct's shared tokens with every other
# construct can be counted at once.
.tf_screen_fields <- function(theory) {
  cons <- .tf_list(theory, "constructs")
  toks <- lapply(cons, function(c) tf_tokens(.tf_str(c, "definition")))
  measures <- lapply(cons, function(c) {
    m <- unique(vapply(.tf_str_list(.tf_get(c, "measurement")), .tf_screen_name, character(1)))
    m[nzchar(m)]
  })
  labels <- vapply(cons, function(c) .tf_screen_name(.tf_get(c, "label")), character(1))
  codes <- function(sets) {
    all <- unlist(sets, use.names = FALSE)
    owner <- rep(seq_along(sets), lengths(sets))
    code <- match(all, unique(all))
    list(of = split(code, factor(owner, levels = seq_along(sets))),
         holders = split(owner, code), size = lengths(sets))
  }
  list(n = length(cons), ids = vapply(cons, function(c) .tf_str(c, "id"), character(1)),
       toks = codes(toks), measures = codes(measures),
       # Equal labels share a code, as match() compares them.
       label = ifelse(nzchar(labels), match(labels, labels), NA_integer_))
}

# The screen's record of construct i paired with each later construct j, as
# vectors over j: the Jaccard similarity, the overlap coefficient and the
# reasons a pair is flagged, as a code whose bits 1, 2, 4 and 8 stand for the
# four reasons in the order .tf_REDUNDANCY_REASONS gives them. Each value is
# the one tf_jaccard() and .tf_overlap() give for the pair alone.
.tf_screen_row <- function(f, i, thr) {
  j <- seq.int(i + 1L, f$n)
  count <- function(x) {
    hit <- tabulate(as.integer(unlist(x$holders[x$of[[i]]], use.names = FALSE)), nbins = f$n)
    hit[j]
  }
  inter <- count(f$toks)
  la <- f$toks$size[[i]]
  lb <- f$toks$size[j]
  union <- la + lb - inter
  sim <- .tf_rnd(inter / union, 3)
  sim[union == 0L] <- 0.0
  shorter <- pmin(la, lb)
  overlap <- .tf_rnd(inter / shorter, 3)
  overlap[shorter == 0L] <- 0.0
  ma <- f$measures$size[[i]]
  mb <- f$measures$size[j]
  shared <- count(f$measures)
  code <- (sim >= thr$redundancy_similarity_max) +
    2L * (la >= .tf_MIN_OVERLAP_TOKENS & lb >= .tf_MIN_OVERLAP_TOKENS &
            overlap >= thr$redundancy_overlap_max) +
    4L * (!is.na(f$label[[i]]) & f$label[[i]] == f$label[j] & !is.na(f$label[j])) +
    8L * (ma > 0L & mb > 0L & (shared == ma | shared == mb))
  list(j = j, sim = sim, overlap = overlap, code = code)
}

.tf_REDUNDANCY_REASONS <- c("near duplicate", "contained", "same label", "shared measurement")

# The screen's record of every unordered construct pair, in construct order, as
# a data frame. A pair is flagged "review" for any of four reasons, given in
# this order in `reason`: a "near duplicate", when its Jaccard similarity
# reaches redundancy_similarity_max; "contained", when both definitions hold at
# least three tokens and their overlap coefficient reaches
# redundancy_overlap_max; "same label", when the two constructs carry one name;
# and "shared measurement", when every measure one of them lists is listed for
# the other too, so that it has no indicator of its own and data from these
# measures cannot tell the two apart. Constructs that share a method or an
# inventory but keep measures of their own are not flagged. The checklist's
# non_redundancy item reads the same flags (.tf_redundancy_flagged()).
.tf_redundancy_pairs <- function(theory, thr) {
  f <- .tf_screen_fields(theory)
  n <- f$n
  size <- if (n >= 2L) n * (n - 1) / 2 else 0
  a <- character(size)
  b <- character(size)
  sim <- numeric(size)
  overlap <- numeric(size)
  code <- integer(size)
  at <- 0L
  for (i in seq_len(max(n - 1L, 0L))) {
    r <- .tf_screen_row(f, i, thr)
    k <- at + seq_along(r$j)
    a[k] <- f$ids[[i]]
    b[k] <- f$ids[r$j]
    sim[k] <- r$sim
    overlap[k] <- r$overlap
    code[k] <- r$code
    at <- at + length(r$j)
  }
  # Each of the sixteen codes as its reasons, joined in their order.
  reasons <- vapply(0:15, function(x) {
    paste(.tf_REDUNDANCY_REASONS[bitwAnd(x, c(1L, 2L, 4L, 8L)) > 0L], collapse = ", ")
  }, character(1))
  data.frame(a = a, b = b, similarity = sim, overlap = overlap,
             flag = c("ok", "review")[(code > 0L) + 1L], reason = reasons[code + 1L],
             stringsAsFactors = FALSE)
}

# Whether the screen flags any pair, as any(.tf_redundancy_pairs()$flag ==
# "review") would say, stopping at the first construct that has one.
.tf_redundancy_flagged <- function(theory, thr) {
  f <- .tf_screen_fields(theory)
  for (i in seq_len(max(f$n - 1L, 0L))) {
    if (any(.tf_screen_row(f, i, thr)$code > 0L)) return(TRUE)
  }
  FALSE
}

#' Pairwise lexical similarity of construct definitions
#'
#' Compares the definitions of every unordered pair of constructs and returns
#' a data frame with one row per pair, sorted by descending similarity then
#' \code{(a, b)} ascending. \code{similarity} is the Jaccard index of the two
#' definitions' token sets and \code{overlap} their overlap coefficient, the
#' shared tokens over the tokens of the shorter definition. \code{flag} is
#' \code{"review"}, and \code{reason} names why, in this order and separated
#' by commas, for a \code{"near duplicate"} (a similarity at or above the
#' checklist's \code{redundancy_similarity_max}), a definition
#' \code{"contained"} in the other (an overlap at or above
#' \code{redundancy_overlap_max} when both definitions hold at least three
#' tokens), two constructs with the \code{"same label"} and two of which one
#' has no measure that the other does not list (\code{"shared measurement"}). Labels and measures are
#' compared after folding case, accents and whitespace. \code{flag} is
#' \code{"ok"}, and \code{reason} empty, otherwise.
#'
#' The screen compares words, so it cannot detect empirical redundancy, two
#' differently defined constructs that correlate almost perfectly once
#' measurement error is corrected for (Le et al., 2010). Sibling constructs
#' (Lawson & Robins, 2021) may share vocabulary without being redundant.
#'
#' @param theory A theory object (named list).
#' @return A data frame with columns \code{a}, \code{b}, \code{similarity},
#'   \code{overlap}, \code{flag} and \code{reason}.
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
