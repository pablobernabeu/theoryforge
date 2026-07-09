# The scalar-singleton reading (API_SPEC.md section 4).
#
# A nonempty scalar string where the schema expects an array of strings is
# read as a singleton list, so natural YAML such as `derives_from: p1` means
# `["p1"]`. The Python suite (test_scalar_singleton.py) runs the identical
# YAML and asserts the same rigour verdict and gate.

scalar_theory_yaml <- 'schema_version: "1.0"
id: scalar-singleton-demo
title: Scalar singleton demo
maturity: building
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
    measurement: m1
    boundary_conditions: adults
  - id: c2
    label: Beta
    definition: The second construct entirely different.
    measurement: [m2]
    boundary_conditions: [adults]
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
    mechanism: Alpha drives Beta.
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: p1
'

test_that("scalar fields where the schema expects arrays read as singletons", {
  path <- tempfile(fileext = ".yaml")
  writeLines(scalar_theory_yaml, path)
  theory <- tf_read(path)
  expect_true(tf_validate(theory, full = TRUE))

  rep <- tf_check(theory)
  expect_identical(rep$gate, "pass")
  expect_identical(rep$n_blockers_failed, 0L)
  expect_equal(rep$aggregate_score, 67.0)

  items <- rep$items
  names(items) <- vapply(items, function(it) it$id, character(1))
  expect_identical(items$derivation_chain$status, "pass")
  expect_equal(items$derivation_chain$score, 1.0)
  expect_identical(items$construct_clarity$status, "pass")
  expect_identical(items$scope$status, "pass")
})

test_that("an empty or whitespace-only scalar counts as absent", {
  theory <- tf_theory("t", "T")
  theory$constructs <- list(list(
    id = "c1", label = "A", definition = "d",
    measurement = "  ", boundary_conditions = "adults"
  ))
  items <- tf_check(theory)$items
  names(items) <- vapply(items, function(it) it$id, character(1))
  expect_identical(items$construct_clarity$status, "warn")
  expect_identical(items$scope$status, "pass")
})
