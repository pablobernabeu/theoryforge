# tf_read_dagitty() (API_SPEC.md section 35). The Python suite (test_interop.py)
# mirrors these tests, and the parity check compares the two readers on
# fixtures/edge/dagitty.cases.json.

interop_edges <- function(theory) {
  sort(vapply(theory$propositions, function(p) {
    paste(p$from, p$to, if (identical(p$relation, "associates")) "associates" else "directed")
  }, ""))
}

test_that("a diagram becomes constructs and propositions", {
  t <- tf_read_dagitty('dag { a [exposure] a -> "b c" -> d; e <- a; a <-> d; f -> {a d} }')
  expect_identical(vapply(t$constructs, function(c) c$id, ""), c("a", "b c", "d", "e", "f"))
  expect_identical(vapply(t$propositions, function(p) paste(p$id, p$from, p$to, p$relation), ""),
                   c("p1 a b c causes", "p2 b c d causes", "p3 a e causes",
                     "p4 a d associates", "p5 f a causes", "p6 f d causes"))
  expect_identical(t$maturity, "draft")
  expect_identical(t$provenance[[1]]$detail, "5 constructs, 6 propositions")
  # A diagram cannot supply definitions, so the theory does not validate yet.
  expect_error(tf_validate(t), "construct[0] missing/empty definition", fixed = TRUE)
})

test_that("the causal_dag export reads back as the same edges", {
  for (name in c("panic-network.theory.yaml", "modality-switching.theory.yaml")) {
    t <- tf_read(tf_example_path(name))
    back <- tf_read_dagitty(tf_diagram(t, "causal_dag"))
    expect_identical(interop_edges(back), interop_edges(t), info = name)
  }
})

test_that("arrows take the relation asked for and refuse what theoryforge cannot hold", {
  expect_identical(tf_read_dagitty("x -> y", relation = "decreases")$propositions[[1]]$relation,
                   "decreases")
  expect_error(tf_read_dagitty("x -> y", relation = "mediates"),
               "read_dagitty requires relation to be one of causes, increases, decreases",
               fixed = TRUE)
  expect_error(tf_read_dagitty("x -- y"), "undirected edge (--)", fixed = TRUE)
})

test_that("a variable associated only with itself reads as a construct outside the graph", {
  # DAGitty writes z <-> z without complaint. The association adds nothing, so
  # z is no vertex, as in the Python suite.
  t <- tf_read_dagitty("dag { x -> y; z <-> z }")
  expect_identical(vapply(t$propositions, function(p) p$relation, ""), c("causes", "associates"))
  expect_identical(unlist(tf_implications(t)$constructs), c("x", "y"))
})
