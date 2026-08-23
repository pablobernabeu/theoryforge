#' Development mode: amendment appraisal.
#'
#' Operationalises the Lakatosian progressive-vs-degenerating distinction
#' (Lakatos, 1970; Meehl, 1990).
#' @name develop
#' @keywords internal
NULL

#' Appraise an amendment as progressive, degenerating, or neutral
#'
#' Compares an amended theory \code{new} against its \code{prior} version and
#' returns a Lakatosian verdict.
#'
#' @param new The amended theory object (named list).
#' @param prior The prior theory object (named list).
#' @return A named list with \code{verdict} (one of \code{"progressive"},
#'   \code{"degenerating"}, \code{"neutral"}) and the ascending-sorted
#'   character vectors \code{new_predictions}, \code{corroborated_new},
#'   \code{ad_hoc_assumptions}.
#' @references
#' Lakatos, I. (1970). Falsification and the methodology of scientific research
#'   programmes. In \emph{Criticism and the growth of knowledge} (pp. 91-196).
#'   Cambridge University Press. \doi{10.1017/cbo9781139171434.009}
#'
#' Meehl, P. E. (1990). Appraising and amending theories. \emph{Psychological
#'   Inquiry}, 1(2), 108-141. \doi{10.1207/s15327965pli0102_1}
#' @examples
#' prior <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_prediction("h1", "Effect is positive.", "directional")
#' new <- prior |>
#'   tf_add_prediction("h2", "Effect is exactly 0.30.", "point")
#' new$test_outcomes <- list(list(prediction_id = "h2", passed = TRUE))
#' tf_appraise_amendment(new, prior)
#' @export
tf_appraise_amendment <- function(new, prior) {
  prior_pred_ids <- unique(vapply(.tf_list(prior, "predictions"),
                                  function(p) .tf_str(p, "id"), character(1)))
  prior_aux_ids <- unique(vapply(.tf_list(prior, "auxiliary_assumptions"),
                                 function(a) .tf_str(a, "id"), character(1)))
  tos <- .tf_list(new, "test_outcomes")

  passed <- function(pid) {
    for (t in tos) {
      to_pid <- .tf_get(t, "prediction_id")
      if (!is.null(to_pid) && length(to_pid) == 1L && identical(to_pid, pid) &&
          isTRUE(.tf_get(t, "passed"))) {
        return(TRUE)
      }
    }
    FALSE
  }

  new_predictions <- character(0)
  for (p in .tf_list(new, "predictions")) {
    pid <- .tf_str(p, "id")
    if (!(pid %in% prior_pred_ids)) new_predictions <- c(new_predictions, pid)
  }

  corroborated_new <- new_predictions[vapply(new_predictions, passed, logical(1))]

  ad_hoc <- character(0)
  for (a in .tf_list(new, "auxiliary_assumptions")) {
    aid <- .tf_str(a, "id")
    if (aid %in% prior_aux_ids) next
    af <- .tf_get(a, "added_for")
    if (is.null(af)) next
    protects <- .tf_get(a, "protects")
    protects <- if (is.null(protects)) character(0) else unlist(protects, use.names = FALSE)
    immunized <- FALSE
    for (t in tos) {
      to_pid <- .tf_get(t, "prediction_id")
      if (!is.null(to_pid) && length(to_pid) == 1L && to_pid %in% protects &&
          isTRUE(.tf_get(t, "passed"))) {
        immunized <- TRUE
        break
      }
    }
    if (!immunized) ad_hoc <- c(ad_hoc, aid)
  }

  if (length(corroborated_new) >= 1L && length(ad_hoc) == 0L) {
    verdict <- "progressive"
  } else if (length(ad_hoc) >= 1L && length(corroborated_new) == 0L) {
    verdict <- "degenerating"
  } else {
    verdict <- "neutral"
  }

  # Radix sorts match Python's codepoint ordering regardless of locale.
  list(
    verdict = verdict,
    new_predictions = sort(new_predictions, method = "radix"),
    corroborated_new = sort(corroborated_new, method = "radix"),
    ad_hoc_assumptions = sort(ad_hoc, method = "radix")
  )
}
