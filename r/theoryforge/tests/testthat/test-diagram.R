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
  expect_true(grepl('label="Network theory of\\npanic disorder\\nscore 88.0, gate pass"',
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
  expect_true(grepl('  "k_motivation" -> "k_drive" [label="q1: associates", dir=none];', dot,
                    fixed = TRUE))
  dot <- tf_diagram(tf_read(tf_fixture_path("panic-network.theory.yaml")), "nomological_net")
  expect_true(grepl('  "c_arousal" -> "c_perceived_threat" [label="p1: increases"];', dot,
                    fixed = TRUE))
})

test_that("the nomological net names the proposition of each edge", {
  # The ids a hypothesis derives from in the preregistration can then be found
  # on the figure.
  dot <- tf_diagram(tf_read(tf_fixture_path("panic-network.theory.yaml")), "nomological_net")
  expect_true(grepl('  "c_perceived_threat" -> "c_arousal" [label="p3: causes"];', dot,
                    fixed = TRUE))
})

test_that("labels keep a trailing space", {
  # strsplit() dropped the empty field after a final space, which Python's
  # str.split(" ") keeps, so the twins' DOT differed by a space. The Python
  # suite asserts the same lines.
  theory <- list(
    title = "Text that ends in spaces   ",
    boundary_conditions = list("adults  "),
    constructs = list(list(id = "c1", label = "Physiological arousal  ", definition = "d")),
    provenance = list(list(step = "1", action = "tf_construct", detail = "Two constructs added.  "))
  )
  context <- tf_diagram(theory, "context")
  expect_true(grepl('  "theory" [shape=ellipse, label="Text that ends in\\nspaces   ", ',
                    context, fixed = TRUE))
  expect_true(grepl('  "c1" [label="Physiological\\narousal  ", ', context, fixed = TRUE))
  expect_true(grepl('  "scope1" [shape=note, style="filled", label="adults  ", ', context,
                    fixed = TRUE))
  expect_true(grepl('  "n1" [label="tf_construct\\nTwo constructs added.  "];',
                    tf_diagram(theory, "provenance"), fixed = TRUE))
})

test_that("the workflow joins each proposition to the construct it acts on", {
  # The feedback loop of arousal and threat shows, and no outcome construct is
  # left alone.
  dot <- tf_diagram(tf_read(tf_fixture_path("panic-network.theory.yaml")), "workflow")
  expect_true(grepl(paste0('  "c_arousal" -> "prop_p1";\n',
                           '  "prop_p1" -> "c_perceived_threat" [style=dashed, constraint=false];\n'),
                    dot, fixed = TRUE))
  expect_true(grepl('  "prop_p2" -> "c_avoidance" [style=dashed, constraint=false];\n', dot,
                    fixed = TRUE))
  expect_true(grepl('  "prop_p3" -> "c_arousal" [style=dashed, constraint=false];\n', dot,
                    fixed = TRUE))
  # An association has no direction, so its edge has no arrowhead.
  weak <- tf_diagram(tf_read(tf_fixture_path("weak-theory.theory.yaml")), "workflow")
  expect_true(grepl('  "prop_q1" -> "k_drive" [style=dashed, constraint=false, dir=none];\n',
                    weak, fixed = TRUE))
})

test_that("the pipeline lists the predictions from the top in file order", {
  # Under rankdir=LR, Graphviz stacks a rank from the bottom up, so the
  # predictions read upwards until an invisible chain set their order.
  dot <- tf_diagram(tf_read(tf_fixture_path("modality-switching.theory.yaml")), "pipeline")
  expect_true(grepl(paste0(
    '  "pred4" [label="pred4\\ninterval", fillcolor="#E7EDF5", color="#33567A"];\n',
    '  { rank=same; "pred1" -> "pred2" -> "pred3" -> "pred4" [style=invis]; }\n',
    '  "result_pred2" ['
  ), dot, fixed = TRUE))
  # A repeated id joins the chain once, and one prediction needs no chain.
  theory <- tf_theory("dup", "A repeated prediction id") |>
    tf_add_prediction("h1", "Alpha.", "directional") |>
    tf_add_prediction("h2", "Beta.", "directional") |>
    tf_add_prediction("h1", "Gamma.", "directional")
  expect_true(grepl('  { rank=same; "h1" -> "h2" [style=invis]; }\n',
                    tf_diagram(theory, "pipeline"), fixed = TRUE))
  one <- tf_theory("one", "One prediction") |> tf_add_prediction("h1", "Alpha.", "directional")
  expect_false(grepl("rank=same", tf_diagram(one, "pipeline"), fixed = TRUE))
})

test_that("the Venn view wraps names and says when constructs are left out", {
  # The names ran into each other and off the 380-pixel canvas, and the figure
  # did not say that it drew three of the five constructs.
  svg <- tf_diagram(tf_read(tf_fixture_path("modality-switching.theory.yaml")), "venn")
  expect_true(startsWith(svg, '<svg xmlns="http://www.w3.org/2000/svg" width="380" height="382" '))
  expect_true(grepl(paste0(
    '  <text x="190" y="24" text-anchor="middle" font-size="15">Construct scope overlap',
    '<tspan x="190" y="42" font-size="13">first three of 5 constructs</tspan></text>\n'
  ), svg, fixed = TRUE))
  expect_true(grepl(paste0(
    '  <text x="110" y="63" text-anchor="middle"><tspan x="110" y="63">Sensorimotor</tspan>',
    '<tspan x="110" y="79">experience with a</tspan><tspan x="110" y="95">concept</tspan>',
    '</text>\n'
  ), svg, fixed = TRUE))
  expect_true(grepl(paste0(
    '  <text x="190" y="340" text-anchor="middle"><tspan x="190" y="340">Cost of switching</tspan>',
    '<tspan x="190" y="356">modality between</tspan>',
    '<tspan x="190" y="372">consecutive trials</tspan></text>\n'
  ), svg, fixed = TRUE))
  # Every construct of the panic network is drawn, and its first name takes two
  # lines, so the circles sit a line lower.
  panic <- tf_diagram(tf_read(tf_fixture_path("panic-network.theory.yaml")), "venn")
  expect_false(grepl("constructs</tspan>", panic, fixed = TRUE))
  expect_true(grepl('<text x="190" y="176" text-anchor="middle" font-weight="bold">1</text>',
                    panic, fixed = TRUE))
  # A name is wrapped as written and then escaped line by line.
  amp <- tf_theory("amp", "An ampersand") |>
    tf_add_construct("c1", "Fear & avoidance <acute>", "d")
  expect_true(grepl(paste0('<tspan x="190" y="55">Fear &amp; avoidance</tspan>',
                           '<tspan x="190" y="71">&lt;acute&gt;</tspan>'),
                    tf_diagram(amp, "venn"), fixed = TRUE))
})

test_that("the rigour grid escapes the gate", {
  # The gate is one of three plain words, but the grid escapes it as it escapes
  # every other value, as Python's grid does.
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  check <- tf_check
  local_mocked_bindings(tf_check = function(theory) {
    rep <- check(theory)
    rep$gate <- "<a & b>"
    rep
  })
  expect_true(grepl('<text x="20" y="46">aggregate score 88.0, gate &lt;a &amp; b&gt;</text>',
                    tf_diagram(theory, "rigour"), fixed = TRUE))
})

test_that("the engine argument is deprecated", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  msg <- paste("the 'engine' argument of tf_diagram() has no effect and will be removed",
               "in the next minor release")
  expect_warning(out <- tf_diagram(theory, "context", engine = "graphviz"), msg, fixed = TRUE)
  expect_no_warning(plain <- tf_diagram(theory, "context"))
  expect_identical(out, plain)
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
