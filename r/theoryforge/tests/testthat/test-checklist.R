# The rigour checklist (API_SPEC.md section 4).
#
# An item with nothing to assess is "n/a", with a NULL score, and is left out of
# the aggregate, which is the weighted mean of the applicable items. The report
# gives `coverage`, the share of checklist weight that was applicable, and
# `aggregate_range`, the aggregate under other weightings. Parsimony fails an
# assumption that answers an anomaly without independent corroboration,
# non-redundancy follows the redundancy screen's flags, precision counts bounded
# point and interval claims and mean severity counts every prediction, using the
# claim-form rubric where none is declared. The Python suite
# (test_checklist.py) builds the same theories and asserts the same values.

ck_ids <- c("falsifiability", "precision", "risk_severity", "parsimony", "non_redundancy",
            "construct_clarity", "scope", "logical_why", "causal_testability",
            "diagnosticity", "formalisation", "derivation_chain")

ck_two_constructs <- list(
  list(id = "c1", label = "Alpha", definition = "The first construct."),
  list(id = "c2", label = "Beta", definition = "The second construct.")
)
ck_p1 <- list(list(id = "p1", from = "c1", to = "c2", relation = "increases",
                   mechanism = "Alpha drives Beta."))

# A theory holding the four required fields and the fields given.
ck_bare <- function(...) {
  c(list(schema_version = "1.0", id = "t", title = "T", maturity = "building"), list(...))
}

ck_item <- function(theory, id) {
  for (it in tf_check(theory)$items) {
    if (identical(it$id, id)) return(list(status = it$status, score = it$score))
  }
  stop("no such item: ", id)
}

# -- the checklist file and the report ----------------------------------------

test_that("the checklist is version 3.1 with five default thresholds", {
  spec <- theoryforge:::tf_checklist()
  expect_identical(spec$schema_version, "3.1")
  # parsimony_ratio_max is gone: parsimony no longer counts assumptions.
  thr <- spec$thresholds
  expect_identical(sort(names(thr)),
                   sort(c("redundancy_similarity_max", "redundancy_overlap_max",
                          "embedding_similarity_max", "min_precision_share", "min_severity")))
  expect_identical(unlist(thr[sort(names(thr))], use.names = FALSE),
                   c(0.85, 0.5, 0.5, 0.85, 0.85))
  expect_identical(vapply(spec$items, function(it) it$id, character(1)), ck_ids)
  items <- stats::setNames(spec$items, ck_ids)
  expect_identical(items$risk_severity$criterion,
                   paste("Mean prediction riskiness (declared severity, else the claim-form rubric)",
                         "at or above threshold"))
  # Meehl (1990a) is the Psychological Inquiry article, Meehl (1990b) the
  # Psychological Reports one, as in the methodology article.
  expect_identical(items$precision$citation, "Meehl (1967, 1990a)")
  expect_identical(items$risk_severity$citation, "Popper (1959); Meehl (1967, 1990b)")
  expect_identical(items$parsimony$citation, "Lakatos (1970); Meehl (1990a)")
  expect_identical(items$derivation_chain$criterion, paste(
    "Every prediction cites declared propositions, the causal graph entails any claim it",
    "states and contradicts no phenomenon's claim (a claim left unread because of a",
    "feedback loop warns)"))
  # The criteria say what is checked, which the dossier and the HTML report print.
  expect_identical(items$falsifiability$criterion, paste(
    "At least one prediction is typed point, interval or directional; the label is the",
    "author's"))
  expect_identical(items$logical_why$criterion,
                   "Every proposition's mechanism field is filled in; its text is not judged")
})

test_that("the report gives coverage after the aggregate", {
  rep <- tf_check(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_identical(names(rep), c("theory_id", "schema_version", "checklist_version",
                                 "maturity", "aggregate_score", "aggregate_range", "coverage",
                                 "gate", "n_blockers_failed", "items"))
  # parsimony has nothing to assess, and the other eleven items weigh 0.92.
  expect_identical(rep$checklist_version, "3.1")
  expect_equal(rep$aggregate_score, 88.0)
  expect_equal(rep$coverage, 0.92)
  parsimony <- rep$items[[4L]]
  expect_identical(parsimony$status, "n/a")
  expect_null(parsimony$score)
  # The score is kept as a NULL element, so the item keeps its keys.
  expect_identical(names(parsimony),
                   c("id", "status", "score", "weight", "severity_if_fail", "citation"))
})

test_that("the empty theory scores zero", {
  # It scored 26.0: parsimony, non_redundancy and derivation_chain each passed
  # at 1.0 with nothing to assess.
  rep <- tf_check(ck_bare())
  expect_equal(rep$aggregate_score, 0.0)
  expect_equal(rep$coverage, 0.74)
  expect_identical(rep$gate, "blocked")
  for (id in c("parsimony", "non_redundancy", "derivation_chain")) {
    expect_identical(ck_item(ck_bare(), id), list(status = "n/a", score = NULL), info = id)
  }
  statuses <- vapply(rep$items, function(it) it$status, character(1))
  expect_true(all(statuses %in% c("n/a", "warn", "fail")))
})

test_that("one prediction never scores below the empty theory", {
  # The empty theory with one existence prediction scored 18.0, below the 26.0
  # of the empty theory, since the prediction made derivation_chain fail.
  empty <- tf_check(ck_bare())$aggregate_score
  for (type in c("existence", "directional", "interval", "point")) {
    t <- ck_bare(predictions = list(list(id = "h1", statement = "S.", type = type)))
    expect_true(tf_check(t)$aggregate_score >= empty, info = type)
  }
  rep <- tf_check(ck_bare(predictions = list(
    list(id = "h1", statement = "X exists.", type = "existence"))))
  expect_equal(rep$aggregate_score, 1.2)
  expect_equal(rep$coverage, 0.82)
})

# -- risk_severity: declared, else the claim-form rubric ----------------------

test_that("mean severity counts every prediction", {
  # Undeclared predictions were skipped, so a theory built without severities
  # scored warn 0.0 however risky its claims were.
  b <- tf_theory("b", "Builder demo") |>
    tf_add_construct("a", "A", "first thing", measurement = "m1",
                     boundary_conditions = "adults") |>
    tf_add_construct("c", "C", "second other thing", measurement = "m2",
                     boundary_conditions = "adults") |>
    tf_add_proposition("p1", "a", "c", "increases", mechanism = "a drives c") |>
    tf_add_prediction("h1", "C equals 3.", "point", derives_from = "p1",
                      bounds = list(lower = 2.9, upper = 3.1)) |>
    tf_add_prediction("h2", "C lies in [2, 4].", "interval", derives_from = "p1",
                      bounds = list(lower = 2, upper = 4))
  expect_identical(ck_item(b, "risk_severity"), list(status = "pass", score = 0.8))
  # A declared value is used where one is given, the rubric elsewhere.
  t <- ck_bare(predictions = list(
    list(id = "h1", statement = "C equals 3.", type = "point", severity = 0.3),
    list(id = "h2", statement = "C lies in [2, 4].", type = "interval",
         bounds = list(lower = 2, upper = 4))
  ))
  expect_identical(ck_item(t, "risk_severity"), list(status = "pass", score = 0.5))
  # Nine undeclared existence predictions no longer leave one declared at 0.9
  # to pass on its own.
  preds <- lapply(0:8, function(i) {
    list(id = paste0("e", i), statement = "X exists.", type = "existence")
  })
  preds[[10L]] <- list(id = "h1", statement = "X is 3.", type = "point", severity = 0.9)
  expect_identical(ck_item(ck_bare(predictions = preds), "risk_severity"),
                   list(status = "warn", score = 0.18))
})

test_that("a declared severity counts and the dossier sets it beside the rubric", {
  t <- ck_bare(predictions = list(
    list(id = "h1", statement = "X exists.", type = "existence", severity = 0.95),
    list(id = "h2", statement = "X is positive.", type = "directional", severity = 0.5),
    list(id = "h3", statement = "X is 3.", type = "point", bounds = list(lower = 2.9, upper = 3.1))
  ))
  expect_identical(ck_item(t, "risk_severity"), list(status = "pass", score = 0.783))
  d <- tf_dossier(t)
  expect_true(grepl(paste0("- h1: severity 0.1, risk 0.1, declared 0.95 ",
                           "(declared exceeds the rubric by more than 0.2)\n"), d, fixed = TRUE))
  # 0.5 exceeds the directional rubric value, 0.3, by exactly 0.2: no note.
  expect_true(grepl("- h2: severity 0.3, risk 0.4, declared 0.5\n", d, fixed = TRUE))
  expect_true(grepl("- h3: severity 0.9, risk 0.9\n", d, fixed = TRUE))
  # The preregistration appended to the dossier leaves its own severity list out.
  expect_false(grepl("\n### Severity", d, fixed = TRUE))
  expect_true(grepl("\n## Severity (pre-data rubric of claim form)\n\n- h1: severity 0.1, risk 0.1,",
                    d, fixed = TRUE))
})

test_that("tf_add_prediction() stores a severity only when given", {
  t <- tf_theory("b", "B") |>
    tf_add_prediction("h1", "C equals 3.", "point", severity = 0.95) |>
    tf_add_prediction("h2", "C equals 4.", "point", bounds = list(lower = 3.9, upper = 4.1))
  expect_identical(t$predictions[[1]],
                   list(id = "h1", statement = "C equals 3.", type = "point", severity = 0.95))
  expect_false("severity" %in% names(t$predictions[[2]]))
  expect_identical(ck_item(t, "risk_severity"), list(status = "pass", score = 0.925))
})

# -- parsimony: assumptions added for an anomaly ------------------------------

# x1 answers the anomaly of h1, and may protect h2 as well.
ck_defended <- function(protects, outcomes) {
  ck_bare(
    constructs = ck_two_constructs, propositions = ck_p1,
    predictions = list(
      list(id = "h1", statement = "Beta rises with Alpha.", type = "directional",
           derives_from = list("p1")),
      list(id = "h2", statement = "Beta lags Alpha by a day.", type = "directional",
           derives_from = list("p1"))
    ),
    auxiliary_assumptions = list(list(id = "x1", statement = "The effect needs a calm setting.",
                                      added_for = "h1", protects = as.list(protects))),
    test_outcomes = outcomes
  )
}

test_that("parsimony is not applicable without an assumption added for an anomaly", {
  # The ratio of assumptions to propositions penalised declaring core
  # assumptions, which every derivation uses (Meehl, 1990a).
  core <- list(list(id = "a1", statement = "Self-report tracks arousal.", added_for = NULL),
               list(id = "a2", statement = "A blank added_for names no anomaly.",
                    added_for = " "))
  expect_identical(ck_item(ck_bare(auxiliary_assumptions = core), "parsimony"),
                   list(status = "n/a", score = NULL))
  expect_identical(ck_item(ck_bare(), "parsimony"), list(status = "n/a", score = NULL))
})

test_that("parsimony passes an independently corroborated assumption", {
  t <- ck_defended(c("h1", "h2"), list(list(prediction_id = "h2", passed = TRUE)))
  expect_identical(ck_item(t, "parsimony"), list(status = "pass", score = 1.0))
})

test_that("parsimony fails an assumption supported only by its anomaly", {
  # A pass of h1, the prediction the assumption answers, used to clear it.
  t <- ck_defended("h1", list(list(prediction_id = "h1", passed = TRUE)))
  expect_identical(ck_item(t, "parsimony"), list(status = "fail", score = 0.0))
})

test_that("parsimony fails an assumption whose other support is not corroborated", {
  # A failed replication leaves h2 mixed, which used to count as a pass.
  mixed <- list(list(prediction_id = "h2", passed = TRUE),
                list(prediction_id = "h2", passed = FALSE))
  expect_identical(ck_item(ck_defended(c("h1", "h2"), mixed), "parsimony"),
                   list(status = "fail", score = 0.0))
  expect_identical(ck_item(ck_defended(c("h1", "h2"), list()), "parsimony"),
                   list(status = "fail", score = 0.0))
})

# -- non_redundancy: the screen's flags ---------------------------------------

test_that("the screen flags a definition contained in another", {
  # Their Jaccard similarity, 0.8, stayed under 0.85, so the deliberately
  # redundant pair of the weak example passed.
  t <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  expect_identical(tf_redundancy_check(t), data.frame(
    a = "k_motivation", b = "k_drive", similarity = 0.8, overlap = 1.0, flag = "review",
    reason = "contained", stringsAsFactors = FALSE
  ))
  expect_identical(ck_item(t, "non_redundancy"), list(status = "warn", score = 0.0))
})

ck_pair <- function(d1, d2) {
  t <- ck_bare(constructs = list(list(id = "a", label = "A", definition = d1),
                                 list(id = "b", label = "B", definition = d2)))
  row <- tf_redundancy_check(t)
  list(list(row$similarity, row$overlap, row$flag), ck_item(t, "non_redundancy"))
}

test_that("overlap counts only between definitions of three tokens or more", {
  expect_identical(ck_pair("Bodily arousal response.", "Bodily arousal response under threat."),
                   list(list(0.6, 1.0, "review"), list(status = "warn", score = 0.0)))
  expect_identical(ck_pair("Bodily arousal.", "Bodily arousal under threat in adults."),
                   list(list(0.4, 1.0, "ok"), list(status = "pass", score = 1.0)))
  # A construct with no definition cannot be screened, so the item cannot pass.
  expect_identical(ck_pair("", "Bodily arousal response."),
                   list(list(0.0, 0.0, "ok"), list(status = "warn", score = 0.0)))
})

test_that("non_redundancy is not applicable to one construct", {
  t <- ck_bare(constructs = ck_two_constructs[1L])
  expect_identical(ck_item(t, "non_redundancy"), list(status = "n/a", score = NULL))
  # Shared vocabulary below the thresholds no longer costs points.
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_identical(ck_item(panic, "non_redundancy"), list(status = "pass", score = 1.0))
})

# -- causal_testability, formalisation and the relation table -----------------

test_that("causal_testability counts every directed relation", {
  cases <- c(mediates = "pass", moderates = "pass", causes = "pass", decreases = "pass",
             associates = "warn")
  for (rel in names(cases)) {
    t <- ck_bare(constructs = ck_two_constructs,
                 propositions = list(list(id = "p1", from = "c1", to = "c2", relation = rel)))
    expect_identical(ck_item(t, "causal_testability")$status, cases[[rel]], info = rel)
  }
})

test_that("the relation table covers the schema enum", {
  table <- theoryforge:::.tf_RELATIONS
  schema <- theoryforge:::tf_theory_schema()
  enum <- unlist(schema$properties$propositions$items$properties$relation$enum)
  expect_identical(sort(names(table)), sort(enum))
  expect_identical(table, list(
    increases = list(kind = "directed", sign = 1L),
    decreases = list(kind = "directed", sign = -1L),
    causes = list(kind = "directed", sign = NA_integer_),
    mediates = list(kind = "directed", sign = NA_integer_),
    moderates = list(kind = "directed", sign = NA_integer_),
    associates = list(kind = "bidirected", sign = NA_integer_)
  ))
  expect_identical(sort(theoryforge:::.tf_DIRECTED),
                   sort(c("increases", "decreases", "causes", "mediates", "moderates")))
  expect_identical(sort(theoryforge:::.tf_PATHS),
                   sort(c("increases", "decreases", "causes", "mediates")))
})

test_that("formalisation needs a recognised model type", {
  cases <- list(list(list(type = "banana"), "warn"), list(list(type = "none"), "warn"),
                list(list(type = ""), "warn"), list(list(), "warn"),
                list(list(type = "abm"), "pass"), list(list(type = "sem"), "pass"))
  for (cs in cases) {
    t <- ck_bare(formal_model = cs[[1]])
    expect_identical(ck_item(t, "formalisation")$status, cs[[2]],
                     info = paste(unlist(cs[[1]]), collapse = ""))
  }
})

test_that("tf_embedding_redundancy() defaults to its own threshold", {
  # A cosine threshold depends on the embedding model, so it is not the
  # lexical screen's Jaccard threshold.
  cache <- theoryforge:::.tf_cache
  original <- theoryforge:::tf_checklist()
  spec <- original
  spec$thresholds$embedding_similarity_max <- 0.5
  vectors <- list("The first construct." = c(1, 0), "The second construct." = c(0.6, 0.8))
  df <- tryCatch({
    assign("checklist", spec, envir = cache)
    tf_embedding_redundancy(ck_bare(constructs = ck_two_constructs),
                            function(d) vectors[[d]])
  }, finally = assign("checklist", original, envir = cache))
  expect_identical(df$cosine, 0.6)
  expect_identical(df$flag, "review")
})

# -- what the renderers print -------------------------------------------------

test_that("the dossier gives coverage and names the failed blockers", {
  d <- tf_dossier(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_true(grepl(paste0("- Checklist score: 2.2 (1.1 to 3.9 with equal weights or one weight ",
                           "halved or doubled)\n",
                           "- Checklist coverage: 0.92\n",
                           "- Gate: blocked\n",
                           "- Blockers failed: 2 (falsifiability, derivation_chain)\n"),
                    d, fixed = TRUE))
  expect_true(grepl(paste0("| parsimony | No auxiliary assumption added for an anomaly (named in ",
                           "added_for) lacks independent corroboration | n/a | n/a | 0.08 |\n"),
                    d, fixed = TRUE))
  expect_true(grepl(paste0("| non_redundancy | Every construct is defined, and no two have ",
                           "near-duplicate or contained definitions or one label, and no ",
                           "construct's measures are all listed for another (lexical screen) | ",
                           "warn | 0.0 | 0.1 |\n"),
                    d, fixed = TRUE))
})

test_that("the views and the HTML report show not-applicable items", {
  t <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  roadmap <- tf_diagram(t, "development_roadmap")
  expect_true(grepl("checklist score 2.2, gate blocked", roadmap, fixed = TRUE))
  expect_false(grepl('"parsimony"', roadmap, fixed = TRUE))
  svg <- tf_diagram(t, "rigour")
  # parsimony is the fourth row, at y = 60 + 24 * 3.
  expect_true(grepl('<rect x="20" y="132" width="16" height="16" rx="3" fill="#9e9e9e"/>',
                    svg, fixed = TRUE))
  expect_true(grepl('<text x="320" y="144">n/a</text>', svg, fixed = TRUE))
  expect_true(grepl(paste0("<tr><td>parsimony</td><td>No auxiliary assumption added for an ",
                           "anomaly (named in added_for) lacks independent corroboration</td>",
                           "<td>n/a</td><td>n/a</td>"),
                    tf_report(t, "html"), fixed = TRUE))
})


# -- checklist 3.0 --------------------------------------------------------------

ck_pred <- function(id, type, ...) {
  list(id = id, statement = "s", type = type, derives_from = list("p1"), ...)
}

test_that("precision counts point and interval claims only with two finite bounds", {
  t <- ck_bare(constructs = ck_two_constructs, propositions = ck_p1, predictions = list(
    ck_pred("h1", "point"),
    ck_pred("h2", "interval", bounds = list(lower = 20, upper = 60)),
    ck_pred("h3", "point", bounds = list(lower = 5, upper = 5)),
    ck_pred("h4", "directional", bounds = list(lower = 0))
  ))
  expect_identical(ck_item(t, "precision"), list(status = "pass", score = 0.5))
  t$predictions[[3]]$bounds <- list(lower = 5)
  expect_identical(ck_item(t, "precision"), list(status = "warn", score = 0.25))
})

test_that("parsimony leaves a core assumption whose prediction failed to the appraisal", {
  # Without a prior version the checklist cannot tell an assumption made before
  # a test from one made after it, so only a declared added_for is assessed,
  # and tf_appraise_amendment() infers undeclared additions.
  preds <- list(ck_pred("h1", "directional"), ck_pred("h2", "directional"))
  aux <- list(list(id = "a1", statement = "Only in calm settings.", protects = list("h1", "h2")))
  failed <- list(list(prediction_id = "h1", passed = FALSE))
  t <- ck_bare(constructs = ck_two_constructs, propositions = ck_p1, predictions = preds,
               auxiliary_assumptions = aux, test_outcomes = failed)
  expect_identical(ck_item(t, "parsimony"), list(status = "n/a", score = NULL))
  t$auxiliary_assumptions[[1]]$added_for <- "h1"
  expect_identical(ck_item(t, "parsimony"), list(status = "fail", score = 0.0))
  t$test_outcomes <- c(failed, list(list(prediction_id = "h2", passed = TRUE)))
  expect_identical(ck_item(t, "parsimony"), list(status = "pass", score = 1.0))
})

test_that("the screen flags a shared label and a shared measure", {
  t <- ck_bare(constructs = list(
    list(id = "a", label = "Anxiety", definition = "Worry about future threat.",
         measurement = list("GAD-7 total score")),
    list(id = "b", label = " anxiety ", definition = "Bodily arousal under danger.",
         measurement = list("gad-7  total score", "Heart rate")),
    list(id = "c", label = "Fear", definition = "An urge to escape present danger.",
         measurement = list("Heart rate"))
  ))
  df <- tf_redundancy_check(t)
  df <- df[order(df$a, df$b), ]
  expect_identical(paste(df$a, df$b), c("a b", "a c", "b c"))
  expect_identical(df$flag, c("review", "ok", "review"))
  expect_identical(df$reason, c("same label, shared measurement", "", "shared measurement"))
  expect_identical(ck_item(t, "non_redundancy"), list(status = "warn", score = 0.0))
  # Constructs that share a method but keep measures of their own are not
  # flagged, as in a multitrait-multimethod design.
  t <- ck_bare(constructs = list(
    list(id = "a", label = "A", definition = "Worry about future threat.",
         measurement = list("Self-report", "Informant rating")),
    list(id = "b", label = "B", definition = "Bodily arousal under danger.",
         measurement = list("self-report", "Heart rate"))
  ))
  expect_identical(tf_redundancy_check(t)$flag, "ok")
})

test_that("non_redundancy cannot pass while a definition is empty", {
  defined <- ck_two_constructs
  expect_identical(ck_item(ck_bare(constructs = defined), "non_redundancy"),
                   list(status = "pass", score = 1.0))
  defined[[2]]$definition <- "  "
  expect_identical(ck_item(ck_bare(constructs = defined), "non_redundancy"),
                   list(status = "warn", score = 0.0))
})

test_that("the aggregate range spans the alternative weightings", {
  rep <- tf_check(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_identical(rep$aggregate_range, c(84.2, 90.2))
  expect_true(rep$aggregate_range[[1]] <= rep$aggregate_score &&
                rep$aggregate_score <= rep$aggregate_range[[2]])
  # When every applicable item has one score, no weighting can move it.
  rep <- tf_check(ck_bare(constructs = ck_two_constructs[1]))
  expect_identical(rep$aggregate_range, rep(rep$aggregate_score, 2))
})

test_that("a severity too large for a double is refused as non-numeric", {
  t <- ck_bare(constructs = ck_two_constructs,
               predictions = list(ck_pred("h1", "point", severity = Inf)))
  expect_error(tf_check(t), paste0("check requires numeric prediction severities; ",
                                   "non-numeric severity for prediction: h1"), fixed = TRUE)
})

test_that("full validation checks a claim form and sign against its bounds", {
  positive <- list(kind = "effect", x = "c1", y = "c2", sign = "positive")
  t <- ck_bare(constructs = ck_two_constructs, predictions = list(
    ck_pred("h1", "point", bounds = list(lower = 1)),
    ck_pred("h2", "interval", bounds = list(upper = 2)),
    ck_pred("h3", "directional", bounds = list(lower = 0.2, upper = 1)),
    ck_pred("h4", "existence", bounds = list(lower = 0.2, upper = 0.8)),
    ck_pred("h5", "interval", bounds = list(lower = -1, upper = 1), claim = positive),
    # A sign stated with a bound at 0 on a bounded scale is accepted.
    ck_pred("h6", "directional", bounds = list(lower = 0, upper = 1), claim = positive),
    # An existence claim takes no bounds, on one side or on two, and without
    # them it may state the sign nonzero.
    ck_pred("h7", "existence", bounds = list(lower = 0.2)),
    ck_pred("h8", "existence", bounds = list(upper = 0.5)),
    ck_pred("h9", "existence", claim = utils::modifyList(positive, list(sign = "nonzero")))
  ), test_outcomes = list(
    # A pass with the estimate outside the region is not invalid: a test that
    # fails to reject a predicted value passes it (Meehl, 1967).
    list(prediction_id = "h6", passed = TRUE, estimate = -0.1, se = 0.2)
  ))
  msg <- tryCatch({
    tf_validate(t, full = TRUE)
    ""
  }, error = conditionMessage)
  expect_true(endsWith(msg, paste0(
    "prediction[0] is a point claim, so its bounds need a finite lower and a finite upper; ",
    "prediction[1] is an interval claim, so its bounds need a finite lower and a finite upper; ",
    "prediction[2] is a directional claim, so its bounds must leave one side open or end at 0; ",
    "prediction[3] is an existence claim, so it takes no bounds: the region it allows, ",
    "every value but 0, is not one interval; ",
    "prediction[4] claims a positive sign, so its lower bound must be 0 or above; ",
    "prediction[6] is an existence claim, so it takes no bounds: the region it allows, ",
    "every value but 0, is not one interval; ",
    "prediction[7] is an existence claim, so it takes no bounds: the region it allows, ",
    "every value but 0, is not one interval")))
})

test_that("the dossier writes an extreme severity as a bound", {
  t <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  t$test_outcomes <- list(list(prediction_id = "pred1", passed = TRUE, estimate = 20, se = 0.5))
  expect_true(grepl("post-data severity > 0.999 for [15, 25]", tf_dossier(t), fixed = TRUE))
  t$test_outcomes <- list(list(prediction_id = "pred1", passed = FALSE, estimate = 40, se = 1))
  expect_true(grepl("post-data severity < 0.001 for [15, 25]\n", tf_dossier(t), fixed = TRUE))
  t$test_outcomes <- list(list(prediction_id = "pred1", passed = TRUE, estimate = 26, se = 2))
  expect_true(grepl(paste0("post-data severity 0.309 for [15, 25]; recorded as passed, with the ",
                           "estimate outside that region\n"), tf_dossier(t), fixed = TRUE))
})

test_that("equal weights can set the end of the aggregate range", {
  # Two low-weight items that pass beside a heavy one that fails: equal weights
  # give the highest aggregate, doubling the heavy weight the lowest.
  expect_identical(.tf_aggregate_range(c(0.15, 0.05, 0.05), c(0, 1, 1)), c(25.0, 66.7))
})

test_that("precision does not count an infinite bound", {
  t <- ck_bare(constructs = ck_two_constructs, propositions = ck_p1,
               predictions = list(ck_pred("h1", "point", bounds = list(lower = 0, upper = Inf))))
  expect_identical(ck_item(t, "precision"), list(status = "warn", score = 0.0))
})

test_that("non_redundancy reads a definition of stopwords as no definition", {
  cons <- ck_two_constructs
  cons[[2]]$definition <- "The and of"
  expect_identical(ck_item(ck_bare(constructs = cons), "non_redundancy"),
                   list(status = "warn", score = 0.0))
})

test_that("an unknown field names the first of two equally close fields", {
  # The Python suite asserts the same messages.
  expect_identical(
    .tf_unknown_fields(list(tyet = 1, x = 1, xnote = 1, x_note = 1, abcdef = 1), "p",
                       c("id", "type", "test")),
    c("p has unknown field: tyet (did you mean type?)",
      "p has unknown field: x (did you mean id?)",
      "p has unknown field: xnote",
      "p has unknown field: abcdef"))
})

# -- checklist 3.1: the derivation chain, the cycles option and the labels ------

# x -> m -> y gives the effect of x on y a negative sign, and an unrelated
# feedback loop joins u and w. fixtures/edge/derivation-unrelated-loop is the
# same theory.
ck_loop_theory <- function(sign = "positive") {
  prop <- function(id, from, to, relation) {
    list(id = id, from = from, to = to, relation = relation, mechanism = "It does.")
  }
  ck_bare(
    maturity = "developing",
    constructs = lapply(c("x", "m", "y", "u", "w"), function(c) {
      list(id = c, label = toupper(c), definition = paste0("Construct ", c, "."))
    }),
    propositions = list(prop("p1", "x", "m", "increases"), prop("p2", "m", "y", "decreases"),
                        prop("q1", "u", "w", "increases"), prop("q2", "w", "u", "increases")),
    predictions = list(list(id = "h1", statement = "x raises y.", type = "directional",
                            derives_from = list("p1", "p2"),
                            claim = list(kind = "effect", x = "x", y = "y", sign = sign)))
  )
}

ck_derivation <- function(theory, cycles = "refuse") {
  rep <- tf_check(theory, cycles = cycles)
  it <- rep$items[[12L]]
  list(it$status, it$score, unlist(it$not_checked), rep$gate)
}

test_that("check refuses an unknown cycles option", {
  for (bad in list("acyclic", NULL, NA_character_, c("sigma", "refuse"), "")) {
    expect_error(tf_check(ck_bare(), cycles = bad),
                 "^check requires cycles to be 'refuse' or 'sigma'$")
  }
  # The option is checked before the theory is read, so a refusal of the
  # theory does not hide it.
  bad_outcome <- ck_bare(test_outcomes = list(list(prediction_id = "h1", passed = "true")))
  expect_error(tf_check(bad_outcome, cycles = "x"), "^check requires cycles")
})

test_that("an unrelated feedback loop leaves the claim not checked", {
  # The loop u <-> w has no path to the claim, yet under cycles = "refuse"
  # every claim of the graph is left unread. The item warns and the gate
  # stays open. Nothing was found wrong with the claim and the references
  # resolve, so the prediction counts as derived, as it did under 3.0.
  t <- ck_loop_theory()
  expect_identical(ck_derivation(t), list("warn", 1.0, "h1", "pass"))
  expect_identical(tf_check(t)$n_blockers_failed, 0L)
  # Read by sigma-separation, the claim is contradicted and the item fails.
  expect_identical(ck_derivation(t, "sigma"), list("fail", 0.0, NULL, "blocked"))
  # A claim the sigma reading entails passes.
  expect_identical(ck_derivation(ck_loop_theory("negative"), "sigma"),
                   list("pass", 1.0, NULL, "pass"))
  expect_identical(ck_derivation(ck_loop_theory("negative")), list("warn", 1.0, "h1", "pass"))
})

test_that("only the derivation chain record lists unchecked claims", {
  rep <- tf_check(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  keys <- c("id", "status", "score", "weight", "severity_if_fail", "citation")
  extra <- c("not_checked", "phenomena_not_checked")
  for (it in rep$items) {
    expect_identical(names(it), if (it$id == "derivation_chain") c(keys, extra) else keys)
  }
  expect_identical(rep$items[[12L]]$not_checked, list("pred_indep"))
  expect_identical(rep$items[[12L]]$phenomena_not_checked, list())
  # A not-checked prediction whose references do not resolve still fails the
  # item, is still listed and is not derived.
  t <- ck_loop_theory()
  t$predictions[[1L]]$derives_from <- list("p9")
  expect_identical(ck_derivation(t), list("fail", 0.0, "h1", "blocked"))
  # With no prediction the item is n/a and lists nothing, even with a
  # phenomenon behind a loop.
  t <- ck_loop_theory()
  t$predictions <- list()
  t$phenomena <- list(list(id = "ph1", statement = "s",
                           claim = list(kind = "effect", x = "u", y = "w", sign = "positive")))
  dc <- tf_check(t)$items[[12L]]
  expect_identical(list(dc$status, dc$not_checked, dc$phenomena_not_checked),
                   list("n/a", list(), list()))
})

test_that("a not-checked prediction counts as derived when its references resolve", {
  # fixtures/edge/derivation-loop-unresolved: both claims are behind a loop.
  # h1 cites a declared proposition and counts as derived; h2 cites p9 and is
  # not derived, so the item fails with 0.5.
  loop <- list(list(id = "p1", from = "c1", to = "c2", relation = "increases"),
               list(id = "p2", from = "c2", to = "c1", relation = "increases"))
  up <- list(kind = "effect", x = "c1", y = "c2", sign = "positive")
  back <- list(kind = "effect", x = "c2", y = "c1", sign = "positive")
  h2 <- ck_pred("h2", "directional", claim = back)
  h2$derives_from <- list("p9")
  t <- ck_bare(constructs = ck_two_constructs, propositions = loop,
               predictions = list(ck_pred("h1", "directional", claim = up), h2))
  expect_identical(ck_derivation(t), list("fail", 0.5, c("h1", "h2"), "blocked"))
  t$predictions[[2L]]$derives_from <- list("p2")
  expect_identical(ck_derivation(t), list("warn", 1.0, c("h1", "h2"), "pass"))
  expect_identical(ck_derivation(t, "sigma"), list("pass", 1.0, NULL, "pass"))
  # The score is that of the same file without the claims: stating a claim
  # that the loop leaves unread costs nothing.
  bare <- t
  for (i in seq_along(bare$predictions)) bare$predictions[[i]]$claim <- NULL
  expect_identical(ck_derivation(bare), list("pass", 1.0, NULL, "pass"))
  expect_identical(tf_check(bare)$aggregate_score, tf_check(t)$aggregate_score)
})

test_that("the panic network scores the same under both readings", {
  # Its one claim, on pred_indep, is behind a loop under the default. The item
  # warns and names it, and the score is that of sigma-separation, which
  # entails the claim.
  t <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  refuse <- tf_check(t)
  sigma <- tf_check(t, cycles = "sigma")
  expect_identical(list(refuse$aggregate_score, refuse$aggregate_range), list(88.0, c(84.2, 90.2)))
  expect_identical(list(sigma$aggregate_score, sigma$aggregate_range), list(88.0, c(84.2, 90.2)))
  expect_identical(ck_derivation(t), list("warn", 1.0, "pred_indep", "pass"))
  expect_identical(ck_derivation(t, "sigma"), list("pass", 1.0, NULL, "pass"))
})

# fixtures/edge/derivation-phenomenon-loop: a loop a <-> b, a phenomenon whose
# claim is that a lowers b, and one prediction without a claim.
ck_phenomenon_loop <- function(claim_id = "ph1") {
  prop <- function(id, from, to) {
    list(id = id, from = from, to = to, relation = "increases", mechanism = "It does.")
  }
  ck_bare(
    maturity = "developing",
    constructs = lapply(c("a", "b", "z"), function(c) {
      list(id = c, label = toupper(c), definition = paste0("Construct ", c, "."))
    }),
    propositions = list(prop("p1", "a", "b"), prop("p2", "b", "a")),
    phenomena = list(
      list(id = claim_id, statement = "Raising a lowers b.",
           claim = list(kind = "effect", x = "a", y = "b", sign = "negative")),
      list(id = "ph2", statement = "z tracks a.",
           claim = list(kind = "association", x = "a", y = "z", sign = "positive"))),
    predictions = list(list(id = "h1", statement = "b rises with a.", type = "directional",
                            derives_from = list("p1")))
  )
}

ck_chain <- function(theory, cycles = "refuse") {
  dc <- tf_check(theory, cycles = cycles)$items[[12L]]
  list(dc$status, dc$score, unlist(dc$not_checked), unlist(dc$phenomena_not_checked))
}

test_that("a phenomenon behind a feedback loop is not checked", {
  # Under "refuse" the loop leaves ph1's claim unread. The item warns and
  # names it, the documents' derivation line says it was not checked, and the
  # score, which counts predictions, is that of a passing item. ph2 names a
  # construct outside the graph and changes nothing under either reading.
  t <- ck_phenomenon_loop()
  expect_identical(ck_chain(t), list("warn", 1.0, NULL, "ph1"))
  expect_identical(tf_check(t)$gate, "pass")
  expect_true(grepl(paste0("contradicts no claim a phenomenon states: not checked (feedback ",
                           "loop; use cycles = \"sigma\")\n"), tf_preregister(t), fixed = TRUE))
  # Under "sigma" the claim is read and contradicted.
  expect_identical(ck_chain(t, "sigma"), list("fail", 1.0, NULL, NULL))
  expect_identical(tf_check(t, cycles = "sigma")$gate, "blocked")
  # A failure elsewhere takes precedence over the warning, and ph1 is still
  # listed.
  t$predictions[[1L]]$derives_from <- list("p9")
  expect_identical(ck_chain(t)[c(1L, 4L)], list("fail", "ph1"))
})

test_that("a phenomenon and a prediction with one id are listed apart", {
  # Ids are unique within each collection but not across them, so the two
  # lists keep a prediction and a phenomenon named h1 apart.
  t <- ck_phenomenon_loop("h1")
  t$predictions[[1L]]$claim <- list(kind = "effect", x = "a", y = "b", sign = "positive")
  expect_true(isTRUE(tf_validate(t, full = TRUE)))
  expect_identical(ck_chain(t), list("warn", 1.0, "h1", "h1"))
})

test_that("a claim the graph cannot place or read is not derived", {
  base <- list(constructs = c(ck_two_constructs,
                              list(list(id = "c3", label = "Gamma",
                                        definition = "A construct no proposition relates."))),
               propositions = ck_p1)
  entailed <- list(kind = "effect", x = "c1", y = "c2", sign = "positive")
  with_y <- function(y) utils::modifyList(entailed, list(y = y))
  # fixtures/edge/derivation-not-in-graph: a construct outside the graph.
  t <- do.call(ck_bare, c(base, list(predictions = list(
    ck_pred("h1", "directional", claim = entailed),
    ck_pred("h2", "directional", claim = with_y("c3"))))))
  expect_identical(ck_derivation(t), list("fail", 0.5, NULL, "blocked"))
  # A claim that cannot be read as written.
  t <- do.call(ck_bare, c(base, list(predictions = list(
    ck_pred("h1", "directional", claim = with_y("c1"))))))
  expect_identical(ck_derivation(t), list("fail", 0.0, NULL, "blocked"))
  # A graph that cannot be built reads no claim, so a stated claim fails,
  # while a prediction that states none is judged on its references.
  refused <- list(constructs = ck_two_constructs,
                  propositions = c(ck_p1, list(list(id = "p2", from = "c1", to = "c9",
                                                    relation = "increases"))))
  expect_identical(
    ck_derivation(do.call(ck_bare, c(refused, list(predictions = list(
      ck_pred("h1", "directional", claim = entailed)))))),
    list("fail", 0.0, NULL, "blocked"))
  expect_identical(
    ck_derivation(do.call(ck_bare, c(refused, list(predictions = list(
      ck_pred("h1", "directional")))))),
    list("pass", 1.0, NULL, "pass"))
})

test_that("a phenomenon the graph contradicts fails the derivation chain", {
  # fixtures/edge/derivation-phenomenon. A prediction with this claim failed
  # the item, and a phenomenon with it left the item and the gate as they were.
  positive <- list(kind = "effect", x = "c1", y = "c2", sign = "positive")
  negative <- list(kind = "association", x = "c1", y = "c2", sign = "negative")
  t <- ck_bare(constructs = ck_two_constructs, propositions = ck_p1,
               predictions = list(ck_pred("h1", "directional", claim = positive)),
               phenomena = list(list(id = "ph1", statement = "s", claim = negative)))
  expect_identical(ck_derivation(t), list("fail", 1.0, NULL, "blocked"))
  # A phenomenon the graph leaves open or does not evaluate changes nothing.
  for (claim in list(list(kind = "effect", x = "c1", y = "c9", sign = "positive"),
                     list(kind = "effect", x = "c1", y = "c2", sign = "bogus"))) {
    t$phenomena[[1L]]$claim <- claim
    expect_identical(ck_derivation(t), list("pass", 1.0, NULL, "pass"))
  }
  t$propositions[[1L]]$relation <- "causes"
  t$predictions[[1L]]$claim <- NULL
  t$phenomena[[1L]]$claim <- negative
  expect_identical(ck_derivation(t), list("pass", 1.0, NULL, "pass"))
})

test_that("diagnosticity reads the claims with the same cycles", {
  # Under "refuse" the theory's graph leaves the claim unread, so the declared
  # rival stands. Under "sigma" both graphs entail the claim, which shows the
  # declaration false.
  t <- ck_loop_theory("negative")
  t$alternatives <- list(list(id = "r", label = "A rival", propositions = t$propositions))
  t$predictions[[1L]]$diagnostic_vs <- list("r")
  expect_identical(ck_item(t, "diagnosticity"), list(status = "pass", score = 1.0))
  expect_identical(tf_check(t, cycles = "sigma")$items[[10L]]$score, 0.0)
})

test_that("full validation reports a directional claim that states no direction", {
  nonzero <- list(kind = "effect", x = "c1", y = "c2", sign = "nonzero")
  t <- ck_bare(constructs = c(ck_two_constructs,
                              list(list(id = "c3", label = "Gamma", definition = "c3."))),
               propositions = ck_p1, predictions = list(
                 ck_pred("h1", "directional", claim = nonzero),
                 # With bounds too, after the messages about the bounds.
                 ck_pred("h2", "directional", bounds = list(lower = 0), claim = nonzero),
                 # A conditional claim can only be zero or nonzero, so the
                 # direction stays in the statement and nothing is reported.
                 ck_pred("h3", "directional", claim = list(kind = "association", x = "c1",
                                                           y = "c2", given = list("c3"),
                                                           sign = "nonzero")),
                 # The other types may claim nonzero.
                 ck_pred("h4", "existence", claim = nonzero),
                 ck_pred("h5", "point", bounds = list(lower = 0.2, upper = 0.3), claim = nonzero)
               ))
  err <- tryCatch(tf_validate(t, full = TRUE), error = function(e) conditionMessage(e))
  expect_identical(err, paste0(
    "invalid theory object: ",
    "prediction[0] is a directional claim, so its claim's sign cannot be nonzero, which ",
    "states no direction; ",
    "prediction[1] claims a nonzero sign, so its bounds must exclude 0; ",
    "prediction[1] is a directional claim, so its claim's sign cannot be nonzero, which ",
    "states no direction"))
  # The falsifiability item still reads the label alone.
  expect_identical(ck_item(t, "falsifiability"), list(status = "pass", score = 1.0))
})

test_that("the rubric rates a point or interval label without bounds as directional", {
  # fixtures/edge/label-without-content. A point label without bounds was
  # graded 0.9, the highest value, while the precision item gave it nothing.
  t <- ck_bare(alternatives = list(list(id = "alt", label = "A rival")), predictions = list(
    ck_pred("h1", "point"),
    ck_pred("h2", "interval", bounds = list(lower = 0.2)),
    ck_pred("h3", "point", diagnostic_vs = list("alt")),
    ck_pred("h4", "point", bounds = list(lower = 0.25, upper = 0.35)),
    ck_pred("h5", "interval", bounds = list(lower = 0.2, upper = Inf)),
    ck_pred("h6", "interval", bounds = list(lower = 0.2, upper = 0.8))
  ))
  sev <- tf_severity(t)
  expect_identical(sev$type, c("point", "interval", "point", "point", "interval", "interval"))
  expect_identical(sev$risk_score, c(0.4, 0.4, 0.4, 0.9, 0.4, 0.7))
  expect_identical(sev$computed_severity, c(0.3, 0.3, 0.4, 0.9, 0.3, 0.7))
  expect_identical(ck_item(t, "precision"), list(status = "warn", score = 0.333))
})

test_that("the HTML report states what the checklist score describes", {
  html <- tf_report(tf_read(tf_fixture_path("panic-network.theory.yaml")), "html")
  has <- function(s) expect_true(grepl(s, html, fixed = TRUE), info = s)
  # The score and the gate are plain text, not set in bold as a headline.
  has(paste0("  <p>Checklist score: 88.0 (84.2 to 90.2 with equal weights or ",
             "one weight halved or doubled) &middot; gate: pass</p>\n"))
  expect_false(grepl("<strong>|<b>", html))
  has(paste0("  <p>The checklist score describes how completely the file states what checklist ",
             "3.1 asks for. Most items read whether a field is filled in or how a prediction is ",
             "labelled, and stated claims are checked against the causal graph. Test outcomes ",
             "are read only by the parsimony item, the weights are conventions, and no study has ",
             "established what difference between two scores is meaningful. The score does not ",
             "show that the theory is true or well reasoned.</p>\n",
             "  <p>The gate reports whether either blocking item failed: at least one prediction ",
             "is typed point, interval or directional, and every prediction cites declared ",
             "propositions whose graph entails any claim it states, with no stated phenomenon ",
             "contradicted. The labels are the author's and are not checked against the ",
             "statements.</p>\n  <table>"))
  has(paste0("<tr><th>item</th><th>criterion</th><th>status</th><th>score</th>",
             "<th>source of the criterion</th></tr>"))
  has(paste0("<tr><td>derivation_chain</td><td>Every prediction cites declared propositions, the ",
             "causal graph entails any claim it states and contradicts no phenomenon's claim (a ",
             "claim left unread because of a feedback loop warns)</td><td>warn</td><td>1.0</td>",
             "<td>Scheel et al. (2021); Szollosi et al. (2020)</td></tr>"))
  expect_false(grepl("igour|grounding|Aggregate", html))
})
