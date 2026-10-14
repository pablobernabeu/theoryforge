# The sampling plan a prediction records (API_SPEC.md section 30). Mirrors the
# Python suite's test_sampling_plan.py: the same theories, messages and lines.

sp_section_heading <- "## Sampling plan (author-recorded; not scored)"

sp_full <- list(n_planned = 120, unit = "participants", alpha = 0.005, sided = "one",
                sesoi = 0.2, sesoi_scale = "Cohen's d", power = 0.9, power_lo = 0.88,
                power_hi = 0.92, method = "simulation in pilotr",
                design_ref = "https://osf.io/abcde",
                justification = "The smallest effect that would change practice.")

# A theory with one interval prediction h<i> per entry, given `test` unless the
# entry is the string "<absent>". list(NULL) entries keep a null block.
sp_theory <- function(...) {
  tests <- list(...)
  preds <- lapply(seq_along(tests), function(i) {
    p <- list(id = paste0("h", i), statement = paste0("Claim ", i, "."), type = "interval")
    if (!identical(tests[[i]], "<absent>")) p["test"] <- list(tests[[i]])
    p
  })
  list(schema_version = "1.0", id = "t", title = "T", maturity = "testing", predictions = preds)
}

sp_full_errors <- function(t) {
  tryCatch({
    tf_validate(t, full = TRUE)
    NA_character_
  }, error = conditionMessage)
}

# The sampling-plan section of a preregistration, from its heading to the blank
# line.
sp_section <- function(text) {
  start <- regexpr(sp_section_heading, text, fixed = TRUE)[[1]]
  rest <- substring(text, start)
  substring(rest, 1L, regexpr("\n\n", rest, fixed = TRUE)[[1]] - 1L)
}

# -- the schema ---------------------------------------------------------------

test_that("the schema closes the test block", {
  test <- tf_theory_schema()$properties$predictions$items$properties$test
  expect_false(test$additionalProperties)
  expect_identical(names(test$properties), c(
    "n_planned", "unit", "alpha", "sided", "sesoi", "sesoi_scale", "power",
    "decision_probability", "power_lo", "power_hi", "method", "design_ref",
    "justification"))
  expect_identical(unlist(test$properties$sided$enum), c("two", "one"))
})

# -- the builder (API_SPEC.md section 8) --------------------------------------

test_that("tf_add_prediction stores a test block when given", {
  t <- tf_theory("t", "T") |>
    tf_add_prediction("h1", "Claim.", "interval", severity = 0.6,
                      test = list(n_planned = 48, alpha = 0.05)) |>
    tf_add_prediction("h2", "Claim.", "interval") |>
    tf_add_prediction("h3", "Claim.", "interval", test = c(n_planned = 48, alpha = 0.05))
  expect_identical(names(t$predictions[[1]]), c("id", "statement", "type", "severity", "test"))
  expect_identical(t$predictions[[1]]$test, list(n_planned = 48, alpha = 0.05))
  expect_false("test" %in% names(t$predictions[[2]]))
  # A named vector is stored as the mapping it names, as a list would be.
  expect_identical(t$predictions[[3]]$test, list(n_planned = 48, alpha = 0.05))
  expect_identical(t$provenance[[3]],
                   list(step = "3", action = "tf_add_prediction", detail = "h2"))
})

# -- validation (API_SPEC.md section 2, item 14) ------------------------------

test_that("a complete block and the empty forms pass full validation", {
  t <- sp_theory(sp_full, NULL, setNames(list(), character(0)), list(), "<absent>",
                 list(n_planned = 2, power = 1L, power_lo = 0, power_hi = 1))
  expect_true(tf_validate(t, full = TRUE))
})

test_that("full validation reports each fault of a test block", {
  t <- sp_theory(
    sp_full,
    "n = 48",
    list(48, 0.05),
    list(sides = "two", n_planned = 0, unit = 5, alpha = 0.05),
    list(n_planned = 48.5, alpha = 1, sided = "both"),
    list(n_planned = "48", alpha = 0, sided = list("two"), sesoi = "20"),
    list(n_planned = TRUE, alpha = TRUE, sesoi = Inf, sesoi_scale = list("ms"),
         power = 1.2, decision_probability = -0.1, power_lo = 0.95, power_hi = 0.85),
    list(power_lo = 0.8, method = 1, design_ref = TRUE, justification = list("x")),
    list(power_lo = "0.8", power_hi = NaN, sesoi = NaN),
    list(power_hi = 0.9)
  )
  # The structural pass leaves the block alone.
  expect_true(tf_validate(t))
  expect_identical(sp_full_errors(t), paste0("invalid theory object: ", paste(c(
    "prediction[1] test must be a mapping",
    "prediction[2] test must be a mapping",
    "prediction[3] test has unknown field: sides",
    "prediction[3] test n_planned must be a whole number of at least 1",
    "prediction[3] test unit must be a string (quote the value in YAML)",
    "prediction[4] test n_planned must be a whole number of at least 1",
    "prediction[4] test alpha must be a number between 0 and 1",
    "prediction[4] test sided must be one of: two, one",
    "prediction[5] test n_planned must be a whole number of at least 1",
    "prediction[5] test alpha must be a number between 0 and 1",
    "prediction[5] test sided must be one of: two, one",
    "prediction[5] test sesoi must be a finite number",
    "prediction[6] test n_planned must be a whole number of at least 1",
    "prediction[6] test alpha must be a number between 0 and 1",
    "prediction[6] test sesoi must be a finite number",
    "prediction[6] test sesoi_scale must be a string",
    "prediction[6] test power must be a number between 0 and 1",
    "prediction[6] test decision_probability must be a number between 0 and 1",
    "prediction[6] test power_lo exceeds power_hi",
    "prediction[7] test power_lo and power_hi must be given together",
    "prediction[7] test method must be a string (quote the value in YAML)",
    "prediction[7] test design_ref must be a string (quote the value in YAML)",
    "prediction[7] test justification must be a string",
    "prediction[8] test sesoi must be a finite number",
    "prediction[8] test power_lo must be a number between 0 and 1",
    "prediction[8] test power_hi must be a number between 0 and 1",
    "prediction[9] test power_lo and power_hi must be given together"
  ), collapse = "; ")))
})

test_that("a test block is reported after the risk score and the bounds", {
  t <- sp_theory(list(alpha = 2))
  t$predictions[[1]]$risk_score <- 2
  t$predictions[[1]]$bounds <- list(20, 60)
  expect_identical(sp_full_errors(t), paste0(
    "invalid theory object: ",
    "prediction[0] risk_score must be a number between 0 and 1; ",
    "prediction[0] bounds must be a mapping with numeric or null lower and upper; ",
    "prediction[0] test alpha must be a number between 0 and 1"))
})

test_that("an integer too large for a double is no planned sample", {
  path <- tempfile(fileext = ".yaml")
  on.exit(unlink(path))
  writeBin(charToRaw(paste0('schema_version: "1.0"
id: t
title: T
maturity: testing
predictions:
  - id: h1
    statement: s
    type: interval
    test: {n_planned: 1', strrep("0", 400), '}
')), path)
  expect_identical(sp_full_errors(tf_read(path)), paste0(
    "invalid theory object: prediction[0] test n_planned must be a whole number of at least 1"))
})

# -- the preregistration (API_SPEC.md sections 11 and 30) ----------------------

test_that("the preregistration lists the sampling plan after the hypotheses", {
  t <- sp_theory(
    sp_full,
    "<absent>",
    list(decision_probability = 0.8, method = "simulation"),
    list(alpha = 0.0001, sided = "two"),
    list(justification = "Fixed by the size of the archive."),
    # A qualifier is written only with the value it qualifies.
    list(unit = "participants", sesoi_scale = "ms", power_lo = 0.8, power_hi = 0.9,
         method = "analytic"),
    list(sided = "two", n_planned = 48L),
    "48 participants",
    # A value that full validation refuses reads as absent.
    list(n_planned = 48.5, alpha = 1, power = 1.5, sided = "both", unit = 5),
    list(power = 0.85, decision_probability = 0.7, power_lo = 0.9, power_hi = 0.8),
    list(n_planned = 1e6, alpha = 5e-8, sesoi = -0.2, power = 1L)
  )
  text <- tf_preregister(t)
  expect_identical(sp_section(text), paste(c(
    sp_section_heading,
    paste0("- h1: n = 120 participants; alpha 0.005, one-sided; smallest effect of interest 0.2 ",
           "Cohen's d; power 0.9 [0.88, 0.92] (simulation in pilotr); design: ",
           "https://osf.io/abcde. The smallest effect that would change practice."),
    "- h2: no sampling plan stated",
    "- h3: decision probability 0.8 (simulation)",
    "- h4: alpha 0.0001, two-sided",
    "- h5: Fixed by the size of the archive.",
    "- h6: no sampling plan stated",
    "- h7: n = 48; two-sided",
    "- h8: no sampling plan stated",
    "- h9: no sampling plan stated",
    "- h10: power 0.85, decision probability 0.7",
    "- h11: n = 1000000; alpha 5e-08; smallest effect of interest -0.2; power 1"
  ), collapse = "\n"))
  # The section sits between the hypotheses and the implied independencies.
  expect_true(grepl(paste0("   - Test record: untested\n\n", sp_section_heading, "\n"), text,
                    fixed = TRUE))
  expect_true(grepl(paste0(sp_section(text), "\n\n## Implied conditional independencies"), text,
                    fixed = TRUE))
})

test_that("a theory without a stated plan has no section", {
  bare <- tf_preregister(sp_theory("<absent>", "<absent>"))
  expect_false(grepl(sp_section_heading, bare, fixed = TRUE))
  for (blocks in list(list(NULL, setNames(list(), character(0))), list(list(), "n = 48"),
                      list(list(unit = "participants"), list(alpha = 2)))) {
    expect_identical(tf_preregister(do.call(sp_theory, blocks)), bare)
  }
})

test_that("the modality example states its plan and matches its golden", {
  t <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  text <- tf_preregister(t)
  expect_identical(text, tf_read_golden(tf_expected_path("modality-switching-2026.prereg.md")))
  expect_identical(sp_section(text), paste(c(
    sp_section_heading,
    "- pred1: no sampling plan stated",
    paste0("- pred2: n = 48 participants; alpha 0.05, two-sided; smallest effect of interest ",
           "20 ms; power 0.9 (simulation). Illustrative values."),
    "- pred3: no sampling plan stated",
    "- pred4: no sampling plan stated"
  ), collapse = "\n"))
  # Without the block the document is the earlier format, the section left out.
  t$predictions[[2]]$test <- NULL
  expect_identical(tf_preregister(t),
                   sub(paste0(sp_section(text), "\n\n"), "", text, fixed = TRUE))
})

test_that("every other fixture keeps its preregistration", {
  cases <- list(
    c("panic-network.theory.yaml", "panic-network-2026.prereg.md"),
    c("panic-network-2026-v2.theory.yaml", "panic-network-2026-v2.prereg.md"),
    c("weak-theory.theory.yaml", "weak-demo.prereg.md")
  )
  for (cs in cases) {
    text <- tf_preregister(tf_read(tf_fixture_path(cs[[1]])))
    expect_false(grepl(sp_section_heading, text, fixed = TRUE), info = cs[[1]])
    expect_identical(text, tf_read_golden(tf_expected_path(cs[[2]])), info = cs[[1]])
  }
})

test_that("the dossier carries the plan in its preregistration", {
  t <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  d <- tf_dossier(t)
  expect_true(grepl("\n## Preregistration\n\n# Preregistration: ", d, fixed = TRUE))
  expect_identical(lengths(regmatches(d, gregexpr(sp_section_heading, d, fixed = TRUE))), 1L)
  expect_true(endsWith(d, tf_preregister(t)))
})

test_that("a written theory reads back with its plan", {
  t <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  for (ext in c(".yaml", ".json")) {
    path <- tempfile(fileext = ext)
    tf_write(t, path)
    back <- tf_read(path)
    unlink(path)
    expect_equal(back$predictions[[2]]$test, t$predictions[[2]]$test, info = ext)
    expect_identical(tf_preregister(back), tf_preregister(t), info = ext)
  }
})

# -- recorded, not scored -----------------------------------------------------

test_that("the block moves no score", {
  # Power must not raise a prediction's severity (Meehl, 1967), so nothing
  # reads the block but validation and the preregistration.
  with_plan <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  without <- with_plan
  without$predictions[[2]]$test <- NULL
  for (i in seq_along(with_plan$predictions)) {
    with_plan$predictions[[i]]$test <- list(n_planned = 10000, alpha = 0.001, power = 0.99)
  }
  expect_identical(tf_check(with_plan), tf_check(without))
  expect_identical(tf_severity(with_plan), tf_severity(without))
  expect_identical(tf_post_data_severity(with_plan), tf_post_data_severity(without))
  expect_identical(tf_report(with_plan), tf_report(without))
})
