# The causal graph a theory's propositions state (API_SPEC.md sections 27 and
# 31). tf_implications(), tf_entailments(), tf_equivalent_models() and
# tf_discriminate() read the same graph, built here once. The Python twin's
# _causal.py holds the same routine.

# Stops with a refusal of API_SPEC.md sections 27 and 31 to 33: an error of
# class `tf_refusal`, the counterpart of the Python twin's ValueError. The
# functions that report a refusal in place of a result catch this class alone,
# so that any other error surfaces as it does in Python.
.tf_refuse <- function(...) {
  stop(structure(class = c("tf_refusal", "error", "condition"),
                 list(message = paste0(...), call = NULL)))
}

# The construct ids in file order, refusing a repeated id. A construct without
# an id cannot be the endpoint of a proposition, so it is skipped, and two of
# them are no repeat.
.tf_declared_constructs <- function(T, caller) {
  declared <- character(0)
  for (c in .tf_list(T, "constructs")) {
    cid <- .tf_str(c, "id")
    if (!nzchar(cid)) next
    if (cid %in% declared) {
      .tf_refuse(caller, " requires unique construct ids; duplicate construct id: ", cid)
    }
    declared <- c(declared, cid)
  }
  declared
}

# The directed mixed graph of a theory's propositions. `propositions` replaces
# the theory's own propositions when given, which is how a rival stated inside
# an alternative is read over the theory's constructs. Returns `nodes` (the
# constructs that some proposition relates to another, in construct file
# order), the `directed` and
# `bidirected` adjacency matrices, `sign` (for each directed edge, 1, -1 or NA
# when its propositions fix no single sign), `edge_from` and `edge_to` (the
# kept ordered pairs in the order first stated, as vertex indices),
# `edge_props` (the proposition ids behind each kept pair), `assoc` (one row
# per bidirected edge, the smaller vertex first, in the order first stated),
# `assoc_props` and the counts `n_edges` and `n_bidirected`.
.tf_causal_graph <- function(T, caller, propositions = NULL) {
  declared <- .tf_declared_constructs(T, caller)
  props <- if (is.null(propositions)) .tf_list(T, "propositions") else propositions

  edge_from <- integer(0)
  edge_to <- integer(0)
  pair_sign <- integer(0)
  pair_props <- list()
  assoc_from <- character(0)
  assoc_to <- character(0)
  assoc_pid <- character(0)
  for (p in props) {
    rel <- .tf_enum_str(p, "relation", .tf_RELATION)
    frm <- .tf_str(p, "from")
    to <- .tf_str(p, "to")
    pid <- .tf_str(p, "id")
    if (!(rel %in% c(.tf_DIRECTED, .tf_BIDIRECTED))) next
    # Dropping an edge whose endpoint was never declared would shrink the graph
    # and so add independencies the theory does not imply.
    for (endpoint in c(frm, to)) {
      if (is.na(match(endpoint, declared))) {
        kind <- if (rel %in% .tf_DIRECTED) "causal propositions" else "associations"
        .tf_refuse(caller, " requires ", kind, " between declared constructs; ",
                   "proposition '", pid, "' refers to unknown construct '", endpoint, "'")
      }
    }
    if (rel %in% .tf_BIDIRECTED) {
      assoc_from <- c(assoc_from, frm)
      assoc_to <- c(assoc_to, to)
      assoc_pid <- c(assoc_pid, pid)
      next
    }
    u <- match(frm, declared)
    v <- match(to, declared)
    s <- .tf_RELATIONS[[rel]]$sign
    hit <- which(edge_from == u & edge_to == v)
    if (length(hit) == 0L) {
      edge_from <- c(edge_from, u)
      edge_to <- c(edge_to, v)
      pair_sign <- c(pair_sign, s)
      pair_props[[length(pair_props) + 1L]] <- pid
    } else {
      # Two propositions on one ordered pair fix a sign only when they agree.
      if (!identical(pair_sign[[hit]], s)) pair_sign[[hit]] <- NA_integer_
      pair_props[[hit]] <- c(pair_props[[hit]], pid)
    }
  }

  # Every construct a proposition relates to another is a vertex. A construct
  # no proposition names is left out, since silence about it is no claim.
  distinct <- assoc_from != assoc_to
  used <- sort(unique(c(edge_from, edge_to, match(c(assoc_from[distinct], assoc_to[distinct]), declared))))
  nodes <- declared[used]
  k <- length(nodes)
  rank_of <- integer(length(declared))
  rank_of[used] <- seq_along(used)
  directed <- matrix(FALSE, nrow = k, ncol = k)
  sign <- matrix(NA_integer_, nrow = k, ncol = k)
  for (e in seq_along(edge_from)) {
    u <- rank_of[[edge_from[[e]]]]
    v <- rank_of[[edge_to[[e]]]]
    directed[u, v] <- TRUE
    sign[u, v] <- pair_sign[[e]]
  }
  bidirected <- matrix(FALSE, nrow = k, ncol = k)
  assoc <- matrix(integer(0), ncol = 2L)
  assoc_props <- list()
  for (e in seq_along(assoc_from)) {
    # An association of a construct with itself adds nothing, and its construct
    # is a vertex only when another proposition relates it to another.
    if (!distinct[[e]]) next
    a <- match(assoc_from[[e]], nodes)
    b <- match(assoc_to[[e]], nodes)
    lo <- min(a, b)
    hi <- max(a, b)
    if (!bidirected[a, b]) {
      bidirected[a, b] <- TRUE
      bidirected[b, a] <- TRUE
      assoc <- rbind(assoc, c(lo, hi))
      assoc_props[[length(assoc_props) + 1L]] <- assoc_pid[[e]]
    } else {
      row <- which(assoc[, 1L] == lo & assoc[, 2L] == hi)
      assoc_props[[row]] <- c(assoc_props[[row]], assoc_pid[[e]])
    }
  }

  list(
    nodes = nodes,
    directed = directed,
    bidirected = bidirected,
    sign = sign,
    edge_from = if (length(edge_from)) rank_of[edge_from] else integer(0),
    edge_to = if (length(edge_to)) rank_of[edge_to] else integer(0),
    edge_props = pair_props,
    assoc = assoc,
    assoc_props = assoc_props,
    n_edges = length(edge_from),
    n_bidirected = nrow(assoc)
  )
}
