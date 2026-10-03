# Malformed theories read the same way in every consumer (API_SPEC.md section 3,
# "Reading a theory"). Each theory is written to a file and read back, so the
# reader's handling of the document is part of what is tested. The Python suite
# (test_lenient_readers.py) reads the same documents and asserts the same values.

lr_read <- function(text) {
  path <- tempfile(fileext = ".yaml")
  writeBin(charToRaw(enc2utf8(text)), path)
  on.exit(unlink(path))
  tf_read(path)
}

lr_item <- function(report, iid) {
  Filter(function(it) identical(it$id, iid), report$items)[[1L]]
}

lr_head <- 'schema_version: "1.0"
id: t
title: T
maturity: building
'

lr_two_constructs <- 'constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct entirely different.
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
    mechanism: Alpha drives Beta.
'

lr_scalar_entries <- paste0(lr_head, 'constructs: [arousal, threat]
propositions:
  - id: p1
    from: arousal
    to: threat
    relation: associates
    mechanism: Arousal goes with perceived threat.
predictions: [h1]
auxiliary_assumptions: [a1]
test_outcomes: [h1]
alternatives: [rival]
evidence: [e1]
provenance: [tf_theory]
')

lr_corpus <- list(schema_version = "1.0", id = "c", records = list(
  list(id = "w1", keywords = list("arousal", "threat")),
  list(id = "w2", keywords = list("arousal", "threat"))
))

test_that("every consumer reads entries that are not mappings", {
  t <- lr_read(lr_scalar_entries)
  rep <- tf_check(t)
  expect_identical(rep$gate, "blocked")
  expect_identical(lr_item(rep, "falsifiability")$status, "fail")
  expect_identical(lr_item(rep, "derivation_chain")$score, 0.0)
  expect_identical(tf_severity(t), data.frame(prediction_id = "", type = "", risk_score = 0.0,
                                              computed_severity = 0.0,
                                              stringsAsFactors = FALSE))
  expect_true(grepl("1. []  (derives from: —)", tf_preregister(t), fixed = TRUE))
  expect_true(startsWith(tf_dossier(t), "# theoryforge dossier: T\n"))
  expect_true(endsWith(tf_compile_sem(t), "# Structural model\narousal ~~ threat\n"))
  expect_identical(tf_implications(t)$n_implications, 0L)
  sim <- tf_simulate(t, steps = 2)
  expect_identical(sim$states, list("", ""))
  expect_length(sim$trajectory, 3L)
  for (kind in c("nomological_net", "provenance", "causal_dag", "development_roadmap",
                 "pipeline", "context", "workflow", "venn", "rigour", "severity")) {
    expect_true(endsWith(tf_diagram(t, kind), "\n"), info = kind)
  }
  expect_true(grepl('"result_"', tf_diagram(t, "pipeline"), fixed = TRUE))
  red <- tf_redundancy_check(t)
  expect_identical(red$a, "")
  expect_identical(red$similarity, 0.0)
  expect_identical(one_theme(tf_landscape(t, lr_corpus))$theory_id, "t")
  expect_identical(tf_new_evidence_dois(t, "10.1/x"), "10.1/x")
  expect_identical(tf_osf_push(t)$request$filename, "t.dossier.md")
  qmd <- tf_render_report(t, tempfile(fileext = ".qmd"))
  expect_true(file.exists(qmd))
  unlink(qmd)
  prior <- lr_read(paste0(lr_head, lr_two_constructs))
  # The scalar prediction has no fields, so nothing derives it.
  expect_identical(tf_appraise_amendment(t, prior), list(
    verdict = "neutral", new_predictions = "", corroborated_new = character(0),
    ad_hoc_assumptions = character(0), articulated = character(0), underived = "",
    corroborated_new_registered = character(0), renamed = list(), dropped = character(0),
    dropped_corroborated = character(0), content_lost = character(0),
    new_anomalies = character(0), assumptions = list()))
})

test_that("full validation reports scalar entries instead of stopping", {
  # tf_validate(full = TRUE) stopped with "subscript out of bounds" and lost
  # every message it had collected.
  t <- lr_read(lr_scalar_entries)
  msg <- tryCatch(tf_validate(t, full = TRUE), error = conditionMessage)
  expect_true(startsWith(msg, "invalid theory object: construct[0] missing/empty id"))
  expect_true(grepl("prediction[0] missing/empty id", msg, fixed = TRUE))
})

test_that("constructs without ids are not duplicates", {
  t <- lr_read(paste0(lr_head, "constructs: [arousal, threat]\n"))
  expect_identical(tf_implications(t)$constructs, list())
  expect_identical(tf_simulate(t, steps = 1)$states, list("", ""))
  dup <- lr_read(paste0(lr_head, "constructs:\n  - id: c1\n  - id: c1\n"))
  expect_error(tf_simulate(dup), "duplicate construct id: c1", fixed = TRUE)
})

test_that("a collection written as a mapping reads as empty", {
  t <- lr_read(paste0(lr_head, lr_two_constructs, 'predictions:
  h1:
    id: h1
    statement: Beta rises with Alpha.
    type: point
    derives_from: [p1]
'))
  rep <- tf_check(t)
  # No predictions: nothing is falsifiable, and there is no derivation to
  # check. R used to iterate the mapping's values and pass the gate.
  expect_identical(lr_item(rep, "falsifiability")$status, "fail")
  expect_identical(lr_item(rep, "derivation_chain")$status, "n/a")
  expect_identical(rep$gate, "blocked")
  expect_identical(nrow(tf_severity(t)), 0L)
})

test_that("a named list built in memory reads as empty", {
  t <- tf_theory("t", "T") |>
    tf_add_prediction("h1", "Beta rises.", "point")
  t$predictions <- list(h1 = t$predictions[[1L]])
  expect_identical(lr_item(tf_check(t), "falsifiability")$status, "fail")
  expect_identical(nrow(tf_severity(t)), 0L)
})

test_that("a collection written as a single string reads as empty", {
  t <- lr_read(paste0(lr_head, lr_two_constructs, "predictions: h1\n"))
  rep <- tf_check(t)
  expect_identical(lr_item(rep, "falsifiability")$status, "fail")
  expect_identical(lr_item(rep, "derivation_chain")$status, "n/a")
  expect_identical(nrow(tf_severity(t)), 0L)
})

lr_seq_relation <- paste0(lr_head, 'constructs:
  - id: a
    label: Alpha
    definition: The first construct.
  - id: b
    label: Beta
    definition: The second construct entirely different.
  - id: c
    label: Gamma
    definition: A third construct with its own meaning.
propositions:
  - id: p1
    from: a
    to: b
    relation: [increases]
  - id: p2
    from: b
    to: c
    relation: increases
predictions:
  - id: h1
    statement: Gamma rises with Alpha.
    type: [point]
    derives_from: [p1, p2]
')

test_that("an enum written as a sequence reads as absent everywhere", {
  t <- lr_read(lr_seq_relation)
  rep <- tf_check(t)
  expect_identical(lr_item(rep, "falsifiability")$status, "fail")
  expect_identical(lr_item(rep, "precision")$score, 0.0)
  expect_identical(tf_severity(t)$type, "")
  expect_identical(tf_severity(t)$risk_score, 0.0)
  impl <- tf_implications(t)
  expect_identical(impl$constructs, list("b", "c"))
  expect_identical(impl$n_edges, 1L)
  sem <- tf_compile_sem(t)
  expect_false(grepl("b ~ a", sem, fixed = TRUE))
  expect_true(grepl("c ~ b", sem, fixed = TRUE))
  expect_false(grepl("a -> b", tf_diagram(t, "causal_dag"), fixed = TRUE))
  expect_true(grepl('"a" -> "b" [label=""];', tf_diagram(t, "nomological_net"), fixed = TRUE))
  expect_true(grepl('"pred_h1" [label="h1\\n"', tf_diagram(t, "workflow"), fixed = TRUE))
  expect_true(grepl("1. [] Gamma rises with Alpha.", tf_preregister(t), fixed = TRUE))
  # Alpha has no coupling to Beta, so Beta decays exactly as Alpha does.
  traj <- tf_simulate(t, steps = 3)$trajectory
  for (row in traj) expect_identical(row[[1L]], row[[2L]])
})

test_that("maturity and formal model type as sequences read as absent", {
  text <- paste0(sub("maturity: building", "maturity: [draft]", lr_head, fixed = TRUE),
                 lr_two_constructs, "formal_model:\n  type: [ode]\n")
  rep <- tf_check(lr_read(text))
  expect_identical(rep$maturity, "")
  expect_false(identical(rep$gate, "advisory"))
  expect_identical(lr_item(rep, "formalisation")$status, "warn")
})

test_that("a formal model type outside its enum does not formalise", {
  for (value in c('""', "bayesian", "none")) {
    text <- paste0(lr_head, lr_two_constructs, "formal_model:\n  type: ", value, "\n")
    expect_identical(lr_item(tf_check(lr_read(text)), "formalisation")$status, "warn",
                     info = value)
  }
  text <- paste0(lr_head, lr_two_constructs, "formal_model:\n  type: sem\n")
  expect_identical(lr_item(tf_check(lr_read(text)), "formalisation")$status, "pass")
})

lr_null_derives <- paste0(lr_head, lr_two_constructs, 'predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [~]
  - id: h2
    statement: Beta is above zero.
    type: interval
    derives_from:
      -
  - id: h3
    statement: Beta is exactly one.
    type: point
    derives_from: [p1, ~]
')

test_that("null entries of a string array are ignored", {
  t <- lr_read(lr_null_derives)
  # Full validation reports each entry the readers ignore (API_SPEC.md section 2,
  # item 10), and every other function reads the theory without them.
  expect_identical(tryCatch(tf_validate(t, full = TRUE), error = conditionMessage), paste(
    "invalid theory object: prediction[0] derives_from entry 0 must be a nonempty string;",
    "prediction[1] derives_from entry 0 must be a nonempty string;",
    "prediction[2] derives_from entry 1 must be a nonempty string"
  ))
  deriv <- lr_item(tf_check(t), "derivation_chain")
  # R passed all three predictions, and its preregistration then said the
  # chain was verified beside "(derives from: -)".
  expect_identical(deriv$status, "fail")
  expect_identical(deriv$score, 0.333)
  text <- tf_preregister(t)
  expect_true(grepl("1. [directional] Beta rises with Alpha. (derives from: —)", text,
                    fixed = TRUE))
  expect_true(grepl("3. [point] Beta is exactly one. (derives from: p1)", text, fixed = TRUE))
  expect_true(grepl("Derivation chain verified: no", text, fixed = TRUE))
})

test_that("a single valid entry beside a null passes the derivation check", {
  t <- lr_read(paste0(lr_head, lr_two_constructs, 'predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1, ~]
'))
  expect_identical(lr_item(tf_check(t), "derivation_chain")$status, "pass")
})

test_that("an empty or blank string-array entry does not count", {
  # The one change for a theory that matches the schema, which allows "". Full
  # validation reports such an entry as it reports a null one.
  t <- lr_read(paste0(lr_head, 'constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
    measurement: [""]
    boundary_conditions: [adults]
  - id: c2
    label: Beta
    definition: The second construct entirely different.
    measurement: [m2]
    boundary_conditions: ["  "]
'))
  expect_identical(tryCatch(tf_validate(t, full = TRUE), error = conditionMessage), paste(
    "invalid theory object: construct[0] measurement entry 0 must be a nonempty string;",
    "construct[1] boundary_conditions entry 0 must be a nonempty string"
  ))
  rep <- tf_check(t)
  expect_identical(lr_item(rep, "construct_clarity")$score, 0.0)
  expect_identical(lr_item(rep, "scope")$status, "warn")
  expect_true(startsWith(tf_compile_sem(t), paste0(
    "# lavaan model generated by theoryforge for t\n",
    "# Measurement model\nc2 =~ m2\n")))
})

test_that("null text fields print as empty strings", {
  t <- lr_read(paste0(sub("title: T", "title: ~", lr_head, fixed = TRUE), lr_two_constructs,
                      'predictions:
  - id: h1
    statement: ~
    type: ~
    derives_from: [p1]
'))
  prereg <- tf_preregister(t)
  expect_true(startsWith(prereg, "# Preregistration: \n"))
  expect_true(grepl("1. []  (derives from: p1)", prereg, fixed = TRUE))
  expect_identical(tf_severity(t)$type, "")
})

lr_idless <- paste0(lr_head, lr_two_constructs, 'predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1]
auxiliary_assumptions:
  - statement: The measure of Beta lags by a week.
    added_for: h1 failed at the first test
    protects: [h1]
test_outcomes:
  - passed: false
')

test_that("entries without ids read as empty ids", {
  t <- lr_read(lr_idless)
  expect_true(grepl('"result_" [label="failed"', tf_diagram(t, "pipeline"), fixed = TRUE))
  expect_identical(lr_item(tf_check(t), "parsimony")$status, "fail")
  prior <- lr_read(paste0(lr_head, lr_two_constructs))
  # h1 needs the new assumption, so it is not an articulation of p1.
  expect_identical(tf_appraise_amendment(t, prior), list(
    verdict = "degenerating", new_predictions = "h1", corroborated_new = character(0),
    ad_hoc_assumptions = "", articulated = character(0), underived = character(0),
    corroborated_new_registered = character(0), renamed = list(), dropped = character(0),
    dropped_corroborated = character(0), content_lost = character(0),
    new_anomalies = character(0),
    assumptions = list(list(id = "", added_for = "h1 failed at the first test", class = "ad_hoc2",
                            independent = list(list(id = "h1", status = "untested"))))))
  two_new <- sub("auxiliary_assumptions:", "  - statement: A prediction without an id.
    type: directional
auxiliary_assumptions:", lr_idless, fixed = TRUE)
  expect_identical(tf_appraise_amendment(lr_read(two_new), prior)$new_predictions, c("", "h1"))
})

test_that("nested boundary conditions read as empty", {
  t <- lr_read(paste0(lr_head, 'constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
    measurement: [m1]
    boundary_conditions: [[adults]]
  - id: c2
    label: Beta
    definition: The second construct entirely different.
    measurement: [m2]
    boundary_conditions: [adults]
'))
  venn <- tf_diagram(t, "venn")
  expect_true(grepl('<text x="110" y="155" text-anchor="middle" font-weight="bold">0</text>',
                    venn, fixed = TRUE))
  expect_identical(lr_item(tf_check(t), "construct_clarity")$score, 0.5)
  expect_identical(lr_item(tf_check(t), "scope")$status, "warn")
})

lr_numeric <- 'schema_version: 1.0
id: 2026
title: Numbers where strings belong
maturity: building
constructs:
  - id: c1
    label: Yes
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct entirely different.
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
predictions:
  - id: 7
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1]
'

test_that("numbers and logicals in text fields read as empty strings", {
  t <- lr_read(lr_numeric)
  rep <- tf_check(t)
  expect_identical(rep$theory_id, "")
  expect_identical(rep$schema_version, "")
  expect_true(grepl("- Theory ID: \n- Schema version: \n", tf_preregister(t), fixed = TRUE))
  expect_identical(tf_severity(t)$prediction_id, "")
  expect_true(grepl('"c1" [label="", ', tf_diagram(t, "nomological_net"), fixed = TRUE))
  expect_identical(tf_osf_push(t)$request$filename, "theory.dossier.md")
})

test_that("the accessors follow the contract", {
  expect_identical(.tf_text("abc"), "abc")
  expect_identical(.tf_text("  "), "  ")
  expect_identical(.tf_text(list("a", "b")), "a")
  expect_identical(.tf_text(c("a", "b")), "a")
  for (v in list(list(), list(NULL, "a"), list(list("a")), NULL, 2026L, 1.0, TRUE,
                 NA_character_, list(a = "b"))) {
    expect_identical(.tf_text(v), "")
  }
  expect_identical(.tf_str_list(list("p1", NULL, "", "  ", 3, list("p2"), "p3")),
                   c("p1", "p3"))
  expect_identical(.tf_str_list("p1"), "p1")
  expect_identical(.tf_str_list(c("p1", "", "p2")), c("p1", "p2"))
  for (v in list("  ", NULL, 5, list(a = "p1"), NA_character_)) {
    expect_identical(.tf_str_list(v), character(0))
  }
  expect_identical(.tf_list(list(k = list(1, "a")), "k"), list(1, "a"))
  for (v in list("a", list(h1 = list()), NULL, 3)) {
    expect_identical(.tf_list(list(k = v), "k"), list())
  }
  expect_identical(.tf_list("not a mapping", "k"), list())
  expect_identical(.tf_enum("point", .tf_PRED_TYPE), "point")
  for (v in list(list("point"), "Point", "", NULL, 1)) {
    expect_null(.tf_enum(v, .tf_PRED_TYPE))
  }
})
