#' Preregistration document export.
#'
#' Deterministic, byte-identical markdown. See API_SPEC.md section 11.
#' @name prereg
#' @keywords internal
NULL

# Format a number identically across languages: 3dp, trailing zeros stripped,
# at least one decimal kept (1.0 -> "1.0", 0.9 -> "0.9", 0.667 -> "0.667").
.tf_fmt <- function(x) {
  sub("\\.$", ".0", sub("0+$", "", sprintf("%.3f", as.numeric(x))))
}

#' Render a preregistration document
#'
#' Produces a byte-identical preregistration markdown string for a theory and,
#' if \code{path} is given, writes it (LF, single trailing newline). Mirrors
#' the Python \code{theory.preregister(path)}. See API_SPEC.md section 11.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param path Optional destination path; when given, the markdown is written
#'   with LF line endings.
#' @return The preregistration markdown as a single string.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "Effect is exactly 0.30.", "point")
#' cat(tf_preregister(theory))
#' @export
tf_preregister <- function(theory, path = NULL) {
  T <- theory
  rep <- tf_check(T)
  verified <- "no"
  for (it in rep$items) {
    if (identical(it$id, "derivation_chain")) {
      verified <- if (identical(it$status, "pass")) "yes" else "no"
      break
    }
  }

  lines <- c(
    sprintf("# Preregistration: %s", .tf_str(T, "title")),
    "",
    sprintf("- Theory ID: %s", .tf_str(T, "id")),
    sprintf("- Schema version: %s", .tf_str(T, "schema_version")),
    sprintf("- Maturity: %s", .tf_str(T, "maturity")),
    sprintf("- Derivation chain verified: %s", verified),
    "",
    "## Hypotheses"
  )

  preds <- .tf_list(T, "predictions")
  if (length(preds) == 0L) {
    lines <- c(lines, "_No predictions specified._")
  } else {
    for (i in seq_along(preds)) {
      p <- preds[[i]]
      df <- .tf_get(p, "derives_from")
      df <- if (is.null(df)) character(0) else unlist(df, use.names = FALSE)
      df_txt <- if (length(df) > 0L) paste(df, collapse = ", ") else "\u2014"
      lines <- c(lines, sprintf("%d. [%s] %s (derives from: %s)",
                                i, .tf_str(p, "type"), .tf_str(p, "statement"), df_txt))
    }
  }

  lines <- c(lines, "", "## Severity")
  sev <- tf_severity(T)
  if (nrow(sev) == 0L) {
    lines <- c(lines, "_No predictions specified._")
  } else {
    for (i in seq_len(nrow(sev))) {
      lines <- c(lines, sprintf("- %s: severity %s, risk %s",
                                sev$prediction_id[i],
                                .tf_fmt(sev$computed_severity[i]),
                                .tf_fmt(sev$risk_score[i])))
    }
  }

  text <- paste0(paste(lines, collapse = "\n"), "\n")
  if (!is.null(path)) {
    con <- file(path, open = "wb")
    on.exit(close(con))
    writeBin(charToRaw(enc2utf8(text)), con)
  }
  text
}
