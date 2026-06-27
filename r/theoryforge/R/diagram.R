#' Diagram intermediate representations.
#'
#' Byte-identical to the Python output (API_SPEC.md section 5).
#' @name diagram
#' @keywords internal
NULL

.tf_DIAGRAM_TYPES <- c("nomological_net", "provenance", "causal_dag",
                       "development_roadmap", "pipeline", "context", "workflow", "venn")

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

.tf_nomological_net <- function(T) {
  lines <- c("digraph nomological_net {", "  rankdir=LR;",
             "  node [shape=box, style=rounded];")
  for (c in .tf_list(T, "constructs")) {
    lines <- c(lines, sprintf('  "%s" [label="%s"];',
                              .tf_esc(.tf_get(c, "id")), .tf_esc(.tf_get(c, "label"))))
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
  lines <- c("digraph provenance {", "  rankdir=TB;", "  node [shape=box];")
  steps <- .tf_list(T, "provenance")
  for (i in seq_along(steps)) {
    s <- steps[[i]]
    action <- .tf_str(s, "action")
    detail <- .tf_str(s, "detail")
    label <- if (nzchar(trimws(detail))) paste0(action, ": ", detail) else action
    lines <- c(lines, sprintf('  "n%d" [label="%s"];', i, .tf_esc(label)))
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
  lines <- c("digraph development_roadmap {", "  rankdir=TB;", "  node [shape=box];")
  todo <- Filter(function(it) !identical(it$status, "pass"), rep$items)
  if (length(todo) == 0L) {
    lines <- c(lines, '  "all_checks_pass" [label="all checks pass"];')
  } else {
    for (it in todo) {
      lines <- c(lines, sprintf('  "%s" [label="%s (%s)"];',
                                .tf_esc(it$id), .tf_esc(it$id), it$status))
    }
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_pipeline <- function(T) {
  lines <- c("digraph pipeline {", "  rankdir=LR;", "  node [shape=box];")
  for (p in .tf_list(T, "predictions")) {
    lines <- c(lines, sprintf('  "%s" [label="%s"];',
                              .tf_esc(.tf_get(p, "id")), .tf_esc(.tf_get(p, "type"))))
  }
  for (t in .tf_list(T, "test_outcomes")) {
    pid <- .tf_str(t, "prediction_id")
    rid <- paste0("result_", pid)
    passed <- if (isTRUE(.tf_get(t, "passed"))) "true" else "false"
    lines <- c(lines, sprintf('  "%s" [label="passed=%s"];', .tf_esc(rid), passed))
    lines <- c(lines, sprintf('  "%s" -> "%s";', .tf_esc(pid), .tf_esc(rid)))
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_context <- function(T) {
  lines <- c("digraph context {", "  rankdir=LR;", "  node [shape=box, style=rounded];")
  lines <- c(lines, sprintf('  "theory" [shape=ellipse, label="%s"];', .tf_esc(.tf_get(T, "title"))))
  for (c in .tf_list(T, "constructs")) {
    cid <- .tf_esc(.tf_get(c, "id"))
    lines <- c(lines, sprintf('  "%s" [label="%s"];', cid, .tf_esc(.tf_get(c, "label"))))
    lines <- c(lines, sprintf('  "theory" -> "%s";', cid))
  }
  bcs <- .tf_list(T, "boundary_conditions")
  for (i in seq_along(bcs)) {
    lines <- c(lines, sprintf('  "scope%d" [shape=note, label="%s"];', i, .tf_esc(bcs[[i]])))
    lines <- c(lines, sprintf('  "scope%d" -> "theory" [style=dotted, label="holds within"];', i))
  }
  for (a in .tf_list(T, "alternatives")) {
    aid <- .tf_esc(.tf_get(a, "id"))
    lines <- c(lines, sprintf('  "%s" [shape=box, style=dashed, label="%s"];', aid, .tf_esc(.tf_get(a, "label"))))
    lines <- c(lines, sprintf('  "theory" -> "%s" [style=dashed, label="contrasts with"];', aid))
  }
  lines <- c(lines, "}")
  paste0(paste(lines, collapse = "\n"), "\n")
}

.tf_workflow <- function(T) {
  lines <- c("digraph workflow {", "  rankdir=LR;", "  node [shape=box];")
  lines <- c(lines, "  subgraph cluster_build {", '    label="building";')
  for (c in .tf_list(T, "constructs")) {
    lines <- c(lines, sprintf('    "%s" [label="%s"];', .tf_esc(.tf_get(c, "id")), .tf_esc(.tf_get(c, "label"))))
  }
  lines <- c(lines, "  }", "  subgraph cluster_relate {", '    label="propositions";')
  for (p in .tf_list(T, "propositions")) {
    lines <- c(lines, sprintf('    "prop_%s" [label="%s"];', .tf_esc(.tf_get(p, "id")), .tf_esc(.tf_get(p, "relation"))))
  }
  lines <- c(lines, "  }", "  subgraph cluster_predict {", '    label="predictions";')
  for (p in .tf_list(T, "predictions")) {
    lines <- c(lines, sprintf('    "pred_%s" [label="%s"];', .tf_esc(.tf_get(p, "id")), .tf_esc(.tf_get(p, "type"))))
  }
  lines <- c(lines, "  }", "  subgraph cluster_test {", '    label="testing";')
  for (t in .tf_list(T, "test_outcomes")) {
    passed <- if (isTRUE(.tf_get(t, "passed"))) "true" else "false"
    lines <- c(lines, sprintf('    "outcome_%s" [label="passed=%s"];', .tf_esc(.tf_get(t, "prediction_id")), passed))
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

.tf_vcircle <- function(cx, cy, r) {
  sprintf('  <circle cx="%d" cy="%d" r="%d" fill="#4e79a7" fill-opacity="0.35" stroke="#33567a"/>', cx, cy, r)
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
  out <- c('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 300" font-family="sans-serif" font-size="13">',
           '  <text x="190" y="24" text-anchor="middle" font-size="15">Construct scope overlap</text>')
  if (n == 0L) {
    out <- c(out, .tf_vlabel(190L, 150L, "(no constructs)"))
  } else if (n == 1L) {
    a <- setlist[[1L]]
    out <- c(out, .tf_vcircle(190L, 150L, 90L), .tf_vlabel(190L, 55L, nms[1]),
             .tf_vcount(190L, 155L, length(a)))
  } else if (n == 2L) {
    a <- setlist[[1L]]; b <- setlist[[2L]]
    out <- c(out, .tf_vcircle(150L, 150L, 90L), .tf_vcircle(230L, 150L, 90L),
             .tf_vlabel(110L, 50L, nms[1]), .tf_vlabel(270L, 50L, nms[2]),
             .tf_vcount(110L, 155L, length(setdiff(a, b))),
             .tf_vcount(190L, 155L, length(intersect(a, b))),
             .tf_vcount(270L, 155L, length(setdiff(b, a))))
  } else {
    a <- setlist[[1L]]; b <- setlist[[2L]]; cc <- setlist[[3L]]
    out <- c(out, .tf_vcircle(150L, 135L, 85L), .tf_vcircle(230L, 135L, 85L), .tf_vcircle(190L, 195L, 85L),
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

#' Render a diagram intermediate representation
#'
#' Produces a byte-identical diagram IR string for the requested type. The
#' \code{engine} argument is accepted for API parity; the IR is engine
#' independent (Graphviz DOT for the two digraphs, dagitty syntax for the
#' causal DAG). See API_SPEC.md section 5.
#'
#' @param theory A theory object (named list).
#' @param type One of \code{"nomological_net"} (default), \code{"provenance"},
#'   \code{"causal_dag"}, \code{"development_roadmap"}, \code{"pipeline"},
#'   \code{"context"} (the theory, its scope, and its rivals),
#'   \code{"workflow"} (the building-to-testing pipeline), or \code{"venn"}
#'   (construct scope overlap, as an SVG).
#' @param engine Rendering engine label, accepted for parity (default
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
  stop(sprintf("unknown diagram type '%s'; expected one of %s",
               type, paste(.tf_DIAGRAM_TYPES, collapse = ", ")), call. = FALSE)
}
