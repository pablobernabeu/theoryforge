#' Preregistration document export.
#'
#' Deterministic markdown output.
#' @name prereg
#' @keywords internal
NULL

# Format a number identically across languages: 3dp, trailing zeros stripped,
# at least one decimal kept (1.0 -> "1.0", 0.9 -> "0.9", 0.667 -> "0.667").
# NULL, the score of a checklist item with nothing to assess, is "n/a".
.tf_fmt <- function(x) {
  if (is.null(x)) return("n/a")
  sub("\\.$", ".0", sub("0+$", "", sprintf("%.3f", as.numeric(x))))
}

# What the derivation line reports for each status of the checklist's
# derivation_chain item (API_SPEC.md section 11). The item checks only that
# every prediction cites declared propositions, so the line says whether those
# references resolve.
.tf_RESOLVE <- c(pass = "yes", fail = "no", "n/a" = "not applicable (no predictions)")

.tf_IMPLIED_HEADING <- paste0("## Implied conditional independencies (derived from the causal ",
                              "graph, not predictions)")

.tf_PLAN_HEADING <- "## Sampling plan (author-recorded; not scored)"

# A recorded value as the sampling plan writes it, with up to 15 significant
# digits. The plan repeats what the author recorded, so it does not round to the
# three decimals of .tf_fmt(), which would write an alpha of 0.0001 as 0.0.
# Python's format(x, ".15g") gives the same text, an exponent such as 5e-08
# included.
.tf_plan_number <- function(x) sprintf("%.15g", as.numeric(x))

# The sampling plan that prediction `p` states, or NULL when it states none. The
# test block is read leniently (API_SPEC.md section 30). A number that full
# validation would refuse reads as absent, text is read through .tf_text() and
# sided through .tf_enum(). A qualifier is written only beside the value it
# qualifies: the unit with n_planned, the scale with sesoi, and the interval and
# method with the power or decision probability.
.tf_plan <- function(p) {
  block <- .tf_get(p, "test")
  if (!.tf_is_mapping(block)) return(NULL)
  num <- function(key, ok) {
    x <- .tf_number(.tf_get(block, key))
    if (!is.null(x) && ok(x)) x else NULL
  }
  txt <- function(key) {
    s <- .tf_str(block, key)
    if (.tf_ne_str(s)) s else ""
  }
  unit_interval <- function(x) x >= 0 && x <= 1

  clauses <- character(0)
  n <- num("n_planned", function(x) is.finite(x) && x == floor(x) && x >= 1)
  if (!is.null(n)) {
    unit <- txt("unit")
    clauses <- c(clauses, paste0("n = ", .tf_plan_number(n), if (nzchar(unit)) paste0(" ", unit)))
  }
  alpha <- num("alpha", function(x) x > 0 && x < 1)
  sided <- .tf_enum(.tf_get(block, "sided"), .tf_SIDED)
  level <- c(if (!is.null(alpha)) paste0("alpha ", .tf_plan_number(alpha)),
             if (!is.null(sided)) paste0(sided, "-sided"))
  if (length(level) > 0L) clauses <- c(clauses, paste(level, collapse = ", "))
  sesoi <- num("sesoi", is.finite)
  if (!is.null(sesoi)) {
    scale <- txt("sesoi_scale")
    clauses <- c(clauses, paste0("smallest effect of interest ", .tf_plan_number(sesoi),
                                 if (nzchar(scale)) paste0(" ", scale)))
  }
  power <- num("power", unit_interval)
  decision <- num("decision_probability", unit_interval)
  prob <- c(if (!is.null(power)) paste0("power ", .tf_plan_number(power)),
            if (!is.null(decision)) paste0("decision probability ", .tf_plan_number(decision)))
  if (length(prob) > 0L) {
    part <- paste(prob, collapse = ", ")
    lo <- num("power_lo", unit_interval)
    hi <- num("power_hi", unit_interval)
    if (!is.null(lo) && !is.null(hi) && lo <= hi) {
      part <- paste0(part, " [", .tf_plan_number(lo), ", ", .tf_plan_number(hi), "]")
    }
    method <- txt("method")
    clauses <- c(clauses, paste0(part, if (nzchar(method)) paste0(" (", method, ")")))
  }
  design <- txt("design_ref")
  if (nzchar(design)) clauses <- c(clauses, paste0("design: ", design))
  justification <- txt("justification")
  if (length(clauses) == 0L) return(if (nzchar(justification)) justification else NULL)
  line <- paste(clauses, collapse = "; ")
  if (nzchar(justification)) paste0(line, ". ", justification) else line
}

# The lines of the sampling-plan section, or none when no prediction states a
# plan, so a theory without a plan has no such section (API_SPEC.md section
# 30).
.tf_sampling_plan <- function(preds) {
  plans <- lapply(preds, .tf_plan)
  if (all(vapply(plans, is.null, logical(1)))) return(character(0))
  ids <- vapply(preds, function(p) .tf_str(p, "id"), character(1))
  stated <- vapply(plans, function(x) if (is.null(x)) "no sampling plan stated" else x,
                   character(1))
  c("", .tf_PLAN_HEADING, paste0("- ", ids, ": ", stated))
}

# What a test outcome found: "passed", "failed" or "no result recorded".
# tf_check() has refused a passed that is present and not a logical, so what is
# left is TRUE, FALSE or absent.
.tf_outcome_result <- function(t) {
  passed <- .tf_get(t, "passed")
  if (isTRUE(passed)) "passed" else if (isFALSE(passed)) "failed" else "no result recorded"
}

# The version line, when the version has an id, naming its parent when it has
# one.
.tf_version_line <- function(T) {
  ver <- .tf_get(T, "version")
  vid <- .tf_str(ver, "id")
  if (!.tf_ne_str(vid)) return(character(0))
  parent <- .tf_str(ver, "parent_id")
  paste0("- Version: ", vid, if (.tf_ne_str(parent)) paste0(" (parent ", parent, ")"))
}

# The assumptions whose protects names `pid`, in file order. An assumption with
# a nonempty added_for was added in answer to that prediction's anomaly, and any
# other is core, as the schema reads a null.
.tf_auxiliaries <- function(pid, aux) {
  out <- character(0)
  for (a in aux) {
    if (!(pid %in% .tf_str_list(.tf_get(a, "protects")))) next
    added <- .tf_str(a, "added_for")
    out <- c(out, paste0(.tf_str(a, "id"), " (",
                         if (.tf_ne_str(added)) paste0("added for ", added) else "core", ")"))
  }
  out
}

# Every outcome of prediction `pid`, in file order, or "untested". An outcome
# counts when its prediction_id is the string `pid`, as in the amendment
# appraisal (API_SPEC.md section 10). The registration is labelled, since a bare
# value could be read as a second date.
.tf_test_record <- function(pid, tos) {
  done <- character(0)
  for (t in tos) {
    tid <- .tf_get(t, "prediction_id")
    if (!(.tf_is_string(tid) && tid == pid)) next
    date <- .tf_str(t, "date")
    reg <- .tf_str(t, "registered")
    when <- c(if (.tf_ne_str(date)) date, if (.tf_ne_str(reg)) paste0("registered ", reg))
    done <- c(done, paste0(.tf_outcome_result(t),
                           if (length(when) > 0L) paste0(" (", paste(when, collapse = ", "), ")")))
  }
  if (length(done) == 0L) "untested" else paste0("already tested: ", paste(done, collapse = "; "))
}

# The lines of the implied-independencies section (API_SPEC.md section 11).
.tf_implied_lines <- function(T) {
  imp <- tryCatch(tf_implications(T), error = function(e) {
    # A refusal is what the section reports: a feedback loop under the default,
    # a repeated construct id or a directed relation naming an undeclared
    # construct. Any other error propagates, as it does in the Python twin,
    # which catches only the ValueError of a refusal.
    if (startsWith(conditionMessage(e), "implications requires ")) e else stop(e)
  })
  if (inherits(imp, "error")) {
    return(paste0("_Not derived: ", conditionMessage(imp), "._"))
  }
  stmts <- vapply(imp$implications, function(i) i$statement, character(1))
  if (length(stmts) > 0L) {
    # A code span keeps dagitty's notation whole, since Markdown reads the
    # underscores of " _||_ " as emphasis around the two bars.
    return(paste0("- `", stmts, "`"))
  }
  if (length(imp$constructs) == 0L) {
    return("_None: the theory states no directed relation between constructs._")
  }
  if (length(imp$inseparable) > 0L) {
    return("_None: no set of constructs separates any pair the theory leaves unjoined._")
  }
  "_None: every pair of constructs in the causal graph is adjacent._"
}

#' Render the hypotheses section of a preregistration
#'
#' Produces a deterministic preregistration markdown string for a theory and,
#' if \code{path} is given, writes it (LF, single trailing newline).
#'
#' The header gives the theory id, the version when it has an id (with its
#' parent, when one is named), the schema version, the maturity and whether
#' every prediction's derivation references resolve: \code{yes}, \code{no} or
#' \code{not applicable (no predictions)}. The derivation line reports the
#' checklist's reference check, which does not show that a prediction follows
#' from the propositions it cites.
#'
#' Each hypothesis is listed in file order with its claim type, statement and
#' derivation, followed by the auxiliary assumptions that protect it
#' (`core` or `added for <id>`), the registered rivals it discriminates and its
#' test record. A hypothesis that a recorded outcome has already tested reads
#' `already tested: passed (<date>, registered <where>)`, one entry per
#' outcome, and any other reads `untested`.
#'
#' When at least one prediction states a sampling plan in its \code{test}
#' block, a section headed `Sampling plan (author-recorded; not scored)`
#' follows, with one line per prediction in file order. A line gives what is
#' recorded of the planned sample, alpha and sidedness, smallest effect of
#' interest, power or decision probability, design analysis and justification.
#' A prediction without a plan reads `no sampling plan stated`. Nothing scores
#' the plan: power does not raise a claim's severity (Meehl, 1967), though it
#' decides how informative a failed test is (Lakens, 2022). A theory without a
#' plan has no such section.
#'
#' A section then lists the conditional independencies that
#' [tf_implications()] derives from the causal graph with its default
#' settings, which are claims the theory makes without stating them, or says
#' why there are none. The claim-form severity rubric closes the document.
#'
#' The document is the part of a preregistration that the theory file holds. It
#' is to be completed with the study design, the analysis plan, the inference
#' criteria and whatever the sampling plan leaves out, the sections that a
#' template such as PRP-QUANT asks for (Bosnjak et al., 2022).
#'
#' It stops, as [tf_check()] does, when a test outcome's \code{passed} is
#' present and not \code{TRUE} or \code{FALSE}, or when a prediction's
#' \code{severity} is not a finite number from 0 to 1, and then writes nothing.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param path Optional destination path; when given, the markdown is written
#'   with LF line endings.
#' @return The preregistration markdown as a single string.
#' @references
#' Bosnjak, M., Fiebach, C. J., Mellor, D., Mueller, S., O'Connor, D. B.,
#'   Oswald, F. L., & Sokol, R. I. (2022). A template for preregistration of
#'   quantitative research in psychology: Report of the joint psychological
#'   societies preregistration task force. \emph{American Psychologist}, 77(4),
#'   602-615. \doi{10.1037/amp0000879}
#'
#' Lakens, D. (2022). Sample size justification. \emph{Collabra: Psychology},
#'   8(1), Article 33267. \doi{10.1525/collabra.33267}
#'
#' Meehl, P. E. (1967). Theory-testing in psychology and physics: A
#'   methodological paradox. \emph{Philosophy of Science}, 34(2), 103-115.
#'   \doi{10.1086/288135}
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "Effect is exactly 0.30.", "point")
#' cat(tf_preregister(theory))
#' @export
tf_preregister <- function(theory, path = NULL) {
  T <- theory
  rep <- tf_check(T)
  resolve <- "no"
  for (it in rep$items) {
    if (identical(it$id, "derivation_chain")) {
      resolve <- .tf_RESOLVE[[it$status]]
      break
    }
  }

  lines <- c(
    sprintf("# Preregistration: %s", .tf_str(T, "title")),
    "",
    sprintf("- Theory ID: %s", .tf_str(T, "id")),
    .tf_version_line(T),
    sprintf("- Schema version: %s", .tf_str(T, "schema_version")),
    sprintf("- Maturity: %s", .tf_enum_str(T, "maturity", .tf_MATURITY)),
    paste0("- Derivation references resolve: ", resolve),
    "",
    "## Hypotheses"
  )

  preds <- .tf_list(T, "predictions")
  if (length(preds) == 0L) {
    lines <- c(lines, "_No predictions specified._")
  } else {
    aux <- .tf_list(T, "auxiliary_assumptions")
    tos <- .tf_list(T, "test_outcomes")
    alt_ids <- vapply(.tf_list(T, "alternatives"), function(a) .tf_str(a, "id"), character(1))
    for (i in seq_along(preds)) {
      p <- preds[[i]]
      df <- .tf_str_list(.tf_get(p, "derives_from"))
      df_txt <- if (length(df) > 0L) paste(df, collapse = ", ") else "\u2014"
      lines <- c(lines, sprintf("%d. [%s] %s (derives from: %s)",
                                i, .tf_enum_str(p, "type", .tf_PRED_TYPE), .tf_str(p, "statement"),
                                df_txt))
      # Markdown nests a line under a numbered item only when it is indented by
      # the width of the number, its full stop and the space.
      pad <- strrep(" ", nchar(as.character(i)) + 2L)
      pid <- .tf_str(p, "id")
      assumptions <- .tf_auxiliaries(pid, aux)
      if (length(assumptions) > 0L) {
        lines <- c(lines, paste0(pad, "- Auxiliary assumptions: ",
                                 paste(assumptions, collapse = ", ")))
      }
      named <- .tf_str_list(.tf_get(p, "diagnostic_vs"))
      rivals <- unique(named[named %in% alt_ids])
      if (length(rivals) > 0L) {
        lines <- c(lines, paste0(pad, "- Rivals it discriminates: ", paste(rivals, collapse = ", ")))
      }
      lines <- c(lines, paste0(pad, "- Test record: ", .tf_test_record(pid, tos)))
    }
    lines <- c(lines, .tf_sampling_plan(preds))
  }

  lines <- c(lines, "", .tf_IMPLIED_HEADING, .tf_implied_lines(T))

  # The values grade the form of each claim before any data (API_SPEC section
  # 9). They say nothing of how severely a claim is tested, and the heading
  # says so.
  lines <- c(lines, "", "## Severity (pre-data rubric of claim form)")
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
    .tf_write_lf(path, text)
  }
  text
}
