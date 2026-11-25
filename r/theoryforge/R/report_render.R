#' Render a theory's audit dossier as a standalone Quarto report.
#'
#' Writes a \code{.qmd} (a YAML header plus the deterministic dossier body) and
#' can optionally invoke Quarto to render it. The report content is the
#' deterministic \code{tf_dossier} output, and only the rendering step depends
#' on the environment. A theory file may come from someone else, and Quarto
#' runs the code chunks and inline code of a document, expands its shortcodes
#' (which can read files and environment variables) and passes on its raw
#' HTML, so the report is written so that the theory's text reaches Quarto as
#' text alone, and text that Quarto would decode as a shortcode after reading
#' it is refused (API_SPEC.md section 23).
#' @name report_render
#' @keywords internal
NULL

#' Write a Quarto report for a theory
#'
#' Writes a standalone Quarto report to \code{path} (forced to a \code{.qmd}
#' suffix): a YAML header followed by the deterministic
#' \code{tf_dossier(theory)} body. Returns the written path. When
#' \code{render = TRUE}, invokes \code{quarto render}, which requires a Quarto
#' installation, and stops if that render fails. Quarto is given the absolute
#' path of the report, so that a path beginning with \code{-} is not read as
#' an option. It stops before writing anything when \code{to} is not a format
#' name or a writer, when [tf_check()] refuses the theory or when the text
#' holds an encoded shortcode.
#'
#' The header gives \code{title} and \code{format}, \code{engine: markdown},
#' so that Quarto runs no code, and
#' \code{from: markdown-raw_html-raw_attribute-raw_tex}, so that it passes on
#' no raw HTML, raw attribute or raw TeX. In the body, every ASCII punctuation
#' character of the dossier's text but the quotation marks gains a backslash
#' and a backtick becomes \code{&#96;}, so that Quarto reads the theory's text
#' as text: no code chunk, inline code, shortcode, link, span or tag can open
#' from it. Typed \code{--} and \code{...} therefore show as typed, and a
#' heading's anchor follows its typed text. The marker of each heading and list
#' item, the underscores of a line in italics and the checklist table are
#' kept. An implied conditional independence keeps its code span when it holds
#' only letters, digits, \code{_}, \code{|}, \code{,}, \code{.} and spaces
#' and does not begin with \code{r} and a space, and is written without it
#' otherwise.
#'
#' Quarto encodes a shortcode as a UUID followed by \code{;<hex>;} and
#' decodes such a run in any text once the document is parsed, escapes
#' removed. Text that holds one, a UUID followed by a semicolon, hexadecimal
#' digits and a semicolon, is therefore refused: the dossier, the default title
#' before it is escaped and a title passed by the caller with its backslashes
#' removed.
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
#'   \code{NA} or empty, with the theory's title or id written on one line and
#'   escaped as the body is, and with Quarto's shortcode delimiters in their
#'   escaped forms \code{\{\{\{<} and \code{>\}\}\}}. It is written as a YAML
#'   double-quoted scalar with backslashes, double quotes and control
#'   characters escaped, so a YAML parser reads back exactly the string passed.
#'   Quarto then reads the title as Markdown, so in a title passed by the
#'   caller raw TeX such as `\emph{}` is dropped from HTML output and
#'   `$\alpha$` becomes mathematics.
#' @param render When \code{TRUE}, run \code{quarto render} on the written file
#'   and stop if it exits non-zero.
#' @param to Quarto output format (default \code{"html"}). It must be a format
#'   name or the path of a custom writer: a letter or digit followed by
#'   letters, digits, \code{_}, \code{.}, \code{+}, \code{/} and \code{-},
#'   as in \code{"pdf"}, \code{"gfm+tex_math_dollars"} or
#'   \code{"writers/plain.lua"}.
#' @return The path of the written \code{.qmd} file.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
#' path <- tempfile(fileext = ".qmd")
#' tf_render_report(theory, path)
#' @export
tf_render_report <- function(theory, path, title = NULL, render = FALSE, to = "html") {
  # A format name or a writer's path alone, so that `to` can add no key to the
  # header and no option or command to the call of Quarto. \z, since $ also
  # matches before a final newline.
  if (!(is.character(to) && length(to) == 1L && !is.na(to) &&
        grepl("^[A-Za-z0-9][A-Za-z0-9_.+/-]*\\z", to, perl = TRUE))) {
    stop(sprintf(paste0("render_report requires `to` to be a Quarto format or writer of letters, ",
                        "digits, '_', '.', '+', '/' and '-' that starts with a letter or digit, ",
                        "not %s"),
                 .tf_quote_arg(to)), call. = FALSE)
  }
  T <- theory
  # An empty title means the default, as in Python, where '' is falsy, and so
  # does NA, R's other way of saying absent. `shown` is the title as Quarto
  # reads it, escapes removed, which the refusal below scans.
  if (is.null(title) || is.na(title) || !nzchar(title)) {
    label <- .tf_str(T, "title")
    if (!nzchar(label)) label <- .tf_str(T, "id")
    label <- .tf_flat(label)
    shown <- paste0("theoryforge report: ", label)
    title <- paste0("theoryforge report: ", .tf_md_text(.tf_shortcodes(label)))
  } else {
    shown <- gsub("\\", "", title, fixed = TRUE)
  }

  path <- .tf_qmd_path(path)
  md <- tf_dossier(T)
  for (scanned in c(shown, md)) {
    found <- regmatches(scanned, regexpr(.tf_ENCODED, scanned, perl = TRUE))
    if (length(found) > 0L) {
      stop(sprintf("render_report refuses text that Quarto reads as an encoded shortcode: '%s'",
                   found), call. = FALSE)
    }
  }

  header <- sprintf(paste0("---\ntitle: \"%s\"\nformat: %s\nengine: markdown\n",
                           "from: markdown-raw_html-raw_attribute-raw_tex\n---\n\n"),
                    .tf_yaml_dq(title), to)
  .tf_write_lf(path, paste0(header, .tf_qmd_body(md)))

  if (render) {
    # A failed render must not return the path as if it had succeeded; the
    # Python twin's subprocess.run(check = TRUE) raises on the same condition.
    # system2() hands its arguments to the shell, so each is quoted. The path is
    # absolute, so that one beginning with - is not read as an option, and
    # expanded, since the shell does not expand a quoted ~.
    target <- normalizePath(path.expand(path), mustWork = FALSE)  # nocov
    status <- system2("quarto", c("render", shQuote(target), "--to", shQuote(to)))  # nocov
    if (!identical(as.integer(status), 0L)) {  # nocov
      stop("quarto render failed with status ", status, call. = FALSE)  # nocov
    }
  }
  path
}

# Quarto's reader encodes each shortcode it finds in the text as a UUID
# followed by ';<hex>;' and, once Pandoc has read the document and removed its
# escapes, decodes such a run in any text and runs it as a shortcode. Any UUID
# is matched, in case another version of Quarto uses another one. The Python
# twin's _ENCODED is the same pattern.
.tf_ENCODED <- "[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12};[0-9A-Fa-f]+;"

# `s` written so that Quarto reads each of its characters as text, as the
# Python twin's _md_text() writes it. Every ASCII punctuation character but the
# quotation marks gains a backslash, which Pandoc's Markdown reads as the
# character itself, so that no emphasis, link, span, attribute, raw HTML,
# mathematics or shortcode can open. The quotation marks open nothing once the
# others are escaped, and keep their typographic form. A backtick becomes the
# entity &#96;, since knitr finds inline code by its backticks whatever
# precedes them.
.tf_md_text <- function(s) {
  s <- gsub("([!#-&(-/:-@\\[-_{-~])", "\\\\\\1", s, perl = TRUE)
  gsub("`", "&#96;", s, fixed = TRUE)
}

# `s` with each Quarto shortcode delimiter in its escaped form. Quarto finds
# the shortcodes of the title once it has read the title as Markdown, so a
# backslash before the brace does not stop them there, and {{{< and >}}} are
# its own escapes.
.tf_shortcodes <- function(s) {
  gsub(">}}", ">}}}", gsub("{{<", "{{{<", s, fixed = TRUE), fixed = TRUE)
}

# The dossier `md` as the report's body, its text escaped by .tf_md_text(), as
# the Python twin's _qmd_body() writes it. A blank line and a row of the
# checklist table, which holds the checklist's own text alone, are kept as they
# are. Every other line keeps the marker of its heading or list item. A line
# without a marker that is set in italics keeps its two underscores. A list
# item that is a code span alone (an implied conditional independence) keeps
# it when its text holds only letters, digits, underscores, bars, commas, full
# stops and spaces and does not begin with 'r ', so that it holds no brace,
# angle bracket, backtick or hyphen and knitr reads no inline code in it.
# Otherwise it loses its backticks, since the escaped text needs no code span
# to keep its underscores. The rest of the line is escaped. The dossier ends in
# a newline, which strsplit() leaves out and paste0() puts back.
.tf_qmd_body <- function(md) {
  lines <- strsplit(md, "\n", fixed = TRUE)[[1L]]
  out <- vapply(lines, function(line) {
    if (!nzchar(line) || startsWith(line, "|")) return(line)
    m <- regexpr("^ *(?:#{1,6}|-|[0-9]+\\.) ", line, perl = TRUE)
    marker <- if (m == 1L) regmatches(line, m) else ""
    rest <- substring(line, nchar(marker) + 1L)
    n <- nchar(rest)
    if (identical(trimws(marker), "-") && n > 1L && startsWith(rest, "`") && endsWith(rest, "`") &&
        !grepl("`", substr(rest, 2L, n - 1L), fixed = TRUE)) {
      inner <- substr(rest, 2L, n - 1L)
      plain <- grepl("^[A-Za-z0-9_|,. ]+\\z", inner, perl = TRUE) && !startsWith(inner, "r ")
      if (!plain) rest <- .tf_md_text(inner)
    } else if (!nzchar(marker) && n > 1L && startsWith(rest, "_") && endsWith(rest, "_")) {
      rest <- paste0("_", .tf_md_text(substr(rest, 2L, n - 1L)), "_")
    } else {
      rest <- .tf_md_text(rest)
    }
    paste0(marker, rest)
  }, character(1), USE.NAMES = FALSE)
  paste0(paste(out, collapse = "\n"), "\n")
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
