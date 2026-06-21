# Builder (BUILDING mode): provenance actions/order, and the result validates.

test_that("tf_theory seeds schema_version and the first provenance entry", {
  t <- tf_theory("demo-1", "A demo theory")
  expect_identical(t$schema_version, "1.0")
  expect_identical(t$id, "demo-1")
  expect_identical(t$title, "A demo theory")
  expect_identical(t$maturity, "building")
  expect_identical(t$theory_form, "network")
  expect_length(t$provenance, 1L)
  expect_identical(t$provenance[[1]]$step, "1")
  expect_identical(t$provenance[[1]]$action, "tf_theory")
  expect_identical(t$provenance[[1]]$detail, "demo-1")
})

test_that("builders append provenance with correct action, detail, and step order", {
  t <- tf_theory("demo-2", "Builder coverage")
  t <- tf_add_construct(t, "c1", "C One", "definition one",
                        measurement = c("m1"), boundary_conditions = c("adults"))
  t <- tf_add_construct(t, "c2", "C Two", "definition two")
  t <- tf_add_proposition(t, "p1", from = "c1", to = "c2", relation = "increases",
                          mechanism = "because")
  t <- tf_add_prediction(t, "pr1", "Some statement", "point",
                         derives_from = c("p1"), diagnostic_vs = c("alt1"))
  t <- tf_add_alternative(t, "alt1", "An alternative", key_constructs = c("x"))
  t <- tf_add_assumption(t, "a1", "An assumption", added_for = "pr1",
                         protects = c("pr1"))
  t <- tf_set_formal_model(t, "ode", spec_ref = "models/x.py")

  actions <- vapply(t$provenance, function(s) s$action, character(1))
  details <- vapply(t$provenance, function(s) s$detail, character(1))
  steps <- vapply(t$provenance, function(s) s$step, character(1))

  expect_identical(actions, c(
    "tf_theory", "tf_add_construct", "tf_add_construct", "tf_add_proposition",
    "tf_add_prediction", "tf_add_alternative", "tf_add_assumption",
    "tf_set_formal_model"
  ))
  expect_identical(details, c(
    "demo-2", "c1", "c2", "p1", "pr1", "alt1", "a1", "ode"
  ))
  expect_identical(steps, as.character(seq_along(t$provenance)))

  # Collections populated in order.
  expect_length(t$constructs, 2L)
  expect_length(t$propositions, 1L)
  expect_length(t$predictions, 1L)
  expect_length(t$alternatives, 1L)
  expect_length(t$auxiliary_assumptions, 1L)
  expect_identical(t$formal_model$type, "ode")
  expect_identical(t$formal_model$spec_ref, "models/x.py")
})

test_that("a builder-constructed theory passes structural validation", {
  t <- tf_theory("demo-3", "Valid theory")
  t <- tf_add_construct(t, "c1", "C One", "definition one")
  t <- tf_add_proposition(t, "p1", from = "c1", to = "c1", relation = "associates")
  t <- tf_add_prediction(t, "pr1", "Statement", "directional")
  expect_true(tf_validate(t))
})

test_that("optional fields are omitted when NULL", {
  t <- tf_theory("demo-4", "Sparse")
  t <- tf_add_construct(t, "c1", "C", "d")
  expect_false("measurement" %in% names(t$constructs[[1]]))
  expect_false("boundary_conditions" %in% names(t$constructs[[1]]))
})
