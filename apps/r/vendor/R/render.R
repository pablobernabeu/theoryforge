# Native rendering of the diagram intermediate representations. The IR itself
# (tf_diagram / tf_lit_diagram) stays dependency-free and byte-identical to the
# Python twin; rendering is a language-native convenience layered on top, so it
# sits outside the cross-language parity contract and its packages live in
# Suggests. The Python twin offers the same convenience through the 'graphviz'
# library (render_diagram()).

.tf_DOT_TYPES <- c("nomological_net", "provenance", "development_roadmap",
                   "pipeline", "context", "workflow")
.tf_SVG_TYPES <- c("venn", "rigour", "severity")

#' Render a diagram in the viewer or as SVG
#'
#' Renders a digraph view of a theory without leaving R. Where [tf_diagram()]
#' returns the deterministic Graphviz DOT string, `tf_render_diagram()` passes
#' that string to the DiagrammeR engine and returns either an interactive
#' widget, which displays in the RStudio viewer and in R Markdown documents, or
#' a standalone SVG string, ready to embed in a page or save to a file.
#'
#' The three chart views (`venn`, `rigour` and `severity`) are already SVG, so
#' they are returned as-is under `as = "svg"` and wrapped for display under
#' `as = "widget"`. The `causal_dag` view emits dagitty syntax rather than DOT,
#' so it is not rendered here; paste it into a dagitty tool or the dagitty R
#' package instead.
#'
#' @param x A theory object (named list), or a diagram IR string from
#'   [tf_diagram()] or [tf_lit_diagram()], so literature diagrams render the
#'   same way.
#' @param type The diagram type, as in [tf_diagram()]. Ignored when `x` is
#'   already an IR string.
#' @param as Either `"widget"` (default), an htmlwidget for the viewer and for
#'   R Markdown, or `"svg"`, a standalone SVG string.
#' @return An htmlwidget when `as = "widget"`; a single SVG string when
#'   `as = "svg"`.
#' @seealso [tf_diagram()] for the intermediate representation itself, which
#'   needs no optional packages and stays byte-identical across the R and
#'   Python implementations.
#' @examplesIf requireNamespace("DiagrammeR", quietly = TRUE)
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "causes")
#' tf_render_diagram(theory, "nomological_net")
#' @export
tf_render_diagram <- function(x, type = "nomological_net", as = c("widget", "svg")) {
  as <- match.arg(as)
  if (is.character(x) && length(x) == 1L) {
    ir <- x
    if (grepl("^\\s*<svg", ir)) {
      return(.tf_render_svg(ir, as))
    }
    if (grepl("^\\s*dag\\b", ir)) {
      stop("this is dagitty syntax (the causal_dag view), not Graphviz DOT; ",
           "render it with the dagitty package or at dagitty.net.",
           call. = FALSE)
    }
  } else {
    if (identical(type, "causal_dag")) {
      stop("the causal_dag view emits dagitty syntax, not Graphviz DOT; ",
           "render tf_diagram(x, \"causal_dag\") with the dagitty package ",
           "or at dagitty.net.", call. = FALSE)
    }
    if (type %in% .tf_SVG_TYPES) {
      return(.tf_render_svg(tf_diagram(x, type), as))
    }
    if (!type %in% .tf_DOT_TYPES) {
      stop(sprintf("unknown diagram type '%s'; expected one of %s",
                   type, paste(.tf_DIAGRAM_TYPES, collapse = ", ")),
           call. = FALSE)
    }
    ir <- tf_diagram(x, type)
  }

  if (!requireNamespace("DiagrammeR", quietly = TRUE)) {
    stop("tf_render_diagram() needs the 'DiagrammeR' package; ",
         "install it with install.packages(\"DiagrammeR\"), or use ",
         "tf_diagram() and render the DOT string with any Graphviz tool.",
         call. = FALSE)
  }
  widget <- DiagrammeR::grViz(ir)
  if (identical(as, "widget")) {
    return(widget)
  }
  if (!requireNamespace("DiagrammeRsvg", quietly = TRUE)) {
    stop("as = \"svg\" needs the 'DiagrammeRsvg' package; ",
         "install it with install.packages(\"DiagrammeRsvg\").",
         call. = FALSE)
  }
  svg <- DiagrammeRsvg::export_svg(widget)
  # Drop the XML prolog and doctype so the string embeds directly in an HTML
  # page; the document is equally valid standalone without them.
  sub("(?s)^.*?(<svg)", "\\1", svg, perl = TRUE)
}

# The chart views are already SVG: pass the string through for as = "svg", and
# wrap it for display for as = "widget" (htmltools ships with DiagrammeR).
.tf_render_svg <- function(svg, as) {
  if (identical(as, "svg")) {
    return(svg)
  }
  if (!requireNamespace("htmltools", quietly = TRUE)) {
    stop("displaying an SVG view needs the 'htmltools' package; ",
         "install it, or call with as = \"svg\" for the raw markup.",
         call. = FALSE)
  }
  htmltools::browsable(htmltools::HTML(svg))
}
