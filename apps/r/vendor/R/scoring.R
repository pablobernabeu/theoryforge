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
