# A chain, arousal -> threat -> avoidance, whose single implication is the
# textbook mediation claim.
tf_chain_theory <- function() {
  tf_theory("mediation", "A mediated chain") |>
    tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
    tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
    tf_add_construct("c_avoidance", "Avoidance", "Withdrawal from the trigger.") |>
    tf_add_proposition("p1", "c_arousal", "c_threat", "increases") |>
    tf_add_proposition("p2", "c_threat", "c_avoidance", "increases")
}

# Build a theory from a node list and an edge matrix, for the property tests.
tf_dag_theory <- function(nodes, edges) {
  theory <- tf_theory("generated", "Generated")
  for (nd in nodes) theory <- tf_add_construct(theory, nd, nd, nd)
  for (e in seq_len(nrow(edges))) {
    theory <- tf_add_proposition(theory, paste0("p", e), edges[e, 1], edges[e, 2], "causes")
  }
  theory
}

# A theory over `nodes` with one proposition per triple c(from, relation, to).
tf_relation_theory <- function(name, nodes, props) {
  theory <- tf_theory(name, name)
  for (nd in nodes) theory <- tf_add_construct(theory, nd, nd, paste("definition of", nd))
  for (i in seq_along(props)) {
    p <- props[[i]]
    theory <- tf_add_proposition(theory, paste0("p", i), p[[1]], p[[3]], p[[2]])
  }
  theory
}

tf_statements <- function(res) {
  vapply(res$implications, function(i) i$statement, character(1))
}

# The app examples sit at the repository root, outside the package, so the
# checks that read them run only from a source checkout.
tf_app_example <- function(name) {
  path <- testthat::test_path("..", "..", "..", "..", "apps", "examples", name)
  if (!file.exists(path)) {
    testthat::skip("apps/examples is not reachable from this test run")
  }
  tf_read(path)
}

test_that("tf_implications returns the basis set of a mediated chain", {
  res <- tf_implications(tf_chain_theory())
  expect_named(res, c("theory_id", "criterion", "acyclic", "constructs", "n_edges",
                      "n_bidirected", "feedback", "implications", "n_implications",
                      "inseparable"))
  expect_equal(res$theory_id, "mediation")
  expect_identical(res$criterion, "m")
  expect_true(res$acyclic)
  expect_equal(unlist(res$constructs), c("c_arousal", "c_threat", "c_avoidance"))
  expect_equal(res$n_edges, 2L)
  expect_equal(res$n_bidirected, 0L)
  expect_identical(res$feedback, list())
  expect_equal(res$n_implications, 1L)
  expect_equal(res$implications[[1]]$a, "c_arousal")
  expect_equal(res$implications[[1]]$b, "c_avoidance")
  expect_equal(unlist(res$implications[[1]]$given), "c_threat")
  expect_equal(res$implications[[1]]$statement,
               "c_arousal _||_ c_avoidance | c_threat")
  expect_identical(res$inseparable, list())
})

test_that("tf_implications leaves a collider pair unconditioned", {
  # a -> c <- b: the two causes are marginally independent, and conditioning on
  # the collider would create the dependence rather than test it.
  theory <- tf_theory("collider", "A collider") |>
    tf_add_construct("a", "A", "d") |>
    tf_add_construct("b", "B", "d") |>
    tf_add_construct("c", "C", "d") |>
    tf_add_proposition("p1", "a", "c", "causes") |>
    tf_add_proposition("p2", "b", "c", "causes")
  res <- tf_implications(theory)
  expect_equal(res$n_implications, 1L)
  expect_equal(length(res$implications[[1]]$given), 0L)
  expect_equal(res$implications[[1]]$statement, "a _||_ b")
})

test_that("tf_implications orders pairs and conditioning sets by construct file order", {
  # Declaration order alone decides the order of the records and of each
  # conditioning set, so the twin comparison has something stable to compare.
  theory <- tf_theory("order", "Declaration order") |>
    tf_add_construct("z", "Z", "d") |>
    tf_add_construct("y", "Y", "d") |>
    tf_add_construct("x", "X", "d") |>
    tf_add_construct("w", "W", "d") |>
    tf_add_proposition("p1", "z", "x", "causes") |>
    tf_add_proposition("p2", "y", "x", "causes") |>
    tf_add_proposition("p3", "x", "w", "causes")
  res <- tf_implications(theory)
  expect_equal(unlist(res$constructs), c("z", "y", "x", "w"))
  statements <- vapply(res$implications, function(i) i$statement, character(1))
  expect_equal(statements,
               c("z _||_ y", "z _||_ w | x", "y _||_ w | x"))
})

test_that("tf_implications counts a repeated causal edge once", {
  theory <- tf_theory("dup-edge", "A repeated edge") |>
    tf_add_construct("a", "A", "d") |>
    tf_add_construct("b", "B", "d") |>
    tf_add_construct("c", "C", "d") |>
    tf_add_proposition("p1", "a", "b", "causes") |>
    tf_add_proposition("p2", "a", "b", "increases") |>
    tf_add_proposition("p3", "b", "c", "causes")
  res <- tf_implications(theory)
  expect_equal(res$n_edges, 2L)
  expect_equal(res$n_implications, 1L)
})

test_that("every directed relation is an edge", {
  # The relation table (API_SPEC.md section 28) makes mediates and moderates
  # directed edges, as the three causal relations are, so a chain through any
  # of them implies what a chain of causes does.
  for (rel in sort(theoryforge:::.tf_DIRECTED)) {
    res <- tf_implications(tf_relation_theory("chain", c("a", "b", "c"),
                                              list(c("a", rel, "b"), c("b", "causes", "c"))))
    expect_equal(unlist(res$constructs), c("a", "b", "c"), info = rel)
    expect_equal(res$n_edges, 2L, info = rel)
    expect_identical(tf_statements(res), "a _||_ c | b", info = rel)
  }
})

test_that("an association between vertices is a bidirected edge", {
  # z -> x -> y with x associates y. The association is covariance the theory
  # leaves unexplained, as a latent common cause of x and y would produce, so
  # x is a collider on z -> x <-> y and holding it fixed opens that path. No
  # set separates z from y, and the pair is listed as inseparable where 0.6.0
  # declared it independent given x.
  res <- tf_implications(tf_relation_theory("iv", c("z", "x", "y"), list(
    c("z", "increases", "x"), c("x", "increases", "y"), c("x", "associates", "y"))))
  expect_identical(res$criterion, "m")
  expect_equal(unlist(res$constructs), c("z", "x", "y"))
  expect_equal(res$n_edges, 2L)
  expect_equal(res$n_bidirected, 1L)
  expect_identical(res$implications, list())
  expect_equal(res$n_implications, 0L)
  expect_identical(res$inseparable, list(list(a = "z", b = "y")))
})

test_that("an association makes its pair adjacent", {
  # a -> c <- b with a associates b: the association is the theory's own claim
  # that a and b covary, so the two causes are no longer independent.
  res <- tf_implications(tf_relation_theory("collider", c("a", "b", "c"), list(
    c("a", "increases", "c"), c("b", "increases", "c"), c("a", "associates", "b"))))
  expect_identical(res$implications, list())
  expect_identical(res$inseparable, list())
})

test_that("a mediates edge makes its pair adjacent", {
  # x mediates m, m -> y and x -> y: every pair is joined, so nothing is
  # implied, where 0.6.0 claimed that x and m are independent.
  res <- tf_implications(tf_relation_theory("triangle", c("x", "m", "y"), list(
    c("x", "mediates", "m"), c("m", "increases", "y"), c("x", "increases", "y"))))
  expect_equal(res$n_edges, 3L)
  expect_identical(res$implications, list())
})

test_that("a moderator points into the outcome", {
  # z moderates y: the relation table reads a moderator as a direct effect
  # modifier, a direct cause of the outcome (VanderWeele & Robins, 2007), so z
  # and y are adjacent, and 0.6.0's claim that they are independent given x is
  # gone.
  res <- tf_implications(tf_relation_theory("moderation", c("z", "w", "x", "y"), list(
    c("z", "increases", "w"), c("x", "increases", "y"), c("z", "moderates", "y"))))
  expect_equal(res$n_edges, 3L)
  expect_identical(tf_statements(res), c("z _||_ x", "w _||_ x | z", "w _||_ y | z, x"))
})

test_that("a moderator outside the causal relations is a vertex", {
  # w moderates both outcomes, so y1 and y2 share a cause and are independent
  # only once w is held fixed as well. Reading only the three causal relations
  # gave 'y1 _||_ y2 | a, b', which is false.
  res <- tf_implications(tf_relation_theory("fork", c("a", "y1", "b", "y2", "w"), list(
    c("a", "causes", "y1"), c("b", "causes", "y2"),
    c("w", "moderates", "y1"), c("w", "moderates", "y2"))))
  expect_identical(tf_statements(res), c(
    "a _||_ b", "a _||_ y2 | b, w", "a _||_ w", "y1 _||_ b | a, w",
    "y1 _||_ y2 | a, b, w", "b _||_ w"))
})

test_that("a mediated chain through an outside construct is read whole", {
  # y1 mediates x and x mediates y2 join a and y1 to y2. Reading only the
  # three causal relations gave 'a _||_ y2 | b' and 'y1 _||_ y2 | a, b', both
  # false.
  res <- tf_implications(tf_relation_theory("chain", c("a", "y1", "x", "b", "y2"), list(
    c("a", "causes", "y1"), c("y1", "mediates", "x"),
    c("x", "mediates", "y2"), c("b", "causes", "y2"))))
  expect_identical(tf_statements(res), c(
    "a _||_ x | y1", "a _||_ b", "a _||_ y2 | x, b", "y1 _||_ b | a",
    "y1 _||_ y2 | a, x, b", "x _||_ b | y1"))
})

test_that("the ancestors separate a pair that the parents do not", {
  # x -> m -> w -> y with w associates y. The parents of x and y, {w}, leave
  # the collider w open on x -> m -> w <-> y, and the ancestors of the pair,
  # {m, w}, close the path at m. Nothing separates m from y, since m -> w <-> y
  # stays open whether or not w is held fixed.
  res <- tf_implications(tf_relation_theory("confounded-link", c("x", "m", "w", "y"), list(
    c("x", "causes", "m"), c("m", "causes", "w"), c("w", "causes", "y"),
    c("w", "associates", "y"))))
  expect_identical(res$implications, list(
    list(a = "x", b = "w", given = list("m"), statement = "x _||_ w | m"),
    list(a = "x", b = "y", given = list("m", "w"), statement = "x _||_ y | m, w")))
  expect_identical(res$inseparable, list(list(a = "m", b = "y")))
})

test_that("a construct touched only by associations is left out", {
  # Every path through k arrives and leaves by an arrowhead, so k is a collider
  # on each and, being no ancestor of anything, closes it. Leaving k out drops
  # no statement about the other constructs, and silence about k is no claim
  # that it is independent of anything (API_SPEC.md section 27).
  res <- tf_implications(tf_relation_theory("silence", c("k", "x", "y"), list(
    c("x", "causes", "y"), c("k", "associates", "x"), c("k", "associates", "y"))))
  expect_equal(unlist(res$constructs), c("x", "y"))
  expect_equal(res$n_bidirected, 0L)
  expect_identical(res$implications, list())
  expect_identical(res$inseparable, list())
})

test_that("a repeated association counts once and a self association not at all", {
  res <- tf_implications(tf_relation_theory("repeat", c("a", "b", "c"), list(
    c("a", "causes", "c"), c("b", "causes", "c"),
    c("a", "associates", "b"), c("b", "associates", "a"), c("c", "associates", "c"))))
  expect_equal(res$n_bidirected, 1L)
  expect_identical(res$implications, list())
})

test_that("an association with an undeclared endpoint adds nothing", {
  # An association names no vertex unless a directed relation names both its
  # constructs, so one with an undeclared endpoint is not an edge, as one with
  # a construct touched only by associations is not. tf_validate() reports the
  # reference.
  res <- tf_implications(tf_relation_theory("loose", c("a", "b"), list(
    c("a", "causes", "b"), c("a", "associates", "ghost"))))
  expect_equal(unlist(res$constructs), c("a", "b"))
  expect_equal(res$n_bidirected, 0L)
})

test_that("tf_implications reports an empty basis set for a theory with no causal relations", {
  # The weak example's one proposition is an association between two
  # constructs that no directed relation names, so there is no vertex.
  res <- tf_implications(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_equal(res$theory_id, "weak-demo")
  expect_true(res$acyclic)
  expect_equal(length(res$constructs), 0L)
  expect_equal(res$n_edges, 0L)
  expect_equal(res$n_bidirected, 0L)
  expect_equal(res$implications, list())
  expect_equal(res$n_implications, 0L)
  expect_identical(res$inseparable, list())
})

test_that("the stereotype-threat moderation adds the statements it implies", {
  # Domain identification moderates the threat-performance link, so it is a
  # parent of test performance: it joins three statements and the conditioning
  # sets of two others.
  res <- tf_implications(tf_app_example("stereotype-threat.theory.yaml"))
  expect_identical(tf_statements(res), c(
    "c_diagnostic_framing _||_ c_stereotype_threat | c_stereotype_salience",
    "c_diagnostic_framing _||_ c_domain_identification",
    paste("c_diagnostic_framing _||_ c_test_performance | c_stereotype_threat,",
          "c_domain_identification"),
    "c_stereotype_salience _||_ c_domain_identification | c_diagnostic_framing",
    paste("c_stereotype_salience _||_ c_test_performance | c_diagnostic_framing,",
          "c_stereotype_threat, c_domain_identification"),
    "c_stereotype_threat _||_ c_domain_identification | c_stereotype_salience"))
})

test_that("the planned-behaviour antecedents covary", {
  # Ajzen (1991) draws attitude, subjective norm and perceived control as
  # intercorrelated, so the example states the three associations, and the
  # three marginal independencies among them are no longer implied.
  res <- tf_implications(tf_app_example("planned-behaviour.theory.yaml"))
  expect_equal(res$n_bidirected, 3L)
  expect_identical(tf_statements(res), c(
    "c_attitude _||_ c_behaviour | c_perceived_control, c_intention",
    "c_subjective_norm _||_ c_behaviour | c_perceived_control, c_intention"))
})

test_that("tf_implications handles the degenerate graphs", {
  empty <- tf_theory("empty", "No constructs at all")
  expect_equal(tf_implications(empty)$n_implications, 0L)

  single <- tf_theory("single", "One construct") |>
    tf_add_construct("a", "A", "d")
  expect_equal(tf_implications(single)$n_implications, 0L)

  # Two constructs with the one edge between them: every pair is adjacent, which
  # is the boundary at which the basis set becomes empty.
  pair <- single |>
    tf_add_construct("b", "B", "d") |>
    tf_add_proposition("p1", "a", "b", "causes")
  res <- tf_implications(pair)
  expect_equal(unlist(res$constructs), c("a", "b"))
  expect_equal(res$n_edges, 1L)
  expect_equal(res$n_implications, 0L)
})

test_that("tf_implications returns the basis set of the shipped acyclic example", {
  # The worked example for this function: five constructs, four causal
  # propositions, a fork at modality activation and a collider at conceptual
  # access. Asserted literally, so a change to the derivation or to the file is
  # caught rather than absorbed.
  theory <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  expect_true(tf_validate(theory, full = TRUE))
  res <- tf_implications(theory)
  expect_equal(res$theory_id, "modality-switching-2026")
  expect_true(res$acyclic)
  expect_equal(unlist(res$constructs),
               c("c_sensorimotor_experience", "c_modality_activation", "c_switch_cost",
                 "c_conceptual_access", "c_lexical_familiarity"))
  expect_equal(res$n_edges, 4L)
  # k(k-1)/2 - m with k = 5 and m = 4
  expect_equal(res$n_implications, 6L)
  expect_equal(vapply(res$implications, function(i) i$a, character(1)),
               c("c_sensorimotor_experience", "c_sensorimotor_experience",
                 "c_sensorimotor_experience", "c_modality_activation",
                 "c_switch_cost", "c_switch_cost"))
  expect_equal(vapply(res$implications, function(i) i$b, character(1)),
               c("c_switch_cost", "c_conceptual_access", "c_lexical_familiarity",
                 "c_lexical_familiarity", "c_conceptual_access", "c_lexical_familiarity"))
  expect_equal(lapply(res$implications, function(i) unlist(i$given)),
               list("c_modality_activation",
                    c("c_modality_activation", "c_lexical_familiarity"),
                    NULL,
                    "c_sensorimotor_experience",
                    c("c_modality_activation", "c_lexical_familiarity"),
                    "c_modality_activation"))
  expect_equal(vapply(res$implications, function(i) i$statement, character(1)),
               c("c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation",
                 paste("c_sensorimotor_experience _||_ c_conceptual_access |",
                       "c_modality_activation, c_lexical_familiarity"),
                 "c_sensorimotor_experience _||_ c_lexical_familiarity",
                 paste("c_modality_activation _||_ c_lexical_familiarity |",
                       "c_sensorimotor_experience"),
                 paste("c_switch_cost _||_ c_conceptual_access |",
                       "c_modality_activation, c_lexical_familiarity"),
                 "c_switch_cost _||_ c_lexical_familiarity | c_modality_activation"))
})

test_that("the shipped acyclic example carries both a fork and a collider", {
  # What makes the example instructive rather than a straight chain. The two
  # children of the fork are independent given their shared parent, and the two
  # parents of the collider are independent with nothing held fixed, which is
  # the pair a study would look at to distinguish this account from one that
  # ties word statistics to perceptual experience.
  res <- tf_implications(tf_read(tf_fixture_path("modality-switching.theory.yaml")))
  given_for <- function(a, b) {
    for (i in res$implications) if (i$a == a && i$b == b) return(unlist(i$given))
    stop("no implication for that pair")
  }
  expect_equal(given_for("c_switch_cost", "c_conceptual_access"),
               c("c_modality_activation", "c_lexical_familiarity"))
  expect_null(given_for("c_sensorimotor_experience", "c_lexical_familiarity"))
})

test_that("dagitty and ggm confirm the shipped acyclic example's basis set", {
  skip_if_not_installed("dagitty")
  skip_if_not_installed("ggm")
  theory <- tf_read(tf_fixture_path("modality-switching.theory.yaml"))
  res <- tf_implications(theory)
  causal <- c("causes", "increases", "decreases")
  from <- character(0)
  to <- character(0)
  for (p in theory$propositions) {
    if (p$relation %in% causal) {
      from <- c(from, p$from)
      to <- c(to, p$to)
    }
  }
  g <- dagitty::dagitty(paste0("dag { ",
                               paste(paste(from, "->", to), collapse = "; "), " }"))
  expect_true(dagitty::isAcyclic(g))
  for (x in res$implications) {
    z <- unlist(x$given)
    if (is.null(z)) z <- character(0)
    expect_true(dagitty::dseparated(g, x$a, x$b, z))
  }
  # ggm::basiSet implements the same d-separation basis, so the two agree
  # statement for statement rather than only on the pairs covered.
  key <- function(a, b, given) {
    pair <- sort(c(a, b))
    paste0(pair[[1]], "~", pair[[2]], "~", paste(sort(given), collapse = ","))
  }
  used <- unlist(res$constructs)
  amat <- matrix(0L, length(used), length(used), dimnames = list(used, used))
  for (e in seq_along(from)) amat[from[[e]], to[[e]]] <- 1L
  theirs <- sort(vapply(ggm::basiSet(amat),
                        function(v) key(v[[1]], v[[2]], v[-(1:2)]), character(1)))
  ours <- sort(vapply(res$implications, function(x) {
    z <- unlist(x$given)
    if (is.null(z)) z <- character(0)
    key(x$a, x$b, z)
  }, character(1)))
  expect_equal(ours, theirs)
})

test_that("tf_implications refuses a cyclic causal graph, naming the cycle", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_error(
    tf_implications(theory),
    paste("implications requires an acyclic causal graph; cycle found:",
          "c_arousal -> c_perceived_threat -> c_arousal"),
    fixed = TRUE
  )
})

test_that("tf_implications refuses a self loop", {
  theory <- tf_theory("loop", "A self loop") |>
    tf_add_construct("a", "A", "d") |>
    tf_add_proposition("p1", "a", "a", "causes")
  expect_error(
    tf_implications(theory),
    "implications requires an acyclic causal graph; cycle found: a -> a",
    fixed = TRUE
  )
})

test_that("tf_implications refuses duplicate construct ids", {
  theory <- tf_theory("dupe", "Duplicated ids") |>
    tf_add_construct("c1", "One", "d") |>
    tf_add_construct("c1", "One again", "d")
  expect_error(
    tf_implications(theory),
    "implications requires unique construct ids; duplicate construct id: c1",
    fixed = TRUE
  )
})

test_that("tf_implications refuses a causal proposition with an undeclared endpoint", {
  # Dropping the edge would shrink the graph and so claim independencies the
  # theory does not imply.
  theory <- tf_theory("dangling", "A dangling endpoint") |>
    tf_add_construct("a", "A", "d") |>
    tf_add_construct("b", "B", "d") |>
    tf_add_proposition("p1", "a", "ghost", "causes")
  expect_error(
    tf_implications(theory),
    paste("implications requires causal propositions between declared constructs;",
          "proposition 'p1' refers to unknown construct 'ghost'"),
    fixed = TRUE
  )
})

test_that("tf_implications refuses an undeclared endpoint of every directed relation", {
  for (rel in c("mediates", "moderates")) {
    theory <- tf_relation_theory("dangling", c("a", "b"),
                                 list(c("a", "causes", "b"), c("b", rel, "ghost")))
    expect_error(
      tf_implications(theory),
      paste("implications requires causal propositions between declared constructs;",
            "proposition 'p2' refers to unknown construct 'ghost'"),
      fixed = TRUE, info = rel
    )
  }
})

test_that("tf_implications refuses a cycle closed by a moderation", {
  theory <- tf_relation_theory("loop", c("a", "b"),
                               list(c("a", "causes", "b"), c("b", "moderates", "a")))
  expect_error(tf_implications(theory),
               "implications requires an acyclic causal graph; cycle found: a -> b -> a",
               fixed = TRUE)
})

test_that("dagitty confirms every statement and every inseparable pair of a mixed graph", {
  # Random acyclic mixed graphs, every directed relation in use, associations
  # placed anywhere and declaration order shuffled. dagitty's dseparated() reads
  # `<->` as a bidirected edge, so it applies m-separation. Each statement must
  # hold, each inseparable pair must stay connected given every set of the other
  # vertices, and the stated pairs must be dagitty's missing edges among the
  # vertices. basis.set is not used, since dagitty 0.3.4 ignores `<->` there.
  skip_if_not_installed("dagitty")
  set.seed(20261003)
  rels <- sort(theoryforge:::.tf_DIRECTED)
  stated <- 0L
  inseparable <- 0L
  for (rep in 1:100) {
    k <- sample(3:6, 1)
    nodes <- paste0("v", seq_len(k))
    props <- list()
    lines <- character(0)
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        if (stats::runif(1) < 0.35) {
          props[[length(props) + 1L]] <- c(nodes[[i]], sample(rels, 1), nodes[[j]])
          lines <- c(lines, paste(nodes[[i]], "->", nodes[[j]]))
        }
        if (stats::runif(1) < 0.25) {
          props[[length(props) + 1L]] <- c(nodes[[i]], "associates", nodes[[j]])
          lines <- c(lines, paste(nodes[[i]], "<->", nodes[[j]]))
        }
      }
    }
    if (!any(vapply(props, function(p) p[[2]] != "associates", logical(1)))) next
    res <- tf_implications(tf_relation_theory("random", sample(nodes), props[sample(length(props))]))
    g <- dagitty::dagitty(paste0("dag { ", paste(lines, collapse = "; "), " }"))
    vertices <- unlist(res$constructs)
    for (x in res$implications) {
      z <- unlist(x$given)
      if (is.null(z)) z <- character(0)
      expect_true(dagitty::dseparated(g, x$a, x$b, z), info = x$statement)
      stated <- stated + 1L
    }
    for (x in res$inseparable) {
      others <- setdiff(vertices, c(x$a, x$b))
      for (r in 0:length(others)) {
        sets <- if (r == 0L) list(character(0)) else utils::combn(others, r, simplify = FALSE)
        for (z in sets) expect_false(dagitty::dseparated(g, x$a, x$b, z))
      }
      inseparable <- inseparable + 1L
    }
    key <- function(a, b) paste(sort(c(a, b)), collapse = "~")
    ours <- sort(vapply(res$implications, function(x) key(x$a, x$b), character(1)))
    theirs <- dagitty::impliedConditionalIndependencies(g, type = "missing.edge")
    theirs <- Filter(function(ci) all(c(ci$X, ci$Y) %in% vertices), theirs)
    expect_identical(ours, sort(unique(vapply(theirs, function(ci) key(ci$X, ci$Y),
                                              character(1)))))
  }
  expect_gt(stated, 100L)
  expect_gt(inseparable, 10L)
})

test_that("the basis set has cardinality k(k-1)/2 - m for random DAGs", {
  # The identity is analytic: one statement per non-adjacent pair, and each edge
  # removes exactly one pair from the k(k-1)/2 available.
  set.seed(4242)
  checked <- 0L
  for (rep in 1:200) {
    k <- sample(2:7, 1)
    nodes <- paste0("v", seq_len(k))
    from <- character(0)
    to <- character(0)
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        if (stats::runif(1) < 0.45) {
          from <- c(from, nodes[[i]])
          to <- c(to, nodes[[j]])
        }
      }
    }
    if (length(from) == 0L) next
    theory <- tf_dag_theory(sample(nodes), cbind(from, to))
    res <- tf_implications(theory)
    kk <- length(res$constructs)
    expect_equal(res$n_implications, kk * (kk - 1L) / 2L - res$n_edges)
    checked <- checked + 1L
  }
  expect_gt(checked, 150L)
})

test_that("every derived independence is confirmed by dagitty", {
  skip_if_not_installed("dagitty")
  set.seed(97)
  confirmed <- 0L
  for (rep in 1:40) {
    k <- sample(3:6, 1)
    nodes <- paste0("v", seq_len(k))
    from <- character(0)
    to <- character(0)
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        if (stats::runif(1) < 0.45) {
          from <- c(from, nodes[[i]])
          to <- c(to, nodes[[j]])
        }
      }
    }
    if (length(from) == 0L) next
    res <- tf_implications(tf_dag_theory(sample(nodes), cbind(from, to)))
    g <- dagitty::dagitty(paste0("dag { ",
                                 paste(paste(from, "->", to), collapse = "; "), " }"))
    expect_true(dagitty::isAcyclic(g))
    for (x in res$implications) {
      z <- unlist(x$given)
      if (is.null(z)) z <- character(0)
      expect_true(dagitty::dseparated(g, x$a, x$b, z))
      confirmed <- confirmed + 1L
    }
    # the pairs covered are exactly dagitty's missing edges
    ours <- sort(vapply(res$implications,
                        function(x) paste(sort(c(x$a, x$b)), collapse = "~"), character(1)))
    theirs <- sort(unique(vapply(
      dagitty::impliedConditionalIndependencies(g, type = "missing.edge"),
      function(ci) paste(sort(c(ci$X, ci$Y)), collapse = "~"), character(1))))
    expect_equal(ours, theirs)
  }
  expect_gt(confirmed, 50L)
})

test_that("the derived set matches ggm::basiSet exactly", {
  skip_if_not_installed("ggm")
  set.seed(1301)
  compared <- 0L
  for (rep in 1:40) {
    k <- sample(3:6, 1)
    nodes <- paste0("v", seq_len(k))
    from <- character(0)
    to <- character(0)
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        if (stats::runif(1) < 0.45) {
          from <- c(from, nodes[[i]])
          to <- c(to, nodes[[j]])
        }
      }
    }
    if (length(from) == 0L) next
    res <- tf_implications(tf_dag_theory(sample(nodes), cbind(from, to)))
    used <- unlist(res$constructs)
    amat <- matrix(0L, length(used), length(used), dimnames = list(used, used))
    for (e in seq_along(from)) amat[from[[e]], to[[e]]] <- 1L
    key <- function(a, b, given) {
      pair <- sort(c(a, b))
      paste0(pair[[1]], "~", pair[[2]], "~", paste(sort(given), collapse = ","))
    }
    theirs <- sort(vapply(ggm::basiSet(amat),
                          function(v) key(v[[1]], v[[2]], v[-(1:2)]), character(1)))
    ours <- sort(vapply(res$implications,
                        function(x) key(x$a, x$b, unlist(x$given)), character(1)))
    expect_equal(ours, theirs)
    compared <- compared + 1L
  }
  expect_gt(compared, 20L)
})

test_that("derived independencies show as near-zero partial correlations in simulated data", {
  # The semantics rather than the syntax: linear-Gaussian data generated from
  # the DAG must satisfy every implication, and must not satisfy the same claim
  # made about an adjacent pair.
  pcor <- function(X, a, b, z) {
    S <- stats::cov(X[, c(a, b, z), drop = FALSE])
    P <- solve(S)
    abs(-P[1, 2] / sqrt(P[1, 1] * P[2, 2]))
  }
  set.seed(20260818)
  n <- 8000
  theory <- tf_chain_theory()
  res <- tf_implications(theory)
  arousal <- stats::rnorm(n)
  threat <- 0.8 * arousal + stats::rnorm(n)
  avoidance <- 0.8 * threat + stats::rnorm(n)
  X <- cbind(c_arousal = arousal, c_threat = threat, c_avoidance = avoidance)
  x <- res$implications[[1]]
  expect_lt(pcor(X, x$a, x$b, unlist(x$given)), 0.05)
  # the same pair without the conditioning set is strongly dependent, so the
  # near-zero value above is the conditioning at work and not a flat dataset
  expect_gt(pcor(X, x$a, x$b, character(0)), 0.2)
  # an adjacent pair is not implied independent, and is not independent here
  expect_gt(pcor(X, "c_threat", "c_avoidance", "c_arousal"), 0.2)
})
