#' Bibliometric / literature layer.
#'
#' The analysis (litmap, landscape, diagrams) is fully deterministic given a
#' corpus. The OpenAlex fetch adapter ([tf_fetch_corpus()]) is the assistive
#' layer, whose results depend on a live network service.
#' @name lit
#' @keywords internal
NULL

.tf_DEFAULT_MIN_LINK <- 2L

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

# tf_litmap(), with the co-citation count skipped when `co_citation` is FALSE.
# tf_landscape() reads only the themes, and on a corpus with references the
# co-citation count is most of the work.
.tf_litmap <- function(corpus, min_link, min_cocitation = NULL, co_citation = TRUE) {
  min_link <- .tf_positive_int(min_link, "min_link")
  min_cocitation <- if (is.null(min_cocitation)) min_link else
    .tf_positive_int(min_cocitation, "min_cocitation")
  records <- .tf_records(corpus)
  keywords <- lapply(records, `[[`, "keywords")
  all_kw <- sort(unique(as.character(unlist(keywords, use.names = FALSE))), method = "radix")
  kw_edges <- .tf_edges(.tf_pair_counts(keywords), min_link)
  out <- list(
    n_records = length(records),
    keywords = as.list(all_kw),
    keyword_cooccurrence = kw_edges,
    themes = .tf_components(kw_edges)
  )
  if (co_citation) {
    references <- lapply(records, `[[`, "references")
    out$co_citation <- .tf_edges(.tf_pair_counts(references), min_cocitation)
  }
  out
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
#' @param corpus A corpus object (named list), e.g. from [tf_read_corpus()].
#' @param min_link Minimum co-occurrence count for a keyword pair to be kept
#'   (default \code{2}). A positive integer.
#' @param min_cocitation Minimum count for a reference pair to be kept in
#'   \code{co_citation}. \code{NULL} (the default) uses \code{min_link}.
#' @return A named list with elements \code{n_records}, \code{keywords},
#'   \code{keyword_cooccurrence}, \code{themes}, and \code{co_citation}.
#' @examples
#' corpus <- list(
#'   schema_version = "1.0", id = "demo-corpus",
#'   records = list(
#'     list(id = "w1", keywords = list("arousal", "threat")),
#'     list(id = "w2", keywords = list("arousal", "threat"))
#'   )
#' )
#' tf_litmap(corpus)
#' @export
tf_litmap <- function(corpus, min_link = 2, min_cocitation = NULL) {
  .tf_litmap(corpus, min_link, min_cocitation)
}

#' Map a theory and its alternatives onto a literature landscape (deterministic)
#'
#' Maps a theory's focal constructs and its registered alternatives onto the
#' thematic structure of a corpus (computed by [tf_litmap()]). Each theme is
#' tagged \code{"under_theorised"}, \code{"covered"}, or \code{"crowded"}.
#'
#' @param theory A theory object (named list), e.g. from \code{tf_read()}.
#' @param corpus A corpus object (named list), e.g. from [tf_read_corpus()].
#' @param min_link Minimum co-occurrence count passed to [tf_litmap()]
#'   (default \code{2}). The co-citation map, which the landscape does not
#'   use, is not computed.
#' @return A named list with elements \code{theory_id}, \code{themes} (each
#'   \code{{id, keywords, alternatives, focal, status}}),
#'   \code{under_theorised_fronts}, and \code{redundancy_risk}.
#' @examples
#' theory <- tf_theory("demo-1", "Arousal and threat") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
#' corpus <- list(
#'   schema_version = "1.0", id = "demo-corpus",
#'   records = list(
#'     list(id = "w1", keywords = list("arousal", "threat")),
#'     list(id = "w2", keywords = list("arousal", "threat"))
#'   )
#' )
#' tf_landscape(theory, corpus)
#' @export
tf_landscape <- function(theory, corpus, min_link = 2) {
  T <- theory
  lm <- .tf_litmap(corpus, min_link, co_citation = FALSE)

  cons <- .tf_list(T, "constructs")
  con_labels <- vapply(cons, function(c) .tf_str(c, "label"), character(1))
  focal_src <- paste(c(.tf_str(T, "title"), con_labels), collapse = " ")
  focal_tokens <- tf_tokens(focal_src)
  alts <- .tf_list(T, "alternatives")

  themes_out <- list()
  under <- character(0)
  crowded <- character(0)
  for (th in lm$themes) {
    kws <- unlist(th$keywords, use.names = FALSE)
    th_tokens <- tf_tokens(paste(kws, collapse = " "))
    on <- character(0)
    for (a in alts) {
      kc <- .tf_str_list(.tf_get(a, "key_constructs"))
      alt_src <- paste(c(.tf_str(a, "label"), kc), collapse = " ")
      alt_tokens <- tf_tokens(alt_src)
      if (length(intersect(alt_tokens, th_tokens)) > 0L) {
        on <- c(on, .tf_str(a, "id"))
      }
    }
    on <- sort(on, method = "radix")
    focal_on <- length(intersect(focal_tokens, th_tokens)) > 0L
    n <- length(on) + (if (focal_on) 1L else 0L)
    status <- if (n == 0L) "under_theorised" else if (n >= 2L) "crowded" else "covered"
    themes_out[[length(themes_out) + 1L]] <- list(
      id = th$id,
      keywords = as.list(kws),
      alternatives = as.list(on),
      focal = focal_on,
      status = status
    )
    if (identical(status, "under_theorised")) {
      under <- c(under, th$id)
    } else if (identical(status, "crowded")) {
      crowded <- c(crowded, th$id)
    }
  }

  list(
    theory_id = .tf_str(T, "id"),
    themes = themes_out,
    under_theorised_fronts = as.list(under),
    redundancy_risk = as.list(crowded)
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

# Theme colours track the landscape statuses: an untouched front is teal (an
# opportunity), a crowded one amber (a redundancy risk), a covered one grey.
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
#'     list(id = "w2", keywords = list("arousal", "threat"))
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
