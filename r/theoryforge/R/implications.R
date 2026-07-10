#' Causal-structure analysis and testable implications.
#'
#' The causal subgraph of a theory (propositions whose relation is causal) is
#' analysed deterministically: construct roles (exogenous/endogenous),
#' acyclicity with a topological order, an exhaustive enumeration of feedback
#' loops, and, when the graph is acyclic, the local-Markov basis set of implied
#' conditional independencies (Pearl, 1988). Everything is derived from the
#' theory object alone, with no graph library, so it runs unchanged in webR and
#' is parity-tested against the Python twin. See API_SPEC.md Part F.
#' @name implications
#' @keywords internal
NULL

.tf_IMPL_CAUSAL <- c("causes", "increases", "decreases")

# Deduplicated (from, to) causal edges in proposition file order, as a list of
# character(2) vectors restricted to declared construct ids.
.tf_causal_edges <- function(theory, nodes) {
  edges <- list()
  seen <- character(0)
  for (p in .tf_list(theory, "propositions")) {
    rel <- .tf_str(p, "relation")
    if (!(rel %in% .tf_IMPL_CAUSAL)) next
    f <- .tf_str(p, "from")
    t <- .tf_str(p, "to")
    key <- paste0(f, "\r", t)
    if (f %in% nodes && t %in% nodes && !(key %in% seen)) {
      seen <- c(seen, key)
      edges[[length(edges) + 1L]] <- c(f, t)
    }
  }
  edges
}

# Out-neighbour list (edge file order) for every node.
.tf_out_adj <- function(nodes, edges) {
  out <- stats::setNames(vector("list", length(nodes)), nodes)
  for (n in nodes) out[[n]] <- character(0)
  for (e in edges) out[[e[[1L]]]] <- c(out[[e[[1L]]]], e[[2L]])
  out
}

# Kahn's algorithm with file-order tie-breaking; character(0) when cyclic.
.tf_topo_order <- function(nodes, edges) {
  indeg <- stats::setNames(integer(length(nodes)), nodes)
  for (e in edges) indeg[[e[[2L]]]] <- indeg[[e[[2L]]]] + 1L
  out <- .tf_out_adj(nodes, edges)
  remaining <- nodes
  order <- character(0)
  while (length(remaining) > 0L) {
    head <- NULL
    for (n in remaining) {
      if (indeg[[n]] == 0L) { head <- n; break }
    }
    if (is.null(head)) return(character(0))
    remaining <- remaining[remaining != head]
    order <- c(order, head)
    for (t in out[[head]]) indeg[[t]] <- indeg[[t]] - 1L
  }
  order
}

# Every simple cycle, reported once, starting at its lowest-index node.
# Explicit stack-based DFS mirrors the Python reference exactly.
.tf_feedback_loops <- function(nodes, edges) {
  idx <- stats::setNames(seq_along(nodes), nodes)
  out <- .tf_out_adj(nodes, edges)
  loops <- list()

  walk <- function(s, node, path) {
    for (t in out[[node]]) {
      if (t == s) {
        loops[[length(loops) + 1L]] <<- as.list(path)
      } else if (idx[[t]] > idx[[s]] && !(t %in% path)) {
        walk(s, t, c(path, t))
      }
    }
  }
  for (s in nodes) walk(s, s, s)
  loops
}

# Nodes reachable from `node` via one or more causal edges.
.tf_descendants <- function(node, out) {
  seen <- character(0)
  stack <- out[[node]]
  while (length(stack) > 0L) {
    n <- stack[[length(stack)]]
    stack <- stack[-length(stack)]
    if (!(n %in% seen)) {
      seen <- c(seen, n)
      stack <- c(stack, out[[n]])
    }
  }
  seen
}

#' Analyse a theory's causal structure and derive its testable implications
#'
#' Restricts the propositions to the causal relations (\code{causes},
#' \code{increases}, \code{decreases}) and analyses the resulting directed graph
#' over the constructs: which constructs are exogenous (no incoming causal edge)
#' or endogenous, whether the graph is acyclic (with a deterministic topological
#' order when it is), every feedback loop, and, for acyclic graphs, the
#' local-Markov basis set of implied conditional independencies (each construct
#' is independent of its non-descendants given its direct causes; Pearl, 1988).
#' Each independence claim is directly testable against data, and each feedback
#' loop is a testable dynamic claim, so the result operationalises how exposed
#' the theory's structure is to refutation. Deterministic, dependency-free and
#' parity-tested against the Python \code{theory.implications()}. See
#' API_SPEC.md Part F.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A named list \code{list(constructs, exogenous, endogenous, acyclic,
#'   order, feedback_loops, implications, n_implications)}. \code{order} is the
#'   topological order (empty when the graph is cyclic), each entry of
#'   \code{feedback_loops} lists a loop's constructs starting at its
#'   lowest-index node, and each entry of \code{implications} is
#'   \code{list(a, b, given)}: \code{a} is independent of \code{b} given the
#'   constructs in \code{given}.
#' @references Pearl, J. (1988). \emph{Probabilistic reasoning in intelligent
#'   systems}. Morgan Kaufmann.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_stressor", "Stressor", "Exposure to evaluation.") |>
#'   tf_add_construct("c_appraisal", "Appraisal", "Judged threat of failing.") |>
#'   tf_add_construct("c_anxiety", "Anxiety", "Worry and arousal.") |>
#'   tf_add_proposition("p1", "c_stressor", "c_appraisal", "increases") |>
#'   tf_add_proposition("p2", "c_appraisal", "c_anxiety", "increases")
#' imp <- tf_implications(theory)
#' imp$acyclic
#' imp$implications[[1]]   # c_anxiety independent of c_stressor given c_appraisal
#' @export
tf_implications <- function(theory) {
  cons <- .tf_list(theory, "constructs")
  nodes <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  edges <- .tf_causal_edges(theory, nodes)

  incoming <- unique(vapply(edges, function(e) e[[2L]], character(1)))
  exogenous <- nodes[!(nodes %in% incoming)]
  endogenous <- nodes[nodes %in% incoming]

  order <- .tf_topo_order(nodes, edges)
  acyclic <- length(order) == length(nodes)
  loops <- .tf_feedback_loops(nodes, edges)

  claims <- list()
  if (acyclic) {
    out <- .tf_out_adj(nodes, edges)
    parents <- stats::setNames(vector("list", length(nodes)), nodes)
    for (n in nodes) {
      froms <- vapply(edges, function(e) if (e[[2L]] == n) e[[1L]] else NA_character_, character(1))
      froms <- froms[!is.na(froms)]
      parents[[n]] <- sort(unique(froms), method = "radix")
    }
    emitted <- character(0)
    for (v in nodes) {
      desc <- .tf_descendants(v, out)
      for (u in nodes) {
        if (u == v || u %in% desc || u %in% parents[[v]]) next
        pair <- paste(sort(c(v, u), method = "radix"), collapse = "\r")
        if (pair %in% emitted) next
        emitted <- c(emitted, pair)
        claims[[length(claims) + 1L]] <- list(a = v, b = u, given = as.list(parents[[v]]))
      }
    }
  }

  list(
    constructs = as.list(nodes),
    exogenous = as.list(exogenous),
    endogenous = as.list(endogenous),
    acyclic = acyclic,
    order = if (acyclic) as.list(order) else list(),
    feedback_loops = loops,
    implications = claims,
    n_implications = length(claims)
  )
}
