# The dossier (API_SPEC.md section 20): byte-identical to goldens.

test_that("tf_dossier includes the expected header, table row, and prereg", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- tf_dossier(panic)
  expect_true(grepl("# theoryforge dossier: Network theory of panic disorder",
                    out, fixed = TRUE))
  expect_true(grepl(paste0("- Checklist score: 88.0 (84.2 to 90.2 with equal weights or one ",
                           "weight halved or doubled)\n- Checklist coverage: 0.92\n"),
                    out, fixed = TRUE))
  # The two items whose failure blocks the gate are marked, and no other.
  expect_true(grepl(paste0("| falsifiability (blocker) | At least one prediction is typed ",
                           "point, interval or directional; the label is the author's | pass | ",
                           "1.0 | 0.15 |"), out, fixed = TRUE))
  expect_true(grepl("\n| derivation_chain (blocker) | ", out, fixed = TRUE))
  expect_identical(lengths(regmatches(out, gregexpr(" (blocker) | ", out, fixed = TRUE))), 2L)
  # The preregistration sits a level below the dossier's heading, and its
  # sections a level below its title.
  expect_true(grepl(paste0("\n## Preregistration\n\n### Preregistration: Network theory of ",
                           "panic disorder\n"), out, fixed = TRUE))
  expect_true(grepl("\n#### Theory\n\n##### Constructs\n", out, fixed = TRUE))
  expect_true(grepl("\n#### Hypotheses\n", out, fixed = TRUE))
})

test_that("tf_dossier emits the table header and one row per checklist item", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- tf_dossier(panic)
  expect_true(grepl("| item | criterion | status | score | weight |", out, fixed = TRUE))
  expect_true(grepl("| --- | --- | --- | --- | --- |", out, fixed = TRUE))
  rep <- tf_check(panic)
  criteria <- vapply(tf_checklist()$items, function(i) i$criterion, "")
  names(criteria) <- vapply(tf_checklist()$items, function(i) i$id, "")
  for (it in rep$items) {
    mark <- if (identical(it$severity_if_fail, "blocker")) " (blocker)" else ""
    row <- sprintf("| %s%s | %s | %s | %s | %s |",
                   it$id, mark, criteria[[it$id]], it$status,
                   theoryforge:::.tf_fmt(it$score),
                   theoryforge:::.tf_fmt(it$weight))
    expect_true(grepl(row, out, fixed = TRUE), info = it$id)
  }
})

test_that("tf_dossier reflects severity and provenance placeholders", {
  weak <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  out <- tf_dossier(weak)
  expect_true(grepl("- w1: severity 0.1, risk 0.1", out, fixed = TRUE))
  expect_true(grepl("_No provenance recorded._", out, fixed = TRUE))
  expect_true(grepl("Gate: blocked", out, fixed = TRUE))
})

test_that("tf_dossier names the rubric for what it is", {
  # Once in the dossier's own severity list and once, a level down, in the
  # preregistration appended to it.
  out <- tf_dossier(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  heading <- "\n## Severity (pre-data rubric of claim form)\n"
  expect_identical(lengths(regmatches(out, gregexpr(heading, out, fixed = TRUE))), 1L)
  # The embedded preregistration leaves its own severity list out.
  expect_false(grepl("\n### Severity", out, fixed = TRUE))
  expect_false(grepl("\n## Severity\n", out, fixed = TRUE))
  expect_true(grepl("- pred1: severity 1.0, risk 0.9", out, fixed = TRUE))
})

test_that("tf_dossier output ends with a single trailing newline (LF)", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- tf_dossier(panic)
  expect_false(grepl("\r", out, fixed = TRUE))
  expect_true(endsWith(out, "\n"))
  expect_false(endsWith(out, "\n\n"))
})

test_that("tf_dossier is byte-identical to the golden markdown files", {
  cases <- list(
    list(fixture = "panic-network.theory.yaml", id = "panic-network-2026"),
    list(fixture = "panic-network-2026-v2.theory.yaml", id = "panic-network-2026-v2"),
    list(fixture = "weak-theory.theory.yaml", id = "weak-demo")
  )
  for (cs in cases) {
    theory <- tf_read(tf_fixture_path(cs$fixture))
    got <- tf_dossier(theory)
    golden <- tf_read_golden(tf_expected_path(paste0(cs$id, ".dossier.md")))
    expect_identical(got, golden, info = cs$id)
  }
})

# What the dossier says it is (API_SPEC.md section 20). The Python suite
# (test_sem_and_dossier.py) asserts the same text.

ds_gate <- paste0(
  "The gate reports whether either blocking item failed: at least one prediction is typed ",
  "point, interval or directional, and every prediction cites declared propositions whose ",
  "graph entails any claim it states, with no stated phenomenon contradicted. Under the ",
  "default reading of feedback loops, a claim that names a construct on a loop or downstream ",
  "of one is not read and blocks nothing. The labels are the author's and are not checked ",
  "against the statements. ")

ds_preamble_end <- paste0(
  "Test outcomes, evidence, registrations and declared severities are as the author recorded ",
  "them. The dossier flags a recorded pass whose estimate lies outside its claimed region, a ",
  "recorded failure whose estimate lies inside it and a declared severity more than 0.2 above ",
  "the rubric, and checks nothing else that the author entered. It is not an independent ",
  "audit._\n")

test_that("the dossier names the checklist score and says what it is", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  d <- tf_dossier(panic)
  rep <- tf_check(panic)
  expect_true(grepl(paste0("\n- Blockers failed: 0\n- Feedback loops: refused (a claim that names ",
                           "a construct on a loop or downstream of one is not read)\n\n",
                           "_Generated by theoryforge from the file ",
                           "with the content hash above. The checklist score describes how ",
                           "completely the file states what checklist ", rep$checklist_version,
                           " asks for."), d, fixed = TRUE))
  # What the gate checks follows what the score describes, and the margin of
  # the severity note is the one the note uses.
  expect_true(grepl(paste0("is true or well reasoned. ", ds_gate, ds_preamble_end,
                           "\n## Checklist\n\n| item |"), d, fixed = TRUE))
  expect_false(grepl("rigour", tolower(d), fixed = TRUE))
  expect_false(grepl("/100", d, fixed = TRUE))
  expect_true(grepl("\n## Equivalent models (observational data)\n\n", d, fixed = TRUE))
})

test_that("the dossier reads the checklist with its own cycles", {
  # Under sigma, the loop no longer leaves pred_indep unread, so the derivation
  # chain passes, and the score is that of tf_check(cycles = "sigma"). A claim
  # not checked costs nothing, so the two scores are equal and the derivation
  # line tells the readings apart.
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  answers <- c(refuse = 'not checked (feedback loop; use cycles = "sigma")', sigma = "yes")
  for (cycles in c("refuse", "sigma")) {
    rep <- tf_check(panic, cycles = cycles)
    line <- sprintf("\n- Checklist score: %s (%s to %s with equal weights or one weight halved or doubled)\n",
                    theoryforge:::.tf_fmt(rep$aggregate_score),
                    theoryforge:::.tf_fmt(rep$aggregate_range[[1]]),
                    theoryforge:::.tf_fmt(rep$aggregate_range[[2]]))
    d <- tf_dossier(panic, cycles = cycles)
    expect_true(grepl(line, d, fixed = TRUE), info = cycles)
    expect_true(grepl(paste0("contradicts no claim a phenomenon states: ", answers[[cycles]], "\n"),
                      d, fixed = TRUE), info = cycles)
  }
})

test_that("the dossier flags a failure whose estimate lies inside the region", {
  # pred1 claims a value in [15, 25]. A failure with the estimate inside the
  # region, at a bound included, is noted as a pass outside it is. A failure
  # outside the region and a pass inside it carry no note.
  t <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  inside <- "; recorded as failed, with the estimate inside that region\n"
  for (est in c(20, 25)) {
    t$test_outcomes <- list(list(prediction_id = "pred1", passed = FALSE, estimate = est, se = 6))
    expect_true(grepl(inside, tf_dossier(t), fixed = TRUE), info = est)
  }
  t$test_outcomes <- list(list(prediction_id = "pred1", passed = FALSE, estimate = 20, se = 6))
  expect_true(grepl(paste0("- pred1: failed; post-data severity 0.798 for [15, 25]", inside),
                    tf_dossier(t), fixed = TRUE))
  t$test_outcomes <- list(list(prediction_id = "pred1", passed = FALSE, estimate = 26, se = 2))
  expect_true(grepl("post-data severity 0.309 for [15, 25]\n", tf_dossier(t), fixed = TRUE))
  t$test_outcomes <- list(list(prediction_id = "pred1", passed = TRUE, estimate = 20, se = 6))
  expect_true(grepl("post-data severity 0.798 for [15, 25]\n", tf_dossier(t), fixed = TRUE))
  # An outcome without a result is not flagged either way.
  t$test_outcomes <- list(list(prediction_id = "pred1", estimate = 20, se = 6))
  expect_true(grepl("- pred1: no result recorded; post-data severity 0.798 for [15, 25]\n",
                    tf_dossier(t), fixed = TRUE))
})

ds_assumptions <- paste0(
  "_The verdicts on the claims assume that the graph of the propositions is the causal structure, ",
  "with no omitted common cause of two of its constructs, that each directed relation acts in ",
  "its stated direction whatever the other inputs (as in a linear model or a uniformly monotone ",
  "one), that effects do not cancel exactly where a verdict says 'unless effects cancel exactly' ",
  "(faithfulness) and, for feedback loops read by sigma-separation, that each loop settles to a ",
  "unique equilibrium, also once the intervened construct is held fixed._\n")

# x raises y through m1 and lowers it through m2, so the sign of the effect is
# open, and a claimed zero is contradicted only if the two paths do not cancel
# exactly.
ds_offsetting <- function(sign) {
  t <- tf_theory("offset", "Offsetting paths") |>
    tf_add_construct("x", "X", "The cause.") |>
    tf_add_construct("m1", "M1", "The first mediator.") |>
    tf_add_construct("m2", "M2", "The second mediator.") |>
    tf_add_construct("y", "Y", "The outcome.") |>
    tf_add_proposition("p1", "x", "m1", "increases") |>
    tf_add_proposition("p2", "m1", "y", "increases") |>
    tf_add_proposition("p3", "x", "m2", "increases") |>
    tf_add_proposition("p4", "m2", "y", "decreases") |>
    tf_add_prediction("h1", "The paths offset.", "directional",
                      derives_from = c("p1", "p2", "p3", "p4"))
  t$predictions[[1]]$claim <- list(kind = "effect", x = "x", y = "y", sign = sign)
  t
}

test_that("the claim lines say when a verdict rests on faithfulness", {
  zero <- ds_offsetting("zero")
  line <- paste0("the effect of x on y is zero; contradicted by the causal graph, unless effects ",
                 "cancel exactly")
  expect_true(grepl(paste0("- h1 (prediction): ", line, "\n"), tf_dossier(zero), fixed = TRUE))
  expect_true(grepl(paste0("   - Claim: ", line, "\n"), tf_preregister(zero), fixed = TRUE))
  expect_true(grepl(paste0("   - Claim: the effect of x on y is not zero; entailed by the causal ",
                           "graph through p1, p2, p3, p4, unless effects cancel exactly\n"),
                    tf_preregister(ds_offsetting("nonzero")), fixed = TRUE))
  # A verdict that rests on paths of one sign says nothing of cancellation.
  expect_false(grepl("cancel exactly\n", tf_preregister(ds_offsetting("positive")), fixed = TRUE))
})

test_that("one unsigned route rests on effects not cancelling", {
  # One causes relation is the only route, so there are no paths to offset,
  # but an effect of no fixed sign can still cancel itself in a nonlinear
  # model, and the clause names effects.
  t <- tf_theory("one", "One edge") |>
    tf_add_construct("a", "A", "The cause.") |>
    tf_add_construct("b", "B", "The outcome.") |>
    tf_add_proposition("p1", "a", "b", "causes") |>
    tf_add_prediction("h", "A affects B.", "existence", derives_from = "p1")
  t$predictions[[1]]$claim <- list(kind = "effect", x = "a", y = "b", sign = "nonzero")
  expect_true(grepl(paste0("   - Claim: the effect of a on b is not zero; entailed by the causal ",
                           "graph through p1, unless effects cancel exactly\n"),
                    tf_preregister(t), fixed = TRUE))
  expect_false(grepl("paths cancel", paste0(tf_preregister(t), tf_dossier(t)), fixed = TRUE))
})

# How the documents read a feedback loop (API_SPEC.md sections 11 and 20).
ds_refused <- paste0("- Feedback loops: refused (a claim that names a construct on a loop or ",
                     "downstream of one is not read)")
ds_sigma <- paste0("- Feedback loops: read by sigma-separation (each loop is assumed to settle ",
                   "to a unique equilibrium)")
ds_count <- function(x, s) lengths(regmatches(x, gregexpr(s, x, fixed = TRUE)))

test_that("the documents name their reading of a feedback loop", {
  t <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  cases <- list(list("refuse", 'not checked (feedback loop; use cycles = "sigma")', ds_refused),
                list("sigma", "yes", ds_sigma))
  for (cs in cases) {
    pre <- tf_preregister(t, cycles = cs[[1]])
    dos <- tf_dossier(t, cycles = cs[[1]])
    # The line closes the header of each document, after the derivation line
    # in the preregistration, and the dossier's embedded preregistration
    # repeats it in its own header.
    expect_true(grepl(paste0("contradicts no claim a phenomenon states: ", cs[[2]], "\n", cs[[3]],
                             "\n\n_Generated by theoryforge from the theory file."), pre,
                      fixed = TRUE))
    expect_identical(ds_count(pre, cs[[3]]), 1L)
    expect_true(grepl(paste0("\n- Blockers failed: 0\n", cs[[3]], "\n\n_Generated by theoryforge"),
                      dos, fixed = TRUE))
    expect_identical(ds_count(dos, cs[[3]]), 2L)
  }
  expect_false(grepl(ds_refused, tf_dossier(t, cycles = "sigma"), fixed = TRUE))
  expect_false(grepl(ds_sigma, tf_dossier(t), fixed = TRUE))
})

test_that("a graph without a loop gets no feedback line", {
  t <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  for (cy in c("refuse", "sigma")) {
    expect_false(grepl("Feedback loops", paste0(tf_preregister(t, cycles = cy),
                                                tf_dossier(t, cycles = cy)), fixed = TRUE))
  }
})

test_that("a proposition from a construct to itself is a loop", {
  t <- tf_theory("self", "Self loop") |>
    tf_add_construct("a", "A", "A construct.") |>
    tf_add_construct("b", "B", "Another.") |>
    tf_add_proposition("p1", "a", "a", "increases") |>
    tf_add_proposition("p2", "a", "b", "increases")
  expect_true(grepl(ds_refused, tf_preregister(t), fixed = TRUE))
  expect_true(grepl(ds_sigma, tf_dossier(t, cycles = "sigma"), fixed = TRUE))
})

test_that("a graph that cannot be built gets no feedback line", {
  # A loop between a and b beside a relation to an undeclared construct: the
  # graph is refused, no claim is read against it, and the line is left out.
  t <- tf_theory("broken", "Broken graph") |>
    tf_add_construct("a", "A", "A construct.") |>
    tf_add_construct("b", "B", "Another.") |>
    tf_add_proposition("p1", "a", "b", "increases") |>
    tf_add_proposition("p2", "b", "a", "increases") |>
    tf_add_proposition("p3", "a", "c_typo", "increases")
  for (cy in c("refuse", "sigma")) {
    expect_false(grepl("Feedback loops", paste0(tf_preregister(t, cycles = cy),
                                                tf_dossier(t, cycles = cy)), fixed = TRUE))
  }
})

test_that("the dossier flags a declared severity only beyond the margin", {
  # The preamble names the margin the severity note applies: 0.1 above the
  # rubric is not flagged, 0.3 above is.
  t <- tf_theory("flags", "Flags") |>
    tf_add_construct("a", "A", "A construct.") |>
    tf_add_construct("b", "B", "Another.") |>
    tf_add_proposition("p1", "a", "b", "increases") |>
    tf_add_prediction("h1", "B rises by 0.2 to 0.4.", "interval", derives_from = "p1",
                      bounds = list(lower = 0.2, upper = 0.4), severity = 0.8) |>
    tf_add_prediction("h2", "B rises by 0.1 to 0.5.", "interval", derives_from = "p1",
                      bounds = list(lower = 0.1, upper = 0.5), severity = 1.0)
  d <- tf_dossier(t)
  expect_true(grepl("a declared severity more than 0.2 above the rubric, and checks nothing else",
                    d, fixed = TRUE))
  expect_true(grepl("- h1: severity 0.7, risk 0.7, declared 0.8\n", d, fixed = TRUE))
  expect_true(grepl(paste0("- h2: severity 0.7, risk 0.7, declared 1.0 (declared exceeds the ",
                           "rubric by more than 0.2)\n"), d, fixed = TRUE))
})

test_that("the documents name the assumptions of the verdicts once", {
  t <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  pre <- tf_preregister(t)
  dos <- tf_dossier(t)
  count <- function(x) lengths(regmatches(x, gregexpr(ds_assumptions, x, fixed = TRUE)))
  expect_identical(count(pre), 1L)
  expect_true(grepl(paste0("\n## Hypotheses\n", ds_assumptions, "\n1. [directional]"), pre,
                    fixed = TRUE))
  expect_true(grepl(paste0("\n## Claims and the causal graph\n\n", ds_assumptions,
                           "\n- pred1 (prediction):"), dos, fixed = TRUE))
  # Once in the dossier's claims section and once in its preregistration.
  expect_identical(count(dos), 2L)
  # A theory that states no claim has no verdicts to qualify.
  bare <- tf_theory("bare", "No claims")
  expect_false(grepl("The verdicts on the claims", paste0(tf_preregister(bare), tf_dossier(bare)),
                     fixed = TRUE))
})
