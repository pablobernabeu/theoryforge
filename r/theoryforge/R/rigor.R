#' The theory-rigour checklist engine.
#'
#' See API_SPEC.md section 4 for the binding contract.
#' @name rigor
#' @keywords internal
NULL

.tf_CAUSAL <- c("causes", "increases", "decreases")
.tf_FORBIDDING <- c("point", "interval", "directional")
.tf_PRECISE <- c("point", "interval")

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

  # 1 falsifiability
  n_forbidding <- sum(vapply(preds, function(p) {
    ty <- .tf_get(p, "type")
    length(ty) == 1L && !is.na(ty) && ty %in% .tf_FORBIDDING
  }, logical(1)))
  out$falsifiability <- if (n_forbidding >= 1L) item("pass", 1.0) else item("fail", 0.0)

  # 2 precision
  if (length(preds) == 0L) {
    out$precision <- item("warn", 0.0)
  } else {
    n_precise <- sum(vapply(preds, function(p) {
      ty <- .tf_get(p, "type")
      length(ty) == 1L && !is.na(ty) && ty %in% .tf_PRECISE
    }, logical(1)))
    share <- n_precise / length(preds)
    out$precision <- item(if (share >= thr$min_precision_share) "pass" else "warn",
                          .tf_rnd(share, 3))
  }

  # 3 risk_severity
  sevs <- numeric(0)
  for (p in preds) {
    s <- .tf_get(p, "severity")
    if (!is.null(s) && length(s) == 1L && !is.na(s)) {
      sevs <- c(sevs, as.numeric(s))
    }
  }
  if (length(sevs) == 0L) {
    out$risk_severity <- item("warn", 0.0)
  } else {
    m <- sum(sevs) / length(sevs)
    out$risk_severity <- item(if (m >= thr$min_severity) "pass" else "warn",
                              .tf_rnd(m, 3))
  }

  # 4 parsimony
  ratio <- length(aux) / max(1L, length(props))
  ad_hoc <- 0L
  for (x in aux) {
    af <- .tf_get(x, "added_for")
    if (!is.null(af)) {
      protects <- .tf_get(x, "protects")
      if (is.null(protects)) protects <- list()
      protects <- unlist(protects, use.names = FALSE)
      ok <- FALSE
      for (t in tos) {
        pid <- .tf_get(t, "prediction_id")
        passed <- .tf_get(t, "passed")
        if (!is.null(pid) && length(pid) == 1L && pid %in% protects &&
            isTRUE(passed)) {
          ok <- TRUE
          break
        }
      }
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
    toks <- lapply(cons, function(c) tf_tokens(.tf_get(c, "definition", "")))
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
    rel <- .tf_get(p, "relation")
    length(rel) == 1L && !is.na(rel) && rel %in% .tf_CAUSAL
  }, logical(1)))
  out$causal_testability <- if (n_causal >= 1L) item("pass", 1.0) else item("warn", 0.0)

  # 10 diagnosticity
  if (length(preds) == 0L) {
    out$diagnosticity <- item("warn", 0.0)
  } else {
    n_diag <- sum(vapply(preds, function(p) {
      dv <- .tf_get(p, "diagnostic_vs")
      if (!.tf_ne_list(dv)) return(FALSE)
      dv <- unlist(dv, use.names = FALSE)
      any(dv %in% alt_ids)
    }, logical(1)))
    out$diagnosticity <- item(if (n_diag >= 1L) "pass" else "warn",
                              .tf_rnd(n_diag / length(preds), 3))
  }

  # 11 formalization
  fm <- .tf_get(T, "formal_model")
  fm_type <- if (is.list(fm)) .tf_get(fm, "type") else NULL
  present <- is.list(fm) && !is.null(fm_type) && length(fm_type) == 1L &&
    !is.na(fm_type) && !(fm_type %in% "none")
  out$formalization <- if (present) item("pass", 1.0) else item("warn", 0.0)

  # 12 derivation_chain
  if (length(preds) == 0L) {
    out$derivation_chain <- item("pass", 1.0)
  } else {
    n_valid <- sum(vapply(preds, function(p) {
      df <- .tf_get(p, "derives_from")
      if (!.tf_ne_list(df)) return(FALSE)
      df <- unlist(df, use.names = FALSE)
      all(df %in% prop_ids)
    }, logical(1)))
    frac <- n_valid / length(preds)
    out$derivation_chain <- item(if (frac == 1.0) "pass" else "fail", .tf_rnd(frac, 3))
  }

  out
}

#' Compute the rigour checklist report
#'
#' Runs the full rigour checklist (12 items) over a theory object and returns a
#' report. Mirrors the Python \code{theory.check()} dict, including key order
#' and item order. See API_SPEC.md section 4.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A named list with elements \code{theory_id}, \code{schema_version},
#'   \code{maturity}, \code{aggregate_score}, \code{gate},
#'   \code{n_blockers_failed}, and \code{items} (a list of per-item lists).
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

  maturity <- .tf_str(T, "maturity")
  if (identical(maturity, "draft")) {
    gate <- "advisory"
  } else {
    gate <- if (n_blockers_failed > 0L) "blocked" else "pass"
  }

  list(
    theory_id = .tf_str(T, "id"),
    schema_version = .tf_str(T, "schema_version"),
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
#' fragment.
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
    rows <- vapply(rep$items, function(it) {
      sprintf('    <tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
              it$id, it$status, format_score_html(it$score), it$citation)
    }, character(1))
    rows <- paste(rows, collapse = "\n")
    return(paste0(
      '<section class="theoryforge-report">\n',
      sprintf('  <h2>Rigor report: %s</h2>\n', rep$theory_id),
      sprintf('  <p>Aggregate score: <strong>%s</strong> &middot; gate: <strong>%s</strong></p>\n',
              format_score_html(rep$aggregate_score), rep$gate),
      '  <table>\n    <tr><th>item</th><th>status</th><th>score</th><th>grounding</th></tr>\n',
      rows, '\n  </table>\n</section>\n'
    ))
  }
  stop(sprintf("unknown report format: '%s'", format), call. = FALSE)
}

# Render a numeric score the way Python's str() would for the HTML table
# (e.g. 1.0, 0.667). Not parity-tested, but kept readable.
format_score_html <- function(x) {
  if (is.numeric(x)) {
    if (x == round(x)) {
      return(sprintf("%.1f", x))
    }
    return(format(x, trim = TRUE))
  }
  as.character(x)
}
