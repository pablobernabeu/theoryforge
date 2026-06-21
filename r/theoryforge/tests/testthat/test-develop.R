# Amendment appraisal (API_SPEC.md section 10).

test_that("v2-vs-v1 is progressive with corroborated new prediction, no ad-hoc", {
  v1 <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  v2 <- tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml"))
  ap <- tf_appraise_amendment(v2, v1)
  expect_identical(ap$verdict, "progressive")
  expect_identical(ap$new_predictions, "pred4")
  expect_identical(ap$corroborated_new, "pred4")
  expect_identical(ap$ad_hoc_assumptions, character(0))
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
