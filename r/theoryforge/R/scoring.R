#' Severity rubric (deterministic).
#'
#' A documented, deterministic operationalization of predictive risk. See
#' API_SPEC.md section 9. Byte-/value-identical to the Python reference.
#' @name scoring
#' @keywords internal
NULL

# BASE riskiness of each claim form. CRUD = Meehl (1990) ambient-correlation
# discount applied to directional predictions only.
.tf_SEV_BASE <- c(existence = 0.1, directional = 0.4, interval = 0.7, point = 0.9)
.tf_SEV_CRUD <- 0.25

#' Per-prediction risk and computed severity
#'
#' Computes, for each prediction (in file order), the riskiness of the claim
#' form and the discounted/bonus-adjusted severity. Mirrors the Python
#' \code{theory.severity()}. See API_SPEC.md section 9.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A \code{data.frame} with columns \code{prediction_id}, \code{type},
#'   \code{risk_score}, \code{computed_severity}, one row per prediction in
#'   file order.
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
    typ <- .tf_str(p, "type")
    base <- if (typ %in% names(.tf_SEV_BASE)) .tf_SEV_BASE[[typ]] else 0.0
    discounted <- if (identical(typ, "directional")) base * (1 - .tf_SEV_CRUD) else base
    dv <- .tf_get(p, "diagnostic_vs")
    diag_bonus <- 0.0
    if (.tf_ne_list(dv)) {
      dv <- unlist(dv, use.names = FALSE)
      if (any(dv %in% alt_ids)) diag_bonus <- 0.1
    }
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
