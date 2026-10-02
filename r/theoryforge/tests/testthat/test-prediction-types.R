# The four prediction types, defined and honoured by the shipped examples.
#
# The precision item, the falsifiability blocker and the claim-form rubric all
# read a prediction's declared type, so the schema defines each type and the
# bundled theories use the labels as defined. The Python suite asserts the same
# in test_prediction_types.py.

test_that("the schema defines each prediction type", {
  props <- theoryforge:::tf_theory_schema()$properties
  desc <- props$predictions$items$properties$type$description
  for (phrase in c("existence: that an effect or relation exists, without a direction",
                   "directional: a sign or an order",
                   "the range the theory permits",
                   "measurement tolerance, not latitude the theory allows",
                   "self-declared")) {
    expect_true(grepl(phrase, desc, fixed = TRUE), info = phrase)
  }
})

test_that("the schema marks the unread fields as informational", {
  props <- theoryforge:::tf_theory_schema()$properties
  risk <- props$predictions$items$properties$risk_score$description
  at_test <- props$test_outcomes$items$properties$severity_at_test$description
  expect_match(risk, "^Informational, read by no function\\.")
  expect_identical(at_test, "Informational, read by no function.")
})

test_that("the panic point predictions state a value and a tolerance", {
  # These read "to a specified level" before, a point claim that named no value.
  heart <- paste("An interoceptive challenge raises heart rate 20 beats per minute",
                 "above baseline, within a measurement tolerance of 5, within 90 seconds.")
  avoid <- paste("Blocking interoceptive feedback lowers avoidance-task scores by 30",
                 "per cent, within a tolerance of 5 percentage points, within two weeks.")
  cases <- list(
    list(fixture = "panic-network.theory.yaml", id = "pred1", statement = heart),
    list(fixture = "panic-network-2026-v2.theory.yaml", id = "pred1", statement = heart),
    list(fixture = "panic-network-2026-v2.theory.yaml", id = "pred4", statement = avoid)
  )
  for (cs in cases) {
    preds <- tf_read(tf_fixture_path(cs$fixture))$predictions
    p <- preds[[which(vapply(preds, function(x) x$id, character(1)) == cs$id)]]
    expect_identical(p$type, "point", info = paste(cs$fixture, cs$id))
    expect_identical(p$statement, cs$statement, info = paste(cs$fixture, cs$id))
  }
})

# The app examples sit at the repository root, outside the package, so these
# checks run only from a source checkout.
app_example <- function(name) {
  path <- testthat::test_path("..", "..", "..", "..", "apps", "examples", name)
  if (!file.exists(path)) {
    testthat::skip("apps/examples is not reachable from this test run")
  }
  tf_read(path)
}

test_that("the app examples type comparative claims as directional", {
  # Ordinal, comparative, anti-phase and invariance claims, typed as the sign or
  # order they assert. Their declared severities are left as the authors set them.
  retyped <- list(
    list(name = "effort-recovery.theory.yaml", id = "pred3", declared = 0.7),
    list(name = "happy-vowel-manchester.theory.yaml", id = "pred_independence", declared = 0.8),
    list(name = "cognitive-dissonance.theory.yaml", id = "pred_rating_point", declared = 0.7),
    list(name = "cognitive-dissonance.theory.yaml", id = "pred_dissonance_mediates", declared = 0.6),
    list(name = "stereotype-threat.theory.yaml", id = "pred_salience_activation", declared = 0.6)
  )
  for (cs in retyped) {
    preds <- app_example(cs$name)$predictions
    p <- preds[[which(vapply(preds, function(x) x$id, character(1)) == cs$id)]]
    expect_identical(p$type, "directional", info = paste(cs$name, cs$id))
    expect_equal(p$severity, cs$declared, info = paste(cs$name, cs$id))
  }
})

test_that("effort-recovery's precision reflects its one interval prediction", {
  items <- tf_check(app_example("effort-recovery.theory.yaml"))$items
  precision <- items[[which(vapply(items, function(x) x$id, character(1)) == "precision")]]
  expect_identical(precision$status, "warn")
  expect_equal(precision$score, 0.333)
})
