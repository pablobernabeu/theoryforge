# Amendment appraisal (API_SPEC.md section 10). The appraisal compares the
# content of two versions, not their prediction ids. Most cases amend the panic
# example, and the rest amend the edge cases fixtures/edge/amend-*.theory.yaml.
# The Python suite (test_develop.py) builds the same amendments and asserts the
# same records.

dv_S4 <- paste("Blocking interoceptive feedback lowers avoidance-task scores by 30 per cent,",
               "within a tolerance of 5 percentage points, within two weeks.")

# The one independence the panic example's v1 implies. A direct path from
# arousal to avoidance withdraws it, and the failed test of pred_indep refutes it.
dv_LOST <- "c_arousal _||_ c_avoidance | c_perceived_threat"

# The record of an amendment that changes nothing, with the fields in `...`
# replaced, keys in the order of API_SPEC.md section 10.
dv_record <- function(...) {
  rec <- list(
    verdict = "neutral", new_predictions = character(0), corroborated_new = character(0),
    ad_hoc_assumptions = character(0), articulated = character(0), underived = character(0),
    corroborated_new_registered = character(0), renamed = list(), dropped = character(0),
    dropped_corroborated = character(0), content_lost = character(0),
    new_anomalies = character(0), assumptions = list(),
    theoretically_progressive = FALSE, empirically_progressive = FALSE, revised = list(),
    weakened_refuted = character(0), unresolved = character(0), implications_compared = TRUE,
    implications_lost = character(0), implications_lost_unrefuted = character(0),
    implications_gained = character(0)
  )
  changes <- list(...)
  for (k in names(changes)) rec[k] <- list(changes[[k]])
  rec
}

# The record of dv_with_p4(v1): corroborated new content and the refuted
# independence lost.
dv_p4_record <- function(...) {
  base <- list(verdict = "progressive", new_predictions = "pred4", corroborated_new = "pred4",
               corroborated_new_registered = "pred4", theoretically_progressive = TRUE,
               empirically_progressive = TRUE, implications_lost = dv_LOST)
  changes <- list(...)
  for (k in names(changes)) base[k] <- list(changes[[k]])
  do.call(dv_record, base)
}

dv_v1 <- function() tf_read(tf_fixture_path("panic-network.theory.yaml"))

# The edge cases live at the repository root and are not shipped in the
# package, so the tests that read them are skipped where the root is absent,
# as under R CMD check.
dv_edge <- function(name) {
  dir <- normalizePath(testthat::test_path("..", ".."), winslash = "/", mustWork = FALSE)
  for (i in 1:6) {
    path <- file.path(dir, "fixtures", "edge", paste0(name, ".theory.yaml"))
    if (file.exists(path)) return(tf_read(path))
    parent <- dirname(dir)
    if (identical(parent, dir)) break
    dir <- parent
  }
  testthat::skip("fixtures/edge is not available")
}

# The panic example with a failed test of pred2, the anomaly the rescue cases answer.
dv_with_failed_pred2 <- function() {
  prior <- dv_v1()
  prior$test_outcomes <- c(prior$test_outcomes, list(list(prediction_id = "pred2", passed = FALSE)))
  prior
}

# `theory` amended as v2 amends v1: a new proposition and a prediction from it.
dv_with_p4 <- function(theory) {
  theory$propositions <- c(theory$propositions, list(list(
    id = "p4", from = "c_arousal", to = "c_avoidance", relation = "increases",
    mechanism = paste("Bodily sensations are themselves feared, so activities that raise",
                      "arousal are avoided directly.")
  )))
  theory$predictions <- c(theory$predictions, list(list(
    id = "pred4", derives_from = list("p4"), statement = dv_S4, type = "point"
  )))
  theory$test_outcomes <- c(theory$test_outcomes, list(list(
    prediction_id = "pred4", passed = TRUE, registered = "osf.io/fghij"
  )))
  theory
}

dv_add <- function(theory, key, item) {
  theory[[key]] <- c(theory[[key]], list(item))
  theory
}

dv_drop <- function(items, ids, key = "id") Filter(function(x) !(x[[key]] %in% ids), items)

test_that("the shipped amendment answers a refuted independence", {
  # v2 drops pred_indep, which a test refuted, and adds p4 and pred4. The
  # independence p4 withdraws is the refuted one, so no content is lost.
  v1 <- dv_v1()
  v2 <- tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml"))
  expect_identical(tf_appraise_amendment(v2, v1), dv_p4_record(dropped = "pred_indep"))
  # Had the test of pred_indep passed, v2 would give up a corroborated
  # prediction and an unrefuted implication.
  passed <- v1
  passed$test_outcomes[[2]]$passed <- TRUE
  expect_identical(tf_appraise_amendment(v2, passed), dv_p4_record(
    verdict = "neutral", dropped = "pred_indep", dropped_corroborated = "pred_indep",
    implications_lost_unrefuted = dv_LOST))
  # Untested, pred_indep and the implication would both be content lost.
  passed$test_outcomes[[2]] <- NULL
  expect_identical(tf_appraise_amendment(v2, passed), dv_p4_record(
    verdict = "neutral", dropped = "pred_indep", content_lost = "pred_indep",
    implications_lost_unrefuted = dv_LOST))
})

test_that("an immunizing ad-hoc assumption yields a degenerating verdict", {
  # Take panic v1, add an unprotected ad-hoc assumption, appraise vs v1 itself
  # (no new predictions -> no corroboration; one ad-hoc -> degenerating).
  v1 <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  amended <- v1
  amended <- tf_add_assumption(amended, "aux_adhoc",
                               "An untested rescue assumption.",
                               added_for = "pred2", protects = c("pred2"))
  ap <- tf_appraise_amendment(amended, v1)
  expect_identical(ap$verdict, "degenerating")
  expect_identical(ap$new_predictions, character(0))
  expect_identical(ap$corroborated_new, character(0))
  expect_identical(ap$ad_hoc_assumptions, "aux_adhoc")
})

test_that("new but uncorroborated prediction with no ad-hoc is neutral", {
  v1 <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  amended <- v1
  amended <- tf_add_prediction(amended, "pred_new", "An untested claim", "point")
  ap <- tf_appraise_amendment(amended, v1)
  expect_identical(ap$verdict, "neutral")
  expect_identical(ap$new_predictions, "pred_new")
  expect_identical(ap$corroborated_new, character(0))
  expect_identical(ap$ad_hoc_assumptions, character(0))
})

test_that("the record keeps its fields in order", {
  # D6: identical versions add nothing, lose nothing and are neutral.
  v1 <- dv_v1()
  expect_identical(tf_appraise_amendment(v1, v1), dv_record())
})

test_that("a status reads every outcome of the prediction", {
  tos <- list(
    list(prediction_id = "h1", passed = TRUE),
    list(prediction_id = "h2", passed = FALSE),
    list(prediction_id = "h3", passed = TRUE),
    list(prediction_id = "h3", passed = FALSE),
    list(prediction_id = "h4"),
    list(prediction_id = "h4", passed = NA),
    "h5",
    list(prediction_id = 5, passed = TRUE),
    list(prediction_id = list("h6"), passed = TRUE)
  )
  statuses <- vapply(c("h1", "h2", "h3", "h4", "h5", "5", "h6"), .tf_prediction_status,
                     character(1), tos = tos, USE.NAMES = FALSE)
  expect_identical(statuses, c("corroborated", "refuted", "mixed", "untested", "untested",
                               "untested", "untested"))
})

test_that("a prediction derived from unchanged propositions is an articulation", {
  # D0: the v2 shipped with 0.6.0. pred4 derives from p1 and p2, which v1
  # already held, so it states a consequence of the prior's own content. The
  # dropped functional_form is not part of what the appraisal compares.
  v1 <- dv_v1()
  new <- v1
  new$propositions[[1]]$functional_form <- NULL
  new <- dv_add(new, "predictions", list(id = "pred4", derives_from = list("p1", "p2"),
                                         statement = dv_S4, type = "point"))
  new <- dv_add(new, "test_outcomes", list(prediction_id = "pred4", passed = TRUE,
                                           registered = "osf.io/fghij"))
  expect_identical(tf_appraise_amendment(new, v1), dv_record(
    new_predictions = "pred4", corroborated_new = "pred4", articulated = "pred4",
    corroborated_new_registered = "pred4"))
})

test_that("a claim the prior graph entails is an articulation", {
  # h3 cites the new p3 but claims that c1 raises c3, which the prior's chain
  # c1 -> c2 -> c3 already entails. Without the claim, h3 is new content.
  prior <- dv_edge("amend-prior")
  new <- dv_edge("amend-unresolved")
  new$predictions[[3]]$derives_from <- list("p3")
  new$predictions[[3]]$claim <- list(kind = "effect", x = "c1", y = "c3", sign = "positive")
  gained <- c("c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3")
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    new_predictions = "h3", corroborated_new = "h3", articulated = "h3",
    implications_gained = gained))
  # A claim about c4, which the prior does not name, is not evaluated there.
  new$predictions[[3]]$claim <- list(kind = "effect", x = "c3", y = "c4", sign = "positive")
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "progressive", new_predictions = "h3", corroborated_new = "h3",
    theoretically_progressive = TRUE, empirically_progressive = TRUE,
    implications_gained = gained))
})

test_that("failed replications leave a new prediction mixed", {
  # D1: one pass and two failures make pred4 mixed, which is not corroborated.
  v1 <- dv_v1()
  new <- dv_with_p4(v1)
  new$test_outcomes <- c(new$test_outcomes,
                         rep(list(list(prediction_id = "pred4", passed = FALSE)), 2L))
  expect_identical(.tf_prediction_status("pred4", new$test_outcomes), "mixed")
  expect_identical(tf_appraise_amendment(new, v1), dv_p4_record(
    verdict = "neutral", corroborated_new = character(0),
    corroborated_new_registered = character(0), empirically_progressive = FALSE))
})

test_that("a renamed prediction is not new", {
  # D2: pred1 under a new id, its statement reflowed, is the same content.
  v1 <- dv_v1()
  new <- v1
  statement <- new$predictions[[1]]$statement
  new$predictions[[1]]$id <- "pred1_v2"
  new$predictions[[1]]$statement <- paste0("  ", sub(" ", "  \n ", statement, fixed = TRUE), "\t")
  new$test_outcomes[[1]]$prediction_id <- "pred1_v2"
  expect_identical(tf_appraise_amendment(new, v1),
                   dv_record(renamed = list(list(prior = "pred1", new = "pred1_v2"))))
  # A different claim form is a different prediction, so pred1 is then dropped.
  new$predictions[[1]]$type <- "interval"
  ap <- tf_appraise_amendment(new, v1)
  expect_identical(ap$renamed, list())
  expect_identical(ap$new_predictions, "pred1_v2")
  expect_identical(ap$dropped, "pred1")
  expect_identical(ap$dropped_corroborated, "pred1")
})

test_that("renames are matched in file order and sorted by new id", {
  pred <- function(id, statement) list(id = id, statement = statement, type = "point")
  prior <- list(predictions = list(pred("x", "S1"), pred("y", "S2"), pred("a", "S"),
                                   pred("b", "S"), pred("e", "")))
  new <- list(predictions = list(pred("z1", "S2"), pred("a1", "S1"), pred("c", "S"),
                                 pred("d", "S"), pred("f", " ")))
  ap <- tf_appraise_amendment(new, prior)
  expect_identical(ap$renamed, list(list(prior = "x", new = "a1"), list(prior = "a", new = "c"),
                                    list(prior = "b", new = "d"), list(prior = "y", new = "z1")))
  # A blank statement says nothing about content, so it is never a rename.
  expect_identical(ap$new_predictions, "f")
  expect_identical(ap$dropped, "e")
  expect_identical(ap$content_lost, "e")
})

test_that("every list of ids is sorted by code point", {
  prior <- list(predictions = lapply(c("b2", "a3", "B1"), function(i) {
    list(id = i, statement = paste("claim", i), type = "point")
  }))
  ap <- tf_appraise_amendment(list(predictions = list()), prior)
  expect_identical(ap$dropped, c("B1", "a3", "b2"))
  expect_identical(ap$content_lost, c("B1", "a3", "b2"))
})

test_that("a rescue cleared by a re-analysis of its anomaly is ad hoc", {
  # D3, and I16 case A: the amendment answers the failed pred2 with an
  # assumption and a passing re-analysis of pred2 itself. Accommodating the
  # anomaly adds no content.
  prior <- dv_with_failed_pred2()
  new <- dv_add(prior, "auxiliary_assumptions", list(
    id = "aux_rescue", statement = "The band holds only for high baseline avoidance.",
    added_for = "pred2", protects = list("pred2")))
  new <- dv_add(new, "test_outcomes", list(prediction_id = "pred2", passed = TRUE))
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "degenerating", ad_hoc_assumptions = "aux_rescue",
    assumptions = list(list(id = "aux_rescue", added_for = "pred2", class = "ad_hoc1",
                            independent = list(), added_for_inferred = FALSE))))
})

test_that("an old corroborated prediction cannot clear a rescue", {
  # I16 case B: pred1 passed before the amendment, so listing it in protects
  # lends the assumption no support.
  prior <- dv_with_failed_pred2()
  new <- dv_add(prior, "auxiliary_assumptions", list(
    id = "aux_rescue", statement = "s", added_for = "pred2", protects = list("pred2", "pred1")))
  ap <- tf_appraise_amendment(new, prior)
  expect_identical(ap$assumptions, list(list(id = "aux_rescue", added_for = "pred2",
                                             class = "ad_hoc1", independent = list(),
                                             added_for_inferred = FALSE)))
  expect_identical(ap$verdict, "degenerating")
})

test_that("a free-text added_for still marks a rescue", {
  # I16 case D: added_for gives a reason, not the anomaly's id, and the
  # failure record is dropped. pred2 is still old content.
  prior <- dv_with_failed_pred2()
  new <- prior
  new$test_outcomes <- Filter(function(t) isTRUE(t$passed), new$test_outcomes)
  new <- dv_add(new, "auxiliary_assumptions", list(
    id = "aux_rescue", statement = "s", added_for = "a subgroup explanation",
    protects = list("pred2")))
  new <- dv_add(new, "test_outcomes", list(prediction_id = "pred2", passed = TRUE))
  ap <- tf_appraise_amendment(new, prior)
  expect_identical(ap$assumptions, list(list(id = "aux_rescue", added_for = "a subgroup explanation",
                                             class = "ad_hoc1", independent = list(),
                                             added_for_inferred = FALSE)))
  expect_identical(ap$ad_hoc_assumptions, "aux_rescue")
  expect_identical(ap$verdict, "degenerating")
})

test_that("a corroborated new prediction clears the assumption that yields it", {
  # I16 case C. pred5 derives from the unchanged p2 but needs the new
  # assumption, so it is new content and not an articulation. While pred5 is
  # untested, the assumption is ad hoc (ad_hoc2), and its corroboration clears it.
  prior <- dv_with_failed_pred2()
  new <- dv_add(prior, "predictions", list(
    id = "pred5", statement = "Exposure lowers avoidance only where baseline avoidance is high.",
    type = "directional", derives_from = list("p2")))
  new <- dv_add(new, "auxiliary_assumptions", list(
    id = "aux_baseline", statement = "Exposure works through habituation of high avoidance.",
    added_for = "pred2", protects = list("pred2", "pred5", "pred5")))
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "degenerating", new_predictions = "pred5", ad_hoc_assumptions = "aux_baseline",
    assumptions = list(list(id = "aux_baseline", added_for = "pred2", class = "ad_hoc2",
                            independent = list(list(id = "pred5", status = "untested")),
                            added_for_inferred = FALSE)),
    theoretically_progressive = TRUE))
  new <- dv_add(new, "test_outcomes", list(prediction_id = "pred5", passed = TRUE,
                                           registered = "osf.io/x"))
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "progressive", new_predictions = "pred5", corroborated_new = "pred5",
    corroborated_new_registered = "pred5",
    assumptions = list(list(id = "aux_baseline", added_for = "pred2",
                            class = "independently_corroborated",
                            independent = list(list(id = "pred5", status = "corroborated")),
                            added_for_inferred = FALSE)),
    theoretically_progressive = TRUE, empirically_progressive = TRUE))
})

test_that("only an assumption added for an anomaly is appraised", {
  # A NULL, blank or non-text added_for marks a core assumption when the
  # assumption protects nothing that failed in the prior, and added_for is read
  # as text, so a one-element list names its element.
  v1 <- dv_v1()
  new <- v1
  for (a in list(
    list(id = "core_null", statement = "s", added_for = NULL, protects = list("pred2")),
    list(id = "core_blank", statement = "s", added_for = " ", protects = list("pred2")),
    list(id = "core_number", statement = "s", added_for = 5, protects = list("pred2")),
    list(id = "listed", statement = "s", added_for = list("pred2"), protects = list("pred2"))
  )) {
    new <- dv_add(new, "auxiliary_assumptions", a)
  }
  ap <- tf_appraise_amendment(new, v1)
  expect_identical(ap$assumptions, list(list(id = "listed", added_for = "pred2",
                                             class = "ad_hoc1", independent = list(),
                                             added_for_inferred = FALSE)))
  expect_identical(ap$ad_hoc_assumptions, "listed")
})

test_that("an assumption that protects a failed prediction answers it", {
  # amend-inferred: x1 protects h2, untested in the prior, and the refuted h1,
  # and names no anomaly. h1 is taken as its anomaly.
  prior <- dv_edge("amend-prior")
  new <- dv_edge("amend-inferred")
  rescue <- list(list(id = "x1", added_for = "h1", class = "ad_hoc1", independent = list(),
                      added_for_inferred = TRUE))
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "degenerating", ad_hoc_assumptions = "x1", assumptions = rescue))
  # A mixed status in the prior counts as failed too.
  mixed <- dv_add(prior, "test_outcomes", list(prediction_id = "h1", passed = TRUE))
  expect_identical(tf_appraise_amendment(new, mixed)$assumptions, rescue)
  # The anomaly is found under the new id of a renamed prediction.
  renamed <- new
  renamed$predictions[[1]]$id <- "h1_v2"
  renamed$test_outcomes[[1]]$prediction_id <- "h1_v2"
  renamed$auxiliary_assumptions[[1]]$protects <- list("h2", "h1_v2")
  ap <- tf_appraise_amendment(renamed, prior)
  expect_identical(ap$renamed, list(list(prior = "h1", new = "h1_v2")))
  rescue[[1]]$added_for <- "h1_v2"
  expect_identical(ap$assumptions, rescue)
  # Protecting only untested content, the assumption is a core one.
  untested <- new
  untested$auxiliary_assumptions[[1]]$protects <- list("h2")
  expect_identical(tf_appraise_amendment(untested, prior), dv_record())
})

test_that("a retained prediction is compared by type, bounds and claim", {
  # Each case revises h1 of amend-prior, a point prediction with the region
  # [0.4, 0.6] and a positive effect of c1 on c2. A NULL in a change removes
  # the field.
  prior <- dv_edge("amend-prior")
  effect <- function(sign, x = "c1", y = "c2") list(kind = "effect", x = x, y = y, sign = sign)
  cases <- list(
    list(list(), NA),
    list(list(statement = "c2 rises with c1 by half an SD, within 0.1."), "reworded"),
    list(list(statement = "  c2 rises 0.5 SD per SD of c1,\n within 0.1. "), NA),
    list(list(type = "interval"), "weakened"),
    list(list(type = "directional", bounds = NULL, claim = NULL), "weakened"),
    list(list(type = "banana"), "changed"),
    list(list(bounds = list(lower = 0.3, upper = 0.7)), "weakened"),
    list(list(bounds = list(lower = 0.45, upper = 0.55)), "strengthened"),
    list(list(bounds = list(lower = 0.5, upper = 0.7)), "changed"),
    list(list(bounds = list(lower = 0.4)), "weakened"),
    list(list(bounds = list(lower = 0.4, upper = NA)), "weakened"),
    list(list(bounds = list(lower = 0.4, upper = Inf)), "weakened"),
    list(list(bounds = list(lower = "0.4", upper = 0.6)), "weakened"),
    list(list(bounds = list(lower = 0.4, upper = 0.6, note = "ignored")), NA),
    list(list(claim = effect("nonzero")), "weakened"),
    list(list(claim = effect("negative")), "changed"),
    list(list(claim = effect("positive", x = "c2", y = "c1")), "changed"),
    list(list(claim = effect("upward")), "weakened"),
    list(list(claim = NULL), "weakened"),
    list(list(type = "directional", bounds = list(lower = 0.45, upper = 0.55)), "changed"),
    list(list(type = "interval", claim = effect("negative")), "weakened")
  )
  for (case in cases) {
    new <- prior
    change <- case[[1]]
    for (key in names(change)) new$predictions[[1]][key] <- list(change[[key]])
    new$predictions[[1]] <- Filter(Negate(is.null), new$predictions[[1]])
    expected <- if (is.na(case[[2]])) list() else list(list(id = "h1", change = case[[2]]))
    expect_identical(tf_appraise_amendment(new, prior)$revised, expected,
                     info = paste(deparse(change), collapse = ""))
  }
})

test_that("a two-sided region is narrower than a one-sided one", {
  theory <- function(bounds) {
    p <- list(id = "h", statement = "S", type = "interval")
    if (!is.null(bounds)) p$bounds <- bounds
    list(predictions = list(p))
  }
  cases <- list(
    list(list(lower = 20), list(lower = 100, upper = 200), "strengthened"),
    list(list(lower = 20, upper = 60), list(lower = 100), "weakened"),
    list(list(lower = 20), list(upper = 20), "changed"),
    list(NULL, list(upper = 20), "strengthened"),
    list(list(lower = NA, upper = 20), list(lower = -Inf, upper = 20), NA)
  )
  for (case in cases) {
    expected <- if (is.na(case[[3]])) list() else list(list(id = "h", change = case[[3]]))
    expect_identical(tf_appraise_amendment(theory(case[[2]]), theory(case[[1]]))$revised,
                     expected)
  }
})

test_that("a claim is stronger than none and a fixed sign than nonzero", {
  theory <- function(claim) {
    p <- list(id = "h", statement = "S", type = "directional")
    if (!is.null(claim)) p$claim <- claim
    list(predictions = list(p))
  }
  assoc <- function(x, y, sign, given = NULL) {
    cl <- list(kind = "association", x = x, y = y)
    if (!is.null(given)) cl$given <- as.list(given)
    cl$sign <- sign
    cl
  }
  cases <- list(
    list(assoc("a", "b", "positive"), assoc("b", "a", "positive"), NA),
    list(assoc("a", "b", "zero", c("c", "d")), assoc("a", "b", "zero", c("d", "c")), NA),
    list(assoc("a", "b", "zero", "c"), assoc("a", "b", "nonzero", "c"), "weakened"),
    list(assoc("a", "b", "nonzero"), assoc("a", "b", "negative"), "strengthened"),
    list(assoc("a", "b", "positive"), assoc("a", "c", "nonzero"), "changed"),
    list(assoc("a", "b", "positive"), list(kind = "effect", x = "a", y = "b", sign = "positive"),
         "changed"),
    list(NULL, list(kind = "effect", x = "a", y = "b", sign = "nonzero"), "strengthened")
  )
  for (case in cases) {
    expected <- if (is.na(case[[3]])) list() else list(list(id = "h", change = case[[3]]))
    expect_identical(tf_appraise_amendment(theory(case[[2]]), theory(case[[1]]))$revised,
                     expected)
  }
})

test_that("a refuted prediction weakened after its test degenerates", {
  # amend-weakened rewrites the refuted h1 as an existence claim.
  prior <- dv_edge("amend-prior")
  new <- dv_edge("amend-weakened")
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "degenerating", revised = list(list(id = "h1", change = "weakened")),
    weakened_refuted = "h1"))
  # Widening the region after the failed test is enough, and so is a rename
  # that widens it.
  widened <- prior
  widened$predictions[[1]]$bounds <- list(lower = 0.2, upper = 0.8)
  expect_identical(tf_appraise_amendment(widened, prior), dv_record(
    verdict = "degenerating", revised = list(list(id = "h1", change = "weakened")),
    weakened_refuted = "h1"))
  widened$predictions[[1]]$id <- "h1_wide"
  widened$test_outcomes[[1]]$prediction_id <- "h1_wide"
  expect_identical(tf_appraise_amendment(widened, prior), dv_record(
    verdict = "degenerating", renamed = list(list(prior = "h1", new = "h1_wide")),
    revised = list(list(id = "h1_wide", change = "weakened")), weakened_refuted = "h1_wide"))
})

test_that("weakening an untested prediction loses content", {
  # amend-unresolved with p3 cited correctly is progressive. Weakening the
  # untested h2 to an existence claim makes it neutral.
  prior <- dv_edge("amend-prior")
  new <- dv_edge("amend-unresolved")
  new$predictions[[3]]$derives_from <- list("p3")
  new$predictions[[2]]$type <- "existence"
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    new_predictions = "h3", corroborated_new = "h3", content_lost = "h2",
    theoretically_progressive = TRUE, empirically_progressive = TRUE,
    revised = list(list(id = "h2", change = "weakened")),
    implications_gained = c("c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3")))
})

test_that("a new prediction citing a missing proposition is unresolved", {
  # amend-unresolved cites p33 for p3. Citing p3 makes the amendment progressive.
  prior <- dv_edge("amend-prior")
  new <- dv_edge("amend-unresolved")
  gained <- c("c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3")
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    new_predictions = "h3", corroborated_new = "h3", unresolved = "h3",
    implications_gained = gained))
  new$predictions[[3]]$derives_from <- list("p3", "p99")
  expect_identical(tf_appraise_amendment(new, prior)$unresolved, "h3")
  new$predictions[[3]]$derives_from <- list("p3")
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "progressive", new_predictions = "h3", corroborated_new = "h3",
    theoretically_progressive = TRUE, empirically_progressive = TRUE,
    implications_gained = gained))
})

test_that("an unrefuted implication lost blocks a progressive verdict", {
  # amend-lost-implication joins c1 to c3 and gives up c1 _||_ c3 | c2.
  prior <- dv_edge("amend-prior")
  new <- dv_edge("amend-lost-implication")
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    new_predictions = "h3", corroborated_new = "h3", theoretically_progressive = TRUE,
    empirically_progressive = TRUE, implications_lost = "c1 _||_ c3 | c2",
    implications_lost_unrefuted = "c1 _||_ c3 | c2"))
  # A refuted or mixed prediction of the prior that states the independence,
  # with any given and either order, refutes the implication.
  for (outcomes in list(FALSE, c(TRUE, FALSE))) {
    h0 <- list(id = "h0", statement = "c1 and c3 are unrelated.", type = "interval",
               claim = list(kind = "association", x = "c3", y = "c1", sign = "zero"))
    refuted <- dv_add(prior, "predictions", h0)
    for (p in outcomes) refuted <- dv_add(refuted, "test_outcomes", list(prediction_id = "h0", passed = p))
    expect_identical(tf_appraise_amendment(dv_add(new, "predictions", h0), refuted), dv_record(
      verdict = "progressive", new_predictions = "h3", corroborated_new = "h3",
      theoretically_progressive = TRUE, empirically_progressive = TRUE,
      implications_lost = "c1 _||_ c3 | c2"))
  }
})

test_that("a version whose graph is refused is not compared", {
  # A repeated construct id makes tf_implications() refuse the new version.
  prior <- dv_edge("amend-prior")
  new <- dv_edge("amend-lost-implication")
  new <- dv_add(new, "constructs", new$constructs[[1]])
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "progressive", new_predictions = "h3", corroborated_new = "h3",
    theoretically_progressive = TRUE, empirically_progressive = TRUE,
    implications_compared = FALSE))
})

test_that("dropping untested predictions loses content", {
  # D4: refuted pred2 and untested pred3 are dropped. Losing untested content
  # blocks a progressive verdict.
  prior <- dv_with_failed_pred2()
  new <- dv_with_p4(prior)
  new$predictions <- dv_drop(new$predictions, c("pred2", "pred3"))
  new$test_outcomes <- dv_drop(new$test_outcomes, "pred2", key = "prediction_id")
  expect_identical(tf_appraise_amendment(new, prior), dv_p4_record(
    verdict = "neutral", dropped = c("pred2", "pred3"), content_lost = "pred3"))
})

test_that("dropping a corroborated prediction blocks a progressive verdict", {
  v1 <- dv_v1()
  new <- dv_with_p4(v1)
  new$predictions <- dv_drop(new$predictions, "pred1")
  new$test_outcomes <- dv_drop(new$test_outcomes, "pred1", key = "prediction_id")
  expect_identical(tf_appraise_amendment(new, v1), dv_p4_record(
    verdict = "neutral", dropped = "pred1", dropped_corroborated = "pred1"))
})

test_that("a failed replication of retained content is a new anomaly", {
  # D5. An anomaly is reported and never decides the verdict.
  v1 <- dv_v1()
  new <- dv_add(v1, "test_outcomes", list(prediction_id = "pred1", passed = FALSE,
                                          registered = "osf.io/klmno"))
  expect_identical(tf_appraise_amendment(new, v1), dv_record(new_anomalies = "pred1"))
  ap <- tf_appraise_amendment(dv_with_p4(new), v1)
  expect_identical(ap$verdict, "progressive")
  expect_identical(ap$new_anomalies, "pred1")
  # A renamed prediction is retained content too.
  new$predictions[[1]]$id <- "pred1_v2"
  new$test_outcomes <- lapply(new$test_outcomes, function(t) {
    if (identical(t$prediction_id, "pred1")) t$prediction_id <- "pred1_v2"
    t
  })
  ap <- tf_appraise_amendment(new, v1)
  expect_identical(ap$renamed, list(list(prior = "pred1", new = "pred1_v2")))
  expect_identical(ap$new_anomalies, "pred1_v2")
})

test_that("an unregistered pass corroborates but is not reported as registered", {
  # D7: registered is read for the report key alone.
  v1 <- dv_v1()
  for (registered in list(NA, " ")) {
    new <- dv_with_p4(v1)
    new$test_outcomes[[length(new$test_outcomes)]]$registered <- registered
    expect_identical(tf_appraise_amendment(new, v1),
                     dv_p4_record(corroborated_new_registered = character(0)))
  }
})

test_that("a prediction derived from nothing adds no content", {
  v1 <- dv_v1()
  new <- dv_add(v1, "predictions", list(id = "pred5", statement = "A claim derived from nothing.",
                                        type = "point"))
  new <- dv_add(new, "test_outcomes", list(prediction_id = "pred5", passed = TRUE))
  expect_identical(tf_appraise_amendment(new, v1), dv_record(
    new_predictions = "pred5", corroborated_new = "pred5", underived = "pred5"))
})

test_that("propositions are compared by content, not by id", {
  # p2 renamed q2 holds the same content, so a prediction derived from q2
  # still articulates what the prior held. Reversing p2's relation changes it.
  v1 <- dv_v1()
  pred5 <- list(id = "pred5", statement = "Threat predicts avoidance a week later.", type = "point")
  renamed <- v1
  renamed$propositions[[2]]$id <- "q2"
  renamed$predictions <- lapply(renamed$predictions, function(p) {
    p$derives_from <- lapply(p$derives_from, function(d) if (identical(d, "p2")) "q2" else d)
    p
  })
  renamed <- dv_add(renamed, "predictions", c(pred5, list(derives_from = list("q2"))))
  renamed <- dv_add(renamed, "test_outcomes", list(prediction_id = "pred5", passed = TRUE))
  ap <- tf_appraise_amendment(renamed, v1)
  expect_identical(ap$verdict, "neutral")
  expect_identical(ap$articulated, "pred5")
  changed <- v1
  changed$propositions[[2]]$relation <- "decreases"
  changed <- dv_add(changed, "predictions", c(pred5, list(derives_from = list("p2"))))
  changed <- dv_add(changed, "test_outcomes", list(prediction_id = "pred5", passed = TRUE))
  ap <- tf_appraise_amendment(changed, v1)
  expect_identical(ap$verdict, "progressive")
  expect_identical(ap$articulated, character(0))
})
