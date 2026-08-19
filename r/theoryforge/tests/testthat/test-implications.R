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

test_that("tf_implications returns the basis set of a mediated chain", {
  res <- tf_implications(tf_chain_theory())
  expect_named(res, c("theory_id", "acyclic", "constructs", "n_edges",
                      "implications", "n_implications"))
  expect_equal(res$theory_id, "mediation")
  expect_true(res$acyclic)
  expect_equal(unlist(res$constructs), c("c_arousal", "c_threat", "c_avoidance"))
  expect_equal(res$n_edges, 2L)
  expect_equal(res$n_implications, 1L)
  expect_equal(res$implications[[1]]$a, "c_arousal")
  expect_equal(res$implications[[1]]$b, "c_avoidance")
  expect_equal(unlist(res$implications[[1]]$given), "c_threat")
  expect_equal(res$implications[[1]]$statement,
               "c_arousal _||_ c_avoidance | c_threat")
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

test_that("tf_implications ignores non-causal relations", {
  # `associates` and `moderates` state no direction, so they are not edges of a
  # causal graph and cannot carry a d-separation claim.
  theory <- tf_theory("assoc", "Associative only") |>
    tf_add_construct("a", "A", "d") |>
    tf_add_construct("b", "B", "d") |>
    tf_add_proposition("p1", "a", "b", "associates")
  res <- tf_implications(theory)
  expect_equal(res$n_edges, 0L)
  expect_equal(length(res$constructs), 0L)
  expect_equal(res$n_implications, 0L)
})

test_that("tf_implications reports an empty basis set for a theory with no causal relations", {
  res <- tf_implications(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_equal(res$theory_id, "weak-demo")
  expect_true(res$acyclic)
  expect_equal(length(res$constructs), 0L)
  expect_equal(res$n_edges, 0L)
  expect_equal(res$implications, list())
  expect_equal(res$n_implications, 0L)
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
