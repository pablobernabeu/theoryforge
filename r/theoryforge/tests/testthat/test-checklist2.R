# Checklist 2.0 (API_SPEC.md section 4).
#
# An item with nothing to assess is "n/a", with a NULL score, and is left out of
# the aggregate, which is the weighted mean of the applicable items. The report
# gains `coverage`, the share of checklist weight that was applicable.
# Parsimony fails only an assumption added for an anomaly that has no
# independent corroboration, non-redundancy follows the redundancy screen's
# flags and mean severity counts every prediction, using the claim-form rubric
# where none is declared. The Python suite (test_checklist2.py) builds the same
# theories and asserts the same values.

c2_ids <- c("falsifiability", "precision", "risk_severity", "parsimony", "non_redundancy",
            "construct_clarity", "scope", "logical_why", "causal_testability",
            "diagnosticity", "formalisation", "derivation_chain")

c2_two_constructs <- list(
  list(id = "c1", label = "Alpha", definition = "The first construct."),
  list(id = "c2", label = "Beta", definition = "The second construct.")
)
c2_p1 <- list(list(id = "p1", from = "c1", to = "c2", relation = "increases",
                   mechanism = "Alpha drives Beta."))

# A theory holding the four required fields and the fields given.
c2_bare <- function(...) {
  c(list(schema_version = "1.0", id = "t", title = "T", maturity = "building"), list(...))
}

c2_item <- function(theory, id) {
  for (it in tf_check(theory)$items) {
    if (identical(it$id, id)) return(list(status = it$status, score = it$score))
  }
  stop("no such item: ", id)
}

# -- the checklist file and the report ----------------------------------------

test_that("the checklist is version 2.0 with five default thresholds", {
  spec <- theoryforge:::tf_checklist()
  expect_identical(spec$schema_version, "2.0")
  # parsimony_ratio_max is gone: parsimony no longer counts assumptions.
  thr <- spec$thresholds
  expect_identical(sort(names(thr)),
                   sort(c("redundancy_similarity_max", "redundancy_overlap_max",
                          "embedding_similarity_max", "min_precision_share", "min_severity")))
  expect_identical(unlist(thr[sort(names(thr))], use.names = FALSE),
                   c(0.85, 0.5, 0.5, 0.85, 0.85))
  expect_identical(vapply(spec$items, function(it) it$id, character(1)), c2_ids)
  items <- stats::setNames(spec$items, c2_ids)
  expect_identical(items$risk_severity$criterion,
                   "Mean prediction severity (declared, else the claim-form rubric) at or above threshold")
  expect_identical(items$risk_severity$citation, "Popper (1959); Meehl (1967, 1990)")
  expect_identical(items$parsimony$citation, "Lakatos (1970); Meehl (1990)")
  expect_identical(items$derivation_chain$criterion, paste(
    "Every prediction cites at least one proposition, and every cited id is a declared",
    "proposition (reference check only)"))
})

test_that("the report gives coverage after the aggregate", {
  rep <- tf_check(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_identical(names(rep), c("theory_id", "schema_version", "checklist_version",
                                 "maturity", "aggregate_score", "coverage", "gate",
                                 "n_blockers_failed", "items"))
  # parsimony has nothing to assess, and the other eleven items weigh 0.92.
  expect_identical(rep$checklist_version, "2.0")
  expect_equal(rep$aggregate_score, 87.3)
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
  rep <- tf_check(c2_bare())
  expect_equal(rep$aggregate_score, 0.0)
  expect_equal(rep$coverage, 0.74)
  expect_identical(rep$gate, "blocked")
  for (id in c("parsimony", "non_redundancy", "derivation_chain")) {
    expect_identical(c2_item(c2_bare(), id), list(status = "n/a", score = NULL), info = id)
  }
  statuses <- vapply(rep$items, function(it) it$status, character(1))
  expect_true(all(statuses %in% c("n/a", "warn", "fail")))
})

test_that("one prediction never scores below the empty theory", {
  # The empty theory with one existence prediction scored 18.0, below the 26.0
  # of the empty theory, since the prediction made derivation_chain fail.
  empty <- tf_check(c2_bare())$aggregate_score
  for (type in c("existence", "directional", "interval", "point")) {
    t <- c2_bare(predictions = list(list(id = "h1", statement = "S.", type = type)))
    expect_true(tf_check(t)$aggregate_score >= empty, info = type)
  }
  rep <- tf_check(c2_bare(predictions = list(
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
    tf_add_prediction("h1", "C equals 3.", "point", derives_from = "p1") |>
    tf_add_prediction("h2", "C lies in [2, 4].", "interval", derives_from = "p1")
  expect_identical(c2_item(b, "risk_severity"), list(status = "pass", score = 0.8))
  # A declared value is used where one is given, the rubric elsewhere.
  t <- c2_bare(predictions = list(
    list(id = "h1", statement = "C equals 3.", type = "point", severity = 0.3),
    list(id = "h2", statement = "C lies in [2, 4].", type = "interval")
  ))
  expect_identical(c2_item(t, "risk_severity"), list(status = "pass", score = 0.5))
  # Nine undeclared existence predictions no longer leave one declared at 0.9
  # to pass on its own.
  preds <- lapply(0:8, function(i) {
    list(id = paste0("e", i), statement = "X exists.", type = "existence")
  })
  preds[[10L]] <- list(id = "h1", statement = "X is 3.", type = "point", severity = 0.9)
  expect_identical(c2_item(c2_bare(predictions = preds), "risk_severity"),
                   list(status = "warn", score = 0.18))
})

test_that("a declared severity counts and the dossier sets it beside the rubric", {
  t <- c2_bare(predictions = list(
    list(id = "h1", statement = "X exists.", type = "existence", severity = 0.95),
    list(id = "h2", statement = "X is positive.", type = "directional", severity = 0.5),
    list(id = "h3", statement = "X is 3.", type = "point")
  ))
  expect_identical(c2_item(t, "risk_severity"), list(status = "pass", score = 0.783))
  d <- tf_dossier(t)
  expect_true(grepl(paste0("- h1: severity 0.1, risk 0.1, declared 0.95 ",
                           "(declared exceeds the rubric by more than 0.2)\n"), d, fixed = TRUE))
  # 0.5 exceeds the directional rubric value, 0.3, by exactly 0.2: no note.
  expect_true(grepl("- h2: severity 0.3, risk 0.4, declared 0.5\n", d, fixed = TRUE))
  expect_true(grepl("- h3: severity 0.9, risk 0.9\n", d, fixed = TRUE))
  # The preregistration appended to the dossier keeps its own lines.
  expect_true(grepl("\n## Severity (pre-data rubric of claim form)\n- h1: severity 0.1, risk 0.1\n",
                    d, fixed = TRUE))
})

test_that("tf_add_prediction() stores a severity only when given", {
  t <- tf_theory("b", "B") |>
    tf_add_prediction("h1", "C equals 3.", "point", severity = 0.95) |>
    tf_add_prediction("h2", "C equals 4.", "point")
  expect_identical(t$predictions[[1]],
                   list(id = "h1", statement = "C equals 3.", type = "point", severity = 0.95))
  expect_false("severity" %in% names(t$predictions[[2]]))
  expect_identical(c2_item(t, "risk_severity"), list(status = "pass", score = 0.925))
})

# -- parsimony: assumptions added for an anomaly ------------------------------

# x1 answers the anomaly of h1, and may protect h2 as well.
c2_defended <- function(protects, outcomes) {
  c2_bare(
    constructs = c2_two_constructs, propositions = c2_p1,
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
  # assumptions, which every derivation uses (Meehl, 1990).
  core <- list(list(id = "a1", statement = "Self-report tracks arousal.", added_for = NULL),
               list(id = "a2", statement = "A blank added_for names no anomaly.",
                    added_for = " "))
  expect_identical(c2_item(c2_bare(auxiliary_assumptions = core), "parsimony"),
                   list(status = "n/a", score = NULL))
  expect_identical(c2_item(c2_bare(), "parsimony"), list(status = "n/a", score = NULL))
})

test_that("parsimony passes an independently corroborated assumption", {
  t <- c2_defended(c("h1", "h2"), list(list(prediction_id = "h2", passed = TRUE)))
  expect_identical(c2_item(t, "parsimony"), list(status = "pass", score = 1.0))
})

test_that("parsimony fails an assumption supported only by its anomaly", {
  # A pass of h1, the prediction the assumption answers, used to clear it.
  t <- c2_defended("h1", list(list(prediction_id = "h1", passed = TRUE)))
  expect_identical(c2_item(t, "parsimony"), list(status = "fail", score = 0.0))
})

test_that("parsimony fails an assumption whose other support is not corroborated", {
  # A failed replication leaves h2 mixed, which used to count as a pass.
  mixed <- list(list(prediction_id = "h2", passed = TRUE),
                list(prediction_id = "h2", passed = FALSE))
  expect_identical(c2_item(c2_defended(c("h1", "h2"), mixed), "parsimony"),
                   list(status = "fail", score = 0.0))
  expect_identical(c2_item(c2_defended(c("h1", "h2"), list()), "parsimony"),
                   list(status = "fail", score = 0.0))
})

# -- non_redundancy: the screen's flags ---------------------------------------

test_that("the screen flags a definition contained in another", {
  # Their Jaccard similarity, 0.8, stayed under 0.85, so the deliberately
  # redundant pair of the weak example passed.
  t <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  expect_identical(tf_redundancy_check(t), data.frame(
    a = "k_motivation", b = "k_drive", similarity = 0.8, overlap = 1.0, flag = "review",
    stringsAsFactors = FALSE
  ))
  expect_identical(c2_item(t, "non_redundancy"), list(status = "warn", score = 0.0))
})

c2_pair <- function(d1, d2) {
  t <- c2_bare(constructs = list(list(id = "a", label = "A", definition = d1),
                                 list(id = "b", label = "B", definition = d2)))
  row <- tf_redundancy_check(t)
  list(list(row$similarity, row$overlap, row$flag), c2_item(t, "non_redundancy"))
}

test_that("overlap counts only between definitions of three tokens or more", {
  expect_identical(c2_pair("Bodily arousal response.", "Bodily arousal response under threat."),
                   list(list(0.6, 1.0, "review"), list(status = "warn", score = 0.0)))
  expect_identical(c2_pair("Bodily arousal.", "Bodily arousal under threat in adults."),
                   list(list(0.4, 1.0, "ok"), list(status = "pass", score = 1.0)))
  expect_identical(c2_pair("", "Bodily arousal response."),
                   list(list(0.0, 0.0, "ok"), list(status = "pass", score = 1.0)))
})

test_that("non_redundancy is not applicable to one construct", {
  t <- c2_bare(constructs = c2_two_constructs[1L])
  expect_identical(c2_item(t, "non_redundancy"), list(status = "n/a", score = NULL))
  # Shared vocabulary below the thresholds no longer costs points.
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_identical(c2_item(panic, "non_redundancy"), list(status = "pass", score = 1.0))
})

# -- causal_testability, formalisation and the relation table -----------------

test_that("causal_testability counts every directed relation", {
  cases <- c(mediates = "pass", moderates = "pass", causes = "pass", decreases = "pass",
             associates = "warn")
  for (rel in names(cases)) {
    t <- c2_bare(constructs = c2_two_constructs,
                 propositions = list(list(id = "p1", from = "c1", to = "c2", relation = rel)))
    expect_identical(c2_item(t, "causal_testability")$status, cases[[rel]], info = rel)
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
})

test_that("formalisation needs a recognised model type", {
  cases <- list(list(list(type = "banana"), "warn"), list(list(type = "none"), "warn"),
                list(list(type = ""), "warn"), list(list(), "warn"),
                list(list(type = "abm"), "pass"), list(list(type = "sem"), "pass"))
  for (cs in cases) {
    t <- c2_bare(formal_model = cs[[1]])
    expect_identical(c2_item(t, "formalisation")$status, cs[[2]],
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
    tf_embedding_redundancy(c2_bare(constructs = c2_two_constructs),
                            function(d) vectors[[d]])
  }, finally = assign("checklist", original, envir = cache))
  expect_identical(df$cosine, 0.6)
  expect_identical(df$flag, "review")
})

# -- what the renderers print -------------------------------------------------

test_that("the dossier gives coverage and names the failed blockers", {
  d <- tf_dossier(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_true(grepl(paste0("- Aggregate rigour score: 2.2/100\n- Checklist coverage: 0.92\n",
                           "- Gate: blocked\n",
                           "- Blockers failed: 2 (falsifiability, derivation_chain)\n"),
                    d, fixed = TRUE))
  expect_true(grepl("| parsimony | n/a | n/a | 0.08 |\n", d, fixed = TRUE))
  expect_true(grepl("| non_redundancy | warn | 0.0 | 0.1 |\n", d, fixed = TRUE))
})

test_that("the views and the HTML report show not-applicable items", {
  t <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  roadmap <- tf_diagram(t, "development_roadmap")
  expect_true(grepl("score 2.2, gate blocked", roadmap, fixed = TRUE))
  expect_false(grepl('"parsimony"', roadmap, fixed = TRUE))
  svg <- tf_diagram(t, "rigour")
  # parsimony is the fourth row, at y = 60 + 24 * 3.
  expect_true(grepl('<rect x="20" y="132" width="16" height="16" rx="3" fill="#9e9e9e"/>',
                    svg, fixed = TRUE))
  expect_true(grepl('<text x="320" y="144">n/a</text>', svg, fixed = TRUE))
  expect_true(grepl("<tr><td>parsimony</td><td>n/a</td><td>n/a</td>",
                    tf_report(t, "html"), fixed = TRUE))
})
