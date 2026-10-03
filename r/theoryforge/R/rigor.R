#' The theory-rigour checklist engine.
#'
#' Scores a theory against the vendored 12-item checklist.
#' @name rigor
#' @keywords internal
NULL

.tf_CAUSAL <- c("causes", "increases", "decreases")
.tf_FORBIDDING <- c("point", "interval", "directional")
.tf_PRECISE <- c("point", "interval")

# Whether a test outcome records a pass for one of `prediction_ids`. The
# outcome's prediction_id must be a string: `%in%` would match the number 1
# against the id "1", where the Python twin's `in` does not.
# The mean as a left fold in file order (API_SPEC.md section 4). R's sum()
# keeps an extended accumulator on x86_64 but not on Apple Silicon, and CPython
# 3.12+ sum() compensates, so either can differ from a plain double sum in the
# last bit, as for c(0.6, 0.7, 0.2).
.tf_mean <- function(xs) {
  acc <- 0.0
  for (x in xs) acc <- acc + x
  acc / length(xs)
}

.tf_passed_for <- function(outcome, prediction_ids) {
  pid <- .tf_get(outcome, "prediction_id")
  is.character(pid) && length(pid) == 1L && !is.na(pid) && pid %in% prediction_ids &&
    isTRUE(.tf_get(outcome, "passed"))
}

# Refuse a test outcome whose `passed` is present and not a logical. A quoted
# "true" read as a failure in both engines. The prediction then counted as
# uncorroborated and an assumption added for it as ad hoc, so an amendment that
# should be progressive came out degenerating. A missing or NULL `passed`, or a
# single NA, still reads as not passed (API_SPEC.md section 4). The first
# offending outcome in file order is named, as the Python twin names it.
.tf_refuse_non_boolean_outcomes <- function(theory, caller) {
  for (t in .tf_list(theory, "test_outcomes")) {
    passed <- .tf_get(t, "passed")
    if (!.tf_absent(passed) && !(is.logical(passed) && length(passed) == 1L)) {
      stop(caller, " requires boolean test outcomes; ",
           "non-boolean passed for test outcome of prediction: ", .tf_str(t, "prediction_id"),
           call. = FALSE)
    }
  }
}

# Compute (status, score) for each checklist item; returns a named list of
# c(status, score) per item id.
.tf_check_items <- function(T, thr) {
  preds <- .tf_list(T, "predictions")
  cons <- .tf_list(T, "constructs")
  props <- .tf_list(T, "propositions")
  aux <- .tf_list(T, "auxiliary_assumptions")
  alts <- .tf_list(T, "alternatives")
  tos <- .tf_list(T, "test_outcomes")
  prop_ids <- unique(vapply(props, function(p) .tf_str(p, "id"), character(1)))
  alt_ids <- unique(vapply(alts, function(a) .tf_str(a, "id"), character(1)))

  out <- list()
  item <- function(status, score) list(status = status, score = score)

  ptype <- function(p) .tf_enum_str(p, "type", .tf_PRED_TYPE)

  # 1 falsifiability
  n_forbidding <- sum(vapply(preds, function(p) ptype(p) %in% .tf_FORBIDDING, logical(1)))
  out$falsifiability <- if (n_forbidding >= 1L) item("pass", 1.0) else item("fail", 0.0)

  # 2 precision
  if (length(preds) == 0L) {
    out$precision <- item("warn", 0.0)
  } else {
    n_precise <- sum(vapply(preds, function(p) ptype(p) %in% .tf_PRECISE, logical(1)))
    share <- .tf_rnd(n_precise / length(preds), 3)
    out$precision <- item(if (share >= thr$min_precision_share) "pass" else "warn",
                          share)
  }

  # 3 risk_severity
  # A non-numeric severity has no defensible mean, and the two engines read
  # one differently by accident (as.numeric() coerced quoted numbers and
  # scored, Python crashed mid-sum), so the same file produced a verdict in
  # one language and a raw TypeError in the other. Refuse instead of
  # coercing; tf_validate(full = TRUE) reports the same file as invalid. An
  # infinity has no mean either, and a finite value outside [0, 1] would put
  # the score outside the checklist's scale (a severity of 7 could lift the
  # aggregate above 100). The status compares the rounded mean with the threshold, so the last
  # bit of the sum cannot decide it.
  sevs <- numeric(0)
  for (p in preds) {
    s <- .tf_get(p, "severity")
    if (is.null(s)) next
    if (!is.numeric(s) || length(s) != 1L || !is.finite(s)) {
      stop("check requires numeric prediction severities; ",
           "non-numeric severity for prediction: ", .tf_str(p, "id"),
           call. = FALSE)
    }
    if (s < 0 || s > 1) {
      stop("check requires prediction severities within [0, 1]; ",
           "out-of-range severity for prediction: ", .tf_str(p, "id"),
           call. = FALSE)
    }
    sevs <- c(sevs, as.numeric(s))
  }
  if (length(sevs) == 0L) {
    out$risk_severity <- item("warn", 0.0)
  } else {
    m <- .tf_rnd(.tf_mean(sevs), 3)
    out$risk_severity <- item(if (m >= thr$min_severity) "pass" else "warn", m)
  }

  # 4 parsimony
  ratio <- length(aux) / max(1L, length(props))
  ad_hoc <- 0L
  for (x in aux) {
    af <- .tf_get(x, "added_for")
    if (!is.null(af)) {
      protects <- .tf_str_list(.tf_get(x, "protects"))
      ok <- any(vapply(tos, .tf_passed_for, logical(1), prediction_ids = protects))
      if (!ok) ad_hoc <- ad_hoc + 1L
    }
  }
  score <- .tf_rnd(max(0.0, 1.0 - ratio / thr$parsimony_ratio_max), 3)
  if (ad_hoc > 0L) {
    out$parsimony <- item("fail", 0.0)
  } else {
    out$parsimony <- item(if (ratio <= thr$parsimony_ratio_max) "pass" else "warn",
                          score)
  }

  # 5 non_redundancy
  if (length(cons) < 2L) {
    max_sim <- 0.0
  } else {
    toks <- lapply(cons, function(c) tf_tokens(.tf_str(c, "definition")))
    max_sim <- 0.0
    n <- length(toks)
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        max_sim <- max(max_sim, tf_jaccard(toks[[i]], toks[[j]]))
      }
    }
  }
  out$non_redundancy <- item(
    if (max_sim < thr$redundancy_similarity_max) "pass" else "warn",
    .tf_rnd(1.0 - max_sim, 3)
  )

  # 6 construct_clarity
  if (length(cons) == 0L) {
    out$construct_clarity <- item("warn", 0.0)
  } else {
    complete <- sum(vapply(cons, function(c) {
      .tf_ne_str(.tf_get(c, "definition")) &&
        .tf_ne_list(.tf_get(c, "measurement")) &&
        .tf_ne_list(.tf_get(c, "boundary_conditions"))
    }, logical(1)))
    frac <- complete / length(cons)
    out$construct_clarity <- item(if (frac == 1.0) "pass" else "warn", .tf_rnd(frac, 3))
  }

  # 7 scope
  present <- .tf_ne_list(.tf_get(T, "boundary_conditions")) ||
    (length(cons) > 0L &&
       all(vapply(cons, function(c) .tf_ne_list(.tf_get(c, "boundary_conditions")),
                  logical(1))))
  out$scope <- if (present) item("pass", 1.0) else item("warn", 0.0)

  # 8 logical_why
  if (length(props) == 0L) {
    out$logical_why <- item("warn", 0.0)
  } else {
    frac <- sum(vapply(props, function(p) .tf_ne_str(.tf_get(p, "mechanism")),
                       logical(1))) / length(props)
    out$logical_why <- item(if (frac == 1.0) "pass" else "warn", .tf_rnd(frac, 3))
  }

  # 9 causal_testability
  n_causal <- sum(vapply(props, function(p) {
    .tf_enum_str(p, "relation", .tf_RELATION) %in% .tf_CAUSAL
  }, logical(1)))
  out$causal_testability <- if (n_causal >= 1L) item("pass", 1.0) else item("warn", 0.0)

  # 10 diagnosticity
  if (length(preds) == 0L) {
    out$diagnosticity <- item("warn", 0.0)
  } else {
    n_diag <- sum(vapply(preds, function(p) {
      any(.tf_str_list(.tf_get(p, "diagnostic_vs")) %in% alt_ids)
    }, logical(1)))
    out$diagnosticity <- item(if (n_diag >= 1L) "pass" else "warn",
                              .tf_rnd(n_diag / length(preds), 3))
  }

  # 11 formalisation
  fm_type <- .tf_enum_str(.tf_get(T, "formal_model"), "type", .tf_FORMAL_MODEL_TYPE)
  present <- !(fm_type %in% c("", "none"))
  out$formalisation <- if (present) item("pass", 1.0) else item("warn", 0.0)

  # 12 derivation_chain
  if (length(preds) == 0L) {
    out$derivation_chain <- item("pass", 1.0)
  } else {
    n_valid <- sum(vapply(preds, function(p) {
      df <- .tf_str_list(.tf_get(p, "derives_from"))
      length(df) > 0L && all(df %in% prop_ids)
    }, logical(1)))
    frac <- n_valid / length(preds)
    out$derivation_chain <- item(if (frac == 1.0) "pass" else "fail", .tf_rnd(frac, 3))
  }

  out
}

#' Compute the rigour checklist report
#'
#' Runs the full rigour checklist (12 items) over a theory object and returns a
#' report, with the items in checklist order.
#'
#' Two values are refused before anything is scored, since no score built on
#' them would be defensible. One is a test outcome whose \code{passed} is
#' present and not \code{TRUE} or \code{FALSE}, such as the quoted string
#' \code{"true"}. The other is a prediction \code{severity} that is present and
#' not a number. Both stop with the message the Python twin raises, and
#' [tf_validate()] with \code{full = TRUE} reports both.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A named list with elements \code{theory_id}, \code{schema_version}
#'   (the theory's), \code{checklist_version} (the rigour checklist's, which is
#'   what the weights and thresholds came from), \code{maturity},
#'   \code{aggregate_score}, \code{gate}, \code{n_blockers_failed}, and
#'   \code{items} (a list of per-item lists). An error is raised for a
#'   prediction severity that is not a finite number or is below 0 or above 1.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "causes",
#'                      mechanism = "Activation raises salience of threat cues.") |>
#'   tf_add_prediction("h1", "Arousal precedes threat appraisal.", "point")
#' report <- tf_check(theory)
#' report$aggregate_score
#' report$gate
#' @export
tf_check <- function(theory) {
  T <- theory
  .tf_refuse_non_boolean_outcomes(T, "check")
  spec <- tf_checklist()
  thr <- spec$thresholds
  results <- .tf_check_items(T, thr)

  items <- vector("list", length(spec$items))
  weighted <- 0.0
  n_blockers_failed <- 0L
  for (k in seq_along(spec$items)) {
    spec_item <- spec$items[[k]]
    iid <- spec_item$id
    res <- results[[iid]]
    status <- res$status
    score <- res$score
    weighted <- weighted + spec_item$weight * score
    if (identical(spec_item$severity_if_fail, "blocker") && identical(status, "fail")) {
      n_blockers_failed <- n_blockers_failed + 1L
    }
    items[[k]] <- list(
      id = iid,
      status = status,
      score = score,
      weight = spec_item$weight,
      severity_if_fail = spec_item$severity_if_fail,
      citation = spec_item$citation
    )
  }

  # A maturity outside its enum, a sequence included, is absent (API_SPEC.md
  # section 3, "Reading a theory"), so the report prints "" for it.
  maturity <- .tf_enum_str(T, "maturity", .tf_MATURITY)
  if (identical(maturity, "draft")) {
    gate <- "advisory"
  } else {
    gate <- if (n_blockers_failed > 0L) "blocked" else "pass"
  }

  list(
    theory_id = .tf_str(T, "id"),
    schema_version = .tf_str(T, "schema_version"),
    # Every number below comes from the checklist's weights and thresholds, so
    # two reports are only comparable if they were scored against the same
    # checklist. `schema_version` above is the theory's, not this.
    checklist_version = .tf_str(spec, "schema_version"),
    maturity = maturity,
    aggregate_score = .tf_rnd(weighted * 100, 1),
    gate = gate,
    n_blockers_failed = n_blockers_failed,
    items = items
  )
}

#' Render the rigour report as a string
#'
#' Renders the result of [tf_check()] as a string. \code{format = "json"}
#' returns valid, pretty-printed JSON; \code{format = "html"} returns an HTML
#' fragment in which every interpolated value is escaped.
#'
#' @param theory A theory object (named list).
#' @param format One of \code{"json"} (default) or \code{"html"}.
#' @return A single string.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_prediction("h1", "Arousal precedes threat appraisal.", "point")
#' cat(tf_report(theory, format = "json"))
#' @export
tf_report <- function(theory, format = "json") {
  rep <- tf_check(theory)
  if (identical(format, "json")) {
    json <- jsonlite::toJSON(rep, auto_unbox = TRUE, pretty = 2, digits = NA,
                             null = "null")
    return(as.character(json))
  }
  if (identical(format, "html")) {
    # Every interpolated value is escaped: the schema allows any non-empty id,
    # so '<' or '&' in it would otherwise reach the markup.
    rows <- vapply(rep$items, function(it) {
      sprintf('    <tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
              .tf_xml(it$id), .tf_xml(it$status),
              .tf_xml(.tf_format_score_html(it$score)), .tf_xml(it$citation))
    }, character(1))
    rows <- paste(rows, collapse = "\n")
    return(paste0(
      '<section class="theoryforge-report">\n',
      sprintf('  <h2>Rigour report: %s</h2>\n', .tf_xml(rep$theory_id)),
      sprintf('  <p>Aggregate score: <strong>%s</strong> &middot; gate: <strong>%s</strong></p>\n',
              .tf_xml(.tf_format_score_html(rep$aggregate_score)), .tf_xml(rep$gate)),
      '  <table>\n    <tr><th>item</th><th>status</th><th>score</th><th>grounding</th></tr>\n',
      rows, '\n  </table>\n</section>\n'
    ))
  }
  stop(sprintf("unknown report format: '%s'", format), call. = FALSE)
}

# Render a numeric score the way Python's str() would for the HTML table
# (e.g. 1.0, 0.667). Not parity-tested, but kept readable. The integrality test
# uses trunc() rather than base round(), so that no call to base round() (which
# is banker's rounding, and diverges across platforms) remains in the package.
.tf_format_score_html <- function(x) {
  if (is.numeric(x)) {
    if (x == trunc(x)) {
      return(sprintf("%.1f", x))
    }
    return(format(x, trim = TRUE))
  }
  as.character(x)
}
