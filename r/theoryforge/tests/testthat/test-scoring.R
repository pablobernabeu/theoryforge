# Severity rubric (API_SPEC.md section 9): exact parity values.

test_that("tf_severity returns the documented panic values in file order", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sev <- tf_severity(theory)
  expect_s3_class(sev, "data.frame")
  expect_identical(names(sev),
                   c("prediction_id", "type", "risk_score", "computed_severity"))
  expect_identical(sev$prediction_id, c("pred1", "pred2", "pred3"))
  expect_identical(sev$type, c("point", "interval", "directional"))

  # pred1: point, diagnostic_vs hits a registered alternative -> 0.9 + 0.1 = 1.0
  expect_equal(sev$risk_score[1], 0.9)
  expect_equal(sev$computed_severity[1], 1.0)
  # pred2: interval, no diagnostic -> 0.7 / 0.7
  expect_equal(sev$risk_score[2], 0.7)
  expect_equal(sev$computed_severity[2], 0.7)
  # pred3: directional, CRUD discount -> 0.4 * 0.75 = 0.3
  expect_equal(sev$risk_score[3], 0.4)
  expect_equal(sev$computed_severity[3], 0.3)
})

test_that("existence predictions and missing diagnostics score the base", {
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  sev <- tf_severity(theory)
  expect_identical(sev$prediction_id, "w1")
  expect_equal(sev$risk_score[1], 0.1)
  expect_equal(sev$computed_severity[1], 0.1)
})

test_that("diagnostic bonus only fires against a registered alternative", {
  t <- tf_theory("sev-1", "Severity coverage")
  # diagnostic_vs points at an unregistered alternative -> no bonus.
  t <- tf_add_prediction(t, "p1", "stmt", "point", diagnostic_vs = c("not_registered"))
  sev <- tf_severity(t)
  expect_equal(sev$computed_severity[1], 0.9)
})
