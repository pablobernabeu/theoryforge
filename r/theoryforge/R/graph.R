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
  children <- lapply(seq_len(k), function(u) which(directed[u, ]))
  for (s in seq_len(k)) {
    reach[s, ] <- .tf_reached(children, s, logical(k))
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

# A directed mixed graph prepared for m-separation queries. `parents[[v]]` holds
# the parents of v in vertex order, and `ends_w[[v]]`, `ends_hv[[v]]` and
# `ends_hw[[v]]` the edges at v: the vertex w at the other end, whether the edge
# has an arrowhead at v and whether it has one at w (1 or 0). Both are built
# once, so that a query reads the edges at a vertex without scanning every
# vertex. `reach`, when given, is .tf_reach() of the directed edges, from which
# a query reads ancestors directly.
.tf_mixed_graph <- function(directed, bidirected, reach = NULL) {
  k <- nrow(directed)
  children <- lapply(seq_len(k), function(v) which(directed[v, ]))
  parents <- lapply(seq_len(k), function(v) which(directed[, v]))
  ends_w <- ends_hv <- ends_hw <- vector("list", k)
  for (v in seq_len(k)) {
    joined <- which(bidirected[v, ])
    nc <- length(children[[v]])
    np <- length(parents[[v]])
    nb <- length(joined)
    ends_w[[v]] <- c(children[[v]], parents[[v]], joined)
    ends_hv[[v]] <- c(logical(nc), rep(TRUE, np + nb))
    ends_hw[[v]] <- c(rep(1L, nc), integer(np), rep(1L, nb))
  }
  list(k = k, parents = parents, ends_w = ends_w, ends_hv = ends_hv, ends_hw = ends_hw,
       ends_n = lengths(ends_w), reach = reach)
}

# `g` without the directed edges from u to the vertices in `targets`.
.tf_without_edges <- function(g, u, targets) {
  drop <- g$ends_w[[u]] %in% targets & !g$ends_hv[[u]] & g$ends_hw[[u]] == 1L
  g$ends_w[[u]] <- g$ends_w[[u]][!drop]
  g$ends_hv[[u]] <- g$ends_hv[[u]][!drop]
  g$ends_hw[[u]] <- g$ends_hw[[u]][!drop]
  for (v in unique(targets)) {
    g$parents[[v]] <- g$parents[[v]][g$parents[[v]] != u]
    drop <- g$ends_w[[v]] == u & g$ends_hv[[v]] & g$ends_hw[[v]] == 0L
    g$ends_w[[v]] <- g$ends_w[[v]][!drop]
    g$ends_hv[[v]] <- g$ends_hv[[v]][!drop]
    g$ends_hw[[v]] <- g$ends_hw[[v]][!drop]
  }
  g$ends_n <- lengths(g$ends_w)
  g["reach"] <- list(NULL)
  g
}

# Marks the seeds and every vertex the lists in `adjacent` lead to from one, on
# top of the logical vector `mark`. With each vertex's parents in `adjacent`,
# the marks are the seeds and their ancestors, and with its children, the seeds
# and their descendants. Every vertex that a vertex marked in `mark` leads to
# must be marked there too, as in a result of this function.
.tf_reached <- function(adjacent, seeds, mark) {
  new <- unique(seeds[!mark[seeds]])
  mark[new] <- TRUE
  while (length(new) > 0L) {
    nxt <- unlist(adjacent[new], use.names = FALSE)
    new <- unique(nxt[!mark[nxt]])
    mark[new] <- TRUE
  }
  mark
}

# Whether x and y are m-separated given the vertices in `given`, in the graph
# `g` of .tf_mixed_graph(). A path between x and y connects them given Z when
# every collider on it, a vertex into which both of its edges on the path point,
# is in Z or an ancestor of a member of Z, and no other vertex on it is in Z
# (Richardson, 2003). Without bidirected edges, this is d-separation. `given`
# holds neither x nor y.
#
# The search walks the graph over the states (vertex, whether the walk arrived
# through an arrowhead), so each state is visited once and no path is
# enumerated. A walk that passes the tests at every step can be shortened, and
# detoured through Z at each collider outside Z, into a path that passes them,
# so the walk reaches y exactly when a connecting path exists. Every vertex of a
# connecting path is an ancestor of x, y or a member of Z. From a vertex that is
# not a collider, the path leads along the directions of its edges to x, y or a
# collider, and every collider on it is in Z or an ancestor of a member of Z. The
# walk therefore keeps to those ancestors, which leaves its result unchanged.
# Each round extends every state the previous round found by one edge.
.tf_m_separated <- function(g, x, y, given) {
  k <- g$k
  in_z <- logical(k)
  in_z[given] <- TRUE
  if (is.null(g$reach)) {
    ancestor_of_z <- .tf_reached(g$parents, given, logical(k))
    region <- .tf_reached(g$parents, c(x, y), ancestor_of_z)
  } else {
    ancestor_of_z <- logical(k)
    for (z in given) ancestor_of_z <- ancestor_of_z | g$reach[, z]
    region <- ancestor_of_z | g$reach[, x] | g$reach[, y]
  }
  # The state (v, arrived by a tail) is numbered v, and (v, by an arrowhead)
  # k + v.
  seen <- logical(2L * k)
  w <- g$ends_w[[x]]
  keep <- region[w]
  state <- w[keep] + k * g$ends_hw[[x]][keep]
  while (length(state) > 0L) {
    state <- unique(state[!seen[state]])
    seen[state] <- TRUE
    head_in <- state > k
    v <- state - k * head_in
    if (any(v == y)) return(FALSE)
    n <- g$ends_n[v]
    w <- unlist(g$ends_w[v], use.names = FALSE)
    from <- rep.int(v, n)
    collider <- rep.int(head_in, n) & unlist(g$ends_hv[v], use.names = FALSE)
    # A walk that returns to x can start from x afresh, and those starts are
    # already taken.
    keep <- w != x & region[w] &
      ((collider & ancestor_of_z[from]) | (!collider & !in_z[from]))
    state <- w[keep] + k * unlist(g$ends_hw[v], use.names = FALSE)[keep]
  }
  TRUE
}
