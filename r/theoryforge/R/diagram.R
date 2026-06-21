#' Diagram intermediate representations.
#'
#' Byte-identical to the Python output (API_SPEC.md section 5).
#' @name diagram
#' @keywords internal
NULL

.tf_DIAGRAM_TYPES <- c("nomological_net", "provenance", "causal_dag",
                       "development_roadmap", "pipeline")

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

#' Render a diagram intermediate representation
#'
#' Produces a byte-identical diagram IR string for the requested type. The
#' \code{engine} argument is accepted for API parity; the IR is engine
#' independent (Graphviz DOT for the two digraphs, dagitty syntax for the
#' causal DAG). See API_SPEC.md section 5.
#'
#' @param theory A theory object (named list).
#' @param type One of \code{"nomological_net"} (default), \code{"provenance"},
#'   \code{"causal_dag"}, \code{"development_roadmap"}, or \code{"pipeline"}.
#' @param engine Rendering engine label, accepted for parity (default
#'   \code{"graphviz"}).
#' @return A single string ending in a newline.
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
  stop(sprintf("unknown diagram type '%s'; expected one of %s",
               type, paste(.tf_DIAGRAM_TYPES, collapse = ", ")), call. = FALSE)
}
