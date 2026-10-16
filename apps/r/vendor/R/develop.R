#' Development mode: amendment appraisal.
#'
#' Operationalises the Lakatosian progressive-vs-degenerating distinction
#' (Lakatos, 1970; Meehl, 1990a).
#' @name develop
#' @keywords internal
NULL

# The helpers below read the evidence of the appraisal (API_SPEC.md section
# 10). The Python twin's _status.py holds the same three.

# The status of prediction `pid` over every test outcome in `tos`:
# "corroborated" when at least one outcome passed and none failed, "refuted"
# when some failed and none passed, "mixed" when both occur and "untested"
# otherwise. The order of the outcomes is not read, and neither are their
# dates, which the schema leaves free-form. An outcome counts only when its
# prediction_id is the string `pid`, and a missing, NULL or NA `passed` is
# neither a pass nor a failure.
.tf_prediction_status <- function(pid, tos) {
  passed <- FALSE
  failed <- FALSE
  for (t in tos) {
    tid <- .tf_get(t, "prediction_id")
    if (!(.tf_is_string(tid) && tid == pid)) next
    outcome <- .tf_get(t, "passed")
    if (isTRUE(outcome)) {
      passed <- TRUE
    } else if (isFALSE(outcome)) {
      failed <- TRUE
    }
  }
  if (passed) {
    if (failed) "mixed" else "corroborated"
  } else {
    if (failed) "refuted" else "untested"
  }
}

# What a prediction claims: its statement with whitespace runs squished, and its
# type ("" outside its enum). Two predictions with the same key make the same
# claim whatever their ids, so a prediction that changed only its id, or the
# line breaks of its statement, is the same content.
.tf_content_key <- function(p) {
  c(.tf_squish(.tf_str(p, "statement")), .tf_enum_str(p, "type", .tf_PRED_TYPE))
}

# The ad hoc class of an assumption added for an anomaly, with the evidence for
# it. The independent predictions are the distinct entries of its protects, in
# their order, that are in `eligible` and are not its added_for: what could
# support the assumption other than the anomaly it answers, each with its status
# in `tos`. The class is "ad_hoc1" when there are none, "ad_hoc2" when none is
# corroborated and "independently_corroborated" otherwise. The appraisal passes
# the predictions that are new in the amended version as `eligible`, so content
# the prior already held cannot clear an assumption.
.tf_classify_auxiliary <- function(a, tos, eligible) {
  added_for <- .tf_str(a, "added_for")
  protects <- .tf_str_list(.tf_get(a, "protects"))
  ids <- unique(protects[protects != added_for & protects %in% eligible])
  independent <- lapply(ids, function(q) list(id = q, status = .tf_prediction_status(q, tos)))
  statuses <- vapply(independent, function(r) r$status, character(1))
  class <- if (length(ids) == 0L) {
    "ad_hoc1"
  } else if (!any(statuses == "corroborated")) {
    "ad_hoc2"
  } else {
    "independently_corroborated"
  }
  list(class = class, independent = independent)
}

# Whether each of `ids` has one of `statuses` over `tos`.
.tf_status_in <- function(ids, tos, statuses) {
  vapply(ids, function(pid) .tf_prediction_status(pid, tos) %in% statuses, logical(1),
         USE.NAMES = FALSE)
}

#' Appraise an amendment as progressive, degenerating, or neutral
#'
#' Compares an amended theory \code{new} with its \code{prior} version by
#' content, not by prediction ids, and returns a Lakatosian verdict with the
#' evidence behind it.
#'
#' A new prediction whose statement and type match a prediction the amendment
#' dropped is that prediction renamed. A new prediction derived only from
#' propositions the prior already held, and needing no new assumption,
#' articulates old content. A prediction is corroborated when at least one test
#' outcome passes it and none fails it. An assumption added for an anomaly (its
#' \code{added_for} names the prediction it answers) is ad hoc unless a
#' prediction it protects that is new in this version, other than the anomaly,
#' is corroborated.
#'
#' The verdict is \code{"progressive"} when a corroborated new prediction is
#' neither an articulation nor underived, no assumption is ad hoc and no
#' corroborated prediction is dropped. It is \code{"degenerating"} when an
#' assumption is ad hoc and no such prediction exists, and \code{"neutral"}
#' otherwise. Lakatos has only the first two. \code{"neutral"} is
#' theoryforge's label for an amendment that meets neither rule, and the
#' vectors returned tell its cases apart. Only
#' \code{corroborated_new_registered} reads a test outcome's
#' \code{registered}, and no date or \code{version} field is read, so which
#' version is the prior is the caller's responsibility.
#'
#' A test outcome whose \code{passed} is present and not \code{TRUE} or
#' \code{FALSE}, in \code{new} (checked first) or in \code{prior}, is refused
#' with the message the Python twin raises. A quoted \code{"true"} read as a
#' failure and could turn a progressive amendment into a degenerating one.
#'
#' @param new The amended theory object (named list).
#' @param prior The prior theory object (named list).
#' @return A named list whose first element, \code{verdict}, is one of
#'   \code{"progressive"}, \code{"degenerating"} and \code{"neutral"}.
#'   \code{new_predictions}, \code{corroborated_new}, \code{ad_hoc_assumptions},
#'   \code{articulated}, \code{underived}, \code{corroborated_new_registered},
#'   \code{dropped}, \code{dropped_corroborated}, \code{content_lost} and
#'   \code{new_anomalies} are ascending-sorted character vectors.
#'   \code{renamed} is a list of \code{list(prior, new)} pairs sorted by
#'   \code{new}, and \code{assumptions} holds one
#'   \code{list(id, added_for, class, independent)} per new assumption added
#'   for an anomaly, in file order. The four elements of earlier versions come
#'   first, in their old order.
#' @references
#' Lakatos, I. (1970). Falsification and the methodology of scientific research
#'   programmes. In \emph{Criticism and the growth of knowledge} (pp. 91-196).
#'   Cambridge University Press. \doi{10.1017/cbo9781139171434.009}
#'
#' Meehl, P. E. (1990a). Appraising and amending theories: The strategy of
#'   Lakatosian defense and two principles that warrant it. \emph{Psychological
#'   Inquiry}, 1(2), 108-141. \doi{10.1207/s15327965pli0102_1}
#' @examples
#' prior <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases") |>
#'   tf_add_prediction("h1", "Threat rises with arousal.", "directional",
#'                     derives_from = "p1")
#' new <- prior |>
#'   tf_add_construct("c_avoid", "Avoidance", "Withdrawal from feared situations.") |>
#'   tf_add_proposition("p2", "c_threat", "c_avoid", "increases") |>
#'   tf_add_prediction("h2", "Avoidance rises 0.3 SD per SD of threat.", "point",
#'                     derives_from = "p2")
#' new$test_outcomes <- list(list(prediction_id = "h2", passed = TRUE))
#' tf_appraise_amendment(new, prior)$verdict
#' @export
tf_appraise_amendment <- function(new, prior) {
  .tf_refuse_non_boolean_outcomes(new, "appraise_amendment")
  .tf_refuse_non_boolean_outcomes(prior, "appraise_amendment")
  # A missing id reads as "" (API_SPEC.md section 3, "Reading a theory"), as in
  # Python. tf_validate() reports the entry; the appraisal still runs.
  ids_of <- function(xs) unname(vapply(xs, function(x) .tf_str(x, "id"), character(1)))
  new_tos <- .tf_list(new, "test_outcomes")
  prior_tos <- .tf_list(prior, "test_outcomes")
  new_preds <- .tf_list(new, "predictions")
  prior_preds <- .tf_list(prior, "predictions")
  new_ids <- ids_of(new_preds)
  prior_ids <- ids_of(prior_preds)

  # A prediction under an id the prior lacks takes the first prior prediction
  # that makes the same claim, under an id the amendment dropped. A blank
  # statement claims nothing, so it is never matched.
  prior_keys <- lapply(prior_preds, .tf_content_key)
  taken <- rep(FALSE, length(prior_preds))
  renamed <- list()
  for (i in seq_along(new_preds)) {
    pid <- new_ids[[i]]
    key <- .tf_content_key(new_preds[[i]])
    if (pid %in% prior_ids || !nzchar(key[[1L]])) next
    for (j in seq_along(prior_preds)) {
      if (!taken[[j]] && !(prior_ids[[j]] %in% new_ids) && identical(prior_keys[[j]], key)) {
        taken[[j]] <- TRUE
        renamed[[length(renamed) + 1L]] <- list(prior = prior_ids[[j]], new = pid)
        break
      }
    }
  }
  renamed_new <- vapply(renamed, function(r) r$new, character(1))
  renamed_prior <- vapply(renamed, function(r) r$prior, character(1))

  new_predictions <- new_ids[!(new_ids %in% prior_ids) & !(new_ids %in% renamed_new)]
  corroborated_new <- new_predictions[.tf_status_in(new_predictions, new_tos, "corroborated")]

  # Old content: a proposition whose endpoints and relation the prior holds,
  # under any id, so renaming a proposition adds nothing either.
  prior_aux_ids <- ids_of(.tf_list(prior, "auxiliary_assumptions"))
  new_aux <- Filter(function(a) !(.tf_str(a, "id") %in% prior_aux_ids),
                    .tf_list(new, "auxiliary_assumptions"))
  protected <- as.character(unlist(lapply(new_aux, function(a) .tf_str_list(.tf_get(a, "protects")))))
  content <- function(p) {
    c(.tf_str(p, "from"), .tf_str(p, "to"), .tf_enum_str(p, "relation", .tf_RELATION))
  }
  old_content <- lapply(.tf_list(prior, "propositions"), content)
  new_props <- .tf_list(new, "propositions")
  new_prop_ids <- ids_of(new_props)
  is_old <- vapply(new_props, function(p) {
    any(vapply(old_content, identical, logical(1), content(p)))
  }, logical(1))
  articulated <- character(0)
  underived <- character(0)
  for (i in seq_along(new_preds)) {
    pid <- new_ids[[i]]
    if (!(pid %in% new_predictions)) next
    sources <- .tf_str_list(.tf_get(new_preds[[i]], "derives_from"))
    if (length(sources) == 0L) {
      underived <- c(underived, pid)
    } else if (!(pid %in% protected)) {
      j <- match(sources, new_prop_ids)
      if (!anyNA(j) && all(is_old[j])) articulated <- c(articulated, pid)
    }
  }

  dropped <- prior_ids[!(prior_ids %in% new_ids) & !(prior_ids %in% renamed_prior)]
  dropped_corroborated <- dropped[.tf_status_in(dropped, prior_tos, "corroborated")]
  content_lost <- dropped[.tf_status_in(dropped, prior_tos, "untested")]

  kept <- new_ids[new_ids %in% prior_ids]
  was <- c(kept, renamed_prior)
  now <- c(kept, renamed_new)
  new_anomalies <- now[.tf_status_in(now, new_tos, c("refuted", "mixed")) &
                         .tf_status_in(was, prior_tos, c("corroborated", "untested"))]

  assumptions <- list()
  ad_hoc <- character(0)
  for (a in new_aux) {
    added_for <- .tf_str(a, "added_for")
    if (!.tf_ne_str(added_for)) next
    aid <- .tf_str(a, "id")
    res <- .tf_classify_auxiliary(a, new_tos, new_predictions)
    assumptions[[length(assumptions) + 1L]] <- list(id = aid, added_for = added_for,
                                                    class = res$class,
                                                    independent = res$independent)
    if (!identical(res$class, "independently_corroborated")) ad_hoc <- c(ad_hoc, aid)
  }

  registered_pass <- function(pid) {
    any(vapply(new_tos, function(t) {
      tid <- .tf_get(t, "prediction_id")
      .tf_is_string(tid) && tid == pid && isTRUE(.tf_get(t, "passed")) &&
        .tf_ne_str(.tf_str(t, "registered"))
    }, logical(1)))
  }
  registered <- corroborated_new[vapply(corroborated_new, registered_pass, logical(1),
                                        USE.NAMES = FALSE)]

  adds_content <- corroborated_new[!(corroborated_new %in% articulated) &
                                     !(corroborated_new %in% underived)]
  if (length(adds_content) >= 1L && length(ad_hoc) == 0L && length(dropped_corroborated) == 0L) {
    verdict <- "progressive"
  } else if (length(ad_hoc) >= 1L && length(adds_content) == 0L) {
    verdict <- "degenerating"
  } else {
    verdict <- "neutral"
  }

  # Radix sorts match Python's codepoint ordering regardless of locale, and the
  # radix order is stable, so renames with one new id keep their file order.
  radix <- function(x) sort(x, method = "radix")
  list(
    verdict = verdict,
    new_predictions = radix(new_predictions),
    corroborated_new = radix(corroborated_new),
    ad_hoc_assumptions = radix(ad_hoc),
    articulated = radix(articulated),
    underived = radix(underived),
    corroborated_new_registered = radix(registered),
    renamed = renamed[order(renamed_new, method = "radix")],
    dropped = radix(dropped),
    dropped_corroborated = radix(dropped_corroborated),
    content_lost = radix(content_lost),
    new_anomalies = radix(new_anomalies),
    assumptions = assumptions
  )
}
