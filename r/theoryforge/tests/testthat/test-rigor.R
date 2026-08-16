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
  expect_equal(rep$aggregate_score, 84.8)
  expect_identical(rep$gate, "pass")
  expect_identical(rep$n_blockers_failed, 0L)

  expected <- list(
    falsifiability     = c("pass", 1.0),
    precision          = c("pass", 0.667),
    risk_severity      = c("pass", 0.567),
    parsimony          = c("pass", 0.667),
    non_redundancy     = c("pass", 0.909),
    construct_clarity  = c("pass", 1.0),
    scope              = c("pass", 1.0),
    logical_why        = c("pass", 1.0),
    causal_testability = c("pass", 1.0),
    diagnosticity      = c("pass", 0.333),
    formalisation      = c("pass", 1.0),
    derivation_chain   = c("pass", 1.0)
  )
  for (id in names(expected)) {
    expect_identical(item_status(rep, id), expected[[id]][[1]], info = id)
    expect_equal(item_score(rep, id), as.numeric(expected[[id]][[2]]), info = id)
  }
})

test_that("weak-demo rigor matches exact targets", {
  rep <- tf_check(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_equal(rep$aggregate_score, 12.0)
  expect_identical(rep$gate, "blocked")
  expect_identical(rep$n_blockers_failed, 2L)

  expected <- list(
    falsifiability     = c("fail", 0.0),
    precision          = c("warn", 0.0),
    risk_severity      = c("warn", 0.2),
    parsimony          = c("pass", 1.0),
    non_redundancy     = c("pass", 0.2),
    construct_clarity  = c("warn", 0.0),
    scope              = c("warn", 0.0),
    logical_why        = c("warn", 0.0),
    causal_testability = c("warn", 0.0),
    diagnosticity      = c("warn", 0.0),
    formalisation      = c("warn", 0.0),
    derivation_chain   = c("fail", 0.0)
  )
  for (id in names(expected)) {
    expect_identical(item_status(rep, id), expected[[id]][[1]], info = id)
    expect_equal(item_score(rep, id), as.numeric(expected[[id]][[2]]), info = id)
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

test_that("tf_report returns valid JSON", {
  out <- tf_report(tf_read(tf_fixture_path("panic-network.theory.yaml")), "json")
  expect_true(jsonlite::validate(out))
  parsed <- jsonlite::fromJSON(out, simplifyVector = FALSE)
  expect_equal(parsed$aggregate_score, 84.8, tolerance = 1e-9)
  expect_identical(parsed$gate, "pass")
})

test_that("tf_report html format works and json/html are the only formats", {
  html <- tf_report(tf_read(tf_fixture_path("weak-theory.theory.yaml")), "html")
  expect_true(grepl("theoryforge-report", html))
  expect_error(tf_report(tf_read(tf_fixture_path("weak-theory.theory.yaml")), "xml"),
               "unknown report format")
})
