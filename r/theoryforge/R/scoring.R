#' Claim-form riskiness rubric (deterministic, pre-data)
#'
#' A pre-data ranking of the form of each prediction's claim. It reads a
#' prediction's declared \code{type} and its \code{diagnostic_vs} ids, and
#' neither the statement nor any test, outcome or data.
#' @name scoring
#' @keywords internal
NULL

# The base riskiness of each claim form. The order follows Popper's (1959,
# sections 31-33) comparison of falsifiability by the subclass relation. Of two
# claims about one quantity, the one whose potential falsifiers include the
# other's is the more falsifiable, and an existence claim, a sign within it, a
# range within that sign and a value within that range form such a chain. The
# four values themselves are a package convention.
.tf_SEV_BASE <- c(existence = 0.1, directional = 0.4, interval = 0.7, point = 0.9)
# The discount on a directional prediction, also a package convention. Meehl
# (1967, 1990b) argues that predicting a sign alone risks little where almost
# everything correlates a little, but he gives no discount. His .25 and .30 are
# sizes of those ambient (crud) correlations, a different quantity from this
# discount.
.tf_SEV_CRUD <- 0.25

#' Per-prediction claim-form riskiness
#'
#' A pre-data rubric of the form of each prediction's claim. \code{risk_score}
#' is the base riskiness of the declared type: existence 0.1, directional 0.4,
#' interval 0.7 and point 0.9. \code{computed_severity} discounts a directional
#' prediction by 25 per cent, adds 0.1 when \code{diagnostic_vs} names a
#' registered alternative and is capped at 1. The order of the types follows
#' Popper (1959, sections 31-33) for nested claims about one quantity, and the
#' directional penalty follows Meehl's (1967, 1990b) argument that a sign alone
#' risks little. The base values, the discount and the bonus are the package's
#' conventions, and neither source gives them.
#'
#' How severely a claim is tested depends on the design and the data, which the
#' rubric does not read. A prediction scores the same however it is tested, and
#' a failed test leaves the value where it was.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A \code{data.frame} with columns \code{prediction_id}, \code{type},
#'   \code{risk_score}, \code{computed_severity}, one row per prediction in
#'   file order.
#' @references
#' Meehl, P. E. (1967). Theory-testing in psychology and physics: A
#'   methodological paradox. \emph{Philosophy of Science}, 34(2), 103-115.
#'   \doi{10.1086/288135}
#'
#' Meehl, P. E. (1990b). Why summaries of research on psychological theories
#'   are often uninterpretable. \emph{Psychological Reports}, 66(1), 195-244.
#'   \doi{10.2466/pr0.1990.66.1.195}
#'
#' Popper, K. R. (1959). \emph{The logic of scientific discovery}. Hutchinson.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "Effect is exactly 0.30.", "point") |>
#'   tf_add_prediction("h2", "Effect is positive.", "directional")
#' tf_severity(theory)
#' @export
tf_severity <- function(theory) {
  T <- theory
  preds <- .tf_list(T, "predictions")
  alts <- .tf_list(T, "alternatives")
  alt_ids <- unique(vapply(alts, function(a) .tf_str(a, "id"), character(1)))

  n <- length(preds)
  prediction_id <- character(n)
  type <- character(n)
  risk_score <- numeric(n)
  computed_severity <- numeric(n)

  for (i in seq_len(n)) {
    p <- preds[[i]]
    typ <- .tf_enum_str(p, "type", .tf_PRED_TYPE)
    base <- if (typ %in% names(.tf_SEV_BASE)) .tf_SEV_BASE[[typ]] else 0.0
    discounted <- if (identical(typ, "directional")) base * (1 - .tf_SEV_CRUD) else base
    dv <- .tf_str_list(.tf_get(p, "diagnostic_vs"))
    # A package convention: naming a registered alternative the prediction
    # would discriminate from adds 0.1. The alternative is declared, not
    # checked against the statement.
    diag_bonus <- if (any(dv %in% alt_ids)) 0.1 else 0.0
    prediction_id[i] <- .tf_str(p, "id")
    type[i] <- typ
    risk_score[i] <- .tf_rnd(base, 3)
    computed_severity[i] <- .tf_rnd(min(1.0, discounted + diag_bonus), 3)
  }

  data.frame(
    prediction_id = prediction_id,
    type = type,
    risk_score = risk_score,
    computed_severity = computed_severity,
    stringsAsFactors = FALSE
  )
}

.tf_PDS_REFUSAL <- "post_data_severity requires "

# `v` as a double when it is a single number other than NaN, and NULL
# otherwise. A logical is not a number. The Python twin's _num.number() reads an
# integer too large for a float as an infinity, as R's reader holds it.
.tf_number <- function(v) {
  if (is.numeric(v) && length(v) == 1L && !is.na(v)) as.numeric(v) else NULL
}

.tf_finite <- function(x) {
  if (!is.null(x) && is.finite(x)) x else NULL
}

# The post-data severity of test outcome `t`, at 1-based position `i`, as
# list(row = <list>) when it is computed, list(error = <message>) when the
# outcome or its prediction's bounds are refused, and list() when there is
# nothing to compute: the outcome records neither an estimate nor a standard
# error, or names no prediction with bounds. A prediction's bounds are read
# only here, for an outcome whose data passed. The Python twin's _outcome_row()
# makes the same checks in the same order.
.tf_outcome_severity <- function(t, i, preds) {
  est_raw <- .tf_get(t, "estimate")
  se_raw <- .tf_get(t, "se")
  est_absent <- .tf_absent(est_raw)
  se_absent <- .tf_absent(se_raw)
  if (est_absent && se_absent) return(list())
  where <- sprintf("; test_outcome[%d]", i - 1L)
  if (est_absent || se_absent) {
    return(list(error = paste0(.tf_PDS_REFUSAL, "both estimate and se", where)))
  }
  se <- .tf_number(se_raw)
  if (is.null(se) || !is.finite(se) || se <= 0) {
    return(list(error = paste0(.tf_PDS_REFUSAL, "a finite se greater than 0", where)))
  }
  est <- .tf_number(est_raw)
  if (is.null(est) || !is.finite(est)) {
    return(list(error = paste0(.tf_PDS_REFUSAL, "a finite estimate", where)))
  }

  # The matching rule of the amendment appraisal (API_SPEC.md section 10): the
  # outcome's prediction_id must be a string, and the first prediction with
  # that id in file order is the one tested.
  pid <- .tf_get(t, "prediction_id")
  if (!.tf_is_string(pid)) return(list())
  pred <- NULL
  for (p in preds) {
    if (identical(.tf_str(p, "id"), pid)) {
      pred <- p
      break
    }
  }
  bounds <- .tf_get(pred, "bounds")
  if (.tf_absent(bounds)) return(list())
  where <- sprintf("; prediction '%s'", pid)
  shape <- paste0(.tf_PDS_REFUSAL, "bounds with numeric or null lower and upper", where)
  # An empty list() stands for an empty mapping, as {} and [] both read.
  if (!is.list(bounds) || (length(bounds) > 0L && !.tf_is_mapping(bounds))) {
    return(list(error = shape))
  }
  lo_raw <- .tf_get(bounds, "lower")
  up_raw <- .tf_get(bounds, "upper")
  lo <- .tf_number(lo_raw)
  up <- .tf_number(up_raw)
  # A bound that is present and not a number would otherwise read as open and
  # turn a two-sided claim into a one-sided one.
  if ((!.tf_absent(lo_raw) && is.null(lo)) || (!.tf_absent(up_raw) && is.null(up))) {
    return(list(error = shape))
  }
  lower <- .tf_finite(lo)
  upper <- .tf_finite(up)
  if (is.null(lower) && is.null(upper)) {
    return(list(error = paste0(.tf_PDS_REFUSAL, "at least one finite bound", where)))
  }
  if (!is.null(lo) && !is.null(up) && lo > up) {
    return(list(error = paste0(.tf_PDS_REFUSAL, "lower <= upper", where)))
  }

  z <- c(if (!is.null(lower)) (est - lower) / se, if (!is.null(upper)) (upper - est) / se)
  list(row = list(
    prediction_id = pid, outcome = i - 1L,
    lower = if (is.null(lower)) NA_real_ else lower,
    upper = if (is.null(upper)) NA_real_ else upper,
    estimate = est, se = se, severity = .tf_rnd(min(stats::pnorm(z)), 3)
  ))
}

# .tf_outcome_severity() for every test outcome, in file order.
# tf_post_data_severity() stops at the first refusal, and tf_dossier() gives the
# rows it can compute without stopping.
.tf_outcome_severities <- function(theory) {
  preds <- .tf_list(theory, "predictions")
  tos <- .tf_list(theory, "test_outcomes")
  lapply(seq_along(tos), function(i) .tf_outcome_severity(tos[[i]], i, preds))
}

#' Post-data severity of each bounded prediction
#'
#' How severely each bounded claim passed its test, from the test outcome's
#' estimate and standard error.
#'
#' A prediction states the region its claim allows in \code{bounds}, a mapping
#' of \code{lower} and \code{upper}, either of which may be null (or infinite)
#' for an open side. A test outcome records the \code{estimate} it observed and
#' its standard error \code{se}. For an outcome with both, whose prediction
#' declares bounds, the severity with which the claim passed is the smallest of
#' \eqn{\Phi((estimate - lower) / se)}{Phi((estimate - lower) / se)} and
#' \eqn{\Phi((upper - estimate) / se)}{Phi((upper - estimate) / se)} over the
#' finite bounds, rounded to three decimals (Mayo & Spanos, 2006, 2011). It is
#' the probability that the test would have given a result less in accord with
#' the claim, had the claim been false at the bound. A one-sided claim, such as
#' an effect above a smallest effect of interest, is a lower bound with the
#' upper one open.
#'
#' The computation is a normal approximation to the sampling distribution of
#' the estimate. With two finite bounds, the value equals 1 minus the p value of
#' the two one-sided tests (TOST) of equivalence. A point claim with lower equal
#' to upper can pass with a severity of at most 0.5, so it needs a tolerance
#' around its value. Unlike [tf_severity()], which grades the form of a claim
#' before any data, this value depends on the design and the data. The rigour
#' checklist does not read it. [tf_dossier()] gives each value in its test
#' record.
#'
#' The function stops at the first outcome, in file order, that cannot be
#' read, with the Python twin's text:
#' `post_data_severity requires both estimate and se; test_outcome[<i>]`,
#' `... requires a finite se greater than 0; ...` and
#' `... requires a finite estimate; ...`, and for its prediction's bounds
#' `... requires bounds with numeric or null lower and upper; prediction '<id>'`,
#' `... requires at least one finite bound; ...` and
#' `... requires lower <= upper; ...`. [tf_validate()] with `full = TRUE`
#' reports each of these.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A \code{data.frame} with one row per test outcome, in file order,
#'   that carries both an estimate and a standard error and whose prediction
#'   declares bounds. Its columns are \code{prediction_id}, \code{outcome} (the
#'   outcome's 0-based index among the test outcomes), \code{lower} and
#'   \code{upper} (\code{NA} for an open bound), \code{estimate}, \code{se} and
#'   \code{severity}.
#' @references
#' Mayo, D. G., & Spanos, A. (2006). Severe testing as a basic concept in a
#'   Neyman-Pearson philosophy of induction. \emph{The British Journal for the
#'   Philosophy of Science}, 57(2), 323-357. \doi{10.1093/bjps/axl003}
#'
#' Mayo, D. G., & Spanos, A. (2011). Error statistics. In P. S. Bandyopadhyay &
#'   M. R. Forster (Eds.), \emph{Philosophy of statistics} (pp. 153-198).
#'   Elsevier. \doi{10.1016/B978-0-444-51862-0.50005-8}
#' @examples
#' theory <- tf_read(tf_example_path("modality-switching.theory.yaml"))
#' tf_post_data_severity(theory)
#'
#' # A claim that |r| <= .10, tested with an estimate of 0 and a standard error
#' # of .10, passes with a severity of .841.
#' theory$predictions[[4]]$bounds <- list(lower = -0.10, upper = 0.10)
#' theory$test_outcomes <- list(list(prediction_id = "pred4", passed = TRUE,
#'                                   estimate = 0, se = 0.10))
#' tf_post_data_severity(theory)
#' @export
tf_post_data_severity <- function(theory) {
  rows <- list()
  for (res in .tf_outcome_severities(theory)) {
    if (!is.null(res$error)) stop(res$error, call. = FALSE)
    if (!is.null(res$row)) rows[[length(rows) + 1L]] <- res$row
  }
  column <- function(key, empty) {
    if (length(rows) == 0L) empty else unlist(lapply(rows, `[[`, key), use.names = FALSE)
  }
  data.frame(
    prediction_id = column("prediction_id", character(0)),
    outcome = column("outcome", integer(0)),
    lower = column("lower", numeric(0)),
    upper = column("upper", numeric(0)),
    estimate = column("estimate", numeric(0)),
    se = column("se", numeric(0)),
    severity = column("severity", numeric(0)),
    stringsAsFactors = FALSE
  )
}
