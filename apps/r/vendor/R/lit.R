#' Bibliometric / literature layer.
#'
#' The analysis (litmap, landscape, diagrams) is fully deterministic given a
#' corpus. The OpenAlex fetch adapter ([tf_fetch_corpus()]) is the assistive
#' layer, whose results depend on a live network service.
#' @name lit
#' @keywords internal
NULL

.tf_DEFAULT_MIN_LINK <- 2L

# Words that name a kind of account and say nothing about what it is about, so
# that "model" in a rival's label cannot match a theme on model fit
# (API_SPEC.md section 15). Python lit.THEORY_WORDS.
.tf_THEORY_WORDS <- c(
  "theory", "theories", "model", "models", "account", "accounts",
  "hypothesis", "hypotheses", "framework", "frameworks", "approach", "approaches"
)

# Escape a DOT label: replace backslash then double-quote (order matters).
# Mirrors Python lit._esc (treats NULL/NA as "").
.tf_lit_esc <- function(s) {
  .tf_lit_esc_all(.tf_lit_text(s))
}

# A label value as one string, NULL and NA read as "" (Python's `s or ""`).
.tf_lit_text <- function(s) {
  if (is.null(s) || length(s) == 0L) return("")
  s <- s[[1L]]
  if (is.na(s)) "" else as.character(s)
}

# .tf_lit_esc() over a character vector.
.tf_lit_esc_all <- function(s) {
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  gsub('"', '\\"', s, fixed = TRUE)
}

#' Read a literature corpus from a YAML or JSON file
#'
#' Reads a corpus object (\code{{schema_version, id, records}}) into a named
#' list. The format is chosen by the file extension (\code{.json} -> JSON,
#' otherwise YAML). The file is read by the rules [tf_read()] follows, which
#' are the Python twin's, so an unquoted keyword such as \code{y} or \code{n}
#' stays a string and a repeated key is refused.
#'
#' @param path Path to a \code{.yaml}/\code{.yml} or \code{.json} corpus file.
#' @return A named list holding the parsed corpus object.
#' @examples
#' corpus <- list(
#'   schema_version = "1.0", id = "demo-corpus",
#'   records = list(
#'     list(id = "w1", keywords = list("arousal", "threat")),
#'     list(id = "w2", keywords = list("arousal", "threat"))
#'   )
#' )
#' path <- tempfile(fileext = ".json")
#' jsonlite::write_json(corpus, path, auto_unbox = TRUE)
#' tf_read_corpus(path)
#' @export
tf_read_corpus <- function(path) {
  data <- .tf_read_file(path)
  if (!.tf_is_mapping(data)) {
    stop("Corpus data must be a mapping", call. = FALSE)
  }
  data
}

# `value` as an integer when it is one integral number of at least 1, as the
# Python twin's _positive_int accepts it. A logical, a string, NA and a vector
# of two values are refused, where they were truncated, recycled or read as an
# empty map (API_SPEC.md section 14).
.tf_positive_int <- function(value, name) {
  ok <- is.numeric(value) && length(value) == 1L && is.finite(value) &&
    value == trunc(value) && value >= 1
  if (!ok) stop(sprintf("%s must be a positive integer", name), call. = FALSE)
  # A value beyond R's integer range stays a double, which compares as Python's
  # int does, where as.integer() would make it NA.
  if (value <= .Machine$integer.max) as.integer(value) else as.numeric(value)
}

# `value` as a double when it is one number from 0 to 1, as the Python twin's
# _share accepts it. A logical, a string, NA, NaN, an infinity and a vector of
# two values are refused (API_SPEC.md section 15).
.tf_share <- function(value, name) {
  ok <- is.numeric(value) && length(value) == 1L && !is.na(value) &&
    value >= 0 && value <= 1
  if (!ok) stop(sprintf("%s must be a number between 0 and 1", name), call. = FALSE)
  as.numeric(value)
}

# R holds a number read from a file as a double, exact for integers below 2^53.
# A larger one cannot be written as the same decimal string in both twins, so
# it is refused (API_SPEC.md section 14).
.tf_EXACT_LIMIT <- 2^53

.tf_not_strings <- function(i, field) {
  sprintf(paste("invalid corpus: record[%d] %s must be strings",
                "(an unquoted no, yes, on or off is read as a boolean; quote it)"),
          i, field)
}

# One keyword or reference as a string, or NULL when it is dropped. A string is
# kept as it is and an empty one dropped, as null and NA are. An integer-valued
# number becomes its decimal string through format(), since as.character()
# writes 100000 as "1e+05". A logical, a fractional or non-finite number and a
# list are refused. NaN is a number, so it is tested before NA drops it.
.tf_entry <- function(x, i, field, k) {
  if (is.null(x)) return(NULL)
  if (is.list(x) || !is.atomic(x) || length(x) != 1L || is.logical(x) && !is.na(x)) {
    stop(.tf_not_strings(i, field), call. = FALSE)
  }
  if (is.double(x) && is.nan(x)) stop(.tf_not_strings(i, field), call. = FALSE)
  if (is.na(x)) return(NULL)
  if (is.character(x)) return(if (nzchar(x)) x else NULL)
  if (!is.numeric(x) || !is.finite(x) || x != trunc(x)) {
    stop(.tf_not_strings(i, field), call. = FALSE)
  }
  if (abs(x) >= .tf_EXACT_LIMIT) {
    stop(sprintf(paste("invalid corpus: record[%d] %s entry %d is a number too large",
                       "to be an exact identifier; quote it"), i, field, k), call. = FALSE)
  }
  format(x, scientific = FALSE, trim = TRUE)
}

# The keywords or references of record `i` (0-based) as a character vector, in
# file order. A sequence gives its entries, an absent or null field none, and
# any other value is a one-entry list (keywords: arousal). A mapping is refused.
.tf_values <- function(record, i, field) {
  v <- record[[field]]
  if (is.null(v)) return(character(0))
  if (.tf_is_mapping(v)) stop(.tf_not_strings(i, field), call. = FALSE)
  entries <- if (is.list(v)) v else as.list(v)
  out <- character(length(entries))
  keep <- logical(length(entries))
  for (k in seq_along(entries)) {
    s <- .tf_entry(entries[[k]], i, field, k - 1L)
    if (!is.null(s)) {
      out[[k]] <- s
      keep[[k]] <- TRUE
    }
  }
  out[keep]
}

# Each record's keywords and references, every entry checked, mirroring Python
# lit._records. The corpus must hold a records sequence (an unnamed list, empty
# or not) of mappings; a named list is a mapping, as it is when read from a file.
.tf_records <- function(corpus) {
  recs <- if (.tf_is_mapping(corpus)) corpus[["records"]] else NULL
  if (!is.list(recs) || .tf_is_mapping(recs)) {
    stop("invalid corpus: missing records list", call. = FALSE)
  }
  lapply(seq_along(recs), function(n) {
    r <- recs[[n]]
    i <- n - 1L
    if (!.tf_is_mapping(r)) {
      stop(sprintf("invalid corpus: record[%d] is not a mapping", i), call. = FALSE)
    }
    list(keywords = .tf_values(r, i, "keywords"), references = .tf_values(r, i, "references"))
  })
}

# Count every unordered pair (a < b) of each record's sorted unique values.
# Pairs are generated a record at a time, keyed once and counted once at the
# end, which is linear in the number of pairs. Matching each new key against
# the keys seen so far, as this did, made the count quadratic: a record with 300
# references took about a minute and a fetched corpus hours. The order of the
# result is irrelevant, since .tf_edges() sorts it.
.tf_pair_counts <- function(values) {
  a_all <- vector("list", length(values))
  b_all <- vector("list", length(values))
  for (r in seq_along(values)) {
    vals <- sort(unique(values[[r]]), method = "radix")
    n <- length(vals)
    if (n < 2L) next
    # The pairs (i, j), i < j, in the order utils::combn(n, 2) lists them.
    # combn() builds them one at a time in R code, which made it most of the
    # cost of a record with hundreds of references.
    a_all[[r]] <- vals[rep.int(seq_len(n - 1L), (n - 1L):1L)]
    b_all[[r]] <- vals[sequence((n - 1L):1L, from = 2:n)]
  }
  a <- unlist(a_all, use.names = FALSE)
  b <- unlist(b_all, use.names = FALSE)
  if (length(a) == 0L) return(list(a = character(0), b = character(0), count = integer(0)))
  # The unit separator cannot occur in a keyword or an identifier, so a key
  # stands for exactly one pair.
  key <- paste0(a, "\037", b)
  first <- !duplicated(key)
  list(a = a[first], b = b[first],
       count = tabulate(match(key, key[first]), nbins = sum(first)))
}

# Build the row-set [{a, b, count}] for pairs with count >= min_link, sorted by
# (a, b) ascending. Returns an unnamed list of length-3 named lists so that
# jsonlite serialises it as a JSON array of objects (each count an integer).
.tf_edges <- function(pc, min_link) {
  keep <- which(pc$count >= min_link)
  if (length(keep) == 0L) return(list())
  a <- pc$a[keep]
  b <- pc$b[keep]
  cnt <- pc$count[keep]
  ord <- order(a, b, method = "radix")
  a <- a[ord]; b <- b[ord]; cnt <- cnt[ord]
  lapply(seq_along(a), function(i) {
    list(a = a[[i]], b = b[[i]], count = as.integer(cnt[[i]]))
  })
}

# Connected components (deterministic union-find) over keyword co-occurrence
# edges. Each component's keywords are sorted ascending; components are ordered
# by their smallest keyword; ids are theme_1, theme_2, ... in that order.
.tf_components <- function(edges) {
  parent <- new.env(parent = emptyenv())
  find <- function(x) {
    if (is.null(parent[[x]])) parent[[x]] <- x
    while (!identical(parent[[x]], x)) {
      parent[[x]] <- parent[[parent[[x]]]]
      x <- parent[[x]]
    }
    x
  }
  do_union <- function(x, y) {
    parent[[find(x)]] <- find(y)
  }
  # Track insertion order of nodes so the grouping is deterministic.
  nodes <- character(0)
  for (e in edges) {
    a <- e$a; b <- e$b
    if (is.null(parent[[a]])) { parent[[a]] <- a; nodes <- c(nodes, a) }
    if (is.null(parent[[b]])) { parent[[b]] <- b; nodes <- c(nodes, b) }
    do_union(a, b)
  }
  groups <- list()
  roots <- character(0)
  for (node in nodes) {
    root <- find(node)
    idx <- match(root, roots)
    if (is.na(idx)) {
      roots <- c(roots, root)
      groups[[length(groups) + 1L]] <- node
    } else {
      groups[[idx]] <- c(groups[[idx]], node)
    }
  }
  comps <- lapply(groups, function(members) sort(unique(members), method = "radix"))
  if (length(comps) == 0L) return(list())
  smallest <- vapply(comps, function(kws) kws[[1L]], character(1))
  comps <- comps[order(smallest, method = "radix")]
  lapply(seq_along(comps), function(i) {
    kws <- comps[[i]]
    list(id = paste0("theme_", i), keywords = as.list(kws), size = length(kws))
  })
}

.tf_METHODS <- c("components", "simple_centres")

.tf_method <- function(value) {
  if (!is.character(value) || length(value) != 1L || is.na(value) ||
      !(value %in% .tf_METHODS)) {
    stop("litmap requires method to be 'components' or 'simple_centres'", call. = FALSE)
  }
  value
}

# tf_litmap()'s arguments checked in signature order, as Python lit._settings
# (API_SPEC.md section 14). The theme sizes and max_df are checked whichever
# method is asked for, although only simple centres reads them.
.tf_settings <- function(min_link, method, min_cocitation, min_theme_size, max_theme_size,
                         max_df) {
  min_link <- .tf_positive_int(min_link, "min_link")
  method <- .tf_method(method)
  min_cocitation <- if (is.null(min_cocitation)) min_link else
    .tf_positive_int(min_cocitation, "min_cocitation")
  min_theme_size <- .tf_positive_int(min_theme_size, "min_theme_size")
  ok <- is.numeric(max_theme_size) && length(max_theme_size) == 1L &&
    is.finite(max_theme_size) && max_theme_size == trunc(max_theme_size) && max_theme_size >= 2
  if (!ok) stop("max_theme_size must be an integer of at least 2", call. = FALSE)
  max_theme_size <- if (max_theme_size <= .Machine$integer.max) as.integer(max_theme_size) else
    as.numeric(max_theme_size)
  if (min_theme_size > max_theme_size) {
    stop("min_theme_size must not exceed max_theme_size", call. = FALSE)
  }
  max_df <- .tf_share(max_df, "max_df")
  list(method = method, min_link = min_link, min_cocitation = min_cocitation,
       min_theme_size = min_theme_size, max_theme_size = max_theme_size, max_df = max_df)
}

# The median of `values`, the mean of the middle two for an even count.
.tf_median <- function(values) {
  v <- sort(values)
  mid <- length(v) %/% 2L
  if (length(v) %% 2L == 1L) v[[mid + 1L]] else (v[[mid]] + v[[mid + 1L]]) / 2
}

# Co-word themes by simple centres (Coulter et al., 1998; Cobo et al., 2011),
# as Python lit._simple_centres: the field terms, the keyword edges over the
# other keywords and the themes, each with its centrality, density and
# quadrant. Every rule, tie-break and summation order is pinned in API_SPEC.md
# section 14, so that the two twins compute the same floats. Sums are added one
# term at a time, since sum() accumulates in extended precision.
.tf_simple_centres <- function(keyword_lists, s) {
  sets <- lapply(keyword_lists, function(k) sort(unique(k), method = "radix"))
  n <- length(sets)
  all_kw <- unlist(sets, use.names = FALSE)
  if (length(all_kw) == 0L) return(list(field_terms = list(), edges = list(), themes = list()))
  kws <- unique(all_kw)
  df <- tabulate(match(all_kw, kws), nbins = length(kws))
  field <- sort(kws[df / n > s$max_df], method = "radix")
  rest <- lapply(sets, function(k) k[!(k %in% field)])
  edges <- .tf_edges(.tf_pair_counts(rest), s$min_link)
  themes <- list()
  if (length(edges) > 0L) {
    a <- vapply(edges, function(x) x$a, character(1))
    b <- vapply(edges, function(x) x$b, character(1))
    cnt <- vapply(edges, function(x) as.numeric(x$count), numeric(1))
    # The equivalence index from the integer counts, in one division. Doubles
    # hold these products exactly, and an integer product could overflow.
    e <- (cnt * cnt) / (as.numeric(df[match(a, kws)]) * as.numeric(df[match(b, kws)]))
    nb_to <- split(c(b, a), c(a, b))
    nb_e <- split(c(e, e), c(a, b))
    linked <- names(nb_to)
    assigned <- stats::setNames(logical(length(linked)), linked)

    # Pass 1: the strongest link whose ends are both free seeds a theme, which
    # takes the free neighbour of a member with the strongest link, the smaller
    # keyword on a tie, until it reaches max_theme_size or has no free
    # neighbour.
    groups <- list()
    for (i in order(-e, a, b, method = "radix")) {
      if (assigned[[a[[i]]]] || assigned[[b[[i]]]]) next
      members <- c(a[[i]], b[[i]])
      while (length(members) < s$max_theme_size) {
        cand_h <- character(0)
        cand_e <- numeric(0)
        for (m in members) {
          h <- nb_to[[m]]
          keep <- !(h %in% members) & !assigned[h]
          cand_h <- c(cand_h, h[keep])
          cand_e <- c(cand_e, nb_e[[m]][keep])
        }
        if (length(cand_h) == 0L) break
        members <- c(members, cand_h[[order(-cand_e, cand_h, method = "radix")[[1L]]]])
      }
      assigned[members] <- TRUE
      if (length(members) >= s$min_theme_size) {
        groups[[length(groups) + 1L]] <- sort(members, method = "radix")
      }
    }
    if (length(groups) > 0L) {
      groups <- groups[order(vapply(groups, function(g) g[[1L]], character(1)), method = "radix")]
    }

    # Pass 2: centrality sums the links from the theme to the keywords of other
    # themes, density the links inside it, each added one at a time over the
    # sorted keywords. A link to a keyword in no theme counts for neither,
    # since Cobo et al. (2011) define centrality over the links to other themes.
    theme_kw <- unlist(groups, use.names = FALSE)
    theme_of <- rep(seq_along(groups), lengths(groups))
    themes <- lapply(seq_along(groups), function(i) {
      g <- groups[[i]]
      external <- 0
      internal <- 0
      for (j in seq_along(g)) {
        h <- nb_to[[g[[j]]]]
        eh <- nb_e[[g[[j]]]]
        o <- order(h, method = "radix")
        h <- h[o]
        eh <- eh[o]
        for (k in seq_along(h)) {
          t_h <- theme_of[match(h[[k]], theme_kw)]
          if (!is.na(t_h) && t_h != i) external <- external + eh[[k]]
        }
        for (other in g[seq_along(g) > j]) {
          k <- match(other, h)
          if (!is.na(k)) internal <- internal + eh[[k]]
        }
      }
      list(id = paste0("theme_", i), keywords = as.list(g), size = length(g),
           centrality = .tf_rnd(10 * external, 6),
           density = .tf_rnd(100 * internal / length(g), 6))
    })
    # The strategic diagram of Cobo et al. (2011), each axis split here at its
    # median, a value at the median counting as high.
    if (length(themes) > 0L) {
      c_med <- .tf_median(vapply(themes, function(th) th$centrality, numeric(1)))
      d_med <- .tf_median(vapply(themes, function(th) th$density, numeric(1)))
      for (i in seq_along(themes)) {
        high_c <- themes[[i]]$centrality >= c_med
        high_d <- themes[[i]]$density >= d_med
        themes[[i]]$quadrant <- if (high_c) {
          if (high_d) "motor" else "basic"
        } else {
          if (high_d) "niche" else "emerging_or_declining"
        }
      }
    }
  }
  list(field_terms = as.list(field), edges = edges, themes = themes)
}

# tf_litmap() with its settings `s` checked, the co-citation count skipped when
# `co_citation` is FALSE. tf_landscape() reads only the themes, and on a corpus
# with references the co-citation count is most of the work. It also passes the
# `records` it has already checked, since it reads their keywords as well.
.tf_litmap <- function(corpus, s, co_citation = TRUE, records = NULL) {
  if (is.null(records)) records <- .tf_records(corpus)
  keywords <- lapply(records, `[[`, "keywords")
  all_kw <- sort(unique(as.character(unlist(keywords, use.names = FALSE))), method = "radix")
  simple <- identical(s$method, "simple_centres")
  if (simple) {
    sc <- .tf_simple_centres(keywords, s)
    kw_edges <- sc$edges
    themes <- sc$themes
  } else {
    kw_edges <- .tf_edges(.tf_pair_counts(keywords), s$min_link)
    themes <- .tf_components(kw_edges)
  }
  out <- list(
    n_records = length(records),
    keywords = as.list(all_kw),
    keyword_cooccurrence = kw_edges,
    themes = themes
  )
  if (co_citation) {
    references <- lapply(records, `[[`, "references")
    out$co_citation <- .tf_edges(.tf_pair_counts(references), s$min_cocitation)
  }
  if (simple) {
    out$method <- s$method
    out$parameters <- s[c("min_link", "min_cocitation", "min_theme_size", "max_theme_size",
                          "max_df")]
    out$field_terms <- sc$field_terms
  }
  out
}

# Warn when the largest theme holds more than half the linked keywords, as
# Python lit._warn_if_one_theme_dominates. Connected components merge every
# theme that shares a keyword, so the hub keywords of a real corpus join it
# into one theme (API_SPEC.md section 14). The call is left out, so that the
# text is the Python twin's.
.tf_warn_if_one_theme_dominates <- function(themes) {
  if (length(themes) == 0L) return(invisible(NULL))
  sizes <- vapply(themes, function(th) as.integer(th$size), integer(1))
  n <- sum(sizes)
  largest <- max(sizes)
  if (2L * largest <= n) return(invisible(NULL))
  p <- .tf_rnd(100 * (largest / n), 1)
  warning(sprintf(paste("litmap: one theme holds %.1f per cent of the %d linked keywords;",
                        "connected components cannot separate themes in a corpus this",
                        "connected, so the themes and any landscape built on them are not",
                        "informative (method 'simple_centres' gives bounded themes)"), p, n),
          call. = FALSE)
}

#' Bibliometric map of a literature corpus (deterministic)
#'
#' Computes keyword co-occurrence, thematic components, and reference
#' co-citation for a corpus. Records iterate in file order.
#'
#' The corpus is checked before anything is counted, with the Python twin's
#' messages. It must hold a \code{records} list of mappings (an empty list is
#' an empty corpus). A keyword or reference that is an integer becomes its
#' decimal string, so an unquoted PubMed or Scopus id keys the same work in
#' both languages; one of \eqn{2^{53}} or more is refused, since R cannot hold
#' it exactly. A logical, a fraction or a nested value is refused: an unquoted
#' \code{NO} (nitric oxide) or \code{on} in YAML is read as a logical, so quote
#' it.
#'
#' Co-citation maps of real corpora are large. 200 OpenAlex records give about
#' 11,000 reference pairs that share two or more citing records, so
#' \code{min_cocitation} can be set above \code{min_link}, and
#' [tf_lit_diagram()] can draw only the strongest edges.
#'
#' \code{method} chooses how keywords are grouped into themes. With
#' \code{"components"}, the default, a theme is a connected component of the
#' keyword map, and on a real corpus a few keywords shared by most records join
#' nearly every keyword into one. When the largest theme holds more than half
#' the linked keywords, a warning says so: such themes, and any landscape built
#' on them, do not describe the field. The result is returned unchanged.
#'
#' \code{"simple_centres"} is the co-word clustering of Coulter et al. (1998)
#' and Cobo et al. (2011). Each link is weighted by the equivalence index
#' \eqn{c^2 / (df_a df_b)}, where \eqn{c} counts the records holding both
#' keywords and \eqn{df} the records holding each. The strongest link between
#' two unassigned keywords seeds a theme, which takes its strongest unassigned
#' neighbour until it holds \code{max_theme_size} keywords, ties going to the
#' keyword first in code-point order. A keyword whose links all reach keywords
#' already in themes joins none. Themes smaller than \code{min_theme_size} are
#' dropped. Each theme gains its centrality (ten times the summed index of its
#' links to the keywords of other themes) and its density (100 times the
#' summed index of its internal links, over its size), the measures
#' of Callon et al. (1991) as Cobo et al. (2011) scale them. It also gains its
#' quadrant in the strategic diagram, split here at the median of each:
#' \code{"motor"} (both high), \code{"basic"} (central but not dense),
#' \code{"niche"} (dense but not central) or \code{"emerging_or_declining"}
#' (both low). On real corpora, this gives bounded themes where components give
#' one. Components remain the default for this release.
#'
#' @param corpus A corpus object (named list), e.g. from [tf_read_corpus()].
#' @param min_link Minimum co-occurrence count for a keyword pair to be kept
#'   (default \code{2}). A positive integer.
#' @param method \code{"components"} (the default) or \code{"simple_centres"}.
#' @param min_cocitation Minimum count for a reference pair to be kept in
#'   \code{co_citation}. \code{NULL} (the default) uses \code{min_link}.
#' @param min_theme_size,max_theme_size The smallest theme kept (default
#'   \code{2}) and the largest a theme may grow (default \code{10}) with
#'   \code{"simple_centres"}. A positive integer, and an integer of at least 2
#'   no smaller than \code{min_theme_size}.
#' @param max_df A number from 0 to 1 (default \code{1}). With
#'   \code{"simple_centres"}, a keyword in more than this share of the records
#'   is a field term, left out of the map and listed in \code{field_terms}.
#'   The three theme settings are checked with either method, although only
#'   \code{"simple_centres"} reads them.
#' @return A named list with elements \code{n_records}, \code{keywords},
#'   \code{keyword_cooccurrence}, \code{themes}, and \code{co_citation}. With
#'   \code{"simple_centres"}, each theme also holds \code{centrality},
#'   \code{density} and \code{quadrant}, and the list ends with
#'   \code{method}, \code{parameters} (the five settings used) and
#'   \code{field_terms}.
#' @references
#' Callon, M., Courtial, J. P., & Laville, F. (1991). Co-word analysis as a
#' tool for describing the network of interactions between basic and
#' technological research: The case of polymer chemistry. \emph{Scientometrics,
#' 22}(1), 155-205. \doi{10.1007/BF02019280}
#'
#' Coulter, N., Monarch, I., & Konda, S. (1998). Software engineering as seen
#' through its research literature: A study in co-word analysis. \emph{Journal
#' of the American Society for Information Science, 49}(13), 1206-1223.
#'
#' Cobo, M. J., López-Herrera, A. G., Herrera-Viedma, E., & Herrera, F.
#' (2011). An approach for detecting, quantifying, and visualizing the
#' evolution of a research field: A practical application to the Fuzzy Sets
#' Theory field. \emph{Journal of Informetrics, 5}(1), 146-166.
#' \doi{10.1016/j.joi.2010.10.002}
#' @examples
#' corpus <- list(
#'   schema_version = "1.0", id = "demo-corpus",
#'   records = list(
#'     list(id = "w1", keywords = list("arousal", "threat")),
#'     list(id = "w2", keywords = list("arousal", "threat")),
#'     list(id = "w3", keywords = list("avoidance", "exposure")),
#'     list(id = "w4", keywords = list("avoidance", "exposure"))
#'   )
#' )
#' tf_litmap(corpus)
#'
#' # Simple centres on the frozen OpenAlex corpus, where components give one
#' # theme.
#' openalex <- tf_read_corpus(tf_example_path("openalex-panic-2026.corpus.yaml"))
#' lm <- tf_litmap(openalex, method = "simple_centres")
#' table(vapply(lm$themes, function(th) th$quadrant, character(1)))
#' @export
tf_litmap <- function(corpus, min_link = 2, method = "components", min_cocitation = NULL,
                      min_theme_size = 2, max_theme_size = 10, max_df = 1) {
  s <- .tf_settings(min_link, method, min_cocitation, min_theme_size, max_theme_size, max_df)
  out <- .tf_litmap(corpus, s)
  if (identical(s$method, "components")) .tf_warn_if_one_theme_dominates(out$themes)
  out
}

# Tokens of more than `max_token_share` of the records' keywords, as Python
# lit._field_tokens. A record counts once for each token of its keywords, and
# the share is taken over every record, those without keywords included.
.tf_field_tokens <- function(keyword_lists, max_token_share) {
  n <- length(keyword_lists)
  toks <- unlist(lapply(keyword_lists, function(kws) tf_tokens(paste(kws, collapse = " "))),
                 use.names = FALSE)
  if (length(toks) == 0L) return(character(0))
  # tf_tokens() returns each record's tokens once, so a count is a number of
  # records.
  u <- unique(toks)
  counts <- tabulate(match(toks, u), nbins = length(u))
  u[counts / n > max_token_share]
}

#' Map a theory and its alternatives onto a literature landscape (deterministic)
#'
#' Maps a theory's focal constructs and its registered alternatives onto the
#' thematic structure of a corpus (computed by [tf_litmap()]). Each theme is
#' tagged \code{"under_theorised"}, \code{"covered"}, or \code{"crowded"}.
#'
#' A theme is matched by the words its keywords share with the focal theory's
#' construct labels, or with an alternative's label and key constructs, and
#' every match reports those words (\code{focal_terms} and
#' \code{alternative_terms}). Three kinds of word never match. Field tokens,
#' the words most of the corpus shares, are those in the keywords of more than
#' \code{max_token_share} of the records. Phenomenon tokens are the words of
#' the theory's title, which names the phenomenon that the focal theory and its
#' rivals all explain. A construct word that also appears in the title does not
#' match either. The third kind is a fixed list of words that name a kind of
#' account: theory, model, account, hypothesis, framework and approach, with
#' their plurals. One shared word is enough for a match.
#'
#' The statuses count the registered accounts, the focal theory and its
#' registered alternatives, that address a theme. A theme is
#' \code{"under_theorised"} when none of them addresses it, which says nothing
#' of accounts the theory does not register, \code{"covered"} when one does and
#' \code{"crowded"} when two or more do. A crowded theme calls for predictions
#' that discriminate between the accounts, and is not a finding of redundancy.
#' The two lists keep their 0.6.0 names, \code{under_theorised_fronts} and
#' \code{redundancy_risk}.
#'
#' The arguments are checked in the order \code{min_link},
#' \code{max_token_share}, \code{method}, then the corpus, with the Python
#' twin's messages. The themes are those of [tf_litmap()], built by
#' \code{method} with its other defaults. With \code{"components"},
#' \code{tf_landscape()} gives the warning of [tf_litmap()] when one theme
#' holds most of the linked keywords. With \code{"simple_centres"}, the result
#' gains \code{method} after \code{theory_id}, and each theme its
#' \code{centrality}, \code{density} and \code{quadrant}.
#'
#' @param theory A theory object (named list), e.g. from \code{tf_read()}.
#' @param corpus A corpus object (named list), e.g. from [tf_read_corpus()].
#' @param min_link Minimum co-occurrence count passed to [tf_litmap()]
#'   (default \code{2}). The co-citation map, which the landscape does not
#'   use, is not computed.
#' @param max_token_share A number from 0 to 1 (default \code{0.5}). A word in
#'   the keywords of more than this share of the records is a field token and
#'   never matches.
#' @param method How [tf_litmap()] builds the themes: \code{"components"}
#'   (the default) or \code{"simple_centres"}.
#' @return A named list with elements \code{theory_id},
#'   \code{max_token_share}, \code{field_tokens}, \code{phenomenon_tokens},
#'   \code{themes}, \code{under_theorised_fronts} and \code{redundancy_risk}.
#'   Each theme holds \code{id}, \code{keywords}, \code{alternatives},
#'   \code{focal}, \code{status}, \code{focal_terms} and
#'   \code{alternative_terms}, the last a list of \code{{id, terms}} in the
#'   order of \code{alternatives}.
#' @examples
#' theory <- tf_theory("demo-1", "A theory of panic") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
#' corpus <- list(
#'   schema_version = "1.0", id = "demo-corpus",
#'   records = list(
#'     list(id = "w1", keywords = list("arousal", "threat")),
#'     list(id = "w2", keywords = list("arousal", "threat")),
#'     list(id = "w3", keywords = list("avoidance", "exposure")),
#'     list(id = "w4", keywords = list("avoidance", "exposure"))
#'   )
#' )
#' tf_landscape(theory, corpus)
#' @export
tf_landscape <- function(theory, corpus, min_link = 2, max_token_share = 0.5,
                         method = "components") {
  T <- theory
  min_link <- .tf_positive_int(min_link, "min_link")
  max_token_share <- .tf_share(max_token_share, "max_token_share")
  s <- .tf_settings(min_link, method, NULL, 2, 10, 1)
  simple <- identical(s$method, "simple_centres")
  records <- .tf_records(corpus)
  lm <- .tf_litmap(corpus, s, co_citation = FALSE, records = records)
  if (!simple) .tf_warn_if_one_theme_dominates(lm$themes)

  field_tokens <- .tf_field_tokens(lapply(records, `[[`, "keywords"), max_token_share)
  phenomenon_tokens <- tf_tokens(.tf_str(T, "title"))
  excluded <- c(phenomenon_tokens, .tf_THEORY_WORDS)
  cons <- .tf_list(T, "constructs")
  con_labels <- vapply(cons, function(c) .tf_str(c, "label"), character(1))
  focal_tokens <- setdiff(tf_tokens(paste(con_labels, collapse = " ")), excluded)
  alts <- .tf_list(T, "alternatives")
  alt_ids <- vapply(alts, function(a) .tf_str(a, "id"), character(1))
  alt_tokens <- lapply(alts, function(a) {
    kc <- .tf_str_list(.tf_get(a, "key_constructs"))
    setdiff(tf_tokens(paste(c(.tf_str(a, "label"), kc), collapse = " ")), excluded)
  })
  # Sorted by id once, stably, so a repeated id keeps its file order.
  by_id <- order(alt_ids, method = "radix")

  themes_out <- list()
  under <- character(0)
  crowded <- character(0)
  for (th in lm$themes) {
    kws <- unlist(th$keywords, use.names = FALSE)
    th_tokens <- setdiff(tf_tokens(paste(kws, collapse = " ")),
                         c(field_tokens, .tf_THEORY_WORDS))
    focal_terms <- sort(intersect(focal_tokens, th_tokens), method = "radix")
    alt_terms <- list()
    for (k in by_id) {
      terms <- sort(intersect(alt_tokens[[k]], th_tokens), method = "radix")
      if (length(terms) > 0L) {
        alt_terms[[length(alt_terms) + 1L]] <- list(id = alt_ids[[k]], terms = as.list(terms))
      }
    }
    on <- vapply(alt_terms, function(a) a$id, character(1))
    focal_on <- length(focal_terms) > 0L
    n <- length(on) + (if (focal_on) 1L else 0L)
    status <- if (n == 0L) "under_theorised" else if (n >= 2L) "crowded" else "covered"
    theme <- list(
      id = th$id,
      keywords = as.list(kws),
      alternatives = as.list(on),
      focal = focal_on,
      status = status,
      focal_terms = as.list(focal_terms),
      alternative_terms = alt_terms
    )
    if (simple) theme <- c(theme, th[c("centrality", "density", "quadrant")])
    themes_out[[length(themes_out) + 1L]] <- theme
    if (identical(status, "under_theorised")) {
      under <- c(under, th$id)
    } else if (identical(status, "crowded")) {
      crowded <- c(crowded, th$id)
    }
  }

  c(
    list(theory_id = .tf_str(T, "id")),
    if (simple) list(method = s$method),
    list(
      max_token_share = max_token_share,
      field_tokens = as.list(sort(field_tokens, method = "radix")),
      phenomenon_tokens = as.list(sort(phenomenon_tokens, method = "radix")),
      themes = themes_out,
      under_theorised_fronts = as.list(under),
      redundancy_risk = as.list(crowded)
    )
  )
}

# Undirected diagram (keyword_cooccurrence / co_citation). Nodes = endpoints
# appearing in the edge list (sorted), edges in list order; edge label = integer
# count rendered with as.character(as.integer(.)).
# The lines are built as whole vectors: appending one line at a time copied the
# vector on every edge, which on a co-citation map of 200,000 edges took
# minutes.
.tf_lit_undirected <- function(name, edges) {
  # Nodes are sorted as written and escaped afterwards, as in Python.
  raw <- function(key) {
    vapply(edges, function(e) .tf_lit_text(e[[key]]), character(1), USE.NAMES = FALSE)
  }
  a <- raw("a")
  b <- raw("b")
  count <- vapply(edges, function(e) as.character(as.integer(e$count)), character(1),
                  USE.NAMES = FALSE)
  nodes <- sort(unique(c(rbind(a, b))), method = "radix")
  esc <- .tf_lit_esc_all
  role <- if (identical(name, "keyword_cooccurrence")) "construct" else "prediction"
  lines <- c(.tf_prelude(name, "LR", directed = FALSE),
             sprintf('  node [shape=ellipse, style="filled", %s];', .tf_fill(role)),
             sprintf('  "%s";', esc(nodes)),
             sprintf('  "%s" -- "%s" [label="%s"];', esc(a), esc(b), count),
             "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

# The `max_edges` edges with the highest counts, ties to the earlier (a, b),
# returned in (a, b) order, as Python lit._strongest.
.tf_strongest <- function(edges, max_edges) {
  a <- vapply(edges, function(e) as.character(e$a), character(1))
  b <- vapply(edges, function(e) as.character(e$b), character(1))
  count <- vapply(edges, function(e) as.numeric(e$count), numeric(1))
  kept <- order(-count, a, b, method = "radix")[seq_len(max_edges)]
  edges[kept[order(a[kept], b[kept], method = "radix")]]
}

# Theme colours track the landscape statuses: a theme no registered account
# addresses is teal, one that two or more address is amber and a covered one
# grey.
.tf_THEME_ROLE <- c(under_theorised = "construct", crowded = "proposition",
                    covered = "covered")

# theme_landscape diagram from a landscape() result.
.tf_lit_theme_landscape <- function(ls) {
  lines <- .tf_prelude("theme_landscape", "LR")
  for (th in ls$themes) {
    kws <- unlist(th$keywords, use.names = FALSE)
    label <- paste0(.tf_lit_esc(th$id), "\\n",
                    .tf_wrap(paste(kws, collapse = ", "), 24L),
                    "\\n(", th$status, ")")
    lines <- c(lines, sprintf('  "%s" [label="%s", %s];',
                              .tf_lit_esc(th$id), label,
                              .tf_fill(.tf_THEME_ROLE[[th$status]])))
  }
  # Collect alternatives in first-seen order across themes.
  alt_ids <- character(0)
  for (th in ls$themes) {
    for (a in unlist(th$alternatives, use.names = FALSE)) {
      if (!(a %in% alt_ids)) alt_ids <- c(alt_ids, a)
    }
  }
  for (a in alt_ids) {
    lines <- c(lines, sprintf('  "%s" [label="%s", shape=ellipse, %s];',
                              .tf_lit_esc(a), .tf_wrap(a), .tf_fill("rival")))
  }
  lines <- c(lines, sprintf('  "focal" [label="focal", shape=ellipse, fillcolor="%s", color="%s", fontcolor="#FFFFFF"];',
                            .tf_INK, .tf_INK))
  for (a in alt_ids) {
    for (th in ls$themes) {
      th_alts <- unlist(th$alternatives, use.names = FALSE)
      if (a %in% th_alts) {
        lines <- c(lines, sprintf('  "%s" -> "%s";', .tf_lit_esc(a), .tf_lit_esc(th$id)))
      }
    }
  }
  for (th in ls$themes) {
    if (isTRUE(th$focal)) {
      lines <- c(lines, sprintf('  "focal" -> "%s";', .tf_lit_esc(th$id)))
    }
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

#' Render a literature-layer diagram intermediate representation
#'
#' Produces a deterministic DOT string for the literature layer.
#'
#' @param obj A [tf_litmap()] result (for \code{"keyword_cooccurrence"} /
#'   \code{"co_citation"}) or a [tf_landscape()] result (for
#'   \code{"theme_landscape"}).
#' @param type One of \code{"keyword_cooccurrence"} (default),
#'   \code{"co_citation"}, or \code{"theme_landscape"}.
#' @param max_edges A positive integer that caps a
#'   \code{"keyword_cooccurrence"} or \code{"co_citation"} diagram at that many
#'   edges: the highest counts are kept, ties going to the earlier pair in
#'   \code{(a, b)} order, and only their endpoints are drawn. \code{NULL} (the
#'   default) draws every edge. \code{"theme_landscape"} ignores it.
#' @return A single string ending in a newline.
#' @examples
#' corpus <- list(
#'   schema_version = "1.0", id = "demo-corpus",
#'   records = list(
#'     list(id = "w1", keywords = list("arousal", "threat")),
#'     list(id = "w2", keywords = list("arousal", "threat")),
#'     list(id = "w3", keywords = list("avoidance", "exposure")),
#'     list(id = "w4", keywords = list("avoidance", "exposure"))
#'   )
#' )
#' cat(tf_lit_diagram(tf_litmap(corpus), "keyword_cooccurrence"))
#'
#' # On a large map, draw only the strongest edges.
#' fixture <- tf_read_corpus(system.file("fixtures", "panic-corpus.yaml",
#'                                       package = "theoryforge"))
#' cat(tf_lit_diagram(tf_litmap(fixture), "co_citation", max_edges = 1))
#' @export
tf_lit_diagram <- function(obj, type = "keyword_cooccurrence", max_edges = NULL) {
  if (!is.null(max_edges)) max_edges <- .tf_positive_int(max_edges, "max_edges")
  if (type %in% c("keyword_cooccurrence", "co_citation")) {
    edges <- obj[[type]]
    if (is.null(edges)) edges <- list()
    if (!is.null(max_edges) && length(edges) > max_edges) {
      edges <- .tf_strongest(edges, max_edges)
    }
    return(.tf_lit_undirected(type, edges))
  }
  if (identical(type, "theme_landscape")) {
    return(.tf_lit_theme_landscape(obj))
  }
  stop(sprintf("unknown lit diagram type '%s'; expected one of %s",
               type,
               "keyword_cooccurrence, co_citation, theme_landscape"),
       call. = FALSE)
}

#' DOIs not already cited by a theory (deterministic)
#'
#' Compares each DOI in \code{candidate_dois} against the theory's
#' \code{evidence[].source_doi} and \code{alternatives[].source_doi} fields, by
#' normalised form, so a fresh literature search, for example via OpenAlex,
#' Scopus, or any other source, can be checked against what the theory already
#' engages with. The normalised form is the DOI itself, trimmed, lowercased
#' (ASCII letters only) and percent-decoded, wherever it sits in the text, so
#' \code{doi: 10...}, \code{DOI 10...}, \code{doi.org/10...},
#' \code{https://www.doi.org/10...} and a URL with \code{\%2F} all match the
#' bare DOI, and trailing full stops, commas and semicolons are dropped.
#' Returns the qualifying DOIs in their original form, deduplicated and sorted
#' by normalised form. Deterministic and takes no network dependency:
#' the search itself is left to whichever literature tool the caller prefers.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param candidate_dois Character vector of DOIs to check.
#' @return A character vector of the candidate DOIs not already cited,
#'   deduplicated and sorted.
#' @examples
#' # The bundled panic theory cites one DOI as evidence and one for each of its
#' # two registered alternatives. All three count as already cited.
#' theory <- tf_read(system.file("fixtures", "panic-network.theory.yaml",
#'                               package = "theoryforge"))
#' tf_new_evidence_dois(theory, c(
#'   "10.1016/j.brat.2015.10.002",                   # cited as evidence
#'   "https://doi.org/10.1016/0005-7967(86)90011-2", # an alternative, in URL form
#'   "https://doi.org/10.1037/0033-2909.99.1.20"     # not yet cited
#' ))
#' @export
tf_new_evidence_dois <- function(theory, candidate_dois) {
  known <- character(0)
  for (key in c("evidence", "alternatives")) {
    for (entry in .tf_list(theory, key)) {
      doi <- .tf_str(entry, "source_doi")
      if (nzchar(doi)) known <- c(known, .tf_normalize_doi(doi))
    }
  }
  known <- unique(known)

  seen <- character(0)
  out <- character(0)
  for (doi in candidate_dois) {
    if (is.null(doi) || is.na(doi) || !nzchar(as.character(doi))) next
    norm <- .tf_normalize_doi(doi)
    if (norm %in% known || norm %in% seen) next
    seen <- c(seen, norm)
    out <- c(out, as.character(doi))
  }
  if (length(out) == 0L) return(character(0))
  out[order(vapply(out, .tf_normalize_doi, character(1)), method = "radix")]
}

#' Build a corpus from the OpenAlex API (network call)
#'
#' Assistive helper that builds a corpus by querying the OpenAlex works API
#' (\code{https://api.openalex.org/works?search=...}). This is a network call:
#' it depends on a live external service whose results change over time, so it
#' sits outside the package's deterministic core. Each work is mapped to
#' \code{{id, doi, title, year, keywords, references}}, with the DOI as OpenAlex
#' gives it (keywords falls back to the top concepts when no keywords are
#' present).
#'
#' OpenAlex returns the works that match a search in pages of \code{per_page},
#' ranked by relevance, and a search usually matches far more works than one
#' page holds. A \code{max_records} above \code{per_page} pages on through
#' OpenAlex's cursor until that many works are collected or the results run
#' out. Each page is one request and costs USD 0.001. OpenAlex allows USD 0.10
#' a day without a key, about 100 pages, and USD 1 with a free key. When
#' OpenAlex refuses a request, as it does with HTTP 429 once the budget is
#' spent, the function stops with the status and OpenAlex's own message, and
#' the request is not retried.
#'
#' The corpus records where, when and how it was fetched in \code{source}. It
#' gives the service, endpoint and query and the UTC time of retrieval
#' (\code{retrieved}), then the number of works that matched
#' (\code{total_count}), the number kept (\code{n_records}), the page size and
#' the order (\code{sort}). The date matters because the keywords change.
#' Since late September 2026, OpenAlex has written each work's keywords with a
#' language model that reads its title, abstract and venue. It merges and
#' splits that vocabulary over time. Works without keywords fall back to their
#' concepts, a deprecated vocabulary with capitalised names that do not match
#' the lower-case keywords in [tf_litmap()]. Save a fetched corpus and work
#' from the saved file.
#'
#' @param query Free-text search query.
#' @param per_page Number of works to request in each page (default \code{25}).
#'   It may be 1 to 200, but OpenAlex supports pages of up to 100 and has
#'   deprecated larger ones.
#' @param mailto Optional contact email. It is still sent, but OpenAlex now
#'   ignores it, since API keys replaced the polite pool it once selected.
#' @param api_key An OpenAlex API key, by default the \code{OPENALEX_API_KEY}
#'   environment variable. It is sent only in an \code{Authorization: Bearer}
#'   header, never in the URL, the corpus or an error message. \code{""} or
#'   \code{NULL} sends no key.
#' @param max_records Number of works to collect, paging as needed.
#'   \code{NULL} (the default) means \code{per_page}, which is one request.
#' @return A corpus object (named list) with \code{schema_version}, \code{id},
#'   \code{source} and \code{records}.
#' @examples
#' \dontrun{
#' # With OPENALEX_API_KEY set, for example in .Renviron, the key is sent in a
#' # request header.
#' corpus <- tf_fetch_corpus("panic disorder interoception",
#'                           per_page = 100, max_records = 400)
#' corpus$source
#' # null = "null" writes a missing DOI or count as null, where jsonlite would
#' # write an empty object.
#' path <- tempfile(fileext = ".json")
#' jsonlite::write_json(corpus, path, auto_unbox = TRUE, null = "null")
#' corpus <- tf_read_corpus(path)
#' }
#' @export
tf_fetch_corpus <- function(query, per_page = 25, mailto = NULL,
                            api_key = Sys.getenv("OPENALEX_API_KEY", ""),
                            max_records = NULL) {
  # Reject out-of-range page sizes here rather than passing them through for
  # OpenAlex to reject, and with the same message the Python twin uses.
  if (!is.numeric(per_page) || length(per_page) != 1L || is.na(per_page) ||
      per_page != trunc(per_page) || per_page < 1 || per_page > 200) {
    stop("per_page must be between 1 and 200", call. = FALSE)
  }
  per_page <- as.integer(per_page)
  max_records <- if (is.null(max_records)) per_page else .tf_positive_int(max_records, "max_records")
  key <- .tf_api_key(api_key)
  headers <- if (nzchar(key)) c(Authorization = paste("Bearer", key)) else NULL
  params <- list(search = query, "per-page" = as.character(per_page))
  if (!is.null(mailto)) params[["mailto"]] <- mailto

  # Cursor paging, which OpenAlex serves for a search with no cap on the
  # number of results: "*" asks for the first page, and each page names the
  # cursor of the next. The run ends with enough works, an empty page or no
  # cursor (API_SPEC.md section 17).
  retrieved <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  page <- .tf_openalex_page(c(params, cursor = "*"), headers, key)
  total_count <- .tf_whole_number(.tf_get(page$meta, "count"))
  records <- lapply(page$results, .tf_openalex_record)
  cursor <- .tf_get(page$meta, "next_cursor")
  while (length(records) < max_records && length(page$results) > 0L && .tf_ne_str(cursor)) {
    page <- .tf_openalex_page(c(params, cursor = cursor), headers, key)
    records <- c(records, lapply(page$results, .tf_openalex_record))
    cursor <- .tf_get(page$meta, "next_cursor")
  }
  records <- utils::head(records, max_records)

  list(
    schema_version = "1.0",
    id = paste0("openalex:", query),
    source = list(
      service = "OpenAlex",
      endpoint = .tf_OPENALEX_WORKS,
      query = query,
      retrieved = retrieved,
      total_count = total_count,
      n_records = length(records),
      per_page = per_page,
      # The order OpenAlex gives a search unless told otherwise. The adapter
      # sends no sort, so this records that default.
      sort = "relevance_score:desc"
    ),
    records = records
  )
}

.tf_OPENALEX_WORKS <- "https://api.openalex.org/works"

# The key to send, or "" for none. It travels in a header, so spaces, tabs and
# line breaks around it (a key pasted into .Renviron, say) are trimmed. Any
# other character outside visible ASCII is refused before a request is made,
# because it would break the header and an error about the header could print
# the key.
.tf_api_key <- function(value) {
  msg <- "api_key must be a string of visible ASCII characters"
  if (is.null(value)) return("")
  if (!is.character(value) || length(value) != 1L || is.na(value)) stop(msg, call. = FALSE)
  key <- trimws(value, whitespace = "[ \t\r\n]")
  if (grepl("[^!-~]", key, useBytes = TRUE)) stop(msg, call. = FALSE)
  key
}

# One page of OpenAlex works, list(meta, results), with the HTTP status checked
# and the results list required. `params` are the query parameters in the order
# they are sent.
.tf_openalex_page <- function(params, headers, key) {
  qs <- paste(
    vapply(names(params), function(k) {
      paste0(utils::URLencode(k, reserved = TRUE), "=",
             utils::URLencode(as.character(params[[k]]), reserved = TRUE))
    }, character(1)),
    collapse = "&"
  )
  res <- .tf_http("GET", paste0(.tf_OPENALEX_WORKS, "?", qs), headers)
  body <- res$body
  # A server that repeats the key in an error must not carry it into the message.
  # The replacement works on bytes, so an error page that is not valid UTF-8
  # still gives the status. The key and its stand-in are ASCII, so a valid body
  # stays valid and is marked UTF-8 again.
  if (res$status >= 400 && nzchar(key) && !is.null(body)) {
    body <- gsub(key, "<api_key>", body, fixed = TRUE, useBytes = TRUE)
    Encoding(body) <- "UTF-8"
  }
  .tf_http_check(res$status, body)
  # parse_json(), unlike fromJSON(), never reads a file or downloads a URL that
  # the body names.
  data <- tryCatch(jsonlite::parse_json(body), error = function(e) NULL)
  results <- if (.tf_is_mapping(data)) data[["results"]] else NULL
  # A JSON array is an unnamed list, and `{}` a named one.
  if (!is.list(results) || .tf_is_mapping(results)) {
    stop("OpenAlex response has no results list", call. = FALSE)
  }
  list(meta = data[["meta"]], results = results)
}

# Stop when OpenAlex answered with an HTTP error: "OpenAlex request failed with
# HTTP <status>", followed by ": <message>" when the body is a JSON object whose
# `message`, or failing that `error`, is a nonempty string. `body` is NULL when
# base R's url() could not read it. The Python twin raises OpenAlexHTTPError
# with the same text.
.tf_http_check <- function(status, body) {
  if (status < 400) return(invisible(NULL))
  msg <- sprintf("OpenAlex request failed with HTTP %d", as.integer(status))
  detail <- .tf_json_message(body)
  stop(if (nzchar(detail)) paste0(msg, ": ", detail) else msg, call. = FALSE)
}

# The `message` field of a JSON object, else its `error` field, else "".
.tf_json_message <- function(body) {
  data <- if (is.character(body) && length(body) == 1L) {
    tryCatch(jsonlite::parse_json(body), error = function(e) NULL)
  }
  if (!.tf_is_mapping(data)) return("")
  for (field in c("message", "error")) {
    if (.tf_ne_str(data[[field]])) return(data[[field]])
  }
  ""
}

# `x` when it is one whole number, otherwise NULL.
.tf_whole_number <- function(x) {
  if (is.numeric(x) && length(x) == 1L && is.finite(x) && x == trunc(x)) x else NULL
}

# One OpenAlex work as a corpus record.
.tf_openalex_record <- function(w) {
  kws <- character(0)
  for (k in .tf_as_list(w, "keywords")) {
    dn <- .tf_get(k, "display_name")
    if (!is.null(dn) && nzchar(as.character(dn))) kws <- c(kws, as.character(dn))
  }
  if (length(kws) == 0L) {
    concepts <- .tf_as_list(w, "concepts")
    concepts <- utils::head(concepts, 5L)
    for (cc in concepts) {
      dn <- .tf_get(cc, "display_name")
      if (!is.null(dn) && nzchar(as.character(dn))) kws <- c(kws, as.character(dn))
    }
  }
  refs <- vapply(.tf_as_list(w, "referenced_works"),
                 function(x) as.character(x[[1L]]), character(1))
  list(
    id = .tf_get(w, "id"),
    doi = .tf_get(w, "doi"),
    title = .tf_get(w, "title"),
    year = .tf_get(w, "publication_year"),
    keywords = as.list(kws),
    references = as.list(refs)
  )
}
