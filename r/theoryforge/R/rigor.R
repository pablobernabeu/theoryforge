#' The checklist engine.
#'
#' Scores a theory file against the 12-item checklist installed with the
#' package.
#' @name rigor
#' @noRd
#' @keywords internal
NULL

.tf_FORBIDDING <- c("point", "interval", "directional")
.tf_PRECISE <- c("point", "interval")
# The schema's formal-model types less "none", which declares that there is no
# model. core.R, which defines the enum, is sourced before this file.
.tf_FORMAL <- setdiff(.tf_FORMAL_MODEL_TYPE, "none")

# The mean as a left fold in file order (API_SPEC.md section 4). R's sum()
# accumulates in long double where R has it, as on x86_64 by default, but not
# on Apple Silicon or a build without it, and CPython 3.12+ sum() compensates,
# so either can differ from a plain double sum in the last bit, as for
# c(0.6, 0.7, 0.2).
.tf_mean <- function(xs) {
  acc <- 0.0
  for (x in xs) acc <- acc + x
  acc / length(xs)
}

# Refuse a test outcome whose `passed` is present and not a logical. A quoted
# "true" is not a pass, so the prediction would count as uncorroborated and an
# assumption that protects it as ad hoc, and an amendment that should be
# progressive would come out degenerating. A missing or NULL `passed`, or a
# single NA, reads as not passed (API_SPEC.md section 4). The first offending
# outcome in file order is named, as the Python twin names it.
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

# How the theory's causal graph reads the claims, for the derivation chain:
# list(readings, contradicted, unread). `readings` has one entry per prediction
# in file order, NULL when the prediction states no claim and list(verdict,
# basis) otherwise (API_SPEC.md section 31). `contradicted` says whether the
# graph contradicts the claim of some phenomenon, and `unread` holds the ids of
# the phenomena, in file order, whose claims the graph leaves unread because
# `cycles` is "refuse" and they name a construct behind a feedback loop. A graph
# that cannot be built (section 27, refusals 1 and 2) reads no claim, so each
# stated claim of a prediction gets the verdict not_evaluated with the basis
# graph_refused, and no phenomenon counts as contradicted or unread. The Python
# twin's _claim_readings() reads them alike.
.tf_claim_readings <- function(T, cycles) {
  g <- tryCatch(
    .tf_prepare_graph(.tf_causal_graph(T, "check"), cycles, .tf_list(T, "propositions")),
    tf_refusal = function(e) NULL)
  preds <- .tf_list(T, "predictions")
  readings <- vector("list", length(preds))
  for (i in seq_along(preds)) {
    cl <- .tf_read_claim(.tf_get(preds[[i]], "claim"))
    if (is.null(cl)) next
    readings[[i]] <- if (is.null(g)) {
      list(verdict = "not_evaluated", basis = "graph_refused")
    } else {
      r <- .tf_read_with(g, cl)
      list(verdict = r$verdict, basis = r$basis)
    }
  }
  contradicted <- FALSE
  unread <- character(0)
  if (!is.null(g)) {
    for (ph in .tf_list(T, "phenomena")) {
      cl <- .tf_read_claim(.tf_get(ph, "claim"))
      if (is.null(cl)) next
      r <- .tf_read_with(g, cl)
      if (identical(r$verdict, "contradicted")) {
        contradicted <- TRUE
      } else if (identical(r$verdict, "not_evaluated") && identical(r$basis, "feedback_loop")) {
        unread <- c(unread, .tf_str(ph, "id"))
      }
    }
  }
  list(readings = readings, contradicted = contradicted, unread = unread)
}

# The derivation chain's list(status, score, not_checked,
# phenomena_not_checked) (API_SPEC.md section 4, item 12). A prediction is
# derived when its references resolve and it either states no claim or states
# one the causal graph entails. A claim that the graph contradicts, leaves
# open, cannot read as written or cannot place, since it names a construct no
# proposition relates, is a failure, as is a claim of a theory whose graph
# cannot be built and an unresolved reference. A claim the graph leaves unread
# because `cycles` is "refuse" and it names a construct behind a feedback loop
# is not checked: its id goes to `not_checked` and, failing anything else, the
# item warns. Nothing was found wrong with such a claim, so a prediction not
# checked whose references resolve counts as derived in the score, and stating
# a claim the loop leaves unread costs nothing. A phenomenon whose claim the
# graph contradicts fails the item, and one whose claim it leaves unread for
# the loop goes to `phenomena_not_checked` and, failing anything else, makes
# the item warn. Neither changes the score, the share of predictions derived.
.tf_derivation_chain <- function(T, preds, prop_ids, cycles) {
  if (length(preds) == 0L) {
    return(list(status = "n/a", score = NULL, not_checked = character(0),
                phenomena_not_checked = character(0)))
  }
  read <- .tf_claim_readings(T, cycles)
  derived <- 0L
  failed <- read$contradicted
  not_checked <- character(0)
  for (i in seq_along(preds)) {
    refs <- .tf_str_list(.tf_get(preds[[i]], "derives_from"))
    resolves <- length(refs) > 0L && all(refs %in% prop_ids)
    if (!resolves) failed <- TRUE
    r <- read$readings[[i]]
    if (!is.null(r) && r$verdict == "not_evaluated" && r$basis == "feedback_loop") {
      not_checked <- c(not_checked, .tf_str(preds[[i]], "id"))
    } else if (!is.null(r) && r$verdict != "entailed") {
      failed <- TRUE
      next
    }
    if (resolves) derived <- derived + 1L
  }
  status <- if (failed) {
    "fail"
  } else if (length(not_checked) > 0L || length(read$unread) > 0L) {
    "warn"
  } else {
    "pass"
  }
  list(status = status, score = .tf_rnd(derived / length(preds), 3), not_checked = not_checked,
       phenomena_not_checked = read$unread)
}

# Compute (status, score) for each checklist item; returns list(items,
# not_checked, phenomena_not_checked), where `items` is a named list of
# list(status, score) per item id and the other two hold the ids of the
# predictions and of the phenomena whose claims the derivation chain left
# unread, since `cycles` is "refuse" and they name a construct behind a feedback
# loop.
# An item with nothing to assess is list(status = "n/a", score = NULL).
.tf_check_items <- function(T, thr, cycles) {
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
  # A point or interval claim counts when its bounds state the region, two
  # finite numbers, so that the label can be checked against what the claim
  # allows. A label alone states nothing a test could miss.
  if (length(preds) == 0L) {
    out$precision <- item("warn", 0.0)
  } else {
    n_precise <- sum(vapply(preds, function(p) ptype(p) %in% .tf_PRECISE && .tf_bounded(p),
                            logical(1)))
    share <- .tf_rnd(n_precise / length(preds), 3)
    out$precision <- item(if (share >= thr$min_precision_share) "pass" else "warn",
                          share)
  }

  # 3 risk_severity
  # Every prediction counts, with its declared severity when it has one and the
  # claim-form rubric's computed_severity otherwise, so a theory without
  # declared severities is scored on its claims, and one declared value cannot
  # stand for a list of undeclared claims. A non-numeric severity has no
  # defensible mean, so it is refused rather than coerced, with the Python
  # twin's message, and tf_validate(full = TRUE) reports the same file as
  # invalid. An infinity has no mean either, and a finite value outside [0, 1]
  # would put the score outside the checklist's scale (a severity of 7 could
  # lift the aggregate above 100). The status compares the rounded mean with
  # the threshold, so the last bit of the sum cannot decide it.
  rubric <- tf_severity(T)$computed_severity
  sevs <- numeric(0)
  for (i in seq_along(preds)) {
    p <- preds[[i]]
    raw <- .tf_get(p, "severity")
    # A single NA is absent, as tf_write() writes it as null.
    if (.tf_absent(raw)) {
      sevs <- c(sevs, rubric[[i]])
      next
    }
    s <- .tf_number(raw)
    if (is.null(s) || !is.finite(s)) {
      stop("check requires numeric prediction severities; ",
           "non-numeric severity for prediction: ", .tf_str(p, "id"),
           call. = FALSE)
    }
    if (s < 0 || s > 1) {
      stop("check requires prediction severities within [0, 1]; ",
           "out-of-range severity for prediction: ", .tf_str(p, "id"),
           call. = FALSE)
    }
    sevs <- c(sevs, s)
  }
  if (length(sevs) == 0L) {
    out$risk_severity <- item("warn", 0.0)
  } else {
    m <- .tf_rnd(.tf_mean(sevs), 3)
    out$risk_severity <- item(if (m >= thr$min_severity) "pass" else "warn", m)
  }

  # 4 parsimony
  # Only an assumption added for an anomaly, one whose added_for names the
  # prediction it answers, is assessed. A core assumption (added_for null)
  # protecting a prediction that later failed is not taken for ad hoc: with no
  # prior version the checklist cannot tell an assumption made before the test
  # from one made after it, and tf_appraise_amendment(), which compares
  # versions, infers the anomaly an undeclared addition answers. An assessed
  # assumption fails the item when nothing it protects besides the anomaly is
  # corroborated, which the amendment appraisal (.tf_classify_auxiliary() in
  # develop.R) classes as ad hoc or, while all of it is untested, as pending.
  # With no prior version to compare, every prediction it protects counts. Core assumptions are not counted:
  # every derivation uses auxiliaries (Meehl, 1990a), and a ratio of
  # assumptions to propositions would penalise declaring them.
  defensive <- Filter(function(x) .tf_ne_str(.tf_str(x, "added_for")), aux)
  if (length(defensive) == 0L) {
    out$parsimony <- item("n/a", NULL)
  } else {
    ad_hoc <- vapply(defensive, function(x) {
      protects <- .tf_str_list(.tf_get(x, "protects"))
      !identical(.tf_classify_auxiliary(x, tos, protects)$class, "independently_corroborated")
    }, logical(1))
    out$parsimony <- if (any(ad_hoc)) item("fail", 0.0) else item("pass", 1.0)
  }

  # 5 non_redundancy
  # The item follows the redundancy screen's flags (API_SPEC.md section 6): a
  # near-duplicate pair, a definition contained in another, a shared label or a
  # shared measure, not vocabulary that sibling constructs merely share. A
  # construct whose definition holds no content word cannot be screened, so
  # the item cannot pass while one exists, and deleting the definitions of a
  # redundant pair cannot raise the score.
  if (length(cons) < 2L) {
    out$non_redundancy <- item("n/a", NULL)
  } else {
    flagged <- .tf_redundancy_flagged(T, thr)
    undefined <- any(vapply(cons, function(c) length(tf_tokens(.tf_str(c, "definition"))) == 0L,
                            logical(1)))
    out$non_redundancy <- if (flagged || undefined) item("warn", 0.0) else item("pass", 1.0)
  }

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
  # Every relation that the relation table calls directed states an effect,
  # mediates and moderates included (API_SPEC.md section 28).
  n_causal <- sum(vapply(props, function(p) {
    .tf_enum_str(p, "relation", .tf_RELATION) %in% .tf_DIRECTED
  }, logical(1)))
  out$causal_testability <- if (n_causal >= 1L) item("pass", 1.0) else item("warn", 0.0)

  # 10 diagnosticity
  # A named rival counts unless its stated propositions give the prediction's
  # claim the same verdict as the theory's do, which shows the declaration
  # false (API_SPEC.md section 4). The graphs are read with the same cycles as
  # the derivation chain's.
  verdicts <- .tf_prediction_verdicts(T, cycles)
  discriminates <- function(v, d) {
    if (is.null(v) || v$theory == "not_evaluated" || is.null(v$rivals[[d]])) return(TRUE)
    v$rivals[[d]] != v$theory
  }
  if (length(preds) == 0L) {
    out$diagnosticity <- item("warn", 0.0)
  } else {
    n_diag <- sum(vapply(seq_along(preds), function(i) {
      named <- .tf_str_list(.tf_get(preds[[i]], "diagnostic_vs"))
      any(vapply(named, function(d) d %in% alt_ids && discriminates(verdicts[[i]], d), logical(1)))
    }, logical(1)))
    out$diagnosticity <- item(if (n_diag >= 1L) "pass" else "warn",
                              .tf_rnd(n_diag / length(preds), 3))
  }

  # 11 formalisation
  fm_type <- .tf_enum_str(.tf_get(T, "formal_model"), "type", .tf_FORMAL_MODEL_TYPE)
  out$formalisation <- if (fm_type %in% .tf_FORMAL) item("pass", 1.0) else item("warn", 0.0)

  # 12 derivation_chain
  # With no prediction there is no derivation to check, and a pass would lift
  # the empty theory's score. A claim the causal graph does not entail does not
  # follow from the propositions, whatever the prediction cites.
  dc <- .tf_derivation_chain(T, preds, prop_ids, cycles)
  out$derivation_chain <- item(dc$status, dc$score)

  list(items = out, not_checked = dc$not_checked, phenomena_not_checked = dc$phenomena_not_checked)
}

# The weighted mean of the scores `x` under the weights `w`, times 100 and
# rounded to 1 decimal. The sums are left folds in checklist order, as the
# Python twin computes them, since sum() keeps an extended accumulator.
.tf_weighted <- function(w, x) {
  num <- 0.0
  den <- 0.0
  for (i in seq_along(w)) {
    num <- num + w[[i]] * x[[i]]
    den <- den + w[[i]]
  }
  .tf_rnd(num / den * 100, 1)
}

# The lowest and highest aggregate over the checklist's weights and 2k + 1
# alternatives: equal weights and, for each of the k applicable items in turn,
# its weight halved and its weight doubled. The weights are a convention, and
# the range shows how far the aggregate depends on them.
.tf_aggregate_range <- function(w, x) {
  values <- c(.tf_weighted(w, x), .tf_weighted(rep(1, length(w)), x))
  for (k in seq_along(w)) {
    for (factor in c(0.5, 2)) {
      wk <- w
      wk[[k]] <- w[[k]] * factor
      values <- c(values, .tf_weighted(wk, x))
    }
  }
  c(min(values), max(values))
}

# What the checklist score describes, in the words the documents and the help
# use. tf_report() gives it beside the score, with the checklist's version.
.tf_SCOPE <- paste(
  "The checklist score describes how completely the file states what checklist %s",
  "asks for. Most items read whether a field is filled in or how a prediction is",
  "labelled, and stated claims are checked against the causal graph. Test outcomes are",
  "read only by the parsimony item, the weights are conventions, and no study has",
  "established what difference between two scores is meaningful. The score does not",
  "show that the theory is true or well reasoned.")

#' Check a theory file against the checklist
#'
#' Runs the 12 items of the checklist over a theory object and returns a
#' report, with the items in checklist order.
#'
#' The checklist score describes how completely the file states what checklist
#' 3.1 asks for. Most items read whether a field is filled in or how a
#' prediction is labelled, and stated claims are checked against the causal
#' graph. Test outcomes are read only by the parsimony item, the weights are
#' conventions, and no study has established what difference between two
#' scores is meaningful. The score does not show that the theory is true or
#' well reasoned.
#'
#' Each item has a status (\code{"pass"}, \code{"warn"} or \code{"fail"}) and
#' a score from 0 to 1. An item with nothing to assess has the status
#' \code{"n/a"} and a \code{NULL} score: the redundancy screen with fewer than
#' two constructs, the derivation chain with no prediction and parsimony when
#' no auxiliary assumption names, in \code{added_for}, an anomaly it was added
#' to answer. The checklist score (\code{aggregate_score}) is the weighted mean
#' of the applicable items' scores, times 100, and \code{coverage} is the share
#' of the checklist's weight that was applicable.
#'
#' The derivation chain counts a prediction as derived when the propositions
#' it cites are declared and it states no claim or one that the causal graph
#' entails. It fails when some prediction cites a proposition that is not
#' declared, or none, or states a claim that the graph contradicts, leaves
#' open, cannot read as written or cannot place because it names a construct
#' no proposition relates, and when the graph contradicts the claim of a
#' phenomenon. Under the default, a claim of a prediction or a phenomenon that
#' names a construct on a feedback loop or downstream of one is left unread. It
#' is not checked and, failing anything else, makes the item warn, which does
#' not block the gate. A prediction whose claim is not checked counts as
#' derived when the propositions it cites are declared, since nothing was found
#' wrong with it. Such a claim therefore gets full credit and leaves the gate
#' open whatever the graph would say of it read by sigma-separation, so a file
#' whose claims a loop reaches is checked in full only with
#' \code{cycles = "sigma"}. A loop that reaches no claim changes nothing.
#'
#' Three values are refused before anything is scored, since no score built
#' on them would be defensible. One is a \code{cycles} other than
#' \code{"refuse"} or \code{"sigma"}. Another is a test outcome whose
#' \code{passed} is present and not \code{TRUE} or \code{FALSE}, such as the
#' quoted string \code{"true"}. The third is a prediction \code{severity} that
#' is present and not a finite number from 0 to 1. Each stops with an error,
#' and [tf_validate()] with \code{full = TRUE} reports the last two.
#'
#' @param theory A theory object (named list), such as one from [tf_read()].
#' @param cycles How a causal graph with a feedback loop is read, as in
#'   [tf_entailments()]. \code{"refuse"} (the default) leaves unread the
#'   claims that name a construct on a loop or downstream of one, and
#'   \code{"sigma"} reads every claim by sigma-separation, which assumes that
#'   each loop settles to a unique equilibrium. The derivation chain and
#'   diagnosticity read the claims this way.
#' @return A named list with elements \code{theory_id}, \code{schema_version}
#'   (the theory's), \code{checklist_version} (the checklist's, which is what
#'   the weights and thresholds came from), \code{maturity},
#'   \code{aggregate_score} (the checklist score, 0 to 100, to one decimal),
#'   \code{aggregate_range}, \code{coverage}, \code{gate},
#'   \code{n_blockers_failed} and \code{items}. \code{aggregate_range} holds
#'   the lowest and highest score over the checklist's weights, equal weights
#'   and each applicable item's weight halved and then doubled with the others
#'   unchanged. It is not an interval for the score, and it leaves out the
#'   choices made in coding the file and the rubric's constants. \code{gate} is
#'   \code{"advisory"} at \code{draft} maturity, and otherwise
#'   \code{"blocked"} when an item whose \code{severity_if_fail} is
#'   \code{"blocker"} (falsifiability or derivation_chain) fails and
#'   \code{"pass"} when none does. \code{items} holds one list per checklist
#'   item, in checklist order, with \code{id}, \code{status}, \code{score},
#'   \code{weight}, \code{severity_if_fail} (\code{"blocker"} or
#'   \code{"warning"}) and \code{citation}. The derivation_chain item has two
#'   more elements, \code{not_checked} and \code{phenomena_not_checked}, lists
#'   of the ids of the predictions and of the phenomena whose claims were not
#'   checked. A prediction and a phenomenon may share an id, so the two are
#'   listed apart.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "causes",
#'                      mechanism = "Activation raises salience of threat cues.") |>
#'   tf_add_prediction("h1", "Arousal precedes threat appraisal.", "directional",
#'                     derives_from = "p1")
#' report <- tf_check(theory)
#' report$aggregate_score
#' report$gate
#' @export
tf_check <- function(theory, cycles = "refuse") {
  .tf_check_cycles(cycles, "check")
  T <- theory
  .tf_refuse_non_boolean_outcomes(T, "check")
  spec <- tf_checklist()
  thr <- spec$thresholds
  checked <- .tf_check_items(T, thr, cycles)
  results <- checked$items

  items <- vector("list", length(spec$items))
  applicable <- 0.0
  n_blockers_failed <- 0L
  w <- numeric(0)
  x <- numeric(0)
  for (k in seq_along(spec$items)) {
    spec_item <- spec$items[[k]]
    iid <- spec_item$id
    res <- results[[iid]]
    status <- res$status
    score <- res$score
    # An item with nothing to assess is in neither sum. Scored 1.0, the three
    # such items would give the empty theory 26 and let it outscore a weak but
    # real one.
    if (!is.null(score)) {
      applicable <- applicable + spec_item$weight
      w <- c(w, spec_item$weight)
      x <- c(x, score)
    }
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
    # The predictions and the phenomena whose claims a feedback loop left
    # unread, so that a document can say what was not checked and why. A
    # prediction and a phenomenon may share an id, so the two are kept apart.
    # Lists, so that one id is still written as a JSON array.
    if (identical(iid, "derivation_chain")) {
      items[[k]]$not_checked <- as.list(checked$not_checked)
      items[[k]]$phenomena_not_checked <- as.list(checked$phenomena_not_checked)
    }
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
    # Nine of the twelve items always apply, so `applicable` is at least 0.74.
    aggregate_score = .tf_weighted(w, x),
    aggregate_range = .tf_aggregate_range(w, x),
    coverage = .tf_rnd(applicable, 3),
    gate = gate,
    n_blockers_failed = n_blockers_failed,
    items = items
  )
}

# What the gate checks, in the words the documents use. tf_report() and
# tf_dossier() give it after the statement of what the score describes.
.tf_GATE <- paste(
  "The gate reports whether either blocking item failed: at least one prediction is",
  "typed point, interval or directional, and every prediction cites declared",
  "propositions whose graph entails any claim it states, with no stated phenomenon",
  "contradicted. Under the default reading of feedback loops, a claim that names a",
  "construct on a loop or downstream of one is not read and blocks nothing. The",
  "labels are the author's and are not checked against the statements.")

#' Render the checklist report as a string
#'
#' Renders the result of [tf_check()] as a string. \code{format = "json"}
#' returns valid, pretty-printed JSON. \code{format = "html"} returns an HTML
#' fragment in which every interpolated value is escaped. It gives the
#' checklist score with its range and the gate, then what the score describes
#' and what the gate checks, then a table of the items with the criterion each
#' applies, its status and score and the works from which the criterion is
#' drawn. The two items whose failure blocks the gate have \code{(blocker)}
#' after their ids, as in the dossier. Any other \code{format} stops, and so
#' does a theory that [tf_check()] refuses.
#'
#' @param theory A theory object (named list).
#' @param format One of \code{"json"} (default) or \code{"html"}.
#' @return A single string.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_prediction("h1", "Arousal precedes threat appraisal.", "directional")
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
    spec_items <- tf_checklist()$items
    criteria <- vapply(spec_items, function(it) .tf_str(it, "criterion"), character(1))
    names(criteria) <- vapply(spec_items, function(it) .tf_str(it, "id"), character(1))
    # Every interpolated value is escaped: the schema allows any non-empty id,
    # so '<' or '&' in it would otherwise reach the markup. A blocking item is
    # marked as the dossier marks it, so that the table shows the two items the
    # gate reads.
    rows <- vapply(rep$items, function(it) {
      criterion <- if (it$id %in% names(criteria)) criteria[[it$id]] else ""
      blocker <- if (identical(it$severity_if_fail, "blocker")) " (blocker)" else ""
      sprintf('    <tr><td>%s%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>',
              .tf_xml(it$id), blocker, .tf_xml(criterion), .tf_xml(it$status),
              .tf_xml(.tf_format_score_html(it$score)), .tf_xml(it$citation))
    }, character(1))
    rows <- paste(rows, collapse = "\n")
    return(paste0(
      '<section class="theoryforge-report">\n',
      sprintf('  <h2>Checklist report: %s</h2>\n', .tf_xml(rep$theory_id)),
      sprintf(paste0('  <p>Checklist score: %s (%s to %s with equal ',
                     'weights or one weight halved or doubled) &middot; gate: ',
                     '%s</p>\n'),
              .tf_xml(.tf_format_score_html(rep$aggregate_score)),
              .tf_xml(.tf_format_score_html(rep$aggregate_range[[1]])),
              .tf_xml(.tf_format_score_html(rep$aggregate_range[[2]])), .tf_xml(rep$gate)),
      sprintf('  <p>%s</p>\n', .tf_xml(sprintf(.tf_SCOPE, rep$checklist_version))),
      sprintf('  <p>%s</p>\n', .tf_xml(.tf_GATE)),
      '  <table>\n    <tr><th>item</th><th>criterion</th><th>status</th><th>score</th>',
      '<th>source of the criterion</th></tr>\n',
      rows, '\n  </table>\n</section>\n'
    ))
  }
  stop(paste0("unknown report format: ", .tf_quote_arg(format)), call. = FALSE)
}

# Render a numeric score the way Python's str() would for the HTML table
# (e.g. 1.0, 0.667), and the NULL score of an item with nothing to assess as
# "n/a". Not parity-tested, but kept readable. The integrality test uses
# trunc() rather than base round(), so that no call to base round() (which is
# banker's rounding, and diverges across platforms) remains in the package.
.tf_format_score_html <- function(x) {
  if (is.null(x)) return("n/a")
  if (is.numeric(x)) {
    if (x == trunc(x)) {
      return(sprintf("%.1f", x))
    }
    return(format(x, trim = TRUE))
  }
  as.character(x)
}
