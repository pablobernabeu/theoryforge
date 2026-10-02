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

# The R builders have always taken a single string and a template with null
# collections. The Python builders of 0.6.0 split the string into characters and
# failed on the template. test_builders.py runs the same calls there, and these
# two tests keep the R side as it is.
test_that("a single string is stored as a one-element list", {
  t <- tf_theory("demo-5", "Single strings") |>
    tf_add_construct("c_arousal", "Physiological arousal", "Bodily activation.",
                     measurement = "heart-rate variability",
                     boundary_conditions = "awake adults") |>
    tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
    tf_add_proposition("p1", "c_arousal", "c_threat", "causes") |>
    tf_add_alternative("alt1", "A rival", key_constructs = "c_threat") |>
    tf_add_prediction("h1", "A claim.", "point", derives_from = "p1",
                      diagnostic_vs = "alt1") |>
    tf_add_assumption("a1", "An assumption.", added_for = "h1", protects = "h1")
  expect_identical(t$constructs[[1]]$measurement, list("heart-rate variability"))
  expect_identical(t$constructs[[1]]$boundary_conditions, list("awake adults"))
  expect_identical(t$alternatives[[1]]$key_constructs, list("c_threat"))
  expect_identical(t$predictions[[1]]$derives_from, list("p1"))
  expect_identical(t$predictions[[1]]$diagnostic_vs, list("alt1"))
  expect_identical(t$auxiliary_assumptions[[1]]$protects, list("h1"))
  expect_true(tf_validate(t, full = TRUE))
  expect_match(tf_compile_sem(t), "c_arousal =~ heart_rate_variability\n",
               fixed = TRUE)
})

test_that("builders work on a template whose collections are NULL", {
  path <- tempfile(fileext = ".yaml")
  writeLines(c('schema_version: "1.0"', "id: stub", "title: Stub",
               "maturity: draft", "constructs:", "propositions:",
               "provenance:"), path)
  t <- tf_read(path)
  expect_true("constructs" %in% names(t))
  expect_null(t$constructs)
  expect_null(t$provenance)
  t <- t |>
    tf_add_construct("c1", "C one", "the first") |>
    tf_add_construct("c2", "C two", "the second") |>
    tf_add_proposition("p1", "c1", "c2", "causes") |>
    tf_set_formal_model("ode")
  expect_identical(vapply(t$constructs, function(x) x$id, character(1)),
                   c("c1", "c2"))
  expect_identical(vapply(t$propositions, function(x) x$id, character(1)), "p1")
  expect_identical(t$formal_model$type, "ode")
  expect_identical(
    vapply(t$provenance, function(s) s$action, character(1)),
    c("tf_add_construct", "tf_add_construct", "tf_add_proposition",
      "tf_set_formal_model")
  )
  expect_identical(vapply(t$provenance, function(s) s$step, character(1)),
                   c("1", "2", "3", "4"))
  expect_true(tf_validate(t, full = TRUE))
})
