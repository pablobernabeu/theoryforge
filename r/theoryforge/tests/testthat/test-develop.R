# Amendment appraisal (API_SPEC.md section 10). The appraisal compares the
# content of two versions, not their prediction ids. Most cases amend the panic
# example, and the Python suite (test_develop.py) builds the same amendments and
# asserts the same records.

dv_S4 <- paste("Blocking interoceptive feedback lowers avoidance-task scores by 30 per cent,",
               "within a tolerance of 5 percentage points, within two weeks.")

# The record of an amendment that changes nothing, with the fields in `...`
# replaced, keys in the order of API_SPEC.md section 10.
dv_record <- function(...) {
  rec <- list(
    verdict = "neutral", new_predictions = character(0), corroborated_new = character(0),
    ad_hoc_assumptions = character(0), articulated = character(0), underived = character(0),
    corroborated_new_registered = character(0), renamed = list(), dropped = character(0),
    dropped_corroborated = character(0), content_lost = character(0),
    new_anomalies = character(0), assumptions = list()
  )
  changes <- list(...)
  for (k in names(changes)) rec[[k]] <- changes[[k]]
  rec
}

dv_v1 <- function() tf_read(tf_fixture_path("panic-network.theory.yaml"))

# The panic example with a failed test of pred2, the anomaly the rescue cases answer.
dv_with_failed_pred2 <- function() {
  prior <- dv_v1()
  prior$test_outcomes <- c(prior$test_outcomes, list(list(prediction_id = "pred2", passed = FALSE)))
  prior
}

# `theory` amended as the revised v2 amends v1: a new proposition and a prediction from it.
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

test_that("v2-vs-v1 is progressive with corroborated new prediction, no ad-hoc", {
  # v2 adds proposition p4 and derives pred4 from it, and a registered test
  # corroborates pred4: new content that survived a test.
  v1 <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  v2 <- tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml"))
  ap <- tf_appraise_amendment(v2, v1)
  expect_identical(ap, dv_record(verdict = "progressive", new_predictions = "pred4",
                                 corroborated_new = "pred4",
                                 corroborated_new_registered = "pred4"))
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

test_that("the record keeps its four fields first", {
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

test_that("failed replications leave a new prediction mixed", {
  # D1: one pass and two failures make pred4 mixed, which is not corroborated.
  v1 <- dv_v1()
  new <- dv_with_p4(v1)
  new$test_outcomes <- c(new$test_outcomes,
                         rep(list(list(prediction_id = "pred4", passed = FALSE)), 2L))
  expect_identical(.tf_prediction_status("pred4", new$test_outcomes), "mixed")
  expect_identical(tf_appraise_amendment(new, v1), dv_record(new_predictions = "pred4"))
})

test_that("a renamed prediction is not new", {
  # D2: pred1 under a new id, its statement reflowed, is the same content.
  v1 <- dv_v1()
  new <- v1
  statement <- new$predictions[[1]]$statement
  new$predictions[[1]]$id <- "pred1_v2"
  new$predictions[[1]]$statement <- paste0("  ", sub(" ", "  \n ", statement, fixed = TRUE), "\t")
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
                            independent = list()))))
})

test_that("an old corroborated prediction cannot clear a rescue", {
  # I16 case B: pred1 passed before the amendment, so listing it in protects
  # lends the assumption no support.
  prior <- dv_with_failed_pred2()
  new <- dv_add(prior, "auxiliary_assumptions", list(
    id = "aux_rescue", statement = "s", added_for = "pred2", protects = list("pred2", "pred1")))
  ap <- tf_appraise_amendment(new, prior)
  expect_identical(ap$assumptions, list(list(id = "aux_rescue", added_for = "pred2",
                                             class = "ad_hoc1", independent = list())))
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
                                             class = "ad_hoc1", independent = list())))
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
                            independent = list(list(id = "pred5", status = "untested"))))))
  new <- dv_add(new, "test_outcomes", list(prediction_id = "pred5", passed = TRUE,
                                           registered = "osf.io/x"))
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "progressive", new_predictions = "pred5", corroborated_new = "pred5",
    corroborated_new_registered = "pred5",
    assumptions = list(list(id = "aux_baseline", added_for = "pred2",
                            class = "independently_corroborated",
                            independent = list(list(id = "pred5", status = "corroborated"))))))
})

test_that("only an assumption added for an anomaly is appraised", {
  # A NULL, blank or non-text added_for marks a core assumption, and added_for
  # is read as text, so a one-element list names its element.
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
                                             class = "ad_hoc1", independent = list())))
  expect_identical(ap$ad_hoc_assumptions, "listed")
})

test_that("dropping untested predictions is reported as content lost", {
  # D4: refuted pred2 and untested pred3 are dropped. Losing untested content
  # is reported and does not block a progressive verdict.
  prior <- dv_with_failed_pred2()
  new <- dv_with_p4(prior)
  new$predictions <- dv_drop(new$predictions, c("pred2", "pred3"))
  new$test_outcomes <- dv_drop(new$test_outcomes, "pred2", key = "prediction_id")
  expect_identical(tf_appraise_amendment(new, prior), dv_record(
    verdict = "progressive", new_predictions = "pred4", corroborated_new = "pred4",
    corroborated_new_registered = "pred4", dropped = c("pred2", "pred3"),
    content_lost = "pred3"))
})

test_that("dropping a corroborated prediction blocks a progressive verdict", {
  v1 <- dv_v1()
  new <- dv_with_p4(v1)
  new$predictions <- dv_drop(new$predictions, "pred1")
  new$test_outcomes <- dv_drop(new$test_outcomes, "pred1", key = "prediction_id")
  expect_identical(tf_appraise_amendment(new, v1), dv_record(
    new_predictions = "pred4", corroborated_new = "pred4", corroborated_new_registered = "pred4",
    dropped = "pred1", dropped_corroborated = "pred1"))
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
    t$prediction_id <- "pred1_v2"
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
    expect_identical(tf_appraise_amendment(new, v1), dv_record(
      verdict = "progressive", new_predictions = "pred4", corroborated_new = "pred4"))
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
