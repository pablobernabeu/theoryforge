#' Render a theory's audit dossier as a standalone Quarto report.
#'
#' Writes a \code{.qmd} (a YAML header plus the deterministic dossier body) and
#' can optionally invoke Quarto to render it. The report content is the
#' deterministic \code{tf_dossier} output, and only the rendering step depends
#' on the environment.
#' @name report_render
#' @noRd
#' @keywords internal
NULL

#' Write a Quarto report for a theory
#'
#' Writes a standalone Quarto report to \code{path} (forced to a \code{.qmd}
#' suffix): a YAML header (\code{title}, \code{format}) followed by the
#' deterministic \code{tf_dossier(theory)} body. Returns the written path. When
#' \code{render = TRUE}, invokes \code{quarto render}, which requires a Quarto
#' installation, and stops if that render fails. It stops before writing
#' anything when [tf_check()] refuses the theory.
#'
#' @param theory A theory object (named list), such as one from [tf_read()].
#' @param path Destination path. A file name that does not end in
#'   \code{.qmd} (in any letter case) loses everything from its last dot,
#'   unless the name begins with that dot, and gains \code{.qmd}. So
#'   \code{report.md} is written as \code{report.qmd}, \code{report} and
#'   \code{.hidden} gain the suffix and \code{a.tar.gz} becomes
#'   \code{a.tar.qmd}.
#' @param title Optional report title. It defaults to
#'   \code{"theoryforge report: <title-or-id>"}, also when \code{NULL},
#'   \code{NA} or empty. It is written as a YAML double-quoted scalar with
#'   backslashes, double quotes and control characters escaped, so a YAML
#'   parser reads back exactly the string passed. Quarto then reads the title as Markdown, so
#'   raw TeX such as `\emph{}` is dropped from HTML output and `$\alpha$`
#'   becomes mathematics.
#' @param render When \code{TRUE}, run \code{quarto render} on the written file
#'   and stop if it exits non-zero.
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
  # An empty title means the default, as in Python, where '' is falsy, and so
  # does NA, R's other way of saying absent.
  if (is.null(title) || is.na(title) || !nzchar(title)) {
    label <- .tf_str(T, "title")
    if (!nzchar(label)) label <- .tf_str(T, "id")
    title <- paste0("theoryforge report: ", label)
  }

  path <- .tf_qmd_path(path)

  header <- sprintf("---\ntitle: \"%s\"\nformat: %s\n---\n\n", .tf_yaml_dq(title), to)
  text <- paste0(header, tf_dossier(T))
  .tf_write_lf(path, text)

  if (render) {
    # A failed render must not return the path as if it had succeeded; the
    # Python twin's subprocess.run(check = TRUE) raises on the same condition.
    status <- system2("quarto", c("render", shQuote(path), "--to", to))  # nocov
    if (!identical(as.integer(status), 0L)) {  # nocov
      stop("quarto render failed with status ", status, call. = FALSE)  # nocov
    }
  }
  path
}

# Escape a string for the inside of a YAML double-quoted scalar, by the rule
# the Python twin's _yaml_dq() applies character for character (API_SPEC.md
# section 23). Backslash and double quote are escaped, newline and tab become
# \n and \t, every other C0 control, DEL and the C1 controls become \xNN, and
# the noncharacters U+FFFE and U+FFFF become \uFFFE and \uFFFF, since YAML
# forbids all of these raw in a stream. Unescaped, "A\B" would be a parse error
# and "\emph" an escape sequence.
.tf_yaml_dq <- function(s) {
  cp <- utf8ToInt(enc2utf8(s))
  out <- vapply(cp, function(c) {
    if (c == 0x5CL) return("\\\\")
    if (c == 0x22L) return("\\\"")
    if (c == 0x0AL) return("\\n")
    if (c == 0x09L) return("\\t")
    if (c < 0x20L || (c >= 0x7FL && c <= 0x9FL)) return(sprintf("\\x%02X", c))
    if (c == 0xFFFEL || c == 0xFFFFL) return(sprintf("\\u%04X", c))
    intToUtf8(c)
  }, character(1))
  enc2utf8(paste(out, collapse = ""))
}

# `path` with its file name ending in .qmd, by the rule tf_render_report()
# states, written out character by character as the Python twin's _qmd_path().
.tf_qmd_path <- function(path) {
  seps <- gregexpr("[/\\\\]", path)[[1L]]
  cut <- if (seps[[1L]] == -1L) 0L else max(seps)
  folder <- substr(path, 1L, cut)
  name <- substr(path, cut + 1L, nchar(path))
  if (endsWith(tolower(name), ".qmd")) return(path)
  dots <- gregexpr(".", name, fixed = TRUE)[[1L]]
  dot <- if (dots[[1L]] == -1L) 0L else max(dots)
  if (dot > 1L) name <- substr(name, 1L, dot - 1L)
  paste0(folder, name, ".qmd")
}
