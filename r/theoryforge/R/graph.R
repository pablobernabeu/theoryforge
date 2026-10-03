# Graph routines behind tf_implications() (API_SPEC.md section 27). A graph has
# the vertices 1 to k. `directed[u, v]` is TRUE for an edge u -> v, and
# `bidirected[u, v]`, kept symmetric, for an edge u <-> v. The Python twin's
# _graph.py holds the same routines.

# Indices of the first cycle found, or NULL when the graph is acyclic. A
# depth-first search that takes start vertices and successors in vertex order,
# so the cycle reported for a given theory is the same one in both engines. The
# returned path repeats its first vertex at the end, and a self loop comes back
# as that vertex twice.
.tf_first_cycle <- function(directed, k) {
  colour <- integer(k)  # 0 unvisited, 1 on the current path, 2 finished
  for (start in seq_len(k)) {
    if (colour[[start]] != 0L) next
    colour[[start]] <- 1L
    path <- start
    stack_v <- start
    stack_i <- 0L  # successors of the vertex already examined
    while (length(stack_v) > 0L) {
      top <- length(stack_v)
      v <- stack_v[[top]]
      nxt <- stack_i[[top]] + 1L
      if (nxt <= k) {
        stack_i[[top]] <- nxt
        if (directed[v, nxt]) {
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

# reach[u, v] is TRUE when a directed path leads from u to v. A path may have no
# edges, so every vertex reaches itself, and reach[u, v] then reads "u is v or
# an ancestor of v".
.tf_reach <- function(directed, k) {
  reach <- matrix(FALSE, nrow = k, ncol = k)
  for (s in seq_len(k)) {
    reach[s, s] <- TRUE
    stack <- s
    while (length(stack) > 0L) {
      u <- stack[[length(stack)]]
      stack <- stack[-length(stack)]
      for (v in which(directed[u, ])) {
        if (!reach[s, v]) {
          reach[s, v] <- TRUE
          stack <- c(stack, v)
        }
      }
    }
  }
  reach
}

# The strongly connected components of a graph whose .tf_reach() is `reach`, as
# a list of integer vectors. Two vertices share a component when each reaches
# the other. The members of a component come in vertex order and the components
# in the order of their first members, so both engines list them alike. A vertex
# on no cycle is a component of its own.
.tf_strong_components <- function(reach) {
  k <- nrow(reach)
  seen <- logical(k)
  out <- list()
  for (i in seq_len(k)) {
    if (seen[[i]]) next
    comp <- which(reach[i, ] & reach[, i])
    seen[comp] <- TRUE
    out[[length(out) + 1L]] <- comp
  }
  out
}

# The acyclification of a directed mixed graph (Bongers et al., 2021, Definition
# A.13), as list(directed, bidirected). `comps` are the strongly connected
# components of `directed`. In the result, j -> i when j is a parent of some
# member of i's component and lies outside it, so every member of a feedback
# loop shares the loop's outside parents. i <-> j, for i and j distinct, when
# the two share a component or some member of i's component and some member of
# j's are joined by a bidirected edge. Sigma-separation in the original graph is
# m-separation in this acyclic one (Proposition A.19).
.tf_acyclify <- function(directed, bidirected, comps) {
  k <- nrow(directed)
  n_comp <- length(comps)
  comp_of <- integer(k)
  for (c in seq_len(n_comp)) comp_of[comps[[c]]] <- c
  # Whether the vertex j is a parent of some member of component c, and whether
  # some members of components c and d are joined by a bidirected edge.
  parent_of_comp <- matrix(FALSE, nrow = n_comp, ncol = k)
  joined <- matrix(FALSE, nrow = n_comp, ncol = n_comp)
  for (u in seq_len(k)) {
    for (v in seq_len(k)) {
      if (directed[u, v]) parent_of_comp[comp_of[[v]], u] <- TRUE
      if (bidirected[u, v]) joined[comp_of[[u]], comp_of[[v]]] <- TRUE
    }
  }
  d_acy <- matrix(FALSE, nrow = k, ncol = k)
  b_acy <- matrix(FALSE, nrow = k, ncol = k)
  for (i in seq_len(k)) {
    for (j in seq_len(k)) {
      d_acy[j, i] <- parent_of_comp[comp_of[[i]], j] && comp_of[[j]] != comp_of[[i]]
      b_acy[i, j] <- i != j &&
        (comp_of[[i]] == comp_of[[j]] || joined[comp_of[[i]], comp_of[[j]]])
    }
  }
  list(directed = d_acy, bidirected = b_acy)
}

# The edges at v as rows (w, arrowhead at v, arrowhead at w), with 1 for an
# arrowhead and 0 for a tail.
.tf_ends <- function(directed, bidirected, v) {
  out <- matrix(integer(0), ncol = 3L)
  for (w in seq_len(nrow(directed))) {
    if (directed[v, w]) out <- rbind(out, c(w, 0L, 1L))
    if (directed[w, v]) out <- rbind(out, c(w, 1L, 0L))
    if (bidirected[v, w]) out <- rbind(out, c(w, 1L, 1L))
  }
  out
}

# Whether x and y are m-separated given the vertices in `given`. A path between
# x and y connects them given Z when every collider on it, a vertex into which
# both of its edges on the path point, is in Z or an ancestor of a member of Z,
# and no other vertex on it is in Z (Richardson, 2003). Without bidirected edges,
# this is d-separation. `reach` is .tf_reach() of the directed edges, and
# `given` holds neither x nor y.
#
# The search walks the graph over the states (vertex, whether the walk arrived
# through an arrowhead), so each state is visited once and no path is
# enumerated. A walk that passes the tests at every step can be shortened, and
# detoured through Z at each collider outside Z, into a path that passes them,
# so the walk reaches y exactly when a connecting path exists.
.tf_m_separated <- function(directed, bidirected, reach, x, y, given) {
  k <- nrow(directed)
  in_z <- logical(k)
  in_z[given] <- TRUE
  ancestor_of_z <- if (length(given) > 0L) {
    apply(reach[, given, drop = FALSE], 1L, any)
  } else {
    logical(k)
  }
  seen <- matrix(FALSE, nrow = k, ncol = 2L)  # column 1 arrived by a tail, 2 by an arrowhead
  start <- .tf_ends(directed, bidirected, x)
  stack_v <- start[, 1L]
  stack_h <- start[, 3L]
  while (length(stack_v) > 0L) {
    top <- length(stack_v)
    v <- stack_v[[top]]
    head_in <- stack_h[[top]]
    stack_v <- stack_v[-top]
    stack_h <- stack_h[-top]
    if (seen[v, head_in + 1L]) next
    seen[v, head_in + 1L] <- TRUE
    if (v == y) return(FALSE)
    ends <- .tf_ends(directed, bidirected, v)
    for (e in seq_len(nrow(ends))) {
      w <- ends[e, 1L]
      # A walk that returns to x can start from x afresh, and those starts are
      # already on the stack.
      if (w == x) next
      if (head_in == 1L && ends[e, 2L] == 1L) {
        if (!ancestor_of_z[[v]]) next
      } else if (in_z[[v]]) {
        next
      }
      stack_v <- c(stack_v, w)
      stack_h <- c(stack_h, ends[e, 3L])
    }
  }
  TRUE
}
