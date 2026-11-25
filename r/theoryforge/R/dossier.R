#' Assemble a reviewer-facing audit bundle as a single Markdown document.
#'
#' Composes the rigour report, severity table, test record, evidence,
#' provenance and the hypotheses section of a preregistration into one
#' deterministic bundle.
#' @name dossier
#' @keywords internal
NULL

# A declared severity further above the claim-form rubric than this is noted
# beside it (API_SPEC.md section 20). The note changes no status.
.tf_DECLARED_MARGIN <- 0.2

# The post-data severity note of a test-record line, an open bound written as
# an infinity. A severity that rounds to 1 or 0 is written as "> 0.999" or
# "< 0.001". A pass whose estimate lies outside the region is said to be one.
.tf_post_data_note <- function(row, passed) {
  # The bounds are written as recorded, with up to 15 significant digits, so a
  # small bound is not rounded to zero.
  lower <- if (is.na(row$lower)) "-inf" else .tf_plan_number(row$lower)
  upper <- if (is.na(row$upper)) "inf" else .tf_plan_number(row$upper)
  # Rounded to three decimals, a severity of 0.9996 would read as 1, which no
  # finite test can give.
  sev <- row$severity
  value <- if (sev == 1) "> 0.999" else if (sev == 0) "< 0.001" else .tf_fmt(sev)
  note <- sprintf("; post-data severity %s for [%s, %s]", value, lower, upper)
  # A pass with the estimate outside the region is not refused, since a test
  # that fails to reject a predicted value passes it (Meehl, 1967), but the
  # reader is told.
  outside <- (!is.na(row$lower) && row$estimate < row$lower) ||
    (!is.na(row$upper) && row$estimate > row$upper)
  if (isTRUE(passed) && outside) {
    note <- paste0(note, "; recorded as passed, with the estimate outside that region")
  }
  note
}

#' Render a theory audit dossier (Markdown)
#'
#' Assembles a reviewer-facing audit bundle: the header, the rigour-checklist
#' table, the severity list, the test record, the evidence, the provenance list
#' and, appended, the hypotheses section of a preregistration. The output is
#' deterministic, so the same theory always yields the same dossier.
#'
#' The header gives the checklist version, the aggregate score, the checklist
#' coverage, the gate and the blockers that failed. The rigour table prints
#' \code{n/a} for an item with nothing to assess. The severity list gives each
#' prediction's claim-form rubric values and, when the prediction declares a
#' severity, that value too, with a note when it exceeds the rubric by more
#' than 0.2. The test record lists every test outcome in file order, with what
#' it found and the observation, date and registration it records, and with
#' the post-data severity of [tf_post_data_severity()] where it can be
#' computed, an open bound written as \code{-inf} or \code{inf}. The
#' evidence lists the prediction each entry supports, its direction and its
#' DOI. The implied independencies appear once, in the preregistration.
#'
#' It stops, as [tf_check()] does, when a test outcome's \code{passed} is
#' present and not \code{TRUE} or \code{FALSE}, or when a prediction's
#' \code{severity} is not a finite number from 0 to 1.
#'
#' @param theory A theory object (named list), such as one from [tf_read()].
#' @param cycles \code{"refuse"} (the default) or \code{"sigma"}, passed to
#'   [tf_entailments()], [tf_discriminate()] and [tf_preregister()].
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
tf_dossier <- function(theory, cycles = "refuse") {
  .tf_check_cycles(cycles, "dossier")
  T <- theory
  rep <- tf_check(T)
  criteria <- vapply(tf_checklist()$items, function(it) it$criterion, character(1))
  names(criteria) <- vapply(tf_checklist()$items, function(it) it$id, character(1))
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
    sprintf("# theoryforge dossier: %s", .tf_flat(.tf_str(T, "title"))),
    "",
    sprintf("- Theory ID: %s", .tf_str(T, "id")),
    sprintf("- Content hash: %s", tf_content_hash(T)),
    sprintf("- Maturity: %s", rep$maturity),
    # The score is only interpretable against the checklist that produced it,
    # so a reviewer reading the bundle can see which one that was.
    sprintf("- Checklist version: %s", rep$checklist_version),
    sprintf("- Aggregate rigour score: %s/100 (%s to %s under other weightings)",
            .tf_fmt(rep$aggregate_score), .tf_fmt(rep$aggregate_range[[1]]),
            .tf_fmt(rep$aggregate_range[[2]])),
    # The share of the checklist's weight the aggregate is the mean over.
    sprintf("- Checklist coverage: %s", .tf_fmt(rep$coverage)),
    sprintf("- Gate: %s", rep$gate),
    sprintf("- Blockers failed: %s", blockers),
    "",
    "## Rigour checklist",
    "",
    "| item | criterion | status | score | weight |",
    "| --- | --- | --- | --- | --- |"
  )
  for (it in rep$items) {
    criterion <- if (it$id %in% names(criteria)) criteria[[it$id]] else ""
    lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |", it$id, criterion,
                              it$status, .tf_fmt(it$score), .tf_fmt(it$weight)))
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
      if (!.tf_absent(declared)) {
        line <- paste0(line, ", declared ", .tf_fmt(declared))
        if (.tf_rnd(declared - sev$computed_severity[i], 3) > .tf_DECLARED_MARGIN) {
          line <- paste0(line, " (declared exceeds the rubric by more than ",
                         .tf_fmt(.tf_DECLARED_MARGIN), ")")
        }
      }
      lines <- c(lines, line)
    }
  }

  # Every outcome, in file order, with the fields it records (API_SPEC.md
  # section 20). tf_check() above has refused a passed that is not a logical.
  # An outcome whose post-data severity can be computed gives it last, and one
  # that tf_post_data_severity() would refuse is listed without it.
  lines <- c(lines, "", "## Test record", "")
  tos <- .tf_list(T, "test_outcomes")
  if (length(tos) == 0L) {
    lines <- c(lines, "_No test outcomes recorded._")
  } else {
    sevs <- .tf_outcome_severities(T)
    for (i in seq_along(tos)) {
      t <- tos[[i]]
      line <- paste0("- ", .tf_str(t, "prediction_id"), ": ", .tf_outcome_result(t))
      for (key in c("observed", "date", "registered")) {
        value <- .tf_flat(.tf_str(t, key))
        if (.tf_ne_str(value)) line <- paste0(line, "; ", key, ": ", value)
      }
      row <- sevs[[i]]$row
      if (!is.null(row)) line <- paste0(line, .tf_post_data_note(row, .tf_get(t, "passed")))
      lines <- c(lines, line)
    }
  }

  lines <- c(lines, "", "## Evidence", "")
  evidence <- .tf_list(T, "evidence")
  if (length(evidence) == 0L) {
    lines <- c(lines, "_No evidence recorded._")
  } else {
    for (e in evidence) {
      line <- paste0("- supports ", .tf_str(e, "supports"), ": ",
                     .tf_enum_str(e, "direction", .tf_EVIDENCE_DIRECTION))
      doi <- .tf_str(e, "source_doi")
      if (.tf_ne_str(doi)) line <- paste0(line, "; doi: ", doi)
      lines <- c(lines, line)
    }
  }

  lines <- c(lines, "", "## Claims and the causal graph", "", .tf_claims_section(T, cycles))
  lines <- c(lines, "", "## Equivalent models", "", .tf_equivalence_section(T))
  lines <- c(lines, "", "## Rivals", "", .tf_rivals_section(T, cycles))

  lines <- c(lines, "", "## Provenance", "")
  prov <- .tf_list(T, "provenance")
  if (length(prov) == 0L) {
    lines <- c(lines, "_No provenance recorded._")
  } else {
    for (i in seq_along(prov)) {
      s <- prov[[i]]
      action <- .tf_flat(.tf_str(s, "action"))
      detail <- .tf_flat(.tf_str(s, "detail"))
      lines <- c(lines, if (nzchar(.tf_trim(detail))) {
        sprintf("%d. %s: %s", i, action, detail)
      } else {
        sprintf("%d. %s", i, action)
      })
    }
  }

  # The preregistration is a document of its own, so its headings move one level
  # down to sit under this section. Its severity list is left out, since the
  # dossier gives it above with the declared values.
  prereg <- .tf_document_lines(T, cycles, embedded = TRUE)
  prereg <- ifelse(startsWith(prereg, "#"), paste0("#", prereg), prereg)
  lines <- c(lines, "", "## Preregistration", "", prereg)
  paste0(paste(lines, collapse = "\n"), "\n")
}

# What the causal graph says of each claim (API_SPEC.md section 20).
.tf_claims_section <- function(T, cycles) {
  recs <- tryCatch(tf_entailments(T, cycles = cycles)$claims, tf_refusal = function(e) e)
  if (inherits(recs, "error")) return(paste0("_Not read: ", conditionMessage(recs), "._"))
  if (length(recs) == 0L) return("_No prediction or phenomenon states a claim._")
  vapply(recs, function(r) paste0("- ", r$id, " (", r$source, "): ", .tf_claim_line(r)), "")
}

# Which causal directions an equivalent model reverses (API_SPEC.md section 20).
.tf_equivalence_section <- function(T) {
  eq <- tryCatch(tf_equivalent_models(T), tf_refusal = function(e) e)
  if (inherits(eq, "error")) return(paste0("_Not read: ", conditionMessage(eq), "._"))
  if (identical(eq$reason, "feedback_loop")) {
    return("_Not determined: the causal graph has a feedback loop._")
  }
  if (identical(eq$reason, "associations")) {
    return(paste0("_Not determined: the theory states associations, and the rule covers ",
                  "graphs of directed relations alone._"))
  }
  if (length(eq$edges) == 0L) {
    return("_None: the theory states no directed relation between constructs._")
  }
  word <- c(compelled = "fixed in every equivalent model",
            reversible = "reversed in some equivalent model")
  vapply(eq$edges, function(e) {
    sprintf("- %s: %s -> %s (%s)", paste(unlist(e$propositions), collapse = ", "),
            e$from, e$to, word[[e$status]])
  }, "")
}

# How the theory compares with each rival that states propositions (API_SPEC.md
# section 20).
.tf_rivals_section <- function(T, cycles) {
  out <- character(0)
  for (a in .tf_list(T, "alternatives")) {
    aid <- .tf_str(a, "id")
    if (!(.tf_ne_str(aid) && length(.tf_list(a, "propositions")) > 0L)) next
    d <- tryCatch(tf_discriminate(T, aid, cycles = cycles), tf_refusal = function(e) e)
    if (inherits(d, "error")) {
      out <- c(out, paste0("- ", aid, ": not compared: ", conditionMessage(d)))
      next
    }
    if (!d$evaluated) {
      out <- c(out, paste0("- ", aid, ": not compared, since a causal graph has a feedback loop"))
      next
    }
    found <- vapply(Filter(function(c) isTRUE(c$discriminates), d$claims), function(c) c$id, "")
    n <- d$counts
    line <- paste0("- ", aid, ": claims it discriminates: ",
                   if (length(found)) paste(found, collapse = ", ") else "none",
                   "; independencies one implies and the other does not: ", n$independencies,
                   "; decisive differences in sign: ", n$decisive_effects, " effects, ",
                   n$decisive_associations, " associations")
    if (isTRUE(d$markov_equivalent)) line <- paste0(line, "; Markov equivalent to the theory")
    out <- c(out, line)
  }
  if (length(out) == 0L) "_No alternative states propositions._" else out
}
