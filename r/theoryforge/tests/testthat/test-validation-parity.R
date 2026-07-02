# Validation and cross-language parity behaviour. These lock the contracts the
# byte-identical golden artefacts do not exercise, and mirror the Python
# tests/test_validation_parity.py so the two implementations stay aligned.

consistent_theory <- function() {
  list(
    schema_version = "1.0", id = "t", title = "T", maturity = "building",
    constructs = list(
      list(id = "c1", label = "C1", definition = "d"),
      list(id = "c2", label = "C2", definition = "d")
    ),
    propositions = list(list(id = "p1", from = "c1", to = "c2", relation = "increases")),
    predictions = list(list(id = "h1", statement = "s", type = "directional",
                            derives_from = list("p1"), diagnostic_vs = list("a1"))),
    alternatives = list(list(id = "a1", label = "A1")),
    auxiliary_assumptions = list(list(id = "x1", statement = "s", protects = list("h1"))),
    test_outcomes = list(list(prediction_id = "h1", passed = TRUE)),
    evidence = list(list(supports = "h1"))
  )
}

test_that("tf_validate(full = TRUE) accepts a consistent theory and the fixtures", {
  expect_true(tf_validate(consistent_theory(), full = TRUE))
  expect_true(tf_validate(tf_read(tf_fixture_path("panic-network.theory.yaml")), full = TRUE))
  expect_true(tf_validate(tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml")), full = TRUE))
  expect_true(tf_validate(tf_read(tf_fixture_path("weak-theory.theory.yaml")), full = TRUE))
})

test_that("tf_validate(full = TRUE) flags dangling and duplicate references", {
  bad <- list(
    schema_version = "1.0", id = "b", title = "B", maturity = "building",
    constructs = list(
      list(id = "c1", label = "C1", definition = "d"),
      list(id = "c1", label = "C1b", definition = "d")
    ),
    propositions = list(list(id = "p1", from = "c1", to = "cX", relation = "increases")),
    predictions = list(list(id = "h1", statement = "s", type = "directional",
                            derives_from = list("pZ"), diagnostic_vs = list("altZ"))),
    auxiliary_assumptions = list(list(id = "x1", statement = "s", protects = list("hZ"))),
    test_outcomes = list(list(prediction_id = "hZ", passed = TRUE)),
    evidence = list(list(supports = "hZ"))
  )
  err <- tryCatch(tf_validate(bad, full = TRUE), error = function(e) conditionMessage(e))
  expected <- c(
    "duplicate construct id: c1",
    "proposition[0] to 'cX' is not a known construct",
    "prediction[0] derives_from 'pZ' is not a known proposition",
    "prediction[0] diagnostic_vs 'altZ' is not a known alternative",
    "assumption[0] protects 'hZ' is not a known prediction",
    "test_outcome[0] prediction_id 'hZ' is not a known prediction",
    "evidence[0] supports 'hZ' is not a known prediction"
  )
  for (e in expected) expect_true(grepl(e, err, fixed = TRUE))
})

test_that("default tf_validate skips referential checks", {
  t <- list(schema_version = "1.0", id = "b", title = "B", maturity = "building",
            propositions = list(list(id = "p1", from = "cX", to = "cY", relation = "increases")))
  expect_true(tf_validate(t))
})

test_that("enum message is comma-joined without brackets", {
  bad <- list(schema_version = "1.0", id = "b", title = "B", maturity = "nope")
  err <- tryCatch(tf_validate(bad), error = function(e) conditionMessage(e))
  expect_true(grepl("maturity must be one of building, developing, draft, testing", err, fixed = TRUE))
  expect_false(grepl("[", err, fixed = TRUE))
})

test_that("tf_read and tf_read_corpus reject non-mapping input", {
  p <- tempfile(fileext = ".yaml"); writeLines(c("- a", "- b"), p)
  expect_error(tf_read(p), "Theory data must be a mapping")
  cpath <- tempfile(fileext = ".yaml"); writeLines(c("- 1", "- 2"), cpath)
  expect_error(tf_read_corpus(cpath), "Corpus data must be a mapping")
})

test_that("tf_osf_push base_url override is honoured", {
  res <- tf_osf_push(tf_theory("t", "T"), node = "abc12",
                     base_url = "https://example.org/v1/resources/")
  expect_true(startsWith(res$request$url, "https://example.org/v1/resources/abc12/"))
})
