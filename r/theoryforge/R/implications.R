#' Testable implications derived from a theory's causal subgraph.
#'
#' The causal propositions form a directed graph over the constructs they
#' connect. When that graph is acyclic it entails a set of conditional
#' independencies, and the basis set is the smallest such set from which every
#' other implied independence follows.
#' @name implications
#' @keywords internal
NULL

# Indices of the first cycle found, or NULL when the graph is acyclic. A
# depth-first search that takes start nodes and successors in construct file
# order, so the cycle reported for a given theory is the same one in both
# engines. The returned path repeats its first node at the end, and a self loop
# comes back as that node twice.
.tf_first_cycle <- function(adj, k) {
  colour <- integer(k)  # 0 unvisited, 1 on the current path, 2 finished
  for (start in seq_len(k)) {
    if (colour[[start]] != 0L) next
    colour[[start]] <- 1L
    path <- start
    stack_v <- start
    stack_i <- 0L  # successors of the node already examined
    while (length(stack_v) > 0L) {
      top <- length(stack_v)
      v <- stack_v[[top]]
      nxt <- stack_i[[top]] + 1L
      if (nxt <= k) {
        stack_i[[top]] <- nxt
        if (adj[v, nxt]) {
          if (colour[[nxt]] == 1L) {
            pos <- which(path == nxt)[[1L]]
            return(c(path[pos:length(path)], nxt))
          }
          if (colour[[nxt]] == 0L) {
            colour[[nxt]] <- 1L
            path <- c(path, nxt)
            stack_v <- c(stack_v, nxt)
            stack_i <- c(stack_i, 0L)
          }
        }
      } else {
        colour[[v]] <- 2L
        stack_v <- stack_v[-top]
        stack_i <- stack_i[-top]
        path <- path[-length(path)]
      }
    }
  }
  NULL
}

# Render one independence in the notation dagitty prints.
.tf_ci_statement <- function(a, b, given) {
  if (length(given) == 0L) {
    return(paste0(a, " _||_ ", b))
  }
  paste0(a, " _||_ ", b, " | ", paste(given, collapse = ", "))
}

#' Derive a theory's implied conditional independencies
#'
#' Reads the propositions whose relation is causal (\code{"causes"},
#' \code{"increases"}, \code{"decreases"}) as directed edges over the constructs
#' they connect, checks that the resulting graph is acyclic, and returns its
#' basis set: for every pair of non-adjacent constructs, the claim that the two
#' are independent given the parents of both. A basis set implies every other
#' conditional independence the graph entails, so it is the shortest complete
#' statement of what the theory forbids in data, and each entry is something a
#' study could find and refute.
#'
#' Constructs that no causal proposition connects are left out, because silence
#' about a construct is not a claim that it is independent of anything. A theory
#' with no causal propositions therefore has an empty basis set rather than an
#' error.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A named list
#'   \code{list(theory_id, acyclic, constructs, n_edges, implications,
#'   n_implications)}. \code{constructs} holds, in file order, the constructs a
#'   causal proposition connects. \code{acyclic} is always \code{TRUE} in a
#'   returned record, since a cyclic graph is refused; it is carried so that a
#'   serialised record states the verdict rather than leaving a reader to infer
#'   that the check ran. Each entry of \code{implications} is a list
#'   \code{list(a, b, given, statement)}, where \code{statement} renders the
#'   claim as \code{a _||_ b | z1, z2}. Pairs come in construct file order, as do
#'   the members of \code{given}.
#' @references
#' Pearl, J. (1988). \emph{Probabilistic reasoning in intelligent systems:
#'   Networks of plausible inference}. Morgan Kaufmann.
#'
#' Shipley, B. (2000). A new inferential test for path models based on directed
#'   acyclic graphs. \emph{Structural Equation Modeling}, 7(2), 206-218.
#'   \doi{10.1207/S15328007SEM0702_4}
#' @seealso [tf_diagram()] with \code{type = "causal_dag"}, which exports the
#'   same subgraph as dagitty syntax without reading it, and the methodological
#'   foundations article for the literature behind the causal-testability
#'   criterion.
#' @examples
#' # A mediated chain commits the theory to one thing it does not state
#' # directly: arousal and avoidance are independent once threat is held fixed.
#' theory <- tf_theory("mediation", "A mediated chain") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_construct("c_avoidance", "Avoidance", "Withdrawal from the trigger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases") |>
#'   tf_add_proposition("p2", "c_threat", "c_avoidance", "increases")
#'
#' implied <- tf_implications(theory)
#' implied$n_implications
#' implied$implications[[1]]$statement
#' @export
tf_implications <- function(theory) {
  T <- theory

  declared <- character(0)
  for (c in .tf_list(T, "constructs")) {
    cid <- .tf_str(c, "id")
    # Two constructs sharing an id give the same node two sets of parents, and
    # nothing in the maths says which one a proposition meant.
    if (cid %in% declared) {
      stop("implications requires unique construct ids; duplicate construct id: ", cid,
           call. = FALSE)
    }
    declared <- c(declared, cid)
  }

  edge_from <- integer(0)
  edge_to <- integer(0)
  for (p in .tf_list(T, "propositions")) {
    rel <- .tf_get(p, "relation")
    if (!(length(rel) == 1L && !is.na(rel) && rel %in% .tf_CAUSAL)) next
    pid <- .tf_str(p, "id")
    frm <- .tf_str(p, "from")
    to <- .tf_str(p, "to")
    # Dropping an edge whose endpoint was never declared would shrink the graph
    # and so add independencies the theory does not imply, which is a
    # confidently wrong answer rather than a missing one.
    for (endpoint in c(frm, to)) {
      if (is.na(match(endpoint, declared))) {
        stop("implications requires causal propositions between declared constructs; ",
             "proposition '", pid, "' refers to unknown construct '", endpoint, "'",
             call. = FALSE)
      }
    }
    u <- match(frm, declared)
    v <- match(to, declared)
    if (!any(edge_from == u & edge_to == v)) {
      edge_from <- c(edge_from, u)
      edge_to <- c(edge_to, v)
    }
  }

  used <- sort(unique(c(edge_from, edge_to)))
  nodes <- declared[used]
  k <- length(nodes)
  rank_of <- integer(length(declared))
  rank_of[used] <- seq_along(used)
  adj <- matrix(FALSE, nrow = k, ncol = k)
  for (e in seq_along(edge_from)) {
    adj[rank_of[[edge_from[[e]]]], rank_of[[edge_to[[e]]]]] <- TRUE
  }

  cycle <- .tf_first_cycle(adj, k)
  if (!is.null(cycle)) {
    stop("implications requires an acyclic causal graph; cycle found: ",
         paste(nodes[cycle], collapse = " -> "), call. = FALSE)
  }

  impl <- list()
  if (k >= 2L) {
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        if (adj[i, j] || adj[j, i]) next
        # In a DAG neither member of a non-adjacent pair can be a parent of the
        # other, so the union needs no further exclusion.
        given_idx <- sort(unique(c(which(adj[, i]), which(adj[, j]))))
        given <- nodes[given_idx]
        impl[[length(impl) + 1L]] <- list(
          a = nodes[[i]],
          b = nodes[[j]],
          given = as.list(given),
          statement = .tf_ci_statement(nodes[[i]], nodes[[j]], given)
        )
      }
    }
  }

  list(
    theory_id = .tf_str(T, "id"),
    acyclic = TRUE,
    constructs = as.list(nodes),
    n_edges = length(edge_from),
    implications = impl,
    n_implications = length(impl)
  )
}
