# Byte-identical diagram parity against every golden file.

test_that("diagram IR is byte-identical to the golden files", {
  cases <- list(
    list(fixture = "panic-network.theory.yaml", id = "panic-network-2026"),
    list(fixture = "weak-theory.theory.yaml", id = "weak-demo")
  )
  types <- list(
    nomological_net = "nomological_net.dot",
    provenance      = "provenance.dot",
    causal_dag      = "causal_dag.dag"
  )
  for (cs in cases) {
    theory <- tf_read(tf_fixture_path(cs$fixture))
    for (type in names(types)) {
      got <- tf_diagram(theory, type)
      golden_file <- tf_expected_path(paste0(cs$id, ".", types[[type]]))
      golden <- tf_read_golden(golden_file)
      expect_identical(got, golden,
                       info = paste(cs$id, type, sep = "/"))
    }
  }
})

test_that("new diagram types are byte-identical to the golden files", {
  cases <- list(
    list(fixture = "panic-network.theory.yaml", id = "panic-network-2026"),
    list(fixture = "panic-network-2026-v2.theory.yaml", id = "panic-network-2026-v2"),
    list(fixture = "weak-theory.theory.yaml", id = "weak-demo")
  )
  types <- list(
    development_roadmap = "development_roadmap.dot",
    pipeline            = "pipeline.dot",
    context             = "context.dot",
    workflow            = "workflow.dot",
    venn                = "venn.svg",
    rigour              = "rigour.svg",
    severity            = "severity.svg"
  )
  for (cs in cases) {
    theory <- tf_read(tf_fixture_path(cs$fixture))
    for (type in names(types)) {
      got <- tf_diagram(theory, type)
      golden <- tf_read_golden(tf_expected_path(paste0(cs$id, ".", types[[type]])))
      expect_identical(got, golden, info = paste(cs$id, type, sep = "/"))
    }
  }
})

test_that("development_roadmap collapses to a single node when all checks pass", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- tf_diagram(theory, "development_roadmap")
  expect_true(grepl('label="Network theory of\\npanic disorder\\nscore 87.3, gate pass"',
                    out, fixed = TRUE))
  expect_true(grepl('"all_checks_pass" [label="all checks pass", fillcolor="#E5F2E7", color="#3E7A46"];',
                    out, fixed = TRUE))
  expect_true(grepl('"roadmap" -> "all_checks_pass";', out, fixed = TRUE))
})

test_that("development_roadmap leads on blockers and rows up the advisories", {
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  out <- tf_diagram(theory, "development_roadmap")
  # The failed blocker is step 1 and says what it costs.
  expect_true(grepl(paste0('"falsifiability" [label="1. falsifiability\\nAt least one\\n',
                           'prediction forbids an\\nobservation\\nblocks the gate", ',
                           'fillcolor="#F9E5E4"'),
                    out, fixed = TRUE))
  expect_true(grepl('"roadmap" -> "falsifiability";', out, fixed = TRUE))
  # Advisories follow, pinned three to a row. parsimony has nothing to assess
  # and is left out.
  expect_true(grepl('{ rank=same; "precision" -> "risk_severity" -> "non_redundancy" [style=invis]; }',
                    out, fixed = TRUE))
  expect_false(grepl('"parsimony"', out, fixed = TRUE))
})

test_that("the severity chart is titled for what its bars rank", {
  # The bars rank the form of each claim before any data and do not measure
  # how severely a claim was tested.
  svg <- tf_diagram(tf_read(tf_fixture_path("panic-network.theory.yaml")), "severity")
  expect_true(grepl('<text x="20" y="26" font-size="15">Pre-data riskiness</text>',
                    svg, fixed = TRUE))
  expect_false(grepl("Prediction severity", svg, fixed = TRUE))
})

test_that("the nomological net draws an association without arrowheads", {
  # An association states covariance with no direction (API_SPEC.md section
  # 28), so its edge has no arrowhead. A directed relation keeps its arrow.
  dot <- tf_diagram(tf_read(tf_fixture_path("weak-theory.theory.yaml")), "nomological_net")
  expect_true(grepl('  "k_motivation" -> "k_drive" [label="associates", dir=none];', dot,
                    fixed = TRUE))
  dot <- tf_diagram(tf_read(tf_fixture_path("panic-network.theory.yaml")), "nomological_net")
  expect_true(grepl('  "c_arousal" -> "c_perceived_threat" [label="increases"];', dot,
                    fixed = TRUE))
})

test_that("causal_dag exports the graph tf_implications() reads", {
  # Every directed relation is an edge, and an association between two
  # constructs that a directed relation names is a bidirected edge (API_SPEC.md
  # sections 5 and 27). An association touching any other construct, or joining
  # a construct to itself, is left out, as tf_implications() leaves it out.
  theory <- tf_theory("mixed", "Mixed relations")
  for (n in c("a", "b", "c", "d", "k")) theory <- tf_add_construct(theory, n, toupper(n), "d")
  theory <- theory |>
    tf_add_proposition("p1", "a", "b", "mediates") |>
    tf_add_proposition("p2", "c", "b", "moderates") |>
    tf_add_proposition("p3", "a", "c", "associates") |>
    tf_add_proposition("p4", "k", "a", "associates") |>
    tf_add_proposition("p5", "b", "d", "decreases") |>
    tf_add_proposition("p6", "d", "d", "associates")
  expect_identical(tf_diagram(theory, "causal_dag"),
                   "dag {\n  a -> b\n  c -> b\n  a <-> c\n  b -> d\n}\n")
})

test_that("tf_diagram rejects unknown types", {
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  expect_error(tf_diagram(theory, "mindmap"), "unknown diagram type")
})

test_that("DOT labels escape backslash then double-quote, then wrap", {
  theory <- list(constructs = list(
    list(id = "x", label = 'a "quoted" \\ slash', definition = "d")
  ))
  out <- tf_diagram(theory, "nomological_net")
  # Escaped first (backslashes double, quotes gain a backslash), wrapped
  # second: the escaped text passes the 18-character line width, so "slash"
  # moves to a new DOT label line (a literal backslash-n).
  expect_true(grepl('label="a \\"quoted\\" \\\\\\nslash"', out, fixed = TRUE))
})
