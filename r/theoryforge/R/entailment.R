# What a theory's causal graph entails (API_SPEC.md Part J). The Python twin's
# entailment.py holds the same routines.

.tf_CLAIM_KINDS <- c("effect", "association")
# The largest canonical adjustment set whose subsets are searched for a smallest
# valid one. A larger one is pruned to a minimal valid set (API_SPEC.md
# section 31).
.tf_ADJUSTMENT_SEARCH <- 12L
.tf_CLAIM_SIGNS <- c("positive", "negative", "zero", "nonzero")

# Sign sets as bit masks: the signs that the routes between two constructs take.
# UNK marks a route through a relation that states no sign.
.tf_POS <- 1L
.tf_NEG <- 2L
.tf_UNK <- 4L

# The signs of the products of a sign from `a` and a sign from `b`.
.tf_sign_mul <- function(a, b) {
  if (a == 0L || b == 0L) return(0L)
  out <- if (bitwAnd(a, .tf_UNK) != 0L || bitwAnd(b, .tf_UNK) != 0L) .tf_UNK else 0L
  for (sa in c(.tf_POS, .tf_NEG)) {
    if (bitwAnd(a, sa) == 0L) next
    for (sb in c(.tf_POS, .tf_NEG)) {
      if (bitwAnd(b, sb) == 0L) next
      out <- bitwOr(out, if (sa == sb) .tf_POS else .tf_NEG)
    }
  }
  out
}

# .tf_sign_mul() for every pair of sign sets, so that a product is looked up:
# .tf_MUL[a + 1, b + 1] holds the product of the sets a and b.
.tf_MUL <- matrix(vapply(0:63, function(i) .tf_sign_mul(i %% 8L, i %/% 8L), integer(1)),
                  nrow = 8L, ncol = 8L)

# The strong component of each vertex of the graph G prepared by
# .tf_prepare_graph(), and whether each component is one simple cycle, as
# list(comp, simple). With `held` a vertex, the graph is taken without the edges
# into it. Removing those edges can split the component of `held` and no other,
# so only that one is found again. A component is one simple cycle, a self loop
# included, when it has as many edges as vertices.
.tf_walk_components <- function(G, held = 0L) {
  if (held == 0L) return(list(comp = G$comp, simple = G$simple))
  comp <- G$comp
  simple <- G$simple
  members <- G$comps[[comp[[held]]]]
  sub <- G$directed[members, members, drop = FALSE]
  sub[, members == held] <- FALSE
  for (part in .tf_strong_components(.tf_reach(sub, length(members)))) {
    simple <- c(simple, sum(sub[part, part]) == length(part))
    comp[members[part]] <- length(simple)
  }
  list(comp = comp, simple = simple)
}

# For each vertex, the sign set of the directed walks to it from `start` in the
# graph G prepared by .tf_prepare_graph(). The empty walk counts, so `start`
# holds POS. With `held`, the edges into `start` are left out, so that no walk
# returns to it, as when an intervention holds it fixed. A strong component
# whose edges form one simple cycle, a self loop included, has as many edges as
# vertices, and the effects within it are the path along the cycle times
# 1 / (1 - g), for the cycle's gain g, which is positive whenever the effects
# round the loop die out. A walk that enters such a component therefore never
# closes the cycle back to the vertex where it entered. Other walks may go round
# a loop. The search runs over the states (vertex, sign, the vertex where the
# walk entered its simple cycle or 0), each visited once, so it ends on a graph
# with feedback loops too. Each round extends every state the previous round
# found by one edge.
.tf_walk_signs <- function(G, start, held = FALSE) {
  k <- G$k
  cs <- .tf_walk_components(G, if (held) start else 0L)
  comp <- cs$comp
  simple <- cs$simple
  bits <- c(.tf_POS, .tf_NEG, .tf_UNK)
  # A state is numbered v + k * (i - 1) + 3 * k * (n - 1) for the vertex v, the
  # sign bits[i] and the entry numbered n: 1 for none, and from 2 on for the
  # vertices of simple cycles in vertex order.
  entries <- c(0L, which(simple[comp]))
  # The part of the state number that the entry e gives, at offset[e + 1].
  offset <- integer(k + 1L)
  offset[entries + 1L] <- 3L * k * (seq_along(entries) - 1L)
  masks <- integer(k)
  masks[[start]] <- .tf_POS
  seen <- logical(3L * k * length(entries))
  state <- start + offset[[(if (simple[[comp[[start]]]]) start else 0L) + 1L]]
  seen[state] <- TRUE
  while (length(state) > 0L) {
    s0 <- state - 1L
    v <- s0 %% k + 1L
    n <- lengths(G$children[v])
    w <- unlist(G$children[v], use.names = FALSE)
    v <- rep.int(v, n)
    i <- rep.int((s0 %/% k) %% 3L + 1L, n)
    entry <- rep.int(entries[s0 %/% (3L * k) + 1L], n)
    same <- comp[w] == comp[v]
    keep <- !(same & w == entry)
    if (held) keep <- keep & w != start
    w <- w[keep]
    v <- v[keep]
    i <- i[keep]
    entry <- entry[keep]
    same <- same[keep]
    # The entry stays within a component, and on leaving it is the vertex
    # reached when that vertex's component is a simple cycle, or 0.
    ne <- entry
    out <- !same
    ne[out] <- w[out] * simple[comp[w[out]]]
    nxt <- .tf_MUL[cbind(bits[i] + 1L, G$mask[cbind(v, w)] + 1L)]
    state <- integer(0)
    for (j in 1:3) {
      has <- bitwAnd(nxt, bits[[j]]) != 0L
      masks[w[has]] <- bitwOr(masks[w[has]], bits[[j]])
      state <- c(state, w[has] + k * (j - 1L) + offset[ne[has] + 1L])
    }
    state <- state[!seen[state]]
    if (length(state) > 1L) state <- unique(state)
    seen[state] <- TRUE
  }
  masks
}

# The sign sets of the covariances of every pair of vertices of an acyclic
# graph, as a k by k matrix, by Wright's (1934) rule: the covariance is a sum
# over the simple treks between the two, those whose two directed paths share
# no vertex but their source, each the product of its coefficients and the
# variance of its source. For b that does not reach a, every simple trek
# between them ends in an edge p -> b from a parent p of b, or is an association
# of b with a vertex that reaches a, so the set of (a, b) is the union over the
# parents p of the edge's sign times the set of (a, p), and it gains UNK for
# such an association. The pairs are taken with the vertices in an order in
# which no vertex comes before one that reaches it, and the order does not
# change the result. A trek whose two paths share a segment, such as
# u <- t -> u -> y, holds a coefficient squared, so reading its two copies as
# independent signs would leave a fixed sign open.
.tf_cov_signs <- function(G) {
  k <- G$k
  r <- G$r
  S <- matrix(0L, nrow = k, ncol = k)
  diag(S) <- .tf_POS
  ord <- order(colSums(r), seq_len(k))
  # Each column is filled for all the vertices before b in the order at once.
  for (j in seq_len(k)[-1L]) {
    b <- ord[[j]]
    before <- ord[seq_len(j - 1L)]
    m <- integer(j - 1L)
    for (p in G$parents[[b]]) m <- bitwOr(m, .tf_MUL[G$mask[p, b] + 1L, S[before, p] + 1L])
    joined <- which(G$bidirected[, b])
    if (length(joined) > 0L) {
      open <- colSums(r[joined, before, drop = FALSE]) > 0
      m[open] <- bitwOr(m[open], .tf_UNK)
    }
    S[before, b] <- m
    S[b, before] <- m
  }
  S
}

# The derived sign of a sign set, and the basis of the derivation.
.tf_derived <- function(mask) {
  if (mask == 0L) return(c("zero", "no_path"))
  if (mask == .tf_POS) return(c("positive", "paths_agree"))
  if (mask == .tf_NEG) return(c("negative", "paths_agree"))
  if (bitwAnd(mask, .tf_UNK) != 0L) return(c("undetermined", "unsigned"))
  c("undetermined", "opposite_signs")
}

# Whether a derived sign entails, contradicts or leaves open a claimed one.
.tf_verdict <- function(claimed, derived) {
  if (derived == "zero") return(if (claimed == "zero") "entailed" else "contradicted")
  if (claimed == "zero") return("contradicted")
  if (claimed == "nonzero" || claimed == derived) return("entailed")
  if (derived %in% c("positive", "negative")) return("contradicted")
  "undetermined"
}

# A claim read leniently, or NULL when the value is not a non-empty mapping.
.tf_read_claim <- function(v) {
  if (!is.list(v) || length(v) == 0L || !.tf_is_mapping(v)) return(NULL)
  kind <- .tf_enum_str(v, "kind", .tf_CLAIM_KINDS)
  sign <- .tf_enum_str(v, "sign", .tf_CLAIM_SIGNS)
  x <- .tf_str(v, "x")
  y <- .tf_str(v, "y")
  given <- .tf_str_list(.tf_get(v, "given"))
  ok <- nzchar(kind) && nzchar(sign) && nzchar(x) && nzchar(y) && x != y &&
    !(x %in% given) && !(y %in% given) &&
    !(kind == "effect" && length(given) > 0L) &&
    !(length(given) > 0L && sign %in% c("positive", "negative"))
  list(kind = kind, x = x, y = y, given = given, sign = sign, ok = ok)
}

# Every claim of the theory: predictions first, then phenomena, in file order.
.tf_claims <- function(T) {
  out <- list()
  for (src in list(c("prediction", "predictions"), c("phenomenon", "phenomena"))) {
    for (it in .tf_list(T, src[[2L]])) {
      cl <- .tf_read_claim(.tf_get(it, "claim"))
      if (!is.null(cl)) out[[length(out) + 1L]] <- c(list(source = src[[1L]], id = .tf_str(it, "id")), cl)
    }
  }
  out
}

# A causal graph prepared for reading claims under one `cycles` option.
.tf_prepare_graph <- function(g, cycles, props) {
  k <- length(g$nodes)
  G <- g
  G$k <- k
  # The ids of the propositions, each once in file order, from which a claim's
  # `via` is drawn.
  pids <- vapply(props, function(p) .tf_str(p, "id"), "")
  G$pids <- unique(pids[nzchar(pids)])
  G$children <- lapply(seq_len(k), function(v) which(g$directed[v, ]))
  G$parents <- lapply(seq_len(k), function(v) which(g$directed[, v]))
  # The sign set of each directed edge.
  G$mask <- matrix(.tf_NEG, nrow = k, ncol = k)
  G$mask[is.na(g$sign)] <- .tf_UNK
  G$mask[!is.na(g$sign) & g$sign > 0L] <- .tf_POS
  G$r <- .tf_reach(g$directed, k)
  comps <- .tf_strong_components(G$r)
  G$comps <- comps
  G$comp <- integer(k)
  for (c in seq_along(comps)) G$comp[comps[[c]]] <- c
  G$simple <- vapply(comps, function(m) sum(g$directed[m, m]) == length(m), logical(1))
  feedback <- list()
  for (comp in comps) {
    if (length(comp) > 1L || g$directed[comp[[1L]], comp[[1L]]]) {
      feedback[[length(feedback) + 1L]] <- as.list(g$nodes[comp])
    }
  }
  G$feedback <- feedback
  G$evaluable <- cycles == "sigma" || length(feedback) == 0L
  G$acyclified <- length(feedback) > 0L && cycles == "sigma"
  if (G$acyclified) {
    acy <- .tf_acyclify(g$directed, g$bidirected, comps)
    G$sep_d <- acy$directed
    G$sep_b <- acy$bidirected
  } else {
    G$sep_d <- g$directed
    G$sep_b <- g$bidirected
  }
  G$walk_cache <- new.env(parent = emptyenv())
  G
}

# The graph that separation is read in, prepared by .tf_mixed_graph() when a
# claim first needs it.
.tf_sep_graph <- function(G) {
  if (is.null(G$walk_cache[["sep"]])) {
    r <- if (G$acyclified) .tf_reach(G$sep_d, G$k) else G$r
    G$walk_cache[["sep"]] <- .tf_mixed_graph(G$sep_d, G$sep_b, r)
  }
  G$walk_cache[["sep"]]
}

.tf_walks <- function(G, s) {
  key <- as.character(s)
  if (is.null(G$walk_cache[[key]])) {
    G$walk_cache[[key]] <- .tf_walk_signs(G, s)
  }
  G$walk_cache[[key]]
}

# The ids in `on`, in file order.
.tf_ordered_props <- function(G, on) {
  G$pids[G$pids %in% on]
}

# The sign sets of the walks from `x` that never return to it, in the graph
# without the edges into `x`: the graph an intervention on `x` leaves.
.tf_held <- function(G, x) {
  key <- paste0("held", x)
  if (is.null(G$walk_cache[[key]])) {
    G$walk_cache[[key]] <- .tf_walk_signs(G, x, held = TRUE)
  }
  G$walk_cache[[key]]
}

# The derived sign of the effect of x on y, its basis and, with `via`, the
# propositions on a directed walk from x to y that does not return to x, a
# directed path when the graph is acyclic.
.tf_effect <- function(G, x, y, via = TRUE) {
  # An intervention on x replaces its own equation, so a walk that comes back
  # to x carries nothing to y. In an acyclic graph no walk does.
  d <- .tf_derived(.tf_held(G, x)[[y]])
  if (!via) return(list(derived = d[[1L]], basis = d[[2L]], via = character(0)))
  # The paths run in the graph without the edges into x: from x, which reaches
  # the same vertices there, to y along vertices that reach y without passing
  # through x.
  parents <- G$parents
  parents[[x]] <- integer(0)
  to_y <- .tf_reached(parents, y, logical(G$k))
  from_x <- G$r[x, ]
  hit <- G$edge_to != x & from_x[G$edge_from] & to_y[G$edge_to]
  on <- unlist(G$edge_props[hit], use.names = FALSE)
  list(derived = d[[1L]], basis = d[[2L]], via = .tf_ordered_props(G, on))
}

# The derived sign of the association of x and y, its basis and, with `via`,
# the propositions on a trek between the two.
.tf_association <- function(G, x, y, via = TRUE) {
  r <- G$r
  na <- nrow(G$assoc)
  if (length(G$feedback) == 0L) {
    if (is.null(G$walk_cache[["cov"]])) G$walk_cache[["cov"]] <- .tf_cov_signs(G)
    mask <- G$walk_cache[["cov"]][x, y]
  } else {
    # With feedback loops, the treks are read as pairs of walks from a common
    # source, which counts a trek whose two walks share a segment as well. A
    # source that does not reach both adds nothing.
    mask <- 0L
    for (t in which(r[, x] & r[, y])) {
      walks <- .tf_walks(G, t)
      mask <- bitwOr(mask, .tf_MUL[walks[[x]] + 1L, walks[[y]] + 1L])
    }
    for (row in seq_len(na)) {
      a <- G$assoc[row, 1L]
      b <- G$assoc[row, 2L]
      if ((r[a, x] && r[b, y]) || (r[a, y] && r[b, x])) mask <- bitwOr(mask, .tf_UNK)
    }
  }
  d <- .tf_derived(mask)
  if (!via) return(list(derived = d[[1L]], basis = d[[2L]], via = character(0)))
  # An edge u -> v lies on a trek between x and y when v reaches one of the two
  # and u is near the other: u has an ancestor in common with it, or descends
  # from one end of an association whose other end reaches it. near_x marks the
  # vertices near x, the descendants of x's ancestors and of the ends whose
  # other end reaches x.
  to_x <- r[, x]
  to_y <- r[, y]
  p <- c(G$assoc[, 1L], G$assoc[, 2L])
  q <- c(G$assoc[, 2L], G$assoc[, 1L])
  near_x <- colSums(r[c(which(to_x), p[to_x[q]]), , drop = FALSE]) > 0
  near_y <- colSums(r[c(which(to_y), p[to_y[q]]), , drop = FALSE]) > 0
  u <- G$edge_from
  v <- G$edge_to
  hit <- (to_x[v] & near_y[u]) | (to_y[v] & near_x[u])
  on <- unlist(G$edge_props[hit], use.names = FALSE)
  for (row in seq_len(na)) {
    a <- G$assoc[row, 1L]
    b <- G$assoc[row, 2L]
    if ((r[a, x] && r[b, y]) || (r[a, y] && r[b, x])) on <- c(on, G$assoc_props[[row]])
  }
  list(derived = d[[1L]], basis = d[[2L]], via = .tf_ordered_props(G, on))
}

# A set of constructs whose adjustment identifies the effect of x on y, as
# vertex indices, or NULL. A set is valid when it holds no descendant of a
# vertex on a proper causal path from x to y and m-separates the two once the
# first edge of each such path is removed. The ancestors of x and y that meet
# the first condition and are not marked latent form the canonical set, which
# is valid if any set of constructs that are not marked latent is (van der
# Zander et al., 2019). Its subsets are tried by size and, within a size, in
# vertex order, and the first valid one, a smallest, is returned. A canonical
# set of more than .tf_ADJUSTMENT_SEARCH members is pruned instead: each
# member in turn, in vertex order, is dropped when the others left still
# separate the two, which leaves a minimal valid set. A graph with feedback
# loops gets NULL, since the criterion is not established for it.
.tf_adjustment <- function(G, x, y) {
  if (length(G$feedback) > 0L) return(NULL)
  k <- G$k
  r <- G$r
  on_path <- which(seq_len(k) != x & r[x, ] & r[, y])
  forbidden <- unique(c(x, which(colSums(r[on_path, , drop = FALSE]) > 0)))
  canonical <- setdiff(which((r[, x] | r[, y]) & !G$latent), c(forbidden, y))
  # The proper back-door graph. Without feedback loops, separation is read in
  # the theory's own graph.
  d <- .tf_without_edges(.tf_sep_graph(G), x, on_path)
  if (!.tf_m_separated(d, x, y, canonical)) return(NULL)
  if (length(canonical) > .tf_ADJUSTMENT_SEARCH) {
    # Every member is an ancestor of x or y in the proper back-door graph, and
    # separation by such sets is separation in one undirected graph, so a
    # member kept once stays needed and one pass gives a minimal set.
    z <- canonical
    for (v in canonical) {
      rest <- z[z != v]
      if (.tf_m_separated(d, x, y, rest)) z <- rest
    }
    return(z)
  }
  for (size in 0:length(canonical)) {
    # combn() reads a single number as the range 1:n, so a one-member set is
    # its own only subset of size one.
    subsets <- if (size == 0L) {
      list(integer(0))
    } else if (length(canonical) == 1L) {
      list(canonical)
    } else {
      utils::combn(canonical, size, simplify = FALSE)
    }
    for (z in subsets) {
      if (.tf_m_separated(d, x, y, z)) return(z)
    }
  }
  canonical
}

# The derivation of one claim: list(derived, verdict, basis, faithfulness, via,
# identified, adjustment). The last two are NA except for an evaluated effect
# claim on an acyclic graph, and adjustment is NA too when identified is FALSE.
.tf_read_with <- function(G, cl) {
  out <- function(derived, verdict, basis, faithfulness = FALSE, via = character(0),
                  adjust = NULL) {
    list(derived = derived, verdict = verdict, basis = basis,
         faithfulness = faithfulness, via = as.list(via),
         identified = if (is.null(adjust)) NA else adjust$identified,
         adjustment = if (is.null(adjust) || !adjust$identified) NA else as.list(G$nodes[adjust$set]))
  }
  if (!cl$ok) return(out("", "not_evaluated", "malformed_claim"))
  if (!all(c(cl$x, cl$y, cl$given) %in% G$nodes)) return(out("", "not_evaluated", "not_in_graph"))
  if (!G$evaluable) return(out("", "not_evaluated", "feedback_loop"))
  x <- match(cl$x, G$nodes)
  y <- match(cl$y, G$nodes)
  if (cl$kind == "association" && length(cl$given) > 0L) {
    z <- match(cl$given, G$nodes)
    if (.tf_m_separated(.tf_sep_graph(G), x, y, z)) {
      return(out("zero", .tf_verdict(cl$sign, "zero"), "separated"))
    }
    return(out("nonzero", .tf_verdict(cl$sign, "nonzero"), "connected", faithfulness = TRUE))
  }
  adjust <- NULL
  if (cl$kind == "effect") {
    d <- .tf_effect(G, x, y)
    if (length(G$feedback) == 0L) {
      z <- .tf_adjustment(G, x, y)
      adjust <- list(identified = !is.null(z), set = z)
    }
  } else {
    d <- .tf_association(G, x, y)
  }
  verdict <- .tf_verdict(cl$sign, d$derived)
  # A route of no fixed sign, or routes of opposite signs, make the quantity
  # nonzero only if the effects they carry do not cancel exactly, which is
  # faithfulness.
  faithful <- d$derived == "undetermined" && verdict != "undetermined"
  out(d$derived, verdict, d$basis, faithfulness = faithful, via = d$via, adjust = adjust)
}

.tf_check_cycles <- function(cycles, caller) {
  if (!is.character(cycles) || length(cycles) != 1L || is.na(cycles) ||
      !(cycles %in% c("refuse", "sigma"))) {
    .tf_refuse(caller, " requires cycles to be 'refuse' or 'sigma'")
  }
}

.tf_tally <- function(verdicts) {
  out <- list(entailed = 0L, contradicted = 0L, undetermined = 0L, not_evaluated = 0L)
  for (v in verdicts) out[[v]] <- out[[v]] + 1L
  out
}

#' Read each claim of a theory against its causal graph
#'
#' A prediction or a phenomenon may state a machine-readable \code{claim}
#' about two constructs, \code{x} and \code{y}. An \code{effect} claim concerns
#' the total effect of \code{x} on \code{y}, how \code{y} responds when
#' \code{x} is set by intervention. An \code{association} claim concerns the
#' dependence between the two, given the constructs in \code{given} when there
#' are any. The \code{sign} is \code{positive}, \code{negative}, \code{zero} or
#' \code{nonzero}, and a conditional association can only be \code{zero} or
#' \code{nonzero}.
#'
#' The graph is the one [tf_implications()] reads. \code{increases} carries a
#' positive sign and \code{decreases} a negative one, and the other relations
#' state no sign. The sign of an effect is the product of the signs along each
#' directed path from \code{x} to \code{y}, and the sign of a marginal
#' association the product along each simple trek, a pair of directed paths
#' from a common source to the two constructs that share no other construct,
#' or a directed path from each end of an association to the two constructs
#' that share no construct. A trek topped by an association has no fixed sign.
#' When every path or trek has the same sign, the graph fixes the sign of the
#' quantity, and when none exists, the quantity is zero (Wright, 1934). A trek
#' whose two paths share a construct adds no term of its own, since the
#' product of the coefficients that lead to the construct they share is part
#' of that construct's variance, so when \code{t} causes \code{u} and
#' \code{u} increases \code{y}, \code{u} and \code{y} are positively
#' associated. A conditional association is zero when the two constructs are
#' m-separated given the others and nonzero otherwise.
#'
#' Each claim is then \code{entailed}, \code{contradicted},
#' \code{undetermined} when the graph leaves the sign open, or
#' \code{not_evaluated} when the claim is incomplete, names a construct that no
#' proposition relates to another, or meets a feedback loop under
#' \code{cycles = "refuse"}. \code{faithfulness} is \code{TRUE} when the
#' verdict relies on the effects carried by a route of unknown sign, or by
#' routes of opposite signs, not cancelling exactly, and the claim lines of the
#' preregistration and the dossier then end with \code{unless effects cancel
#' exactly}.
#'
#' The derivations assume that the graph is the causal structure, with no
#' common cause of two constructs left out unless an association stands for
#' it, and that each directed relation acts in its stated direction whatever
#' the other inputs, as in a linear model or a uniformly monotone one
#' (VanderWeele & Robins, 2010). Under \code{cycles = "sigma"}, each feedback
#' loop is assumed to settle to a unique equilibrium. The sign of an effect
#' further assumes that the system with the intervened construct held fixed is
#' stable, so that the effects round each loop that remains die out. Stability
#' of the system as observed is not enough, since holding a construct fixed
#' can leave a loop that does not settle. A loop that is one simple cycle then
#' multiplies the effects through it by a positive factor, so the signs through
#' it are those of the paths. The walks round a loop of any other shape are
#' read as they are, and a graph with feedback loops reads each trek as a pair
#' of walks from a common source, so a sign that the graph fixes can be left
#' open there.
#'
#' For an effect claim on an acyclic graph, \code{identified} says whether
#' adjusting for some set of the theory's constructs would identify the effect
#' from observational data (van der Zander et al., 2019), and
#' \code{adjustment} gives a smallest such set. When more than 12 constructs
#' are candidates, it gives a minimal set instead, from which none can be
#' dropped, though a smaller one may exist. A construct marked
#' \code{x_latent: true}, as [tf_read_dagitty()] marks an unobserved variable,
#' is never adjusted for. \code{identified} reports identification by
#' adjustment alone, so an effect without an adjustment set may still be
#' identified by other means, by the front-door criterion for instance, and
#' when \code{x} is not an ancestor of \code{y} the effect is zero. When
#' \code{x} or \code{y} is itself marked latent, the set is reported all the
#' same, and using it assumes a measure of that construct.
#'
#' @param theory A theory object.
#' @param cycles \code{"refuse"} (the default) or \code{"sigma"}, as in
#'   [tf_implications()].
#' @return A list with \code{theory_id}, \code{criterion}, \code{acyclic},
#'   \code{feedback}, \code{claims} and \code{counts}. Each claim is a list of
#'   \code{source}, \code{id}, \code{kind}, \code{x}, \code{y}, \code{given},
#'   \code{sign}, \code{derived}, \code{verdict}, \code{basis},
#'   \code{faithfulness}, \code{via}, \code{identified} and \code{adjustment}.
#'   \code{via} lists the propositions on some path or trek between the two
#'   constructs. \code{identified} is \code{TRUE} or \code{FALSE} for an
#'   evaluated effect claim on an acyclic graph and \code{NA} for any other
#'   claim, and \code{adjustment} lists the ids of the set when
#'   \code{identified} is \code{TRUE} and is \code{NA} otherwise. The
#'   predictions come first and then the phenomena, each in file order.
#'   \code{counts} tallies the verdicts.
#' @references
#' van der Zander, B., Liśkiewicz, M., & Textor, J. (2019). Separators and
#' adjustment sets in causal graphs: Complete criteria and an algorithmic
#' framework. \emph{Artificial Intelligence}, \emph{270}, 1--40.
#' \doi{10.1016/j.artint.2018.12.006}
#'
#' VanderWeele, T. J., & Robins, J. M. (2010). Signed directed acyclic graphs
#' for causal inference. \emph{Journal of the Royal Statistical Society Series
#' B: Statistical Methodology}, \emph{72}(1), 111--127.
#' \doi{10.1111/j.1467-9868.2009.00728.x}
#'
#' Wright, S. (1934). The method of path coefficients. \emph{The Annals of
#' Mathematical Statistics}, \emph{5}(3), 161--215.
#' \doi{10.1214/aoms/1177732676}
#' @family causal reading
#' @examples
#' t <- tf_read(tf_example_path("modality-switching.theory.yaml"))
#' e <- tf_entailments(t)
#' vapply(e$claims, function(x) paste(x$id, x$verdict), "")
#' @export
tf_entailments <- function(theory, cycles = "refuse") {
  .tf_check_cycles(cycles, "entailments")
  T <- theory
  G <- .tf_prepare_graph(.tf_causal_graph(T, "entailments"), cycles, .tf_list(T, "propositions"))
  records <- list()
  for (cl in .tf_claims(T)) {
    rec <- c(cl[c("source", "id", "kind", "x", "y")], list(given = as.list(cl$given), sign = cl$sign),
             .tf_read_with(G, cl))
    records[[length(records) + 1L]] <- rec
  }
  list(
    theory_id = .tf_str(T, "id"),
    criterion = if (cycles == "sigma") "sigma" else "m",
    acyclic = length(G$feedback) == 0L,
    feedback = G$feedback,
    claims = records,
    counts = .tf_tally(vapply(records, function(r) r$verdict, ""))
  )
}

# The verdict on each prediction's claim, under the theory and under each
# alternative that states propositions: NULL for a prediction without a claim,
# otherwise list(theory, rivals). The checklist's diagnosticity item reads the
# graphs with the checklist's own cycles, "refuse" by default, and a graph that
# would be refused gives no verdicts.
.tf_prediction_verdicts <- function(T, cycles = "refuse") {
  preds <- .tf_list(T, "predictions")
  focal <- tryCatch(
    .tf_prepare_graph(.tf_causal_graph(T, "check"), cycles, .tf_list(T, "propositions")),
    tf_refusal = function(e) NULL)
  if (is.null(focal)) return(vector("list", length(preds)))
  rivals <- list()
  for (a in .tf_list(T, "alternatives")) {
    aid <- .tf_str(a, "id")
    props <- .tf_list(a, "propositions")
    if (!nzchar(aid) || length(props) == 0L || !is.null(rivals[[aid]])) next
    g <- tryCatch(
      .tf_prepare_graph(.tf_causal_graph(T, "check", propositions = props), cycles, props),
      tf_refusal = function(e) NULL)
    if (!is.null(g)) rivals[[aid]] <- g
  }
  out <- vector("list", length(preds))
  for (i in seq_along(preds)) {
    cl <- .tf_read_claim(.tf_get(preds[[i]], "claim"))
    if (is.null(cl)) next
    out[[i]] <- list(theory = .tf_read_with(focal, cl)$verdict,
                     rivals = lapply(rivals, function(g) .tf_read_with(g, cl)$verdict))
  }
  out
}

.tf_ASSOCIATED <- c(positive = "are positively associated", negative = "are negatively associated",
                    zero = "are independent", nonzero = "are associated")
.tf_UNDETERMINED <- c(unsigned = "a route between them passes through a relation that states no sign",
                      opposite_signs = "routes between them have opposite signs")
.tf_NOT_EVALUATED <- c(malformed_claim = "the claim is incomplete",
                       not_in_graph = "it names a construct that no proposition relates to another",
                       feedback_loop = "the causal graph has a feedback loop",
                       graph_refused = "the causal graph cannot be built")

# What the verdicts of the claim lines assume, written once in each section of
# the preregistration and the dossier that prints them (API_SPEC.md section
# 31). A verdict that rests on faithfulness says so in its line.
.tf_CLAIM_ASSUMPTIONS <- paste0(
  "The verdicts on the claims assume that the graph of the propositions is the causal ",
  "structure, with no omitted common cause of two of its constructs, that each directed ",
  "relation acts in its stated direction whatever the other inputs (as in a linear model ",
  "or a uniformly monotone one), that effects do not cancel exactly where a verdict says ",
  "'unless effects cancel exactly' (faithfulness) and, for feedback loops read by ",
  "sigma-separation, that each loop settles to a unique equilibrium, also once the ",
  "intervened construct is held fixed.")

# A claim and what the causal graph says of it, in words, as the
# preregistration and the dossier print it (API_SPEC.md section 11). A verdict
# whose record carries faithfulness TRUE holds only if no effects cancel
# exactly, and its line says so.
.tf_claim_line <- function(rec) {
  if (rec$basis == "malformed_claim") return("incomplete, so not evaluated")
  x <- rec$x
  y <- rec$y
  sign <- rec$sign
  given <- unlist(rec$given)
  if (rec$kind == "effect") {
    word <- switch(sign, zero = "is zero", nonzero = "is not zero", paste("is", sign))
    claim <- paste0("the effect of ", x, " on ", y, " ", word)
  } else {
    claim <- paste(x, "and", y, .tf_ASSOCIATED[[sign]])
    if (length(given)) claim <- paste0(claim, " given ", paste(given, collapse = ", "))
  }
  via <- unlist(rec$via)
  # A record built for a graph that cannot be read has no faithfulness field.
  faith <- if (isTRUE(rec$faithfulness)) ", unless effects cancel exactly" else ""
  said <- switch(rec$verdict,
    entailed = paste0("entailed by the causal graph",
                      if (length(via)) paste0(" through ", paste(via, collapse = ", ")) else "",
                      faith),
    contradicted = paste0("contradicted by the causal graph", faith),
    undetermined = paste0("left open by the causal graph, since ", .tf_UNDETERMINED[[rec$basis]]),
    paste0("not evaluated, since ", .tf_NOT_EVALUATED[[rec$basis]]))
  paste0(claim, "; ", said)
}

.tf_skeleton <- function(directed) directed | t(directed)

# The unshielded colliders a -> c <- b, with a before b, as rows (a, c, b) in
# vertex order.
.tf_v_structures <- function(directed) {
  k <- nrow(directed)
  adj <- .tf_skeleton(directed)
  rows <- vector("list", k)
  for (c in seq_len(k)) {
    parents <- which(directed[, c])
    if (length(parents) < 2L) next
    n <- length(parents)
    a <- parents[rep.int(seq_len(n - 1L), (n - 1L):1)]
    b <- parents[sequence((n - 1L):1, from = 2:n)]
    open <- !adj[cbind(a, b)]
    if (any(open)) rows[[c]] <- c(rbind(a[open], c, b[open]))
  }
  matrix(as.integer(unlist(rows)), ncol = 3L, byrow = TRUE)
}

# Which edges of a DAG keep their direction in every Markov-equivalent DAG:
# the edges of the v-structures, then Meek's (1995) rules R1 to R3 until none
# applies. The result is the essential graph (Andersson et al., 1997), whatever
# order the rules are applied in.
.tf_compelled <- function(directed) {
  k <- nrow(directed)
  adj <- .tf_skeleton(directed)
  comp <- matrix(FALSE, nrow = k, ncol = k)
  vs <- .tf_v_structures(directed)
  for (row in seq_len(nrow(vs))) {
    comp[vs[row, 1L], vs[row, 2L]] <- TRUE
    comp[vs[row, 3L], vs[row, 2L]] <- TRUE
  }
  children <- lapply(seq_len(k), function(v) which(directed[v, ]))
  parents <- lapply(seq_len(k), function(v) which(directed[, v]))
  # Only directed edges are ever compelled, so each rule need look only at the
  # parents or children concerned.
  changed <- TRUE
  while (changed) {
    changed <- FALSE
    for (x in seq_len(k)) {
      for (y in children[[x]]) {
        if (comp[x, y] || comp[y, x]) next
        z <- parents[[x]]
        r1 <- any(comp[z, x] & !adj[z, y] & z != y)
        z <- children[[x]]
        r2 <- any(comp[x, z] & comp[z, y])
        z <- parents[[y]]
        near <- z[comp[z, y] & adj[x, z] & !comp[x, z] & !comp[z, x]]
        r3 <- length(near) >= 2L && !all(adj[near, near][upper.tri(diag(length(near)))])
        if (r1 || r2 || r3) {
          comp[x, y] <- TRUE
          changed <- TRUE
        }
      }
    }
  }
  comp
}

#' Report which causal directions no test of conditional independence can settle
#'
#' Two causal graphs that imply the same conditional independencies are Markov
#' equivalent, and no test of conditional independence can tell them apart
#' (Verma & Pearl, 1990/2022). For an acyclic graph of directed relations, they
#' are the graphs with the same skeleton and the same unshielded colliders. An
#' edge is \code{compelled} when it points the same way in every graph
#' equivalent to the theory's, and \code{reversible} when some equivalent graph
#' reverses it. Telling the direction of a reversible edge needs an
#' intervention, a temporal order or distributional assumptions, such as
#' non-Gaussian errors. The function does not know which constructs a study
#' manipulates, so an edge out of a manipulated construct can be listed as
#' reversible although the experiment settles its direction. The same problem
#' in structural equation modelling is that of equivalent models (MacCallum et
#' al., 1993).
#'
#' @param theory A theory object.
#' @return A list with \code{theory_id}, \code{computed}, \code{reason},
#'   \code{constructs}, \code{v_structures}, \code{edges}, \code{n_compelled}
#'   and \code{n_reversible}. \code{computed} is \code{FALSE}, with
#'   \code{reason} \code{"feedback_loop"} or \code{"associations"}, when the
#'   graph has a feedback loop or states an association, since the rule holds
#'   for acyclic graphs of directed relations alone. Each edge, in the order
#'   the theory first states it, is a list of \code{from}, \code{to},
#'   \code{propositions} and \code{status}.
#' @references
#' Andersson, S. A., Madigan, D., & Perlman, M. D. (1997). A characterization
#' of Markov equivalence classes for acyclic digraphs. \emph{The Annals of
#' Statistics}, \emph{25}(2), 505--541. \doi{10.1214/aos/1031833662}
#'
#' MacCallum, R. C., Wegener, D. T., Uchino, B. N., & Fabrigar, L. R. (1993).
#' The problem of equivalent models in applications of covariance structure
#' analysis. \emph{Psychological Bulletin}, \emph{114}(1), 185--199.
#' \doi{10.1037/0033-2909.114.1.185}
#'
#' Meek, C. (1995). Causal inference and causal explanation with background
#' knowledge. In P. Besnard & S. Hanks (Eds.), \emph{Proceedings of the
#' Eleventh Conference on Uncertainty in Artificial Intelligence} (pp.
#' 403--410). Morgan Kaufmann.
#'
#' Verma, T. S., & Pearl, J. (2022). Equivalence and synthesis of causal
#' models. In H. Geffner, R. Dechter, & J. Y. Halpern (Eds.),
#' \emph{Probabilistic and causal inference: The works of Judea Pearl} (pp.
#' 221--236). Association for Computing Machinery.
#' \doi{10.1145/3501714.3501732} (Original work published 1990)
#' @family causal reading
#' @examples
#' t <- tf_read(tf_example_path("modality-switching.theory.yaml"))
#' eq <- tf_equivalent_models(t)
#' vapply(eq$edges, function(e) paste(e$from, "->", e$to, e$status), "")
#' @export
tf_equivalent_models <- function(theory) {
  T <- theory
  g <- .tf_causal_graph(T, "equivalent_models")
  k <- length(g$nodes)
  comps <- .tf_strong_components(.tf_reach(g$directed, k))
  cyclic <- any(vapply(comps, function(c) length(c) > 1L || g$directed[c[[1L]], c[[1L]]], logical(1)))
  reason <- if (cyclic) "feedback_loop" else if (g$n_bidirected > 0L) "associations" else NA_character_
  out <- list(
    theory_id = .tf_str(T, "id"),
    computed = is.na(reason),
    reason = reason,
    constructs = as.list(g$nodes),
    v_structures = list(),
    edges = list(),
    n_compelled = 0L,
    n_reversible = 0L
  )
  if (!is.na(reason)) return(out)
  comp <- .tf_compelled(g$directed)
  vs <- .tf_v_structures(g$directed)
  for (row in seq_len(nrow(vs))) {
    out$v_structures[[row]] <- list(a = g$nodes[[vs[row, 1L]]], collider = g$nodes[[vs[row, 2L]]],
                                    b = g$nodes[[vs[row, 3L]]])
  }
  for (e in seq_along(g$edge_from)) {
    u <- g$edge_from[[e]]
    v <- g$edge_to[[e]]
    status <- if (comp[u, v]) "compelled" else "reversible"
    out$edges[[e]] <- list(from = g$nodes[[u]], to = g$nodes[[v]],
                           propositions = as.list(g$edge_props[[e]]), status = status)
    key <- paste0("n_", status)
    out[[key]] <- out[[key]] + 1L
  }
  out
}

# The latent projection of an acyclic graph onto the constructs in `keep`:
# a -> b when a directed path leads from a to b through dropped constructs
# only, and a <-> b when a trek joins them through dropped constructs only, by
# a dropped common source or an association, with an arrowhead at both ends.
# Separation among the kept constructs is unchanged (Verma & Pearl, 1990/2022).
.tf_project <- function(G, keep) {
  kept <- match(keep, G$nodes)
  is_kept <- logical(G$k)
  is_kept[kept] <- TRUE
  # The kept vertices reached from s by a path whose interior is all dropped.
  down <- function(s) {
    seen <- logical(G$k)
    seen[[s]] <- TRUE
    found <- logical(G$k)
    frontier <- s
    while (length(frontier) > 0L) {
      w <- unlist(G$children[frontier], use.names = FALSE)
      w <- unique(w[!seen[w]])
      seen[w] <- TRUE
      found[w[is_kept[w]]] <- TRUE
      frontier <- w[!is_kept[w]]
    }
    which(found)
  }
  reach_kept <- lapply(seq_len(G$k), function(v) if (is_kept[[v]]) v else down(v))
  n <- length(kept)
  pos <- integer(G$k)
  pos[kept] <- seq_len(n)
  d <- matrix(FALSE, nrow = n, ncol = n)
  b <- matrix(FALSE, nrow = n, ncol = n)
  for (v in kept) d[pos[[v]], pos[down(v)]] <- TRUE
  for (t in seq_len(G$k)) {
    if (is_kept[[t]]) next
    ends <- pos[reach_kept[[t]]]
    b[ends, ends] <- TRUE
  }
  for (row in seq_len(nrow(G$assoc))) {
    i <- pos[reach_kept[[G$assoc[row, 1L]]]]
    j <- pos[reach_kept[[G$assoc[row, 2L]]]]
    b[i, j] <- TRUE
    b[j, i] <- TRUE
  }
  diag(b) <- FALSE
  list(directed = d, bidirected = b)
}

# The parents of both, or failing that all their other ancestors, when that set
# separates i and j; NULL otherwise. `g` is the acyclic graph of `d` and `bd`
# from .tf_mixed_graph(), and `dag` is TRUE when it has no bidirected edges, in
# which case the parents always separate the two (API_SPEC.md section 27).
.tf_separating_set <- function(d, bd, g, dag, i, j) {
  if (d[i, j] || d[j, i] || bd[i, j]) return(NULL)
  parents <- which(d[, i] | d[, j])
  if (dag || .tf_m_separated(g, i, j, parents)) return(parents)
  ancestors <- setdiff(which(g$reach[, i] | g$reach[, j]), c(i, j))
  if (.tf_m_separated(g, i, j, ancestors)) return(ancestors)
  NULL
}

.tf_discriminating_independencies <- function(shared, views) {
  n <- length(shared)
  graphs <- lapply(views, function(v) .tf_mixed_graph(v$directed, v$bidirected, .tf_reach(v$directed, n)))
  dags <- vapply(views, function(v) !any(v$bidirected), logical(1))
  out <- list()
  if (n < 2L) return(out)
  for (i in seq_len(n - 1L)) {
    for (j in (i + 1L):n) {
      for (side in list(list("theory", 1L, 2L), list("rival", 2L, 1L))) {
        mine <- side[[2L]]
        theirs <- side[[3L]]
        sep <- .tf_separating_set(views[[mine]]$directed, views[[mine]]$bidirected,
                                  graphs[[mine]], dags[[mine]], i, j)
        if (is.null(sep)) next
        if (!.tf_m_separated(graphs[[theirs]], i, j, sep)) {
          given <- shared[sep]
          out[[length(out) + 1L]] <- list(a = shared[[i]], b = shared[[j]], given = as.list(given),
                                          statement = .tf_ci_statement(shared[[i]], shared[[j]], given),
                                          implied_by = side[[1L]])
        }
      }
    }
  }
  out
}

.tf_sign_differences <- function(shared, focal, other) {
  fixed <- c("positive", "negative", "zero")
  effects <- list()
  for (x in shared) {
    for (y in shared) {
      if (x == y) next
      a <- .tf_effect(focal, match(x, focal$nodes), match(y, focal$nodes), via = FALSE)$derived
      b <- .tf_effect(other, match(x, other$nodes), match(y, other$nodes), via = FALSE)$derived
      if (a != b) {
        effects[[length(effects) + 1L]] <- list(x = x, y = y, theory = a, rival = b,
                                                decisive = a %in% fixed && b %in% fixed)
      }
    }
  }
  associations <- list()
  n <- length(shared)
  if (n >= 2L) {
    for (i in seq_len(n - 1L)) {
      for (j in (i + 1L):n) {
        x <- shared[[i]]
        y <- shared[[j]]
        a <- .tf_association(focal, match(x, focal$nodes), match(y, focal$nodes), via = FALSE)$derived
        b <- .tf_association(other, match(x, other$nodes), match(y, other$nodes), via = FALSE)$derived
        if (a != b) {
          associations[[length(associations) + 1L]] <- list(a = x, b = y, theory = a, rival = b,
                                                            decisive = a %in% fixed && b %in% fixed)
        }
      }
    }
  }
  list(effects = effects, associations = associations)
}

#' Compare a theory with a rival account of the same constructs
#'
#' Sets the causal graph of a theory against that of a rival and lists what
#' would tell the two apart. \code{rival} is the id of one of the theory's
#' alternatives that states \code{propositions} over the theory's constructs,
#' or a theory object of its own, whose constructs are matched to the theory's
#' by id. The graphs are compared on the constructs that both graphs contain,
#' those that some proposition of each, directed or an association, relates to
#' another construct.
#'
#' \code{independencies} lists each conditional independence that one graph
#' implies and the other does not, with the graph that implies it. When the
#' two graphs name different constructs, each is first projected onto the
#' shared ones. \code{effects} and \code{associations} list each pair of shared
#' constructs whose total effect, or marginal association, takes a different
#' derived sign under the two graphs, and \code{decisive} is \code{TRUE} when
#' both signs are fixed. \code{claims} reads every claim of the theory's
#' predictions and phenomena under both graphs, as [tf_entailments()] does, and
#' \code{discriminates} is \code{TRUE} when one graph entails the claim and the
#' other contradicts it. \code{markov_equivalent} is \code{TRUE} when the two
#' are acyclic graphs of directed relations over the same constructs with the
#' same skeleton and the same unshielded colliders, in which case no
#' test of conditional independence separates them, and \code{NA} when that
#' rule does not apply.
#'
#' A graph with feedback loops is not compared under \code{cycles = "refuse"}
#' (\code{evaluated} is \code{FALSE}). Under \code{cycles = "sigma"}, it is
#' read as in [tf_entailments()], and its independencies are compared only
#' when the two graphs name the same constructs.
#'
#' @param theory A theory object.
#' @param rival The id of an alternative of \code{theory} that states
#'   propositions, or a theory object.
#' @param cycles \code{"refuse"} (the default) or \code{"sigma"}.
#' @return A list with \code{theory_id}, \code{rival_id}, \code{criterion},
#'   \code{evaluated}, \code{reason}, \code{shared}, \code{only_theory},
#'   \code{only_rival}, \code{markov_equivalent}, \code{independence_basis},
#'   \code{independencies}, \code{effects}, \code{associations}, \code{claims}
#'   and \code{counts}.
#' @family causal reading
#' @examples
#' t <- tf_read(tf_example_path("modality-switching.theory.yaml"))
#' d <- tf_discriminate(t, "alt_grounding_by_interaction")
#' vapply(d$claims, function(x) paste(x$id, x$theory, x$rival), "")
#' @export
tf_discriminate <- function(theory, rival, cycles = "refuse") {
  .tf_check_cycles(cycles, "discriminate")
  T <- theory
  focal <- .tf_prepare_graph(.tf_causal_graph(T, "discriminate"), cycles, .tf_list(T, "propositions"))
  if (is.character(rival) && length(rival) == 1L && !is.na(rival)) {
    alt <- NULL
    for (a in .tf_list(T, "alternatives")) {
      if (identical(.tf_str(a, "id"), rival)) {
        alt <- a
        break
      }
    }
    if (is.null(alt)) .tf_refuse("discriminate found no alternative '", rival, "' in the theory")
    props <- .tf_list(alt, "propositions")
    if (length(props) == 0L) {
      .tf_refuse("discriminate requires alternative '", rival, "' to state propositions")
    }
    other <- .tf_prepare_graph(.tf_causal_graph(T, "discriminate", propositions = props), cycles, props)
    rival_id <- rival
  } else {
    other <- .tf_prepare_graph(.tf_causal_graph(rival, "discriminate"), cycles,
                               .tf_list(rival, "propositions"))
    rival_id <- .tf_str(rival, "id")
  }

  shared <- focal$nodes[focal$nodes %in% other$nodes]
  evaluated <- focal$evaluable && other$evaluable
  claims <- list()
  for (cl in .tf_claims(T)) {
    a <- .tf_read_with(focal, cl)$verdict
    b <- .tf_read_with(other, cl)$verdict
    claims[[length(claims) + 1L]] <- list(
      source = cl$source, id = cl$id, theory = a, rival = b,
      discriminates = setequal(c(a, b), c("entailed", "contradicted")))
  }

  markov <- NA
  basis <- "not_compared"
  independencies <- list()
  effects <- list()
  associations <- list()
  if (evaluated) {
    dags <- length(focal$feedback) == 0L && length(other$feedback) == 0L
    same <- setequal(focal$nodes, other$nodes)
    if (dags && same && !any(focal$bidirected) && !any(other$bidirected)) {
      ix <- match(focal$nodes, other$nodes)
      od <- other$directed[ix, ix, drop = FALSE]
      markov <- identical(.tf_skeleton(focal$directed), .tf_skeleton(od)) &&
        identical(.tf_v_structures(focal$directed), .tf_v_structures(od))
    }
    restrict <- function(G) {
      ix <- match(shared, G$nodes)
      list(directed = G$sep_d[ix, ix, drop = FALSE], bidirected = G$sep_b[ix, ix, drop = FALSE])
    }
    views <- NULL
    if (same) {
      views <- list(restrict(focal), restrict(other))
      basis <- "same_constructs"
    } else if (dags) {
      views <- list(.tf_project(focal, shared), .tf_project(other, shared))
      basis <- "projected"
    }
    if (!is.null(views)) independencies <- .tf_discriminating_independencies(shared, views)
    diffs <- .tf_sign_differences(shared, focal, other)
    effects <- diffs$effects
    associations <- diffs$associations
  }

  count <- function(xs, key) sum(vapply(xs, function(x) isTRUE(x[[key]]), logical(1)))
  list(
    theory_id = .tf_str(T, "id"),
    rival_id = rival_id,
    criterion = if (cycles == "sigma") "sigma" else "m",
    evaluated = evaluated,
    reason = if (evaluated) NA_character_ else "feedback_loop",
    shared = as.list(shared),
    only_theory = as.list(focal$nodes[!(focal$nodes %in% other$nodes)]),
    only_rival = as.list(other$nodes[!(other$nodes %in% focal$nodes)]),
    markov_equivalent = markov,
    independence_basis = basis,
    independencies = independencies,
    effects = effects,
    associations = associations,
    claims = claims,
    counts = list(
      discriminating_claims = count(claims, "discriminates"),
      independencies = length(independencies),
      decisive_effects = count(effects, "decisive"),
      decisive_associations = count(associations, "decisive")
    )
  )
}
