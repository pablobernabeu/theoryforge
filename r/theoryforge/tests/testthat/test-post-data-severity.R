# Post-data severity from an outcome's estimate and standard error (API_SPEC.md
# section 29). Mirrors the Python suite's test_post_data_severity.py: the same
# theories, values, rows and messages, and the same golden file for the
# modality-switching example.

pds_theory <- function(bounds, outcomes) {
  pred <- list(id = "h1", statement = "The effect lies within the bounds.", type = "interval")
  if (!is.null(bounds)) pred$bounds <- bounds
  list(schema_version = "1.0", id = "t", title = "T", maturity = "testing",
       predictions = list(pred), test_outcomes = outcomes)
}

pds_sev <- function(bounds, estimate, se) {
  outcome <- list(prediction_id = "h1", passed = TRUE, estimate = estimate, se = se)
  rows <- tf_post_data_severity(pds_theory(bounds, list(outcome)))
  expect_identical(nrow(rows), 1L)
  rows$severity[[1]]
}

pds_refusal <- function(t) {
  tryCatch({
    tf_post_data_severity(t)
    NA_character_
  }, error = conditionMessage)
}

pds_read <- function(text) {
  path <- tempfile(fileext = ".yaml")
  on.exit(unlink(path))
  writeBin(charToRaw(enc2utf8(text)), path)
  tf_read(path)
}

# -- the values -------------------------------------------------------------

test_that("Mayo and Spanos's worked value is reproduced", {
  # Mayo and Spanos's (2011) worked value: the claim that a mean exceeds mu1
  # passes with SEV = Phi(1) = .841 when the estimate lies one standard error
  # above mu1. A one-sided claim leaves the upper bound open.
  expect_identical(pds_sev(list(lower = 0.2, upper = NULL), 0.4, 0.2), 0.841)
  expect_identical(pds_sev(list(lower = 0.2), 0.4, 0.2), 0.841)
})

test_that("one claim and one estimate pass less severely as the error grows", {
  # |r| <= .10 with an estimate of 0.
  bounds <- list(lower = -0.10, upper = 0.10)
  expect_identical(pds_sev(bounds, 0, 0.01), 1.0)
  expect_identical(pds_sev(bounds, 0, 0.10), 0.841)
  expect_identical(pds_sev(bounds, 0, 0.20), 0.691)
})

test_that("two finite bounds give one minus the TOST p value", {
  bounds <- list(lower = -0.10, upper = 0.10)
  for (case in list(c(0.03, 0.05), c(-0.08, 0.04), c(0.12, 0.10), c(0, 0.2))) {
    est <- case[[1]]
    se <- case[[2]]
    p_lower <- 1 - pnorm((est + 0.10) / se)
    p_upper <- 1 - pnorm((0.10 - est) / se)
    expect_identical(pds_sev(bounds, est, se),
                     theoryforge:::.tf_rnd(1 - max(p_lower, p_upper), 3))
  }
})

test_that("a point claim caps severity at one half", {
  expect_identical(pds_sev(list(lower = 0.3, upper = 0.3), 0.3, 0.05), 0.5)
  expect_identical(pds_sev(list(lower = 0.3, upper = 0.3), 0.32, 0.05), 0.345)
  expect_identical(pds_sev(list(lower = 0.2, upper = 0.4), 0.32, 0.05), 0.945)
})

test_that("an estimate outside the bounds passes with low severity", {
  expect_identical(pds_sev(list(lower = 20, upper = 60), 70, 6), 0.048)
  expect_identical(pds_sev(list(lower = 20, upper = NULL), 15, 5), 0.159)
})

# -- the rows ---------------------------------------------------------------

pds_rows_theory <- function() {
  list(
    schema_version = "1.0", id = "t", title = "T", maturity = "testing",
    predictions = list(
      list(id = "h1", statement = "s", type = "interval", bounds = list(lower = 20L, upper = 60L)),
      list(id = "h2", statement = "s", type = "directional"),
      list(id = "h3", statement = "s", type = "directional",
           bounds = list(lower = 0.1, upper = NULL)),
      list(id = "h4", statement = "s", type = "directional",
           bounds = list(lower = -Inf, upper = 0L))
    ),
    test_outcomes = list(
      list(prediction_id = "h1", passed = TRUE, estimate = 41L, se = 6L),
      # A prediction without bounds states no region for the estimate.
      list(prediction_id = "h2", passed = TRUE, estimate = 1, se = 0.5),
      # An outcome without an estimate and a standard error has no data to read.
      list(prediction_id = "h1", passed = FALSE, estimate = NULL, se = NULL),
      list(prediction_id = "h3", passed = TRUE, estimate = 0.25, se = 0.1),
      # An outcome naming no declared prediction, or naming one by a sequence.
      list(prediction_id = "hZ", passed = TRUE, estimate = 1, se = 0.5),
      list(prediction_id = list("h1"), passed = TRUE, estimate = 1, se = 0.5),
      "not an outcome",
      list(prediction_id = "h4", passed = FALSE, estimate = 0.5, se = 0.25)
    )
  )
}

test_that("one row per outcome that has data and a prediction with bounds", {
  rows <- tf_post_data_severity(pds_rows_theory())
  expect_s3_class(rows, "data.frame")
  expect_identical(names(rows), c("prediction_id", "outcome", "lower", "upper", "estimate",
                                  "se", "severity"))
  # An infinite bound is open, and is reported as one.
  expect_identical(rows, data.frame(
    prediction_id = c("h1", "h3", "h4"), outcome = c(0L, 3L, 7L),
    lower = c(20, 0.1, NA), upper = c(60, NA, 0), estimate = c(41, 0.25, 0.5),
    se = c(6, 0.1, 0.25), severity = c(0.999, 0.933, 0.023), stringsAsFactors = FALSE
  ))
})

test_that("a theory without data has no rows", {
  for (name in c("panic-network.theory.yaml", "weak-theory.theory.yaml")) {
    rows <- tf_post_data_severity(tf_read(tf_fixture_path(name)))
    expect_identical(nrow(rows), 0L, info = name)
    expect_identical(names(rows), c("prediction_id", "outcome", "lower", "upper", "estimate",
                                    "se", "severity"))
  }
  expect_identical(nrow(tf_post_data_severity(tf_theory("t", "T"))), 0L)
})

test_that("the modality example matches its golden", {
  rows <- tf_post_data_severity(tf_read(tf_fixture_path("modality-switching.theory.yaml")))
  expect_identical(rows, data.frame(
    prediction_id = "pred2", outcome = 0L, lower = 20, upper = 60, estimate = 41, se = 6,
    severity = 0.999, stringsAsFactors = FALSE
  ))
  golden <- jsonlite::fromJSON(tf_expected_path("modality-switching-2026.post_data_severity.json"),
                               simplifyVector = FALSE)
  expect_identical(length(golden), nrow(rows))
  for (key in names(rows)) {
    expect_equal(golden[[1]][[key]], rows[[key]][[1]], info = key)
  }
})

# -- the refusals -----------------------------------------------------------

pds_good <- list(prediction_id = "h1", passed = TRUE, estimate = 41, se = 6)

test_that("an outcome without usable data is refused", {
  # The outcome's data are refused whether or not its prediction declares
  # bounds, here none, since a half-recorded result is a mistake to report.
  both <- "requires both estimate and se; test_outcome[1]"
  se_msg <- "requires a finite se greater than 0; test_outcome[1]"
  est_msg <- "requires a finite estimate; test_outcome[1]"
  cases <- list(
    list(list(estimate = 41), both),
    list(list(se = 6, estimate = NULL), both),
    list(list(estimate = 41, se = 0), se_msg),
    list(list(estimate = 41, se = -6), se_msg),
    list(list(estimate = 41, se = "6"), se_msg),
    list(list(estimate = 41, se = TRUE), se_msg),
    list(list(estimate = 41, se = Inf), se_msg),
    list(list(estimate = 41, se = NaN), se_msg),
    list(list(estimate = NaN, se = 6), est_msg),
    list(list(estimate = -Inf, se = 6), est_msg),
    list(list(estimate = "41", se = 6), est_msg),
    list(list(estimate = list(41), se = 6), est_msg)
  )
  for (case in cases) {
    bad <- c(list(prediction_id = "h1", passed = TRUE), case[[1]])
    for (bounds in list(list(lower = 20, upper = 60), NULL)) {
      expect_identical(pds_refusal(pds_theory(bounds, list(pds_good, bad))),
                       paste("post_data_severity", case[[2]]),
                       info = paste(deparse(case[[1]]), collapse = ""))
    }
  }
})

test_that("bounds that state no region are refused", {
  none <- "requires at least one finite bound; prediction 'h1'"
  order <- "requires lower <= upper; prediction 'h1'"
  shape <- "requires bounds with numeric or null lower and upper; prediction 'h1'"
  cases <- list(
    list(list(lower = NULL, upper = NULL), none),
    list(setNames(list(), character(0)), none),
    list(list(), none),
    list(list(lower = -Inf, upper = Inf), none),
    list(list(lower = 60, upper = 20), order),
    list(list(lower = Inf, upper = 20), order),
    list(list(20, 60), shape),
    list(40, shape),
    list(list(lower = "20", upper = 60), shape),
    list(list(lower = 20, upper = TRUE), shape),
    list(list(lower = NaN, upper = 60), shape)
  )
  for (case in cases) {
    expect_identical(pds_refusal(pds_theory(case[[1]], list(pds_good))),
                     paste("post_data_severity", case[[2]]),
                     info = paste(deparse(case[[1]]), collapse = ""))
  }
})

test_that("bounds are read only for an outcome with data", {
  t <- pds_theory(list(lower = 60, upper = 20), list(list(prediction_id = "h1", passed = TRUE)))
  expect_identical(nrow(tf_post_data_severity(t)), 0L)
})

test_that("the first refusal in file order is raised", {
  outcomes <- list(list(prediction_id = "h1", passed = TRUE, estimate = 41, se = 6),
                   list(prediction_id = "h1", passed = TRUE, estimate = 41))
  t <- pds_theory(list(lower = 60, upper = 20), outcomes)
  expect_identical(pds_refusal(t), "post_data_severity requires lower <= upper; prediction 'h1'")
  t$test_outcomes <- rev(outcomes)
  expect_identical(pds_refusal(t),
                   "post_data_severity requires both estimate and se; test_outcome[0]")
})

pds_huge <- paste0("1", strrep("0", 400))

test_that("an integer too large for a double reads as an infinity, as in Python", {
  t <- pds_read(paste0('schema_version: "1.0"
id: t
title: T
maturity: testing
predictions:
  - id: h1
    statement: s
    type: interval
    bounds: {lower: -', pds_huge, ', upper: 60}
test_outcomes:
  - prediction_id: h1
    passed: true
    estimate: 41
    se: 6
'))
  expect_identical(tf_post_data_severity(t), data.frame(
    prediction_id = "h1", outcome = 0L, lower = NA_real_, upper = 60, estimate = 41, se = 6,
    severity = 0.999, stringsAsFactors = FALSE
  ))
  t$test_outcomes[[1]]$estimate <- Inf
  expect_identical(pds_refusal(t),
                   "post_data_severity requires a finite estimate; test_outcome[0]")
})

# -- validation (API_SPEC.md section 2, item 14) ----------------------------

test_that("full validation checks bounds, estimate and se", {
  pred <- function(id, ...) list(id = id, statement = "s", type = "interval", ...)
  outcome <- function(...) list(prediction_id = "h1", passed = TRUE, ...)
  t <- list(
    schema_version = "1.0", id = "t", title = "T", maturity = "testing",
    predictions = list(
      pred("h1", bounds = list(lower = 20, upper = 60)),
      pred("h2", bounds = list(20, 60)),
      pred("h3", bounds = list(lower = "20", upper = 60, unit = "ms")),
      pred("h4", bounds = list(lower = NULL, upper = NULL)),
      pred("h5", bounds = list(lower = 60, upper = 20)),
      pred("h6", bounds = list(lower = Inf, upper = -Inf)),
      pred("h7", bounds = list(lower = NaN)),
      pred("h8", bounds = list(lower = 0.1)),
      pred("h9", bounds = NULL),
      pred("h10", bounds = setNames(list(), character(0)))
    ),
    test_outcomes = list(
      outcome(estimate = 41, se = 6),
      outcome(estimate = "41", se = 6),
      outcome(estimate = NaN, se = 0),
      outcome(estimate = 41),
      outcome(se = Inf),
      outcome(estimate = TRUE, se = -1),
      outcome(estimate = NULL, se = NULL)
    )
  )
  expect_true(tf_validate(t))
  err <- tryCatch({
    tf_validate(t, full = TRUE)
    NA_character_
  }, error = conditionMessage)
  expect_identical(err, paste(
    "invalid theory object:",
    "prediction[1] bounds must be a mapping with numeric or null lower and upper;",
    "prediction[2] bounds has unknown field: unit;",
    "prediction[2] bounds must be a mapping with numeric or null lower and upper;",
    "prediction[3] bounds needs at least one finite bound;",
    "prediction[4] bounds lower exceeds upper;",
    "prediction[5] bounds needs at least one finite bound;",
    "prediction[5] bounds lower exceeds upper;",
    "prediction[6] bounds must be a mapping with numeric or null lower and upper;",
    "prediction[9] bounds needs at least one finite bound;",
    "test_outcome[1] estimate must be a finite number;",
    "test_outcome[2] estimate must be a finite number;",
    "test_outcome[2] se must be a finite number greater than 0;",
    "test_outcome[3] estimate and se must be given together;",
    "test_outcome[4] se must be a finite number greater than 0;",
    "test_outcome[4] estimate and se must be given together;",
    "test_outcome[5] estimate must be a finite number;",
    "test_outcome[5] se must be a finite number greater than 0"
  ))
})

test_that("full validation reads an integer too large for a double as an infinity", {
  t <- pds_read(paste0('schema_version: "1.0"
id: t
title: T
maturity: testing
predictions:
  - id: h1
    statement: s
    type: interval
    bounds: {lower: ', pds_huge, '}
test_outcomes:
  - prediction_id: h1
    passed: true
    estimate: ', pds_huge, '
    se: ', pds_huge, '
'))
  err <- tryCatch({
    tf_validate(t, full = TRUE)
    NA_character_
  }, error = conditionMessage)
  expect_identical(err, paste(
    "invalid theory object:",
    "prediction[0] bounds needs at least one finite bound;",
    "test_outcome[0] estimate must be a finite number;",
    "test_outcome[0] se must be a finite number greater than 0"
  ))
})

test_that("a theory that passes full validation is never refused", {
  t <- pds_rows_theory()
  t$test_outcomes <- t$test_outcomes[c(1, 2, 3, 4, 8)]
  expect_true(tf_validate(t, full = TRUE))
  expect_identical(nrow(tf_post_data_severity(t)), 3L)
})

# -- the dossier (API_SPEC.md section 20) -----------------------------------

test_that("the dossier gives each computable severity in the test record", {
  d <- tf_dossier(tf_read(tf_fixture_path("modality-switching.theory.yaml")))
  expect_true(grepl(paste0(
    "\n## Test record\n\n",
    "- pred2: passed; observed: Illustrative values, not a reported result: switch cost ",
    "41 ms (SE 6 ms).; post-data severity 0.999 for [20.0, 60.0]\n",
    "\n## Evidence\n"
  ), d, fixed = TRUE))
})

test_that("the dossier writes an open bound as an infinity and skips what it cannot compute", {
  t <- pds_rows_theory()
  t$test_outcomes <- list(
    list(prediction_id = "h3", passed = TRUE, estimate = 0.25, se = 0.1, date = "2026-05-01"),
    list(prediction_id = "h4", passed = FALSE, estimate = 0.5, se = 0.25),
    list(prediction_id = "h2", passed = TRUE, estimate = 1, se = 0.5),
    # The dossier lists an outcome it cannot compute without the note, and goes on.
    list(prediction_id = "h1", passed = TRUE, estimate = 41, se = 0)
  )
  expect_true(grepl(paste0(
    "\n## Test record\n\n",
    "- h3: passed; date: 2026-05-01; post-data severity 0.933 for [0.1, inf]\n",
    "- h4: failed; post-data severity 0.023 for [-inf, 0.0]\n",
    "- h2: passed\n",
    "- h1: passed\n",
    "\n## Evidence\n"
  ), tf_dossier(t), fixed = TRUE))
})
