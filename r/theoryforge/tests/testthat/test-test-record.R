# The preregistration, the dossier and the diagrams report the test record
# (API_SPEC.md sections 11, 12 and 20). The Python suite (test_test_record.py)
# reads the same theories and asserts the same text, so the two twins are held
# to one wording.

tr_read <- function(text) {
  path <- tempfile(fileext = ".yaml")
  on.exit(unlink(path))
  writeBin(charToRaw(enc2utf8(text)), path)
  tf_read(path)
}

tr_implied <- paste0("## Implied conditional independencies (derived from the causal graph, ",
                     "not predictions)\n")

tr_panic_v2_prereg <- paste0(
  "# Preregistration: Network theory of panic disorder\n",
  "\n",
  "- Theory ID: panic-network-2026-v2\n",
  "- Version: v2 (parent v1)\n",
  "- Schema version: 1.0\n",
  "- Maturity: testing\n",
  "- Derivation references resolve: yes\n",
  "\n",
  "## Hypotheses\n",
  "1. [point] An interoceptive challenge raises heart rate 20 beats per minute above baseline, ",
  "within a measurement tolerance of 5, within 90 seconds. (derives from: p1, p3)\n",
  "   - Auxiliary assumptions: aux1 (core)\n",
  "   - Rivals it discriminates: alt_cognitive\n",
  "   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde)\n",
  "2. [interval] Avoidance frequency falls within a 20-35% band after exposure therapy. ",
  "(derives from: p2)\n",
  "   - Test record: untested\n",
  "3. [directional] Higher perceived threat is associated with more avoidance. ",
  "(derives from: p2)\n",
  "   - Test record: untested\n",
  "4. [point] Blocking interoceptive feedback lowers avoidance-task scores by 30 per cent, ",
  "within a tolerance of 5 percentage points, within two weeks. (derives from: p4)\n",
  "   - Rivals it discriminates: alt_cognitive\n",
  "   - Test record: already tested: passed (2026-06-10, registered osf.io/fghij)\n",
  "\n",
  tr_implied,
  "_Not derived: implications requires an acyclic causal graph; cycle found: ",
  "c_arousal -> c_perceived_threat -> c_arousal; set cycles to 'sigma' to derive ",
  "sigma-separation statements._\n",
  "\n",
  "## Severity (pre-data rubric of claim form)\n",
  "- pred1: severity 1.0, risk 0.9\n",
  "- pred2: severity 0.7, risk 0.7\n",
  "- pred3: severity 0.3, risk 0.4\n",
  "- pred4: severity 1.0, risk 0.9\n"
)

tr_empty_prereg <- paste0(
  "# Preregistration: No predictions\n",
  "\n",
  "- Theory ID: nopred\n",
  "- Schema version: 1.0\n",
  "- Maturity: building\n",
  "- Derivation references resolve: not applicable (no predictions)\n",
  "\n",
  "## Hypotheses\n",
  "_No predictions specified._\n",
  "\n",
  tr_implied,
  "_None: the theory states no directed relation between constructs._\n",
  "\n",
  "## Severity (pre-data rubric of claim form)\n",
  "_No predictions specified._\n"
)

# h1 passed and then failed a replication. h1_2 is the id that a "_2" suffix
# would have given h1's second outcome, and its one outcome records no result.
# The association of x with y leaves z and y joined by an inducing path, so no
# set of constructs separates them.
tr_replicated <- 'schema_version: "1.0"
id: replicated
title: A prediction that failed its replication
maturity: testing
constructs:
  - id: z
    label: Zeta
    definition: The first construct.
  - id: x
    label: Xi
    definition: The second construct.
  - id: y
    label: Upsilon
    definition: The third construct.
propositions:
  - id: p1
    from: z
    to: x
    relation: increases
  - id: p2
    from: x
    to: y
    relation: increases
  - id: p3
    from: x
    to: y
    relation: associates
predictions:
  - id: h1
    statement: Upsilon rises with Zeta.
    type: directional
    derives_from: [p1, p2]
    diagnostic_vs: [rival, rival, unknown]
  - id: h1_2
    statement: Upsilon rises with Xi.
    type: directional
    derives_from: [p2]
auxiliary_assumptions:
  - id: a1
    statement: Upsilon is measured at rest.
    added_for: ~
    protects: [h1, h1_2]
  - id: x1
    statement: The effect needs a calm setting.
    added_for: h1
    protects: [h1]
alternatives:
  - id: rival
    label: A rival account
test_outcomes:
  - prediction_id: h1
    passed: true
    date: "2026-05-01"
    registered: osf.io/abcde
  - prediction_id: h1
    passed: false
    date: "2026-06-10"
  - prediction_id: h1_2
    observed: The run was abandoned.
'

tr_replicated_hypotheses <- paste0(
  "## Hypotheses\n",
  "1. [directional] Upsilon rises with Zeta. (derives from: p1, p2)\n",
  "   - Auxiliary assumptions: a1 (core), x1 (added for h1)\n",
  "   - Rivals it discriminates: rival\n",
  "   - Test record: already tested: passed (2026-05-01, registered osf.io/abcde); ",
  "failed (2026-06-10)\n",
  "2. [directional] Upsilon rises with Xi. (derives from: p2)\n",
  "   - Auxiliary assumptions: a1 (core)\n",
  "   - Test record: already tested: no result recorded\n",
  "\n",
  tr_implied,
  "_None: no set of constructs separates any pair the theory leaves unjoined._\n"
)

tr_count <- function(pattern, text) {
  lengths(regmatches(text, gregexpr(pattern, text, fixed = TRUE)))
}

test_that("the derivation line says whether the references resolve", {
  # The checklist item checks only that each prediction cites declared
  # propositions, so the line no longer says that a derivation was verified.
  panic <- tf_preregister(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  weak <- tf_preregister(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_true(grepl("\n- Derivation references resolve: yes\n", panic, fixed = TRUE))
  expect_true(grepl("\n- Derivation references resolve: no\n", weak, fixed = TRUE))
  expect_false(grepl("Derivation chain verified", panic, fixed = TRUE))
})

test_that("an empty theory has no derivation to resolve", {
  expect_identical(tf_preregister(tf_theory("nopred", "No predictions")), tr_empty_prereg)
})

test_that("the amended example states its version and its test record", {
  # Both hypotheses of v2 that a registered test corroborated are marked as
  # already tested, where they read as fresh hypotheses.
  v2 <- tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml"))
  expect_identical(tf_preregister(v2), tr_panic_v2_prereg)
})

test_that("the version line needs an id and names a parent only when there is one", {
  panic <- tf_preregister(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_true(grepl("\n- Theory ID: panic-network-2026\n- Version: v1\n- Schema version: 1.0\n",
                    panic, fixed = TRUE))
  weak <- tf_preregister(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_false(grepl("- Version:", weak, fixed = TRUE))
  head <- 'schema_version: "1.0"\nid: t\ntitle: T\nmaturity: building\n'
  numeric <- tr_read(paste0(head, "version:\n  id: 2\n  parent_id: 1\n"))
  expect_false(grepl("- Version:", tf_preregister(numeric), fixed = TRUE))
  blank_parent <- tr_read(paste0(head, 'version:\n  id: v3\n  parent_id: "  "\n'))
  expect_true(grepl("\n- Version: v3\n", tf_preregister(blank_parent), fixed = TRUE))
})

test_that("each hypothesis lists its auxiliaries, rivals and test record", {
  # A rival named twice is listed once, and a name that no registered
  # alternative carries is left out. Every outcome of a prediction is listed,
  # in file order, the one without a result included.
  text <- tf_preregister(tr_read(tr_replicated))
  expect_true(grepl(tr_replicated_hypotheses, text, fixed = TRUE))
  expect_true(endsWith(text, paste0("## Severity (pre-data rubric of claim form)\n",
                                    "- h1: severity 0.4, risk 0.4\n",
                                    "- h1_2: severity 0.3, risk 0.4\n")))
})

test_that("a hypothesis numbered ten indents its lines under its number", {
  # Markdown nests a line under a numbered item only when it is indented by the
  # width of the number and its full stop and space.
  t <- tf_theory("ten", "Ten predictions")
  for (i in 1:10) {
    t <- tf_add_prediction(t, paste0("h", i), paste0("Claim ", i, "."), "directional")
  }
  text <- tf_preregister(t)
  expect_true(grepl("\n9. [directional] Claim 9. (derives from: \u2014)\n   - Test record: untested\n",
                    text, fixed = TRUE))
  expect_true(grepl(paste0("\n10. [directional] Claim 10. (derives from: \u2014)\n",
                           "    - Test record: untested\n"), text, fixed = TRUE))
})

test_that("the implied independencies are listed as code", {
  # A code span keeps dagitty's notation, which Markdown would otherwise read as
  # emphasis around the two bars.
  text <- tf_preregister(tf_read(tf_fixture_path("modality-switching.theory.yaml")))
  expect_true(grepl(paste0(
    tr_implied,
    "- `c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation`\n",
    "- `c_sensorimotor_experience _||_ c_conceptual_access | c_modality_activation, ",
    "c_lexical_familiarity`\n",
    "- `c_sensorimotor_experience _||_ c_lexical_familiarity`\n",
    "- `c_modality_activation _||_ c_lexical_familiarity | c_sensorimotor_experience`\n",
    "- `c_switch_cost _||_ c_conceptual_access | c_modality_activation, c_lexical_familiarity`\n",
    "- `c_switch_cost _||_ c_lexical_familiarity | c_modality_activation`\n",
    "\n## Severity"
  ), text, fixed = TRUE))
})

test_that("the implied independencies say why there are none", {
  # The default refuses a cyclic graph, and the refusal is reported in place.
  panic <- tf_preregister(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_true(grepl(paste0(
    tr_implied,
    "_Not derived: implications requires an acyclic causal graph; cycle found: ",
    "c_arousal -> c_perceived_threat -> c_arousal; set cycles to 'sigma' to derive ",
    "sigma-separation statements._\n"
  ), panic, fixed = TRUE))
  weak <- tf_preregister(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_true(grepl(paste0(tr_implied,
                           "_None: the theory states no directed relation between constructs._\n"),
                    weak, fixed = TRUE))
  pair <- tf_theory("pair", "Two constructs") |>
    tf_add_construct("a", "Alpha", "The first construct.") |>
    tf_add_construct("b", "Beta", "The second construct.") |>
    tf_add_proposition("p1", "a", "b", "increases")
  expect_true(grepl(paste0(tr_implied,
                           "_None: every pair of constructs in the causal graph is adjacent._\n"),
                    tf_preregister(pair), fixed = TRUE))
})

test_that("every refusal of the implications is reported in place", {
  # Python reports the ValueError of a refusal and R the error whose message
  # opens with "implications requires", so the two must meet every refusal.
  dup <- tf_theory("dup", "A repeated construct id") |>
    tf_add_construct("a", "Alpha", "The first construct.") |>
    tf_add_construct("a", "Alpha again", "The same id.") |>
    tf_add_construct("b", "Beta", "The second construct.") |>
    tf_add_proposition("p1", "a", "b", "increases")
  expect_true(grepl(paste0(
    tr_implied,
    "_Not derived: implications requires unique construct ids; duplicate construct id: a._\n"
  ), tf_preregister(dup), fixed = TRUE))
  stray <- tf_theory("stray", "An undeclared construct") |>
    tf_add_construct("a", "Alpha", "The first construct.") |>
    tf_add_proposition("p1", "a", "zz", "causes")
  expect_true(grepl(paste0(
    tr_implied,
    "_Not derived: implications requires causal propositions between declared constructs; ",
    "proposition 'p1' refers to unknown construct 'zz'._\n"
  ), tf_preregister(stray), fixed = TRUE))
})

test_that("the dossier adds the test record and the evidence", {
  d <- tf_dossier(tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml")))
  expect_true(grepl(paste0(
    "- pred4: severity 1.0, risk 0.9, declared 0.75\n",
    "\n## Test record\n\n",
    "- pred1: passed; observed: Arousal reached the predicted band in 78% of trials.; ",
    "date: 2026-05-01; registered: osf.io/abcde\n",
    "- pred4: passed; observed: Avoidance dropped into the predicted band in 71% of cases.; ",
    "date: 2026-06-10; registered: osf.io/fghij\n",
    "\n## Evidence\n\n",
    "- supports pred4: corroborates; doi: 10.1000/example.v2\n",
    "\n## Provenance\n"
  ), d, fixed = TRUE))
  # The dossier embeds the preregistration, which holds the independencies, so
  # they appear once.
  expect_identical(tr_count(tr_implied, d), 1L)
})

test_that("the dossier lists every outcome and marks empty records", {
  d <- tf_dossier(tr_read(tr_replicated))
  expect_true(grepl(paste0(
    "\n## Test record\n\n",
    "- h1: passed; date: 2026-05-01; registered: osf.io/abcde\n",
    "- h1: failed; date: 2026-06-10\n",
    "- h1_2: no result recorded; observed: The run was abandoned.\n",
    "\n## Evidence\n\n_No evidence recorded._\n"
  ), d, fixed = TRUE))
  weak <- tf_dossier(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_true(grepl(paste0("\n## Test record\n\n_No test outcomes recorded._\n",
                           "\n## Evidence\n\n_No evidence recorded._\n"), weak, fixed = TRUE))
})

tr_evidence <- 'schema_version: "1.0"
id: ev
title: Evidence with and without a DOI
maturity: building
evidence:
  - supports: h1
    direction: refutes
    source_doi: ~
  - supports: h1
    direction: confirms
    source_doi: "10.1000/xyz"
'

test_that("an evidence line gives a DOI only when there is one", {
  # A direction outside the schema's three prints as nothing, as every lenient
  # reader prints an enum it does not know.
  d <- tf_dossier(tr_read(tr_evidence))
  expect_true(grepl(paste0("\n## Evidence\n\n",
                           "- supports h1: refutes\n",
                           "- supports h1: ; doi: 10.1000/xyz\n",
                           "\n## Provenance\n"), d, fixed = TRUE))
})

test_that("a replicated prediction has a node for each outcome", {
  # Graphviz merged a node declared twice, so the figure showed only the last
  # result. The second outcome of h1 takes "#2", which no sibling id such as
  # h1_2 can produce, and each repeat carries its date.
  t <- tr_read(tr_replicated)
  pipe <- tf_diagram(t, "pipeline")
  expect_true(grepl(paste0(
    '  "result_h1" [label="passed\\n2026-05-01", fillcolor="#E5F2E7", color="#3E7A46"];\n',
    '  "h1" -> "result_h1";\n',
    '  "result_h1#2" [label="failed\\n2026-06-10", fillcolor="#F9E5E4", color="#B2453C"];\n',
    '  "h1" -> "result_h1#2";\n',
    '  "result_h1_2" [label="'
  ), pipe, fixed = TRUE))
  expect_identical(tr_count('"result_h1_2" [', pipe), 1L)
  expect_true(endsWith(pipe, '  "h1_2" -> "result_h1_2";\n}\n'))
  flow <- tf_diagram(t, "workflow")
  expect_true(grepl(paste0(
    '    "outcome_h1" [label="h1\\npassed\\n2026-05-01", fillcolor="#E5F2E7", color="#3E7A46"];\n',
    '    "outcome_h1#2" [label="h1\\nfailed\\n2026-06-10", fillcolor="#F9E5E4", color="#B2453C"];\n',
    '    "outcome_h1_2" [label="h1_2\\n'
  ), flow, fixed = TRUE))
  expect_identical(tr_count('"outcome_h1_2" [', flow), 1L)
  expect_true(endsWith(flow, paste0('  "pred_h1" -> "outcome_h1";\n',
                                    '  "pred_h1" -> "outcome_h1#2";\n',
                                    '  "pred_h1_2" -> "outcome_h1_2";\n',
                                    "}\n")))
})

test_that("a prediction tested once keeps its node and label", {
  # The date is given only to tell the outcomes of one prediction apart.
  v2 <- tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml"))
  expect_true(grepl('  "result_pred1" [label="passed", fillcolor="#E5F2E7", color="#3E7A46"];\n',
                    tf_diagram(v2, "pipeline"), fixed = TRUE))
  expect_true(grepl('    "outcome_pred4" [label="pred4\\npassed", fillcolor="#E5F2E7", color="#3E7A46"];\n',
                    tf_diagram(v2, "workflow"), fixed = TRUE))
})
