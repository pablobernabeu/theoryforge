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
    evidence = list(list(supports = "h1", direction = "corroborates"))
  )
}

# The message tf_validate(full = TRUE) stops with for `t`.
full_error <- function(t) {
  tryCatch({
    tf_validate(t, full = TRUE)
    NA_character_
  }, error = conditionMessage)
}

vp_item <- function(report, iid) {
  Filter(function(it) identical(it$id, iid), report$items)[[1L]]
}

test_that("tf_validate(full = TRUE) accepts a consistent theory and the fixtures", {
  expect_true(tf_validate(consistent_theory(), full = TRUE))
  expect_true(tf_validate(tf_read(tf_fixture_path("panic-network.theory.yaml")), full = TRUE))
  expect_true(tf_validate(tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml")), full = TRUE))
  expect_true(tf_validate(tf_read(tf_fixture_path("modality-switching.theory.yaml")), full = TRUE))
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

test_that("an unknown top-level field is refused", {
  # A misspelt collection key drops the collection silently; the whole point is
  # that this is caught rather than scored.
  t <- consistent_theory()
  names(t)[names(t) == "predictions"] <- "predicitions"
  err <- tryCatch(tf_validate(t), error = function(e) conditionMessage(e))
  expect_true(grepl("unknown top-level field: predicitions", err, fixed = TRUE))
})

test_that("known top-level fields are accepted", {
  expect_true(tf_validate(consistent_theory()))
})

test_that("tf_read and tf_read_corpus reject non-mapping input", {
  p <- tempfile(fileext = ".yaml"); writeLines(c("- a", "- b"), p)
  expect_error(tf_read(p), "Theory data must be a mapping")
  cpath <- tempfile(fileext = ".yaml"); writeLines(c("- 1", "- 2"), cpath)
  expect_error(tf_read_corpus(cpath), "Corpus data must be a mapping")
})

test_that("tf_read and tf_read_corpus reject a sequence of mappings", {
  # A sequence of mappings, unlike a sequence of scalars, parses to a plain
  # list here too, so this is the form that slipped past the guard.
  p <- tempfile(fileext = ".yaml"); writeLines(c("- {a: 1}", "- {b: 2}"), p)
  expect_error(tf_read(p), "Theory data must be a mapping")
  cpath <- tempfile(fileext = ".yaml"); writeLines(c("- {a: 1}", "- {b: 2}"), cpath)
  expect_error(tf_read_corpus(cpath), "Corpus data must be a mapping")
})

test_that("a string severity is refused by full validation and by scoring", {
  # The schema types severity as a number in [0, 1]. A YAML string severity
  # previously passed tf_validate(full = TRUE) in both engines and then
  # crashed Python's check() while R silently coerced and scored; the Python
  # suite runs the same file and asserts the same two messages.
  p <- tempfile(fileext = ".yaml")
  writeLines(c(
    'schema_version: "1.0"',
    "id: t",
    "title: T",
    "maturity: building",
    "predictions:",
    "  - id: h1",
    "    statement: s",
    "    type: directional",
    '    severity: "0.8"'
  ), p)
  theory <- tf_read(p)
  expect_true(tf_validate(theory))  # the structural pass alone does not reach severity
  expect_error(tf_validate(theory, full = TRUE),
               "prediction[0] severity must be a number between 0 and 1",
               fixed = TRUE)
  expect_error(
    tf_check(theory),
    "check requires numeric prediction severities; non-numeric severity for prediction: h1",
    fixed = TRUE
  )
})

test_that("an out-of-range severity fails full validation", {
  t <- consistent_theory()
  t$predictions[[1]]$severity <- 1.5
  expect_error(tf_validate(t, full = TRUE),
               "prediction[0] severity must be a number between 0 and 1",
               fixed = TRUE)
  t$predictions[[1]]$severity <- 0.8
  expect_true(tf_validate(t, full = TRUE))
})

test_that("tf_osf_push base_url override is honoured", {
  res <- tf_osf_push(tf_theory("t", "T"), node = "abc12",
                     base_url = "https://example.org/v1/resources/")
  expect_true(startsWith(res$request$url, "https://example.org/v1/resources/abc12/"))
})

test_that("a mistyped enum value is refused, identically to the Python twin", {
  # A YAML sequence or mapping where the schema wants a scalar enum. `%in%`
  # coerces, so a one-element list once matched the enum here while Python
  # raised an unhashable-type TypeError. Both engines now give these messages,
  # which name the wrong type where 0.6.0 called the field missing.
  expected_maturity <- paste(
    "invalid theory object: maturity must be a string;",
    "maturity must be one of building, developing, draft, testing"
  )
  for (value in list(list("draft", "building"), list("draft"), list(stage = "draft"))) {
    bad <- list(schema_version = "1.0", id = "x", title = "T", maturity = value)
    expect_error(tf_validate(bad), expected_maturity, fixed = TRUE)
  }
  bad <- list(schema_version = "1.0", id = "x", title = "T", maturity = 1)
  expect_error(tf_validate(bad), paste(
    "invalid theory object: maturity must be a string (quote the value in YAML);",
    "maturity must be one of building, developing, draft, testing"
  ), fixed = TRUE)

  # theory_form is the case R was lenient about: the one-element list passed.
  bad_form <- list(schema_version = "1.0", id = "x", title = "T",
                   maturity = "draft", theory_form = list("network"))
  expect_error(
    tf_validate(bad_form),
    "invalid theory object: theory_form must be one of network, process, typology, variance",
    fixed = TRUE
  )
})

test_that("a collection entry that is not a mapping is refused", {
  # `constructs: [arousal, threat]` is a natural mistake: a sequence of scalars
  # where the schema wants a sequence of mappings. Each entry has no fields, so
  # every required one is reported missing, as in the Python twin.
  bad <- list(schema_version = "1.0", id = "x", title = "T", maturity = "draft",
              constructs = list("arousal", "threat"))
  expect_error(
    tf_validate(bad, full = TRUE),
    paste(
      "invalid theory object: construct[0] missing/empty id;",
      "construct[0] missing/empty label; construct[0] missing/empty definition;",
      "construct[1] missing/empty id; construct[1] missing/empty label;",
      "construct[1] missing/empty definition"
    ),
    fixed = TRUE
  )
})

# -- the whole schema (API_SPEC.md section 2) ----------------------------------
# The Python suite (test_validation_parity.py) builds the same theories and
# asserts the same messages, and the edge phase of scripts/parity_check.py
# compares the two engines on the files in fixtures/edge/.

vp_read <- function(text) {
  path <- tempfile(fileext = ".yaml")
  on.exit(unlink(path))
  writeBin(charToRaw(enc2utf8(text)), path)
  tf_read(path)
}

test_that("a present required value that is not a string is named", {
  # A field holding a number or a logical is present, so calling it missing
  # sent readers looking for a typo. YAML reads an unquoted 1.0, 2026 or Yes as
  # a number or a logical, so the message says how to keep it a string.
  bad <- list(
    schema_version = 1.0, id = 2026, title = "  ", maturity = "building",
    constructs = list(list(id = "c1", label = TRUE, definition = NULL)),
    propositions = list(list(id = "p1", from = "c1", to = "c1",
                             relation = list("increases"))),
    predictions = list(list(id = 7, statement = "s", type = list(form = "point")))
  )
  expect_identical(tryCatch(tf_validate(bad), error = conditionMessage), paste(
    "invalid theory object:",
    "schema_version must be a string (quote the value in YAML);",
    "id must be a string (quote the value in YAML);",
    "missing/empty required field: title;",
    "construct[0] label must be a string (quote the value in YAML);",
    "construct[0] missing/empty definition;",
    "proposition[0] relation must be a string;",
    "prediction[0] id must be a string (quote the value in YAML);",
    "prediction[0] type must be a string"
  ))
})

test_that("a collection that is not a list is named", {
  # A scalar or a non-empty mapping where a collection belongs reads as an
  # empty collection (API_SPEC.md section 3), so validation says so. An empty
  # mapping loses nothing, and list() stands for both kinds of empty value.
  bad <- list(
    schema_version = "1.0", id = "x", title = "T", maturity = "building",
    constructs = "arousal",
    predictions = list(h1 = list(id = "h1", statement = "s", type = "point")),
    evidence = 5, provenance = TRUE, alternatives = setNames(list(), character(0)),
    test_outcomes = list(), propositions = NULL, extra = 1
  )
  expect_identical(tryCatch(tf_validate(bad), error = conditionMessage), paste(
    "invalid theory object: unknown top-level field: extra;",
    "constructs must be a list; predictions must be a list;",
    "evidence must be a list; provenance must be a list"
  ))
})

test_that("full validation checks the required fields of every collection", {
  t <- consistent_theory()
  t$auxiliary_assumptions <- list(list(id = "x1"), list(id = 3, statement = "s"))
  t$alternatives <- list(list(id = "a1"))
  t$evidence <- list(list(supports = "h1", direction = "supports"), list(supports = "h1"),
                     list(direction = "refutes"))
  t$test_outcomes <- list(list(prediction_id = "h1", passed = "true"),
                          list(prediction_id = "h1"), list(passed = TRUE))
  expect_true(tf_validate(t))  # the structural pass does not read these collections
  expect_identical(full_error(t), paste(
    "invalid theory object:",
    "assumption[0] missing/empty statement;",
    "assumption[1] id must be a string (quote the value in YAML);",
    "alternative[0] missing/empty label;",
    "evidence[0] direction 'supports' not allowed;",
    "evidence[1] missing/empty direction;",
    "evidence[2] missing/empty supports;",
    "test_outcome[0] passed must be true or false;",
    "test_outcome[1] passed must be true or false;",
    "test_outcome[2] missing/empty prediction_id"
  ))
})

test_that("full validation checks the typed optional fields", {
  t <- consistent_theory()
  t$auxiliary_assumptions <- list(list(id = "x1", statement = "s", added_for = 5),
                                  list(id = "x2", statement = "s", added_for = NULL))
  t$test_outcomes <- list(
    list(prediction_id = "h1", passed = TRUE, severity_at_test = 1.5, registered = 2026L,
         date = list("2026-05-01")),
    list(prediction_id = "h1", passed = FALSE, severity_at_test = TRUE),
    list(prediction_id = "h1", passed = FALSE, severity_at_test = NULL, registered = NULL,
         date = "2026-05-01")
  )
  expect_identical(full_error(t), paste(
    "invalid theory object:",
    "assumption[0] added_for must be a string or null;",
    "test_outcome[0] severity_at_test must be a number between 0 and 1;",
    "test_outcome[0] registered must be a string or null;",
    "test_outcome[0] date must be a string or null;",
    "test_outcome[1] severity_at_test must be a number between 0 and 1"
  ))
})

test_that("full validation checks every entry of the referencing arrays", {
  # An entry that is not a nonempty string reads as no entry at all (API_SPEC.md
  # section 4), so validation reports it in its place among the reference
  # messages. A single string is a one-element array, and any other value that
  # is not a list cannot be read as one.
  t <- consistent_theory()
  t$predictions <- list(
    list(id = "h1", statement = "s", type = "point",
         derives_from = list("pZ", NULL, "", 5, "p1"), diagnostic_vs = list("a1", list("x"))),
    list(id = "h2", statement = "s", type = "point", derives_from = "p1", diagnostic_vs = 5),
    list(id = "h3", statement = "s", type = "point", derives_from = "  ")
  )
  t$auxiliary_assumptions <- list(
    list(id = "x1", statement = "s", protects = list(NULL, "h1", "hZ")),
    list(id = "x2", statement = "s", protects = list(h1 = TRUE))
  )
  expect_identical(full_error(t), paste(
    "invalid theory object:",
    "prediction[0] derives_from 'pZ' is not a known proposition;",
    "prediction[0] derives_from entry 1 must be a nonempty string;",
    "prediction[0] derives_from entry 2 must be a nonempty string;",
    "prediction[0] derives_from entry 3 must be a nonempty string;",
    "prediction[0] diagnostic_vs entry 1 must be a nonempty string;",
    "prediction[1] diagnostic_vs must be a list;",
    "prediction[2] derives_from must be a list;",
    "assumption[0] protects entry 0 must be a nonempty string;",
    "assumption[0] protects 'hZ' is not a known prediction;",
    "assumption[1] protects must be a list"
  ))
})

# Run each case of a field's table. `t[[field]]` is set to `value`, a NULL kept
# as a present null, and must pass the structural pass. The full pass must then
# accept it (expected NA) or stop with exactly the expected message.
vp_cases <- function(field, cases) {
  for (case in cases) {
    t <- consistent_theory()
    t[field] <- list(case$value)
    label <- paste(deparse(case$value), collapse = "")
    expect_true(tf_validate(t), info = label)
    if (is.na(case$expected)) {
      expect_true(tf_validate(t, full = TRUE), info = label)
    } else {
      expect_identical(full_error(t), paste0("invalid theory object: ", case$expected),
                       info = label)
    }
  }
}

test_that("full validation checks the formal model", {
  vp_cases("formal_model", list(
    list(value = list(type = "ode", spec_ref = "models/panic.ode"), expected = NA),
    list(value = list(type = "none", spec_ref = NULL), expected = NA),
    list(value = list(type = NULL), expected = NA),
    list(value = setNames(list(), character(0)), expected = NA),
    list(value = list(), expected = NA),
    list(value = NULL, expected = NA),
    list(value = "ode", expected = "formal_model must be a mapping"),
    list(value = list("ode"), expected = "formal_model must be a mapping"),
    list(value = list(type = "banana"), expected = "formal_model type 'banana' not allowed"),
    list(value = list(type = "TBD"), expected = "formal_model type 'TBD' not allowed"),
    list(value = list(type = ""), expected = "formal_model type '' not allowed"),
    list(value = list(type = list("none")), expected = "formal_model type must be a string"),
    list(value = list(type = 3),
         expected = "formal_model type must be a string (quote the value in YAML)"),
    list(value = list(type = "sem", spec_ref = 5),
         expected = "formal_model spec_ref must be a string or null")
  ))
})

test_that("full validation checks the version block", {
  vp_cases("version", list(
    list(value = list(id = "v1", parent_id = NULL, content_hash = NULL), expected = NA),
    list(value = list(id = "v2", parent_id = "v1", content_hash = "sha256:00"), expected = NA),
    list(value = setNames(list(), character(0)), expected = NA),
    list(value = list(), expected = NA),
    list(value = NULL, expected = NA),
    list(value = "v1", expected = "version must be a mapping"),
    list(value = list(list(id = "v1")), expected = "version must be a mapping"),
    list(value = list(id = "v1", author = "x", date = "2026"),
         expected = "version has unknown field: author; version has unknown field: date"),
    list(value = list(id = 2, parent_id = 1, content_hash = list("x")), expected = paste(
      "version id must be a string (quote the value in YAML);",
      "version parent_id must be a string or null;",
      "version content_hash must be a string or null"))
  ))
})

test_that("full validation checks the schema_version pattern", {
  pattern_msg <- 'schema_version must match major.minor (for example "1.0")'
  cases <- c(lapply(c("1.0", "10.25"), function(v) list(value = v, expected = NA)),
             lapply(c("one", "1", "1.0.0", "v1.0", " 1.0", "1.0\n"),
                    function(v) list(value = v, expected = pattern_msg)))
  # The structural pass asks only for a nonempty string, which vp_cases checks.
  vp_cases("schema_version", cases)
})

test_that("full validation checks the remaining typed fields", {
  # The schema's other types, so that a theory the schema refuses is refused
  # here too (the Python suite's test_schema_agreement.py checks this with a
  # JSON Schema validator).
  t <- consistent_theory()
  t$constructs <- list(
    list(id = "c1", label = "C1", definition = "d", measurement = list("m1", 5),
         boundary_conditions = list(list("adults"))),
    list(id = "c2", label = "C2", definition = "d", measurement = list(m = "x"))
  )
  t$propositions[[1]]$mechanism <- 5
  t$propositions[[1]]$functional_form <- TRUE
  t$boundary_conditions <- list("adults", NULL)
  t$predictions[[1]]$risk_score <- 2
  t$evidence[[1]]$source_doi <- 5
  t$test_outcomes[[1]]$observed <- 0.42
  t$alternatives[[1]]$key_constructs <- list(3)
  t$alternatives[[1]]$source_doi <- list("10.1/x")
  t$provenance <- list(list(step = 1, action = "tf_theory", detail = "t"), "tf_add_construct",
                       list(), list(1), NULL)
  expect_true(tf_validate(t))
  expect_identical(full_error(t), paste(
    "invalid theory object:",
    "construct[0] measurement entry 1 must be a nonempty string;",
    "construct[0] boundary_conditions entry 0 must be a nonempty string;",
    "construct[1] measurement must be a list;",
    "proposition[0] mechanism must be a string (quote the value in YAML);",
    "proposition[0] functional_form must be a string (quote the value in YAML);",
    "boundary_conditions entry 1 must be a nonempty string;",
    "prediction[0] risk_score must be a number between 0 and 1;",
    "evidence[0] source_doi must be a string or null;",
    "test_outcome[0] observed must be a string (quote the value in YAML);",
    "alternative[0] key_constructs entry 0 must be a nonempty string;",
    "alternative[0] source_doi must be a string or null;",
    "provenance[0] step must be a string (quote the value in YAML);",
    "provenance[1] must be a mapping;",
    "provenance[3] must be a mapping;",
    "provenance[4] must be a mapping"
  ))
})

test_that("an integer too large for a double is reported, as in Python", {
  # An unquoted integer of 400 digits. R's reader holds it as Inf, and the
  # Python twin's as an int, which its full pass used to crash on.
  huge <- paste0("1", strrep("0", 400))
  t <- vp_read(paste0('schema_version: "1.0"
id: t
title: T
maturity: testing
predictions:
  - id: h1
    statement: s
    type: point
    severity: ', huge, '
    risk_score: -', huge, '
test_outcomes:
  - prediction_id: h1
    passed: true
    severity_at_test: ', huge, '
    observed: ', huge, '
'))
  expect_identical(full_error(t), paste(
    "invalid theory object:",
    "prediction[0] severity must be a number between 0 and 1;",
    "test_outcome[0] severity_at_test must be a number between 0 and 1;",
    "prediction[0] risk_score must be a number between 0 and 1;",
    "test_outcome[0] observed must be a string (quote the value in YAML)"
  ))
})

test_that("a missing value written as NA reads as null", {
  # tf_write() writes NA as null, so validation reads it as absent: a required
  # field is missing, and an optional one is not reported.
  t <- consistent_theory()
  t$title <- NA
  t$auxiliary_assumptions[[1]]$added_for <- NA_character_
  t$test_outcomes[[1]]$severity_at_test <- NA_real_
  expect_identical(full_error(t), "invalid theory object: missing/empty required field: title")
})

vp_passed_string <- 'schema_version: "1.0"
id: t
title: T
maturity: testing
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct.
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
    derives_from: [p1]
auxiliary_assumptions:
  - id: x1
    statement: The effect needs a calm setting.
    added_for: h1
    protects: [h1]
test_outcomes:
  - prediction_id: h1
    passed: "true"
'

test_that("tf_check() refuses a test outcome whose passed is not a logical", {
  # A quoted "true" read as a failure, so the assumption added for h1 counted as
  # ad hoc and parsimony failed, in both engines alike.
  t <- vp_read(vp_passed_string)
  expect_error(tf_check(t), paste(
    "check requires boolean test outcomes;",
    "non-boolean passed for test outcome of prediction: h1"
  ), fixed = TRUE)
  expect_true(grepl("test_outcome[0] passed must be true or false", full_error(t), fixed = TRUE))
  # The refusal comes before any item is scored, the severity refusal included.
  t$predictions[[1]]$severity <- "0.8"
  expect_error(tf_check(t), "^check requires boolean test outcomes; ")
  t$predictions[[1]]$severity <- NULL
  # Only a prediction other than h1, the anomaly x1 answers, can support x1, so
  # a second prediction carries the outcome from here on.
  t$predictions[[2]] <- list(id = "h2", statement = "Beta lags Alpha by a day.",
                             type = "directional", derives_from = list("p1"))
  t$auxiliary_assumptions[[1]]$protects <- list("h1", "h2")
  t$test_outcomes <- list(list(prediction_id = "h2", passed = TRUE))
  expect_identical(vp_item(tf_check(t), "parsimony")$status, "pass")
  # A missing or null passed still reads as not passed, and so does NA.
  for (outcome in list(list(prediction_id = "h2"), list(prediction_id = "h2", passed = NULL),
                       list(prediction_id = "h2", passed = NA))) {
    t$test_outcomes <- list(outcome)
    expect_identical(vp_item(tf_check(t), "parsimony")$status, "fail")
  }
})

test_that("tf_appraise_amendment() refuses a non-logical passed in either theory", {
  prior <- consistent_theory()
  new <- consistent_theory()
  new$predictions[[2L]] <- list(id = "h2", statement = "s", type = "point",
                                derives_from = list("p1"))
  new$test_outcomes <- list(list(prediction_id = "h2", passed = "yes"))
  prior$test_outcomes <- list(list(prediction_id = "h1", passed = 1))
  msg <- paste("appraise_amendment requires boolean test outcomes;",
               "non-boolean passed for test outcome of prediction:")
  # The amendment is checked first.
  expect_identical(tryCatch(tf_appraise_amendment(new, prior), error = conditionMessage),
                   paste(msg, "h2"))
  new$test_outcomes <- list(list(prediction_id = "h2", passed = TRUE))
  expect_identical(tryCatch(tf_appraise_amendment(new, prior), error = conditionMessage),
                   paste(msg, "h1"))
  prior$test_outcomes <- list(list(prediction_id = "h1"))
  # The logical pass now counts. h2 derives from p1 alone, which the prior
  # already held, so it articulates old content and the amendment is neutral.
  ap <- tf_appraise_amendment(new, prior)
  expect_identical(ap$corroborated_new, "h2")
  expect_identical(ap$articulated, "h2")
  expect_identical(ap$verdict, "neutral")
})
