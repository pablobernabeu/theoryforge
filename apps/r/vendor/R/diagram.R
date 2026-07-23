#' Diagram intermediate representations.
#'
#' Deterministic string renderers for every diagram type.
#' @name diagram
#' @keywords internal
NULL

.tf_DIAGRAM_TYPES <- c("nomological_net", "provenance", "causal_dag",
                       "development_roadmap", "pipeline", "context", "workflow", "venn",
                       "rigour", "severity")

# Escape a DOT label: replace backslash then double-quote (order matters).
.tf_esc <- function(s) {
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

# Truncate an over-long label with an ellipsis so it does not overrun adjacent
# chart elements. Identical to the Python reference so SVG output stays
# byte-identical; a no-op for the short identifiers used throughout.
.tf_trunc <- function(s, n) {
  s <- as.character(s)
  if (nchar(s) > n) paste0(substr(s, 1L, n - 1L), "\u2026") else s
}

# Escape XML text content: ampersand first, then the angle brackets.
.tf_xml <- function(s) {
  if (is.null(s) || length(s) == 0L) {
    s <- ""
  } else {
    s <- s[[1L]]
    if (is.na(s)) s <- ""
  }
  s <- as.character(s)
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s
}

# The Meridian palette the DOT views share: fill/border pairs keyed by role.
# These are part of the IR (both implementations emit them byte-identically),
# so a renderer needs no styling of its own.
.tf_INK <- "#12283A"
.tf_FILLS <- list(
  construct   = c("#E4F1F1", "#1E7B7B"),
  proposition = c("#FBF1DC", "#9C6B14"),
  prediction  = c("#E7EDF5", "#33567A"),
  passed      = c("#E5F2E7", "#3E7A46"),
  failed      = c("#F9E5E4", "#B2453C"),
  scope       = c("#FBF7EA", "#B49B55"),
  rival       = c("#F1F1F1", "#8A8A8A"),
  warn        = c("#FBF1DC", "#9C6B14"),
  fail        = c("#F9E5E4", "#B2453C"),
  covered     = c("#F1F1F1", "#8A8A8A")
)

# How many advisory steps the development roadmap places side by side.
.tf_ROADMAP_COLS <- 3L

.tf_fill <- function(role) {
  fc <- .tf_FILLS[[role]]
  sprintf('fillcolor="%s", color="%s"', fc[[1L]], fc[[2L]])
}

# The shared style header every DOT view opens with.
.tf_prelude <- function(name, rankdir, directed = TRUE) {
  kw <- if (directed) "digraph" else "graph"
  c(
    paste0(kw, " ", name, " {"),
    paste0('  graph [rankdir=', rankdir, ', bgcolor="transparent", fontname="Helvetica", ',
           'fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];'),
    paste0('  node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", ',
           'color="#33567A", fillcolor="#F2F6F9", fontcolor="', .tf_INK, '", penwidth=1.1, ',
           'margin="0.16,0.1"];'),
    '  edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];'
  )
}

# Escape a label and wrap it onto lines of at most `width` characters, breaking
# at spaces (a longer single word stays whole). Wrapping happens after
# escaping, and lines join with a literal backslash-n, DOT's in-label newline,
# so nodes stay narrow enough for a documentation column.
.tf_wrap <- function(s, width = 18L) {
  text <- .tf_esc(s)
  if (!nzchar(text)) {
    return("")
  }
  words <- strsplit(text, " ", fixed = TRUE)[[1L]]
  lines <- character(0)
  cur <- ""
  for (word in words) {
    if (!nzchar(cur)) {
      cur <- word
    } else if (nchar(cur) + 1L + nchar(word) <= width) {
      cur <- paste0(cur, " ", word)
    } else {
      lines <- c(lines, cur)
      cur <- word
    }
  }
  if (nzchar(cur)) {
    lines <- c(lines, cur)
  }
  paste(lines, collapse = "\\n")
}

.tf_nomological_net <- function(T) {
  lines <- .tf_prelude("nomological_net", "LR")
  for (c in .tf_list(T, "constructs")) {
    lines <- c(lines, sprintf('  "%s" [label="%s", %s];',
                              .tf_esc(.tf_get(c, "id")), .tf_wrap(.tf_get(c, "label")),
                              .tf_fill("construct")))
  }
  for (p in .tf_list(T, "propositions")) {
    lines <- c(lines, sprintf('  "%s" -> "%s" [label="%s"];',
                              .tf_esc(.tf_get(p, "from")), .tf_esc(.tf_get(p, "to")),
                              .tf_esc(.tf_get(p, "relation"))))
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_provenance <- function(T) {
  lines <- .tf_prelude("provenance", "TB")
  steps <- .tf_list(T, "provenance")
  for (i in seq_along(steps)) {
    s <- steps[[i]]
    action <- .tf_str(s, "action")
    detail <- .tf_str(s, "detail")
    label <- paste0(.tf_esc(action),
                    if (nzchar(trimws(detail))) paste0("\\n", .tf_wrap(detail, 26L)) else "")
    lines <- c(lines, sprintf('  "n%d" [label="%s"];', i, label))
  }
  if (length(steps) >= 2L) {
    for (i in seq_len(length(steps) - 1L)) {
      lines <- c(lines, sprintf('  "n%d" -> "n%d";', i, i + 1L))
    }
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_causal_dag <- function(T) {
  lines <- c("dag {")
  for (p in .tf_list(T, "propositions")) {
    rel <- .tf_get(p, "relation")
    if (length(rel) == 1L && !is.na(rel) && rel %in% .tf_CAUSAL) {
      lines <- c(lines, sprintf("  %s -> %s", .tf_str(p, "from"), .tf_str(p, "to")))
    }
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_development_roadmap <- function(T) {
  rep <- tf_check(T)
  spec <- tf_checklist()
  criterion <- vapply(spec$items, function(s) .tf_str(s, "criterion"), character(1L))
  names(criterion) <- vapply(spec$items, function(s) .tf_str(s, "id"), character(1L))
  todo <- Filter(function(it) !identical(it$status, "pass"), rep$items)
  # Blockers before advisories, and heavier checks before lighter ones. The
  # order is the recommendation: a reader who works down the column addresses
  # what gates the theory first, rather than whatever the checklist happens to
  # list first.
  if (length(todo) > 0L) {
    blocks <- vapply(todo, function(it) identical(it$severity_if_fail, "blocker"), logical(1L))
    weight <- vapply(todo, function(it) as.numeric(it$weight), numeric(1L))
    todo <- todo[order(ifelse(blocks, 0L, 1L), -weight, seq_along(todo))]
  }
  lines <- .tf_prelude("development_roadmap", "TB")
  # The hub names the theory and its standing, so the column beneath it reads
  # as this theory's outstanding work rather than an anonymous list.
  lines <- c(lines, sprintf(
    '  "roadmap" [shape=ellipse, label="%s\\nscore %s, gate %s", fillcolor="%s", color="%s", fontcolor="#FFFFFF"];',
    .tf_wrap(.tf_get(T, "title"), 20L), .tf_fmt(rep$aggregate_score), .tf_esc(rep$gate),
    .tf_INK, .tf_INK))
  if (length(todo) == 0L) {
    lines <- c(lines, sprintf('  "all_checks_pass" [label="all checks pass", %s];',
                              .tf_fill("passed")),
               '  "roadmap" -> "all_checks_pass";')
  } else {
    for (i in seq_along(todo)) {
      it <- todo[[i]]
      consequence <- if (identical(it$severity_if_fail, "blocker")) "blocks the gate" else "advisory"
      lines <- c(lines, sprintf('  "%s" [label="%d. %s\\n%s\\n%s", %s];',
                                .tf_esc(it$id), i, .tf_esc(it$id),
                                .tf_wrap(criterion[[as.character(it$id)]], 22L),
                                consequence, .tf_fill(it$status)))
    }
    # What gates the theory runs down the spine one step at a time; the
    # advisories that follow are laid out several abreast, which keeps a
    # long list from growing into a strip too tall to take in at once.
    blockers <- Filter(function(it) identical(it$severity_if_fail, "blocker"), todo)
    advisories <- Filter(function(it) !identical(it$severity_if_fail, "blocker"), todo)
    prev <- "roadmap"
    for (it in blockers) {
      lines <- c(lines, sprintf('  "%s" -> "%s";', prev, .tf_esc(it$id)))
      prev <- .tf_esc(it$id)
    }
    starts <- seq_len(ceiling(length(advisories) / .tf_ROADMAP_COLS))
    heads <- character(0L)
    for (r in starts) {
      from <- (r - 1L) * .tf_ROADMAP_COLS + 1L
      row <- advisories[from:min(from + .tf_ROADMAP_COLS - 1L, length(advisories))]
      head <- .tf_esc(row[[1L]]$id)
      lines <- c(lines, if (r == 1L) {
        sprintf('  "%s" -> "%s";', prev, head)
      } else {
        sprintf('  "%s" -> "%s" [style=invis];', heads[[r - 1L]], head)
      })
      heads <- c(heads, head)
      lines <- c(lines, if (length(row) > 1L) {
        chain <- paste(vapply(row, function(x) sprintf('"%s"', .tf_esc(x$id)), character(1L)),
                       collapse = " -> ")
        sprintf("  { rank=same; %s [style=invis]; }", chain)
      } else {
        sprintf('  { rank=same; "%s"; }', head)
      })
    }
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_pipeline <- function(T) {
  lines <- .tf_prelude("pipeline", "LR")
  for (p in .tf_list(T, "predictions")) {
    lines <- c(lines, sprintf('  "%s" [label="%s\\n%s", %s];',
                              .tf_esc(.tf_get(p, "id")), .tf_esc(.tf_get(p, "id")),
                              .tf_esc(.tf_get(p, "type")), .tf_fill("prediction")))
  }
  for (t in .tf_list(T, "test_outcomes")) {
    pid <- .tf_str(t, "prediction_id")
    rid <- paste0("result_", pid)
    role <- if (isTRUE(.tf_get(t, "passed"))) "passed" else "failed"
    lines <- c(lines, sprintf('  "%s" [label="%s", %s];', .tf_esc(rid), role, .tf_fill(role)))
    lines <- c(lines, sprintf('  "%s" -> "%s";', .tf_esc(pid), .tf_esc(rid)))
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_context <- function(T) {
  lines <- .tf_prelude("context", "LR")
  lines <- c(lines, sprintf('  "theory" [shape=ellipse, label="%s", fillcolor="%s", color="%s", fontcolor="#FFFFFF"];',
                            .tf_wrap(.tf_get(T, "title"), 20L), .tf_INK, .tf_INK))
  for (c in .tf_list(T, "constructs")) {
    cid <- .tf_esc(.tf_get(c, "id"))
    lines <- c(lines, sprintf('  "%s" [label="%s", %s];', cid,
                              .tf_wrap(.tf_get(c, "label")), .tf_fill("construct")))
    lines <- c(lines, sprintf('  "theory" -> "%s";', cid))
  }
  bcs <- .tf_list(T, "boundary_conditions")
  for (i in seq_along(bcs)) {
    lines <- c(lines, sprintf('  "scope%d" [shape=note, style="filled", label="%s", %s];',
                              i, .tf_wrap(bcs[[i]]), .tf_fill("scope")))
    lines <- c(lines, sprintf('  "scope%d" -> "theory" [style=dotted, label="holds within"];', i))
  }
  for (a in .tf_list(T, "alternatives")) {
    aid <- .tf_esc(.tf_get(a, "id"))
    lines <- c(lines, sprintf('  "%s" [style="rounded,filled,dashed", label="%s", %s];',
                              aid, .tf_wrap(.tf_get(a, "label")), .tf_fill("rival")))
    lines <- c(lines, sprintf('  "theory" -> "%s" [style=dashed, label="contrasts with"];', aid))
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_cluster_open <- function(key, title) {
  c(sprintf("  subgraph cluster_%s {", key),
    sprintf('    label="%s";', title),
    '    style="rounded";',
    '    color="#C4D1D9";',
    '    fontcolor="#5B7285";')
}

.tf_workflow <- function(T) {
  lines <- .tf_prelude("workflow", "LR")
  lines <- c(lines, .tf_cluster_open("build", "building"))
  for (c in .tf_list(T, "constructs")) {
    lines <- c(lines, sprintf('    "%s" [label="%s", %s];', .tf_esc(.tf_get(c, "id")),
                              .tf_wrap(.tf_get(c, "label"), 16L), .tf_fill("construct")))
  }
  lines <- c(lines, "  }", .tf_cluster_open("relate", "propositions"))
  for (p in .tf_list(T, "propositions")) {
    lines <- c(lines, sprintf('    "prop_%s" [label="%s\\n%s", %s];',
                              .tf_esc(.tf_get(p, "id")), .tf_esc(.tf_get(p, "id")),
                              .tf_esc(.tf_get(p, "relation")), .tf_fill("proposition")))
  }
  lines <- c(lines, "  }", .tf_cluster_open("predict", "predictions"))
  for (p in .tf_list(T, "predictions")) {
    lines <- c(lines, sprintf('    "pred_%s" [label="%s\\n%s", %s];',
                              .tf_esc(.tf_get(p, "id")), .tf_esc(.tf_get(p, "id")),
                              .tf_esc(.tf_get(p, "type")), .tf_fill("prediction")))
  }
  lines <- c(lines, "  }", .tf_cluster_open("test", "testing"))
  for (t in .tf_list(T, "test_outcomes")) {
    pid <- .tf_esc(.tf_get(t, "prediction_id"))
    role <- if (isTRUE(.tf_get(t, "passed"))) "passed" else "failed"
    lines <- c(lines, sprintf('    "outcome_%s" [label="%s\\n%s", %s];',
                              pid, pid, role, .tf_fill(role)))
  }
  lines <- c(lines, "  }")
  for (p in .tf_list(T, "propositions")) {
    lines <- c(lines, sprintf('  "%s" -> "prop_%s";', .tf_esc(.tf_get(p, "from")), .tf_esc(.tf_get(p, "id"))))
  }
  for (pred in .tf_list(T, "predictions")) {
    df <- .tf_get(pred, "derives_from")
    if (!is.null(df)) {
      for (src in as.character(unlist(df))) {
        lines <- c(lines, sprintf('  "prop_%s" -> "pred_%s";', .tf_esc(src), .tf_esc(.tf_get(pred, "id"))))
      }
    }
  }
  for (t in .tf_list(T, "test_outcomes")) {
    pid <- .tf_esc(.tf_get(t, "prediction_id"))
    lines <- c(lines, sprintf('  "pred_%s" -> "outcome_%s";', pid, pid))
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

# Open an SVG element carrying explicit dimensions as well as a viewBox. A
# viewBox on its own leaves the image with no intrinsic size, so a browser
# resolves `width: auto` to the full width of the container and scales the
# declared 13px type by whatever factor that implies. The three chart views
# declare different viewBox widths, so the same label then rendered at a
# different size in each figure. Stating width and height gives each view its
# natural size wherever it is embedded, which is what the rendered Graphviz
# views already do, and leaves the stylesheet free to shrink a wide chart on a
# narrow viewport without inflating the type on a wide one.
.tf_svg_open <- function(width, height) {
  sprintf(paste0('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" ',
                 'viewBox="0 0 %d %d" font-family="sans-serif" font-size="13">'),
          width, height, width, height)
}

# The outline carries the set structure, so it is drawn in the teal already used
# for construct borders elsewhere in the palette. That colour clears the 3:1
# contrast floor for graphical objects (WCAG 1.4.11) against both the light
# paper and the dark page, whereas the former navy outline fell below it on a
# dark background and took the whole figure with it. The translucent fill is
# decorative reinforcement only: no opacity composites to a readable ratio on a
# dark page, which is why the boundary has to do the work.
.tf_vcircle <- function(cx, cy, r) {
  sprintf('  <circle cx="%d" cy="%d" r="%d" fill="#4e79a7" fill-opacity="0.35" stroke="#1e7b7b"/>', cx, cy, r)
}
.tf_vlabel <- function(x, y, s) {
  sprintf('  <text x="%d" y="%d" text-anchor="middle">%s</text>', x, y, .tf_xml(s))
}
.tf_vcount <- function(x, y, k) {
  sprintf('  <text x="%d" y="%d" text-anchor="middle" font-weight="bold">%d</text>', x, y, k)
}

.tf_venn <- function(T) {
  constructs <- .tf_list(T, "constructs")
  if (length(constructs) > 3L) constructs <- constructs[1:3]
  n <- length(constructs)
  nms <- character(0)
  setlist <- list()
  for (c in constructs) {
    nm <- .tf_str(c, "label")
    if (!nzchar(nm)) nm <- .tf_str(c, "id")
    nms <- c(nms, nm)
    bc <- .tf_get(c, "boundary_conditions")
    s <- if (is.null(bc)) character(0) else unique(as.character(unlist(bc)))
    setlist[[length(setlist) + 1L]] <- s
  }
  out <- c(.tf_svg_open(380L, 300L),
           '  <text x="190" y="24" text-anchor="middle" font-size="15">Construct scope overlap</text>')
  if (n == 0L) {
    out <- c(out, .tf_vlabel(190L, 150L, "(no constructs)"))
  } else if (n == 1L) {
    a <- setlist[[1L]]
    out <- c(out, .tf_vcircle(190L, 150L, 82L), .tf_vlabel(190L, 55L, nms[1]),
             .tf_vcount(190L, 155L, length(a)))
  } else if (n == 2L) {
    a <- setlist[[1L]]; b <- setlist[[2L]]
    out <- c(out, .tf_vcircle(150L, 150L, 82L), .tf_vcircle(230L, 150L, 82L),
             .tf_vlabel(110L, 50L, nms[1]), .tf_vlabel(270L, 50L, nms[2]),
             .tf_vcount(110L, 155L, length(setdiff(a, b))),
             .tf_vcount(190L, 155L, length(intersect(a, b))),
             .tf_vcount(270L, 155L, length(setdiff(b, a))))
  } else {
    a <- setlist[[1L]]; b <- setlist[[2L]]; cc <- setlist[[3L]]
    out <- c(out, .tf_vcircle(150L, 135L, 78L), .tf_vcircle(230L, 135L, 78L), .tf_vcircle(190L, 195L, 78L),
             .tf_vlabel(110L, 45L, nms[1]), .tf_vlabel(270L, 45L, nms[2]), .tf_vlabel(190L, 290L, nms[3]),
             .tf_vcount(120L, 115L, length(setdiff(setdiff(a, b), cc))),
             .tf_vcount(260L, 115L, length(setdiff(setdiff(b, a), cc))),
             .tf_vcount(190L, 230L, length(setdiff(setdiff(cc, a), b))),
             .tf_vcount(190L, 105L, length(setdiff(intersect(a, b), cc))),
             .tf_vcount(145L, 180L, length(setdiff(intersect(a, cc), b))),
             .tf_vcount(235L, 180L, length(setdiff(intersect(b, cc), a))),
             .tf_vcount(190L, 160L, length(intersect(intersect(a, b), cc))))
  }
  out <- c(out, "</svg>")
  paste0(paste(out, collapse = "\n"), "\n")
}

.tf_STATUS_COLOUR <- c(pass = "#4caf50", warn = "#ff9800", fail = "#f44336")

.tf_rigor <- function(T) {
  rep <- tf_check(T)
  items <- rep$items
  h <- 60L + length(items) * 24L + 12L
  out <- c(.tf_svg_open(460L, h),
           '  <text x="20" y="28" font-size="15">Rigour checklist</text>',
           sprintf('  <text x="20" y="46">aggregate score %.1f, gate %s</text>',
                   rep$aggregate_score, .tf_xml(rep$gate)))
  for (i in seq_along(items)) {
    it <- items[[i]]
    y <- 60L + (i - 1L) * 24L
    colour <- if (it$status %in% names(.tf_STATUS_COLOUR)) .tf_STATUS_COLOUR[[it$status]] else "#9e9e9e"
    out <- c(out,
      sprintf('  <rect x="20" y="%d" width="16" height="16" rx="3" fill="%s"/>', y, colour),
      sprintf('  <text x="44" y="%d">%s</text>', y + 12L, .tf_xml(it$id)),
      sprintf('  <text x="320" y="%d">%s</text>', y + 12L, .tf_xml(it$status)))
  }
  out <- c(out, "</svg>")
  paste0(paste(out, collapse = "\n"), "\n")
}

.tf_severity_chart <- function(T) {
  rows <- tf_severity(T)
  n <- nrow(rows)
  h <- 40L + max(n, 1L) * 28L + 8L
  labels <- if (n) vapply(as.character(rows$prediction_id),
                          .tf_trunc, character(1), n = 15L, USE.NAMES = FALSE)
            else character(0)
  # Bars start just past the longest row label (estimated at 8 px per character
  # at this font size), so short labels leave no dead gap before the bars, and
  # each value label trails its own bar.
  bar_x <- 20L + (if (n) max(nchar(labels)) else 0L) * 8L + 10L
  width <- bar_x + 250L  # 200 for a full bar, then the gap and the value label
  out <- c(.tf_svg_open(width, h),
           '  <text x="20" y="26" font-size="15">Prediction severity</text>')
  if (n == 0L) {
    out <- c(out, '  <text x="20" y="54">(no predictions)</text>')
  } else {
    for (i in seq_len(n)) {
      y <- 40L + (i - 1L) * 28L
      sev <- rows$computed_severity[i]
      w <- as.integer(sev * 200 + 0.5 + 1e-6)
      out <- c(out,
        sprintf('  <text x="20" y="%d">%s</text>', y + 12L, .tf_xml(labels[i])),
        sprintf('  <rect x="%d" y="%d" width="%d" height="16" rx="2" fill="#4e79a7"/>', bar_x, y, w),
        sprintf('  <text x="%d" y="%d">%.3f</text>', bar_x + w + 5L, y + 12L, sev))
    }
  }
  out <- c(out, "</svg>")
  paste0(paste(out, collapse = "\n"), "\n")
}

#' Render a diagram intermediate representation
#'
#' Produces a deterministic diagram IR string for the requested type. The
#' \code{engine} argument is accepted but has no effect, because the IR is
#' engine independent (Graphviz DOT for the two digraphs, dagitty syntax for
#' the causal DAG).
#'
#' @param theory A theory object (named list).
#' @param type One of \code{"nomological_net"} (default), \code{"provenance"},
#'   \code{"causal_dag"}, \code{"development_roadmap"}, \code{"pipeline"},
#'   \code{"context"} (the theory, its scope, and its rivals),
#'   \code{"workflow"} (the building-to-testing pipeline), \code{"venn"}
#'   (construct scope overlap, as an SVG), \code{"rigour"} (the checklist as a
#'   status grid, as an SVG), or \code{"severity"} (per-prediction severity
#'   bars, as an SVG).
#' @param engine Rendering engine label, accepted but unused (default
#'   \code{"graphviz"}).
#' @return A single string ending in a newline. Graphviz DOT for the digraphs,
#'   dagitty syntax for the causal DAG, and SVG for the Venn.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "causes")
#' cat(tf_diagram(theory, "nomological_net"))
#' cat(tf_diagram(theory, "causal_dag"))
#' @export
tf_diagram <- function(theory, type = "nomological_net", engine = "graphviz") {
  T <- theory
  if (identical(type, "nomological_net")) {
    return(.tf_nomological_net(T))
  }
  if (identical(type, "provenance")) {
    return(.tf_provenance(T))
  }
  if (identical(type, "causal_dag")) {
    return(.tf_causal_dag(T))
  }
  if (identical(type, "development_roadmap")) {
    return(.tf_development_roadmap(T))
  }
  if (identical(type, "pipeline")) {
    return(.tf_pipeline(T))
  }
  if (identical(type, "context")) {
    return(.tf_context(T))
  }
  if (identical(type, "workflow")) {
    return(.tf_workflow(T))
  }
  if (identical(type, "venn")) {
    return(.tf_venn(T))
  }
  if (identical(type, "rigour")) {
    return(.tf_rigor(T))
  }
  if (identical(type, "severity")) {
    return(.tf_severity_chart(T))
  }
  stop(sprintf("unknown diagram type '%s'; expected one of %s",
               type, paste(.tf_DIAGRAM_TYPES, collapse = ", ")), call. = FALSE)
}
