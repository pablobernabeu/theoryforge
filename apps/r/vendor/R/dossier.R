#' Assemble a reviewer-facing audit bundle as a single Markdown document.
#'
#' Composes the rigour report, severity table, provenance and preregistration
#' document into one deterministic bundle.
#' @name dossier
#' @keywords internal
NULL

# A declared severity further above the claim-form rubric than this is noted
# beside it (API_SPEC.md section 20). The note changes no status.
.tf_DECLARED_MARGIN <- 0.2

#' Render a theory audit dossier (Markdown)
#'
#' Assembles a reviewer-facing audit bundle: the header, the rigour-checklist
#' table, the severity list, the provenance list, and the appended
#' preregistration document. The output is deterministic, so the same theory
#' always yields the same dossier.
#'
#' The header gives the checklist version, the aggregate score, the checklist
#' coverage, the gate and the blockers that failed. The rigour table prints
#' \code{n/a} for an item with nothing to assess. The severity list gives each
#' prediction's claim-form rubric values and, when the prediction declares a
#' severity, that value too, with a note when it exceeds the rubric by more
#' than 0.2.
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
  failed <- character(0)
  for (it in rep$items) {
    if (identical(it$severity_if_fail, "blocker") && identical(it$status, "fail")) {
      failed <- c(failed, it$id)
    }
  }
  blockers <- if (length(failed) > 0L) {
    sprintf("%d (%s)", rep$n_blockers_failed, paste(failed, collapse = ", "))
  } else {
    "0"
  }
  lines <- c(
    sprintf("# theoryforge dossier: %s", .tf_str(T, "title")),
    "",
    sprintf("- Theory ID: %s", .tf_str(T, "id")),
    sprintf("- Maturity: %s", rep$maturity),
    # The score is only interpretable against the checklist that produced it,
    # so a reviewer reading the bundle can see which one that was.
    sprintf("- Checklist version: %s", rep$checklist_version),
    sprintf("- Aggregate rigour score: %s/100", .tf_fmt(rep$aggregate_score)),
    # The share of the checklist's weight the aggregate is the mean over.
    sprintf("- Checklist coverage: %s", .tf_fmt(rep$coverage)),
    sprintf("- Gate: %s", rep$gate),
    sprintf("- Blockers failed: %s", blockers),
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

  lines <- c(lines, "", "## Severity (pre-data rubric of claim form)", "")
  sev <- tf_severity(T)
  preds <- .tf_list(T, "predictions")
  if (nrow(sev) == 0L) {
    lines <- c(lines, "_No predictions specified._")
  } else {
    # tf_check() above has refused any declared severity that is not a number
    # in [0, 1], so what is left is a number or absent.
    for (i in seq_len(nrow(sev))) {
      line <- sprintf("- %s: severity %s, risk %s",
                      sev$prediction_id[i],
                      .tf_fmt(sev$computed_severity[i]),
                      .tf_fmt(sev$risk_score[i]))
      declared <- .tf_get(preds[[i]], "severity")
      if (!is.null(declared)) {
        line <- paste0(line, ", declared ", .tf_fmt(declared))
        if (.tf_rnd(declared - sev$computed_severity[i], 3) > .tf_DECLARED_MARGIN) {
          line <- paste0(line, " (declared exceeds the rubric by more than ",
                         .tf_fmt(.tf_DECLARED_MARGIN), ")")
        }
      }
      lines <- c(lines, line)
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
      lines <- c(lines, if (nzchar(.tf_trim(detail))) {
        sprintf("%d. %s: %s", i, action, detail)
      } else {
        sprintf("%d. %s", i, action)
      })
    }
  }

  lines <- c(lines, "", "## Preregistration", "")
  paste0(paste(lines, collapse = "\n"), "\n", tf_preregister(T))
}
