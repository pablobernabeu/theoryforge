#' Development mode: amendment appraisal.
#'
#' Operationalises the Lakatosian distinction between progressive and
#' degenerating amendments (Lakatos, 1970; Meehl, 1990a).
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
# the prior already held cannot clear an assumption. It also passes the anomaly
# it inferred as `added_for` when the assumption names none.
.tf_classify_auxiliary <- function(a, tos, eligible, added_for = .tf_str(a, "added_for")) {
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

# The helpers below compare the content of a prediction in two versions. Each
# says how the new value stands to the old one: "same", "weaker", "stronger" or
# "different" when neither is weaker. The Python twin's develop.py holds the
# same routines.

# The prediction types from the weakest claim form to the strongest (API_SPEC.md
# section 9).
.tf_TYPE_RANK <- c(existence = 1L, directional = 2L, interval = 3L, point = 4L)

.tf_type_change <- function(old, new) {
  if (identical(old, new)) return("same")
  if (old %in% names(.tf_TYPE_RANK) && new %in% names(.tf_TYPE_RANK)) {
    return(if (.tf_TYPE_RANK[[new]] < .tf_TYPE_RANK[[old]]) "weaker" else "stronger")
  }
  "different"
}

# The region a prediction's bounds allow, as c(lower, upper). An absent, null,
# infinite or non-numeric bound is open.
.tf_region <- function(p) {
  b <- .tf_get(p, "bounds")
  side <- function(key, open) {
    x <- .tf_number(.tf_get(b, key))
    if (is.null(x) || !is.finite(x)) open else x
  }
  c(side("lower", -Inf), side("upper", Inf))
}

# Whether region `a` is narrower than region `b`: it lies within `b` and differs
# from it, or it has more finite sides, so that a two-sided region is narrower
# than a one-sided one.
.tf_narrower <- function(a, b) {
  sides <- function(r) sum(is.finite(r))
  (!all(a == b) && b[[1L]] <= a[[1L]] && a[[2L]] <= b[[2L]]) || sides(a) > sides(b)
}

.tf_bounds_change <- function(old, new) {
  if (all(old == new)) return("same")
  if (.tf_narrower(new, old)) return("stronger")
  if (.tf_narrower(old, new)) return("weaker")
  "different"
}

# The claim a prediction states, or NULL when it states none that can be
# evaluated.
.tf_stated_claim <- function(p) {
  cl <- .tf_read_claim(.tf_get(p, "claim"))
  if (is.null(cl) || !cl$ok) NULL else cl
}

.tf_claim_change <- function(old, new) {
  if (is.null(old) || is.null(new)) {
    if (is.null(old) && is.null(new)) return("same")
    return(if (is.null(old)) "stronger" else "weaker")
  }
  pair <- (old$x == new$x && old$y == new$y) ||
    (old$kind == "association" && old$x == new$y && old$y == new$x)
  if (old$kind != new$kind || !pair || !setequal(old$given, new$given)) return("different")
  if (old$sign == new$sign) return("same")
  if (new$sign == "nonzero") return("weaker")
  if (old$sign == "nonzero") return("stronger")
  "different"
}

# How prediction `new` revises `old`, or NULL when its content is unchanged.
.tf_revision <- function(old, new) {
  changes <- c(
    .tf_type_change(.tf_enum_str(old, "type", .tf_PRED_TYPE), .tf_enum_str(new, "type", .tf_PRED_TYPE)),
    .tf_bounds_change(.tf_region(old), .tf_region(new)),
    .tf_claim_change(.tf_stated_claim(old), .tf_stated_claim(new))
  )
  weaker <- "weaker" %in% changes
  stronger <- "stronger" %in% changes
  if (weaker != stronger) return(if (weaker) "weakened" else "strengthened")
  if (weaker || "different" %in% changes) return("changed")
  if (.tf_content_key(old)[[1L]] != .tf_content_key(new)[[1L]]) return("reworded")
  NULL
}

# Whether the records in `recs` name the pair of constructs `a` and `b`, in
# either order.
.tf_has_pair <- function(recs, a, b) {
  any(vapply(recs, function(r) (r$a == a && r$b == b) || (r$a == b && r$b == a), logical(1)))
}

# The assumptions of `new` that the appraisal reads, in file order, each as
# list(a, change). An assumption kept under a prior id is read, as "revised",
# when its statement, with whitespace runs squished, differs from that of the
# first prior assumption with that id, by any change of wording. An assumption
# under an id the prior lacks is read, as "new", unless its statement is not
# blank and matches that of a prior assumption whose id the new version no
# longer holds, which it then takes, so that a renamed assumption is not new.
# Its added_for and protects alone do not decide. Python's
# _appraised_assumptions holds the same rule.
.tf_appraised_assumptions <- function(new, prior) {
  prior_aux <- .tf_list(prior, "auxiliary_assumptions")
  new_aux <- .tf_list(new, "auxiliary_assumptions")
  prior_ids <- unname(vapply(prior_aux, function(a) .tf_str(a, "id"), character(1)))
  prior_statements <- unname(vapply(prior_aux, function(a) .tf_squish(.tf_str(a, "statement")),
                                    character(1)))
  new_ids <- unname(vapply(new_aux, function(a) .tf_str(a, "id"), character(1)))
  taken <- rep(FALSE, length(prior_aux))
  read <- list()
  for (a in new_aux) {
    aid <- .tf_str(a, "id")
    st <- .tf_squish(.tf_str(a, "statement"))
    k <- match(aid, prior_ids)
    if (!is.na(k)) {
      if (st != prior_statements[[k]]) read[[length(read) + 1L]] <- list(a = a, change = "revised")
      next
    }
    renamed <- FALSE
    if (nzchar(st)) {
      for (j in seq_along(prior_aux)) {
        if (!taken[[j]] && !(prior_ids[[j]] %in% new_ids) && prior_statements[[j]] == st) {
          taken[[j]] <- TRUE
          renamed <- TRUE
          break
        }
      }
    }
    if (!renamed) read[[length(read) + 1L]] <- list(a = a, change = "new")
  }
  read
}

#' Appraise an amendment as progressive, degenerating or neutral
#'
#' Compares an amended theory \code{new} with its \code{prior} version by
#' content, not by prediction ids, and returns a Lakatosian verdict with the
#' evidence behind it.
#'
#' A new prediction whose statement and type match a prediction the amendment
#' dropped is that prediction renamed. Assumptions are compared by statement
#' too. An assumption kept under its id is revised when its statement changed,
#' and one under a new id whose statement matches that of an assumption the
#' amendment dropped is that assumption renamed, so only a new or revised
#' assumption is appraised. A new prediction articulates old content when it
#' derives only from propositions the prior already held and needs no new or
#' revised assumption, or when the prior's causal graph already entails its
#' claim. It is underived when it cites no proposition and unresolved when it
#' cites an id that names no proposition of the new version. A prediction is
#' corroborated when at least one test outcome passes it and none fails it. A
#' new or revised assumption added for an anomaly is ad hoc unless a
#' prediction it protects that is new in this version, other than the anomaly,
#' is corroborated. Its \code{added_for} names the anomaly. When that is empty,
#' the first prediction it protects that was refuted or mixed in the prior is
#' taken as the anomaly.
#'
#' A prediction kept from the prior, under its id or renamed, is revised when
#' its statement, type, bounds or claim changed. Its content is weaker when its
#' type ranks lower in existence < directional < interval < point, when its
#' bounds allow a wider region, when it drops its claim or when its claim gives
#' up a sign of positive, negative or zero for nonzero. The two causal graphs
#' are compared through [tf_implications()] with \code{cycles = "sigma"}. A
#' pair of constructs that the prior's graph separates and the new graph does
#' not is an implication lost. It is refuted when a prediction of the prior
#' that states the independence of the two is refuted or mixed there.
#'
#' The amendment is theoretically progressive when a new prediction adds
#' content, being neither renamed, articulated, underived nor unresolved, and
#' empirically progressive when one of these is corroborated. The verdict is
#' \code{"progressive"} when it is both, no assumption is ad hoc, no
#' corroborated prediction is dropped, no content is lost and no prediction
#' refuted or mixed in the prior is weakened. Content is lost when an untested
#' prediction is dropped, an untested or corroborated prediction is weakened or
#' an implication is lost without being refuted. The rule follows Lakatos
#' (1970, p. 118), who considers series in which 'each theory \[has\] at least
#' as much content as the unrefuted content of its predecessor'. The verdict is
#' \code{"degenerating"} when an assumption is ad hoc or a prediction refuted
#' or mixed in the prior is weakened, and no prediction adds corroborated
#' content. It is \code{"neutral"} otherwise. Lakatos has only the first two.
#' \code{"neutral"} is theoryforge's label for an amendment that meets neither
#' rule, and the vectors returned tell its cases apart. Only
#' \code{corroborated_new_registered} reads a test outcome's
#' \code{registered}, and no date or \code{version} field is read, so which
#' version is the prior is the caller's responsibility. API_SPEC.md section 10
#' states every rule in full.
#'
#' A test outcome whose \code{passed} is present and not \code{TRUE} or
#' \code{FALSE}, in \code{new} (checked first) or in \code{prior}, is
#' refused. Read as not passed, a quoted \code{"true"} could turn a progressive
#' amendment into a degenerating one.
#'
#' @param new The amended theory object (named list).
#' @param prior The prior theory object (named list).
#' @return A named list whose first element, \code{verdict}, is one of
#'   \code{"progressive"}, \code{"degenerating"} and \code{"neutral"}.
#'   \code{new_predictions}, \code{corroborated_new}, \code{ad_hoc_assumptions},
#'   \code{articulated}, \code{underived}, \code{corroborated_new_registered},
#'   \code{dropped}, \code{dropped_corroborated}, \code{content_lost},
#'   \code{new_anomalies}, \code{weakened_refuted} and \code{unresolved} are
#'   ascending-sorted character vectors. \code{content_lost} holds the untested
#'   predictions the amendment drops, under their prior ids, and the untested
#'   or corroborated predictions it weakens, under their new ids.
#'   \code{weakened_refuted} holds the predictions refuted or mixed in the
#'   prior that it weakens. \code{renamed} is a list of
#'   \code{list(prior, new)} pairs sorted by \code{new}, and \code{revised} a
#'   list of \code{list(id, change)} records, one per revised prediction sorted
#'   by its new id, where \code{change} is \code{"weakened"},
#'   \code{"strengthened"}, \code{"reworded"} or \code{"changed"}.
#'   \code{assumptions} holds one
#'   \code{list(id, added_for, class, independent, added_for_inferred, change)}
#'   per new or revised assumption added for an anomaly, in file order.
#'   \code{added_for_inferred} is \code{TRUE} when \code{added_for} was taken
#'   from \code{protects}. \code{change} is \code{"new"} for an assumption
#'   under an id the prior lacks and \code{"revised"} for one kept under its id
#'   whose statement changed, by any change of wording, even one that keeps its
#'   meaning. \code{independent} lists, each as
#'   \code{list(id, status)} and in the order of \code{protects}, the distinct
#'   predictions the assumption protects that are new in this version and
#'   differ from \code{added_for}, with their status in \code{new}
#'   (\code{"corroborated"}, \code{"refuted"}, \code{"mixed"} or
#'   \code{"untested"}). \code{class} is \code{"ad_hoc1"} when there are none,
#'   \code{"ad_hoc2"} when none is corroborated and
#'   \code{"independently_corroborated"} otherwise, and
#'   \code{ad_hoc_assumptions} holds the ids of the first two classes.
#'   \code{theoretically_progressive} and \code{empirically_progressive} are
#'   logical. \code{implications_lost} and \code{implications_lost_unrefuted}
#'   hold the statements of the lost implications, all of them and the
#'   unrefuted ones, in the order of the prior's record, and
#'   \code{implications_gained} the statements of the pairs the new graph
#'   separates and the prior's does not, in the order of the new record.
#'   \code{implications_compared} is \code{FALSE}, and the three vectors are
#'   empty, when [tf_implications()] refuses either version. The elements
#'   come in the order \code{verdict}, \code{new_predictions},
#'   \code{corroborated_new}, \code{ad_hoc_assumptions}, \code{articulated},
#'   \code{underived}, \code{corroborated_new_registered}, \code{renamed},
#'   \code{dropped}, \code{dropped_corroborated}, \code{content_lost},
#'   \code{new_anomalies}, \code{assumptions},
#'   \code{theoretically_progressive}, \code{empirically_progressive},
#'   \code{revised}, \code{weakened_refuted}, \code{unresolved},
#'   \code{implications_compared}, \code{implications_lost},
#'   \code{implications_lost_unrefuted} and \code{implications_gained}.
#' @references
#' Lakatos, I. (1970). Falsification and the methodology of scientific research
#'   programmes. In I. Lakatos & A. Musgrave (Eds.), \emph{Criticism and the
#'   growth of knowledge} (pp. 91-196). Cambridge University Press.
#'   \doi{10.1017/cbo9781139171434.009}
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
  failed <- c("refuted", "mixed")

  # A prediction under an id the prior lacks takes the first prior prediction
  # that makes the same claim, under an id the amendment dropped. A blank
  # statement claims nothing, so it is never matched. Each retained prediction
  # is list(was, now, old, cur): its prior id, its new id and the two entries,
  # those kept under their id in file order and then the renames.
  prior_keys <- lapply(prior_preds, .tf_content_key)
  taken <- rep(FALSE, length(prior_preds))
  renamed <- list()
  retained <- lapply(which(new_ids %in% prior_ids), function(i) {
    list(was = new_ids[[i]], now = new_ids[[i]],
         old = prior_preds[[match(new_ids[[i]], prior_ids)]], cur = new_preds[[i]])
  })
  for (i in seq_along(new_preds)) {
    pid <- new_ids[[i]]
    key <- .tf_content_key(new_preds[[i]])
    if (pid %in% prior_ids || !nzchar(key[[1L]])) next
    for (j in seq_along(prior_preds)) {
      if (!taken[[j]] && !(prior_ids[[j]] %in% new_ids) && identical(prior_keys[[j]], key)) {
        taken[[j]] <- TRUE
        renamed[[length(renamed) + 1L]] <- list(prior = prior_ids[[j]], new = pid)
        retained[[length(retained) + 1L]] <- list(was = prior_ids[[j]], now = pid,
                                                  old = prior_preds[[j]], cur = new_preds[[i]])
        break
      }
    }
  }
  renamed_new <- vapply(renamed, function(r) r$new, character(1))
  renamed_prior <- vapply(renamed, function(r) r$prior, character(1))
  prior_id_of <- function(q) {
    k <- match(q, renamed_new)
    if (is.na(k)) q else renamed_prior[[k]]
  }

  new_predictions <- new_ids[!(new_ids %in% prior_ids) & !(new_ids %in% renamed_new)]
  corroborated_new <- new_predictions[.tf_status_in(new_predictions, new_tos, "corroborated")]

  # The new and revised assumptions, the only ones appraised, each with its
  # change, and the predictions they protect.
  appraised <- .tf_appraised_assumptions(new, prior)
  protected <- as.character(unlist(lapply(appraised, function(entry) {
    .tf_str_list(.tf_get(entry$a, "protects"))
  })))

  # Old content: a proposition whose endpoints and relation the prior holds,
  # under any id, so renaming a proposition adds nothing either. A claim the
  # prior's causal graph entails is old content too, whatever the prediction
  # cites.
  content <- function(p) {
    c(.tf_str(p, "from"), .tf_str(p, "to"), .tf_enum_str(p, "relation", .tf_RELATION))
  }
  old_content <- lapply(.tf_list(prior, "propositions"), content)
  new_props <- .tf_list(new, "propositions")
  new_prop_ids <- ids_of(new_props)
  is_old <- vapply(new_props, function(p) {
    any(vapply(old_content, identical, logical(1), content(p)))
  }, logical(1))
  prior_graph <- tryCatch(
    .tf_prepare_graph(.tf_causal_graph(prior, "appraise_amendment"), "sigma",
                      .tf_list(prior, "propositions")),
    tf_refusal = function(e) NULL)
  entailed <- function(p) {
    cl <- .tf_read_claim(.tf_get(p, "claim"))
    !is.null(prior_graph) && !is.null(cl) &&
      identical(.tf_read_with(prior_graph, cl)$verdict, "entailed")
  }
  articulated <- character(0)
  underived <- character(0)
  unresolved <- character(0)
  for (i in seq_along(new_preds)) {
    pid <- new_ids[[i]]
    if (!(pid %in% new_predictions)) next
    sources <- .tf_str_list(.tf_get(new_preds[[i]], "derives_from"))
    j <- match(sources, new_prop_ids)
    if (length(sources) == 0L) underived <- c(underived, pid)
    if (anyNA(j)) unresolved <- c(unresolved, pid)
    old_only <- length(sources) > 0L && !(pid %in% protected) && !anyNA(j) && all(is_old[j])
    if (old_only || entailed(new_preds[[i]])) articulated <- c(articulated, pid)
  }

  dropped <- prior_ids[!(prior_ids %in% new_ids) & !(prior_ids %in% renamed_prior)]
  dropped_corroborated <- dropped[.tf_status_in(dropped, prior_tos, "corroborated")]
  content_lost <- dropped[.tf_status_in(dropped, prior_tos, "untested")]

  was <- vapply(retained, function(r) r$was, character(1))
  now <- vapply(retained, function(r) r$now, character(1))
  new_anomalies <- now[.tf_status_in(now, new_tos, failed) &
                         .tf_status_in(was, prior_tos, c("corroborated", "untested"))]

  # A weakened prediction loses content when it was unrefuted (untested or
  # corroborated), and retreats from a refutation when it was refuted or mixed.
  revised <- list()
  weakened_refuted <- character(0)
  for (r in retained) {
    change <- .tf_revision(r$old, r$cur)
    if (is.null(change)) next
    revised[[length(revised) + 1L]] <- list(id = r$now, change = change)
    if (change == "weakened") {
      status <- .tf_prediction_status(r$was, prior_tos)
      if (status %in% c("untested", "corroborated")) {
        content_lost <- c(content_lost, r$now)
      } else if (status %in% failed) {
        weakened_refuted <- c(weakened_refuted, r$now)
      }
    }
  }

  assumptions <- list()
  ad_hoc <- character(0)
  for (entry in appraised) {
    a <- entry$a
    added_for <- .tf_str(a, "added_for")
    inferred <- FALSE
    if (!.tf_ne_str(added_for)) {
      # An assumption that protects a failed prediction answers it, whether or
      # not it says so.
      hits <- Filter(function(q) .tf_prediction_status(prior_id_of(q), prior_tos) %in% failed,
                     .tf_str_list(.tf_get(a, "protects")))
      if (length(hits) == 0L) next
      added_for <- hits[[1L]]
      inferred <- TRUE
    }
    aid <- .tf_str(a, "id")
    res <- .tf_classify_auxiliary(a, new_tos, new_predictions, added_for)
    assumptions[[length(assumptions) + 1L]] <- list(id = aid, added_for = added_for,
                                                    class = res$class,
                                                    independent = res$independent,
                                                    added_for_inferred = inferred,
                                                    change = entry$change)
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

  # The independencies the two graphs imply, pair by pair. Sigma-separation
  # reads a graph with feedback loops, and reads an acyclic one as m-separation
  # does.
  implied <- tryCatch(
    list(before = tf_implications(prior, cycles = "sigma")$implications,
         after = tf_implications(new, cycles = "sigma")$implications),
    tf_refusal = function(e) NULL)
  compared <- !is.null(implied)
  before <- if (compared) implied$before else list()
  after <- if (compared) implied$after else list()
  lost <- Filter(function(r) !.tf_has_pair(after, r$a, r$b), before)
  gained <- Filter(function(r) !.tf_has_pair(before, r$a, r$b), after)
  refuted_pairs <- list()
  for (p in prior_preds) {
    cl <- .tf_stated_claim(p)
    if (!is.null(cl) && cl$kind == "association" && cl$sign == "zero" &&
        .tf_prediction_status(.tf_str(p, "id"), prior_tos) %in% failed) {
      refuted_pairs[[length(refuted_pairs) + 1L]] <- list(a = cl$x, b = cl$y)
    }
  }
  unrefuted <- Filter(function(r) !.tf_has_pair(refuted_pairs, r$a, r$b), lost)
  statements <- function(recs) vapply(recs, function(r) r$statement, character(1))

  adds_content <- new_predictions[!(new_predictions %in% c(articulated, underived, unresolved))]
  theoretical <- length(adds_content) > 0L
  empirical <- any(adds_content %in% corroborated_new)
  loses_content <- length(content_lost) > 0L || length(unrefuted) > 0L
  if (empirical && length(ad_hoc) == 0L && length(dropped_corroborated) == 0L &&
      !loses_content && length(weakened_refuted) == 0L) {
    verdict <- "progressive"
  } else if ((length(ad_hoc) > 0L || length(weakened_refuted) > 0L) && !empirical) {
    verdict <- "degenerating"
  } else {
    verdict <- "neutral"
  }

  # Radix sorts match Python's codepoint ordering regardless of locale, and the
  # radix order is stable, so records with one new id keep their file order.
  radix <- function(x) sort(x, method = "radix")
  revised_ids <- vapply(revised, function(r) r$id, character(1))
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
    assumptions = assumptions,
    theoretically_progressive = theoretical,
    empirically_progressive = empirical,
    revised = revised[order(revised_ids, method = "radix")],
    weakened_refuted = radix(weakened_refuted),
    unresolved = radix(unresolved),
    implications_compared = compared,
    implications_lost = statements(lost),
    implications_lost_unrefuted = statements(unrefuted),
    implications_gained = statements(gained)
  )
}
