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
    venn                = "venn.svg"
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
  expect_true(grepl('"all_checks_pass" [label="all checks pass"];', out, fixed = TRUE))
})

test_that("tf_diagram rejects unknown types", {
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  expect_error(tf_diagram(theory, "mindmap"), "unknown diagram type")
})

test_that("DOT labels escape backslash then double-quote", {
  theory <- list(constructs = list(
    list(id = "x", label = 'a "quoted" \\ slash', definition = "d")
  ))
  out <- tf_diagram(theory, "nomological_net")
  expect_true(grepl('label="a \\"quoted\\" \\\\ slash"', out, fixed = TRUE))
})
