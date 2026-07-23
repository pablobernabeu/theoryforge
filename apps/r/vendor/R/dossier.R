#' Assemble a reviewer-facing audit bundle as a single Markdown document.
#'
#' Composes the rigour report, severity table, provenance and preregistration
#' document into one deterministic bundle.
#' @name dossier
#' @keywords internal
NULL

#' Render a theory audit dossier (Markdown)
#'
#' Assembles a reviewer-facing audit bundle: the header, the rigour-checklist
#' table, the severity list, the provenance list, and the appended
#' preregistration document. The output is deterministic, so the same theory
#' always yields the same dossier.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return The dossier Markdown as a single string (LF line endings, single
#'   trailing newline).
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "causes",
#'                      mechanism = "Activation raises salience of threat cues.") |>
#'   tf_add_prediction("h1", "Effect is exactly 0.30.", "point")
#' cat(tf_dossier(theory))
#' @export
tf_dossier <- function(theory) {
  T <- theory
  rep <- tf_check(T)
  lines <- c(
    sprintf("# theoryforge dossier: %s", .tf_str(T, "title")),
    "",
    sprintf("- Theory ID: %s", .tf_str(T, "id")),
    sprintf("- Maturity: %s", .tf_str(T, "maturity")),
    sprintf("- Aggregate rigour score: %s/100", .tf_fmt(rep$aggregate_score)),
    sprintf("- Gate: %s", rep$gate),
    sprintf("- Blockers failed: %d", rep$n_blockers_failed),
    "",
    "## Rigour checklist",
    "",
    "| item | status | score | weight |",
    "| --- | --- | --- | --- |"
  )
  for (it in rep$items) {
    lines <- c(lines, sprintf("| %s | %s | %s | %s |",
                              it$id, it$status, .tf_fmt(it$score), .tf_fmt(it$weight)))
  }

  lines <- c(lines, "", "## Severity", "")
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

  lines <- c(lines, "", "## Provenance", "")
  prov <- .tf_list(T, "provenance")
  if (length(prov) == 0L) {
    lines <- c(lines, "_No provenance recorded._")
  } else {
    for (i in seq_along(prov)) {
      s <- prov[[i]]
      action <- .tf_str(s, "action")
      detail <- .tf_str(s, "detail")
      lines <- c(lines, if (nzchar(trimws(detail))) {
        sprintf("%d. %s: %s", i, action, detail)
      } else {
        sprintf("%d. %s", i, action)
      })
    }
  }

  lines <- c(lines, "", "## Preregistration", "")
  paste0(paste(lines, collapse = "\n"), "\n", tf_preregister(T))
}
