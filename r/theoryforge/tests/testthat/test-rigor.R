# Exact rigor parity targets from API_SPEC.md / the task brief.

item_score <- function(rep, id) {
  for (it in rep$items) if (identical(it$id, id)) return(it$score)
  stop("no such item: ", id)
}
item_status <- function(rep, id) {
  for (it in rep$items) if (identical(it$id, id)) return(it$status)
  stop("no such item: ", id)
}

test_that("the report records the checklist version", {
  # Every number in the report comes from the checklist's weights and
  # thresholds, so a report naming only the theory's schema version cannot be
  # compared against one scored by a different checklist.
  rep <- tf_check(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_identical(rep$checklist_version,
                   theoryforge:::tf_checklist()$schema_version)
  expect_identical(names(rep)[1:4],
                   c("theory_id", "schema_version", "checklist_version", "maturity"))
})

test_that("the dossier header names the checklist version", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_true(grepl(sprintf("- Checklist version: %s", tf_check(panic)$checklist_version),
                    tf_dossier(panic), fixed = TRUE))
})

test_that("panic-network rigor matches exact targets", {
  rep <- tf_check(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_equal(rep$aggregate_score, 87.3)
  expect_equal(rep$coverage, 0.92)
  expect_identical(rep$gate, "pass")
  expect_identical(rep$n_blockers_failed, 0L)

  # An item with nothing to assess has the status "n/a" and a NULL score.
  expected <- list(
    falsifiability     = list("pass", 1.0),
    precision          = list("pass", 0.667),
    risk_severity      = list("pass", 0.567),
    parsimony          = list("n/a", NULL),
    non_redundancy     = list("pass", 1.0),
    construct_clarity  = list("pass", 1.0),
    scope              = list("pass", 1.0),
    logical_why        = list("pass", 1.0),
    causal_testability = list("pass", 1.0),
    diagnosticity      = list("pass", 0.333),
    formalisation      = list("pass", 1.0),
    derivation_chain   = list("pass", 1.0)
  )
  for (id in names(expected)) {
    expect_identical(item_status(rep, id), expected[[id]][[1]], info = id)
    expect_equal(item_score(rep, id), expected[[id]][[2]], info = id)
  }
})

test_that("weak-demo rigor matches exact targets", {
  rep <- tf_check(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_equal(rep$aggregate_score, 2.2)
  expect_equal(rep$coverage, 0.92)
  expect_identical(rep$gate, "blocked")
  expect_identical(rep$n_blockers_failed, 2L)

  expected <- list(
    falsifiability     = list("fail", 0.0),
    precision          = list("warn", 0.0),
    risk_severity      = list("warn", 0.2),
    parsimony          = list("n/a", NULL),
    non_redundancy     = list("warn", 0.0),
    construct_clarity  = list("warn", 0.0),
    scope              = list("warn", 0.0),
    logical_why        = list("warn", 0.0),
    causal_testability = list("warn", 0.0),
    diagnosticity      = list("warn", 0.0),
    formalisation      = list("warn", 0.0),
    derivation_chain   = list("fail", 0.0)
  )
  for (id in names(expected)) {
    expect_identical(item_status(rep, id), expected[[id]][[1]], info = id)
    expect_equal(item_score(rep, id), expected[[id]][[2]], info = id)
  }
})

test_that("rigour report matches the golden report JSON semantically", {
  cases <- list(
    c("panic-network.theory.yaml", "panic-network-2026.report.json"),
    c("weak-theory.theory.yaml", "weak-demo.report.json")
  )
  for (cs in cases) {
    rep <- tf_check(tf_read(tf_fixture_path(cs[[1]])))
    golden <- jsonlite::fromJSON(tf_expected_path(cs[[2]]), simplifyVector = FALSE)

    expect_equal(rep$aggregate_score, golden$aggregate_score, tolerance = 1e-9,
                 info = cs[[2]])
    expect_equal(rep$coverage, golden$coverage, tolerance = 1e-9, info = cs[[2]])
    expect_identical(rep$gate, golden$gate, info = cs[[2]])
    expect_equal(as.integer(rep$n_blockers_failed), as.integer(golden$n_blockers_failed),
                 info = cs[[2]])
    expect_identical(rep$theory_id, golden$theory_id)
    expect_identical(rep$schema_version, golden$schema_version)
    expect_identical(rep$maturity, golden$maturity)

    expect_equal(length(rep$items), length(golden$items))
    for (k in seq_along(golden$items)) {
      gi <- golden$items[[k]]
      ri <- rep$items[[k]]
      expect_identical(ri$id, gi$id, info = gi$id)
      expect_identical(ri$status, gi$status, info = gi$id)
      expect_equal(ri$score, gi$score, tolerance = 1e-9, info = gi$id)
    }
  }
})

test_that("tf_check reads null id and maturity as empty strings", {
  # The report is compared semantically across the twins, so a null field
  # must render as "" here exactly as the Python engine now emits.
  rep <- tf_check(list(schema_version = NULL, id = NULL, title = "T",
                       maturity = NULL))
  expect_identical(rep$theory_id, "")
  expect_identical(rep$schema_version, "")
  expect_identical(rep$maturity, "")
})

with_severities <- function(...) {
  sevs <- list(...)
  list(
    schema_version = "1.0", id = "t", title = "T", maturity = "building",
    predictions = lapply(seq_along(sevs), function(i) {
      list(id = paste0("h", i), statement = "s", type = "directional",
           severity = sevs[[i]])
    })
  )
}

test_that("the severity mean is a left fold", {
  # R's sum() uses an extended accumulator on x86_64 and CPython 3.12+ sum()
  # compensates, so either gives 0.5 here where a plain left-to-right sum, as
  # on Apple Silicon R or Python 3.11, gives 0.49999999999999994. The twins
  # agree only if both fold left in file order (API_SPEC section 4).
  expect_identical(theoryforge:::.tf_mean(c(0.6, 0.7, 0.2)), 0.49999999999999994)
})

test_that("the risk_severity status comes from the rounded mean", {
  # The exact mean equals min_severity (0.5). Comparing the unrounded mean
  # made the status depend on the platform's accumulator.
  rep <- tf_check(with_severities(0.6, 0.7, 0.2))
  expect_identical(item_status(rep, "risk_severity"), "pass")
  expect_identical(item_score(rep, "risk_severity"), 0.5)
})

test_that("tf_check refuses a severity outside the unit interval", {
  # A severity of 7 was scored and could lift the aggregate above 100.
  for (bad in c(7, -3, 1.5)) {
    expect_error(
      tf_check(with_severities(0.5, bad)),
      paste0("check requires prediction severities within [0, 1]; ",
             "out-of-range severity for prediction: h2"),
      fixed = TRUE
    )
  }
  expect_error(tf_check(with_severities(7L)), "out-of-range severity", fixed = TRUE)
})

test_that("tf_check refuses an infinite severity as non-numeric", {
  # R printed an aggregate of Inf and Python raised OverflowError from rnd().
  for (bad in c(Inf, -Inf, NaN)) {
    expect_error(
      tf_check(with_severities(bad)),
      paste0("check requires numeric prediction severities; ",
             "non-numeric severity for prediction: h1"),
      fixed = TRUE
    )
  }
})

test_that("tf_check accepts the ends of the unit interval", {
  rep <- tf_check(with_severities(0, 1L))
  expect_identical(item_status(rep, "risk_severity"), "pass")
  expect_identical(item_score(rep, "risk_severity"), 0.5)
})

test_that(".tf_rnd never returns a negative zero", {
  for (x in c(-0.0004, -0.0, -1e-9)) {
    expect_true(1 / theoryforge:::.tf_rnd(x, 3) > 0, info = format(x))
  }
  expect_identical(jsonlite::toJSON(theoryforge:::.tf_rnd(-0.0004, 3), digits = NA),
                   jsonlite::toJSON(0, digits = NA))
  # NaN and infinities pass through unchanged.
  expect_true(is.nan(theoryforge:::.tf_rnd(NaN, 3)))
  expect_identical(theoryforge:::.tf_rnd(-Inf, 3), -Inf)
})

test_that("tf_report returns valid JSON", {
  out <- tf_report(tf_read(tf_fixture_path("panic-network.theory.yaml")), "json")
  expect_true(jsonlite::validate(out))
  parsed <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  expect_equal(parsed$aggregate_score, 87.3, tolerance = 1e-9)
  # A NULL score is written as null, the value Python's None gives.
  expect_null(parsed$items[[4]]$score)
  expect_true(grepl('"score": null', out, fixed = TRUE))
  expect_identical(parsed$gate, "pass")
})

test_that("tf_report html format works and json/html are the only formats", {
  html <- tf_report(tf_read(tf_fixture_path("weak-theory.theory.yaml")), "html")
  expect_true(grepl("theoryforge-report", html))
  expect_error(tf_report(tf_read(tf_fixture_path("weak-theory.theory.yaml")), "xml"),
               "unknown report format")
})

test_that("tf_report html escapes the id and every cell it interpolates", {
  # The schema allows any non-empty id, and the checklist citations hold a
  # bare '&', so both reached the HTML unescaped.
  html <- tf_report(tf_theory("a<b&c", "T"), "html")
  expect_match(html, "<h2>Rigour report: a&lt;b&amp;c</h2>", fixed = TRUE)
  expect_false(grepl("a<b&c", html, fixed = TRUE))
  expect_false(grepl("&(?!amp;|lt;|gt;|middot;)", html, perl = TRUE))
})
