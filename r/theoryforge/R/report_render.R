#' Render a theory's audit dossier as a standalone Quarto report.
#'
#' Writes a \code{.qmd} (a YAML header plus the deterministic dossier body) and
#' can optionally invoke Quarto to render it. The report content is the
#' deterministic \code{tf_dossier} output, and only the rendering step is
#' environment-dependent.
#' @name report_render
#' @keywords internal
NULL

#' Write a Quarto report for a theory
#'
#' Writes a standalone Quarto report to \code{path} (forced to a \code{.qmd}
#' suffix): a YAML header (\code{title}, \code{format}) followed by the
#' deterministic \code{tf_dossier(theory)} body. Returns the written path. When
#' \code{render = TRUE}, invokes \code{quarto render}, which requires a Quarto
#' installation.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param path Destination path; any extension is replaced with \code{.qmd}.
#' @param title Optional report title; defaults to
#'   \code{"theoryforge report: <title-or-id>"}. Double quotes are escaped.
#' @param render When \code{TRUE}, run \code{quarto render} on the written file.
#' @param to Quarto output format (default \code{"html"}).
#' @return The path of the written \code{.qmd} file.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
#' path <- tempfile(fileext = ".qmd")
#' tf_render_report(theory, path)
#' @export
tf_render_report <- function(theory, path, title = NULL, render = FALSE, to = "html") {
  T <- theory
  if (is.null(title)) {
    label <- .tf_str(T, "title")
    if (!nzchar(label)) label <- .tf_str(T, "id")
    title <- paste0("theoryforge report: ", label)
  }
  title <- gsub("\"", "'", title, fixed = TRUE)

  # Force a .qmd suffix.
  if (!identical(tolower(tools::file_ext(path)), "qmd")) {
    path <- paste0(tools::file_path_sans_ext(path), ".qmd")
  }

  header <- sprintf("---\ntitle: \"%s\"\nformat: %s\n---\n\n", title, to)
  text <- paste0(header, tf_dossier(T))
  con <- file(path, open = "wb")
  on.exit(close(con))
  text <- gsub("\r\n", "\n", text, fixed = TRUE)
  writeBin(charToRaw(enc2utf8(text)), con)

  if (render) {
    system2("quarto", c("render", shQuote(path), "--to", to))  # nocov
  }
  path
}
