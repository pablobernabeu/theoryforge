#' Bibliometric / literature layer (API_SPEC.md Part C).
#'
#' The analysis (litmap, landscape, diagrams) is fully deterministic given a
#' corpus, so it is parity-tested against the Python reference implementation.
#' The OpenAlex fetch adapter ([tf_fetch_corpus()]) is the parity-exempt,
#' network/non-deterministic assistive layer.
#' @name lit
#' @keywords internal
NULL

.tf_DEFAULT_MIN_LINK <- 2L

# Escape a DOT label: replace backslash then double-quote (order matters).
# Mirrors Python lit._esc (treats NULL/NA as "").
.tf_lit_esc <- function(s) {
  if (is.null(s) || length(s) == 0L) {
    s <- ""
  } else {
    s <- s[[1L]]
    if (is.na(s)) s <- ""
  }
  s <- as.character(s)
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub('"', '\\"', s, fixed = TRUE)
  s
}

#' Read a literature corpus from a YAML or JSON file
#'
#' Reads a corpus object (\code{{schema_version, id, records}}; see
#' \code{schema/corpus.schema.json}) into a named list. The format is chosen by
#' the file extension (\code{.json} -> JSON, otherwise YAML). Mirrors the Python
#' \code{theoryforge.read_corpus(path)}.
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
  ext <- tolower(tools::file_ext(path))
  if (identical(ext, "json")) {
    text <- readChar(path, file.info(path)$size, useBytes = TRUE)
    data <- jsonlite::fromJSON(text, simplifyVector = FALSE)
  } else {
    data <- yaml::read_yaml(path)
  }
  if (!is.list(data)) {
    stop("Corpus data must be a mapping", call. = FALSE)
  }
  data
}

# Mirror Python lit._records: the list of records, or list() when absent.
.tf_records <- function(corpus) {
  recs <- corpus[["records"]]
  if (is.list(recs)) recs else list()
}

# Pair-counting over a per-record field. For each record take the sorted unique
# set of its values; for every unordered pair (a < b) increment a counter.
# Returns a named list keyed by "a\037b" with integer counts and the original
# a/b stored alongside (deterministic insertion does not matter; we sort later).
.tf_pair_counts <- function(records, field) {
  keys <- character(0)
  a_of <- character(0)
  b_of <- character(0)
  counts <- integer(0)
  for (r in records) {
    items <- .tf_list(r, field)
    vals <- character(0)
    for (x in items) {
      if (!is.null(x) && length(x) == 1L && !is.na(x) && nzchar(as.character(x))) {
        vals <- c(vals, as.character(x))
      }
    }
    vals <- sort(unique(vals))
    n <- length(vals)
    if (n < 2L) next
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        a <- vals[[i]]
        b <- vals[[j]]
        key <- paste0(a, "\037", b)
        idx <- match(key, keys)
        if (is.na(idx)) {
          keys <- c(keys, key)
          a_of <- c(a_of, a)
          b_of <- c(b_of, b)
          counts <- c(counts, 1L)
        } else {
          counts[[idx]] <- counts[[idx]] + 1L
        }
      }
    }
  }
  list(a = a_of, b = b_of, count = counts)
}

# Build the row-set [{a, b, count}] for pairs with count >= min_link, sorted by
# (a, b) ascending. Returns an unnamed list of length-3 named lists so that
# jsonlite serializes it as a JSON array of objects (each count an integer).
.tf_edges <- function(pc, min_link) {
  keep <- which(pc$count >= as.integer(min_link))
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
  comps <- lapply(groups, function(members) sort(unique(members)))
  if (length(comps) == 0L) return(list())
  smallest <- vapply(comps, function(kws) kws[[1L]], character(1))
  comps <- comps[order(smallest, method = "radix")]
  lapply(seq_along(comps), function(i) {
    kws <- comps[[i]]
    list(id = paste0("theme_", i), keywords = as.list(kws), size = length(kws))
  })
}

#' Bibliometric map of a literature corpus (deterministic)
#'
#' Computes keyword co-occurrence, thematic components, and reference
#' co-citation for a corpus. Records iterate in file order. See API_SPEC.md
#' section 14. Mirrors the Python \code{theoryforge.litmap}.
#'
#' @param corpus A corpus object (named list), e.g. from [tf_read_corpus()].
#' @param min_link Minimum co-occurrence count for an edge to be kept
#'   (default \code{2}).
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
tf_litmap <- function(corpus, min_link = 2) {
  records <- .tf_records(corpus)
  all_kw <- character(0)
  for (r in records) {
    for (k in .tf_list(r, "keywords")) {
      if (!is.null(k) && length(k) == 1L && !is.na(k) && nzchar(as.character(k))) {
        all_kw <- c(all_kw, as.character(k))
      }
    }
  }
  all_kw <- sort(unique(all_kw))
  kw_edges <- .tf_edges(.tf_pair_counts(records, "keywords"), min_link)
  cocit <- .tf_edges(.tf_pair_counts(records, "references"), min_link)
  list(
    n_records = length(records),
    keywords = as.list(all_kw),
    keyword_cooccurrence = kw_edges,
    themes = .tf_components(kw_edges),
    co_citation = cocit
  )
}

#' Map a theory and its alternatives onto a literature landscape (deterministic)
#'
#' Maps a theory's focal constructs and its registered alternatives onto the
#' thematic structure of a corpus (computed by [tf_litmap()]). Each theme is
#' tagged \code{"under_theorized"}, \code{"covered"}, or \code{"crowded"}. See
#' API_SPEC.md section 15. Mirrors the Python \code{theory.landscape(corpus)} /
#' \code{theoryforge.landscape(theory, corpus)}.
#'
#' @param theory A theory object (named list), e.g. from \code{tf_read()}.
#' @param corpus A corpus object (named list), e.g. from [tf_read_corpus()].
#' @param min_link Minimum co-occurrence count passed to [tf_litmap()]
#'   (default \code{2}).
#' @return A named list with elements \code{theory_id}, \code{themes} (each
#'   \code{{id, keywords, alternatives, focal, status}}),
#'   \code{under_theorized_fronts}, and \code{redundancy_risk}.
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
  lm <- tf_litmap(corpus, min_link)

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
      kc <- vapply(.tf_list(a, "key_constructs"),
                   function(x) as.character(x[[1L]]), character(1))
      alt_src <- paste(c(.tf_str(a, "label"), kc), collapse = " ")
      alt_tokens <- tf_tokens(alt_src)
      if (length(intersect(alt_tokens, th_tokens)) > 0L) {
        on <- c(on, .tf_str(a, "id"))
      }
    }
    on <- sort(on)
    focal_on <- length(intersect(focal_tokens, th_tokens)) > 0L
    n <- length(on) + (if (focal_on) 1L else 0L)
    status <- if (n == 0L) "under_theorized" else if (n >= 2L) "crowded" else "covered"
    themes_out[[length(themes_out) + 1L]] <- list(
      id = th$id,
      keywords = as.list(kws),
      alternatives = as.list(on),
      focal = focal_on,
      status = status
    )
    if (identical(status, "under_theorized")) {
      under <- c(under, th$id)
    } else if (identical(status, "crowded")) {
      crowded <- c(crowded, th$id)
    }
  }

  list(
    theory_id = .tf_str(T, "id"),
    themes = themes_out,
    under_theorized_fronts = as.list(under),
    redundancy_risk = as.list(crowded)
  )
}

# Undirected diagram (keyword_cooccurrence / co_citation). Nodes = endpoints
# appearing in the edge list (sorted), edges in list order; edge label = integer
# count rendered with as.character(as.integer(.)).
.tf_lit_undirected <- function(name, edges) {
  nodes <- character(0)
  for (e in edges) nodes <- c(nodes, e$a, e$b)
  nodes <- sort(unique(nodes))
  lines <- c(sprintf("graph %s {", name), "  node [shape=ellipse];")
  for (n in nodes) {
    lines <- c(lines, sprintf('  "%s";', .tf_lit_esc(n)))
  }
  for (e in edges) {
    lines <- c(lines, sprintf('  "%s" -- "%s" [label="%s"];',
                              .tf_lit_esc(e$a), .tf_lit_esc(e$b),
                              as.character(as.integer(e$count))))
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

# theme_landscape diagram from a landscape() result.
.tf_lit_theme_landscape <- function(ls) {
  lines <- c("digraph theme_landscape {", "  rankdir=LR;", "  node [shape=box];")
  for (th in ls$themes) {
    kws <- unlist(th$keywords, use.names = FALSE)
    label <- sprintf("%s: %s (%s)", th$id, paste(kws, collapse = ", "), th$status)
    lines <- c(lines, sprintf('  "%s" [label="%s"];',
                              .tf_lit_esc(th$id), .tf_lit_esc(label)))
  }
  # Collect alternatives in first-seen order across themes.
  alt_ids <- character(0)
  for (th in ls$themes) {
    for (a in unlist(th$alternatives, use.names = FALSE)) {
      if (!(a %in% alt_ids)) alt_ids <- c(alt_ids, a)
    }
  }
  for (a in alt_ids) {
    lines <- c(lines, sprintf('  "%s" [label="%s", shape=ellipse];',
                              .tf_lit_esc(a), .tf_lit_esc(a)))
  }
  lines <- c(lines, '  "focal" [label="focal", shape=ellipse, style=bold];')
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
#' Produces a byte-identical DOT string for the literature layer. See
#' API_SPEC.md section 16. Mirrors the Python \code{theoryforge.lit_diagram}.
#'
#' @param obj A [tf_litmap()] result (for \code{"keyword_cooccurrence"} /
#'   \code{"co_citation"}) or a [tf_landscape()] result (for
#'   \code{"theme_landscape"}).
#' @param type One of \code{"keyword_cooccurrence"} (default),
#'   \code{"co_citation"}, or \code{"theme_landscape"}.
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
#' @export
tf_lit_diagram <- function(obj, type = "keyword_cooccurrence") {
  if (type %in% c("keyword_cooccurrence", "co_citation")) {
    edges <- obj[[type]]
    if (is.null(edges)) edges <- list()
    return(.tf_lit_undirected(type, edges))
  }
  if (identical(type, "theme_landscape")) {
    return(.tf_lit_theme_landscape(obj))
  }
  stop(sprintf("unknown lit diagram type '%s'", type), call. = FALSE)
}

#' Build a corpus from the OpenAlex API (assistive, parity-exempt)
#'
#' Assistive, parity-exempt helper that builds a corpus by querying the
#' OpenAlex works API (\code{https://api.openalex.org/works?search=...}). This
#' is a network call. It is non-deterministic, depends on a live external
#' service, and is therefore not part of the deterministic core and not covered
#' by parity tests or CI. Each work is mapped to
#' \code{{id, title, year, keywords, references}} (keywords falls back to the top
#' concepts when no keywords are present).
#'
#' @param query Free-text search query.
#' @param per_page Number of works to request (default \code{25}).
#' @param mailto Optional contact email for the OpenAlex "polite pool".
#' @return A corpus object (named list) with \code{schema_version}, \code{id},
#'   and \code{records}.
#' @examples
#' \dontrun{
#' corpus <- tf_fetch_corpus("panic disorder interoception", mailto = "me@example.org")
#' }
#' @export
tf_fetch_corpus <- function(query, per_page = 25, mailto = NULL) {
  params <- list(search = query, "per-page" = as.character(per_page))
  if (!is.null(mailto)) params[["mailto"]] <- mailto
  qs <- paste(
    vapply(names(params), function(k) {
      paste0(utils::URLencode(k, reserved = TRUE), "=",
             utils::URLencode(as.character(params[[k]]), reserved = TRUE))
    }, character(1)),
    collapse = "&"
  )
  url <- paste0("https://api.openalex.org/works?", qs)
  data <- jsonlite::fromJSON(url, simplifyVector = FALSE)

  results <- if (is.list(data[["results"]])) data[["results"]] else list()
  records <- lapply(results, function(w) {
    kws <- character(0)
    for (k in .tf_list(w, "keywords")) {
      dn <- .tf_get(k, "display_name")
      if (!is.null(dn) && nzchar(as.character(dn))) kws <- c(kws, as.character(dn))
    }
    if (length(kws) == 0L) {
      concepts <- .tf_list(w, "concepts")
      concepts <- utils::head(concepts, 5L)
      for (cc in concepts) {
        dn <- .tf_get(cc, "display_name")
        if (!is.null(dn) && nzchar(as.character(dn))) kws <- c(kws, as.character(dn))
      }
    }
    refs <- vapply(.tf_list(w, "referenced_works"),
                   function(x) as.character(x[[1L]]), character(1))
    list(
      id = .tf_get(w, "id"),
      title = .tf_get(w, "title"),
      year = .tf_get(w, "publication_year"),
      keywords = as.list(kws),
      references = as.list(refs)
    )
  })
  list(schema_version = "1.0", id = paste0("openalex:", query), records = records)
}
