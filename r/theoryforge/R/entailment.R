# What a theory's causal graph entails (API_SPEC.md Part J). The Python twin's
# entailment.py holds the same routines.

.tf_CLAIM_KINDS <- c("effect", "association")
# The largest canonical adjustment set whose subsets are searched for a smallest
# valid one (API_SPEC.md section 31).
.tf_ADJUSTMENT_SEARCH <- 12L
.tf_CLAIM_SIGNS <- c("positive", "negative", "zero", "nonzero")

# Sign sets as bit masks: the signs that the routes between two constructs take.
# UNK marks a route through a relation that states no sign.
.tf_POS <- 1L
.tf_NEG <- 2L
.tf_UNK <- 4L

.tf_edge_mask <- function(s) {
  if (is.na(s)) .tf_UNK else if (s > 0L) .tf_POS else .tf_NEG
}

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

# For each vertex, the sign set of the directed walks to it from `start`. The
# empty walk counts, so `start` holds POS. Each state (vertex, sign) is visited
# once, so the search ends on a graph with feedback loops too. With `held`, no
# walk returns to `start`, as when an intervention holds it fixed and so cuts
# the edges into it.
.tf_walk_signs <- function(directed, sign, k, start, held = FALSE) {
  masks <- integer(k)
  masks[[start]] <- .tf_POS
  qv <- start
  qb <- .tf_POS
  while (length(qv) > 0L) {
    n <- length(qv)
    v <- qv[[n]]
    bit <- qb[[n]]
    qv <- qv[-n]
    qb <- qb[-n]
    for (w in which(directed[v, ])) {
      if (held && w == start) next
      nxt <- .tf_sign_mul(bit, .tf_edge_mask(sign[v, w]))
      for (b in c(.tf_POS, .tf_NEG, .tf_UNK)) {
        if (bitwAnd(nxt, b) != 0L && bitwAnd(masks[[w]], b) == 0L) {
          masks[[w]] <- bitwOr(masks[[w]], b)
          qv <- c(qv, w)
          qb <- c(qb, b)
        }
      }
    }
  }
  masks
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
  G$props <- props
  G$r <- .tf_reach(g$directed, k)
  comps <- .tf_strong_components(G$r)
  feedback <- list()
  for (comp in comps) {
    if (length(comp) > 1L || g$directed[comp[[1L]], comp[[1L]]]) {
      feedback[[length(feedback) + 1L]] <- as.list(g$nodes[comp])
    }
  }
  G$feedback <- feedback
  G$evaluable <- cycles == "sigma" || length(feedback) == 0L
  if (length(feedback) > 0L && cycles == "sigma") {
    acy <- .tf_acyclify(g$directed, g$bidirected, comps)
    G$sep_d <- acy$directed
    G$sep_b <- acy$bidirected
  } else {
    G$sep_d <- g$directed
    G$sep_b <- g$bidirected
  }
  G$sep_r <- .tf_reach(G$sep_d, k)
  G$walk_cache <- new.env(parent = emptyenv())
  G
}

.tf_walks <- function(G, s) {
  key <- as.character(s)
  if (is.null(G$walk_cache[[key]])) {
    G$walk_cache[[key]] <- .tf_walk_signs(G$directed, G$sign, G$k, s)
  }
  G$walk_cache[[key]]
}

# The ids of the propositions in `on`, in file order, once each.
.tf_ordered_props <- function(G, on) {
  out <- character(0)
  for (p in G$props) {
    pid <- .tf_str(p, "id")
    if (nzchar(pid) && !(pid %in% out) && pid %in% on) out <- c(out, pid)
  }
  out
}

# The sign sets of the walks from `x` that never return to it, and the
# reachability of the graph without the edges into `x`: the graph an
# intervention on `x` leaves.
.tf_held <- function(G, x) {
  key <- paste0("held", x)
  if (is.null(G$walk_cache[[key]])) {
    cut <- G$directed
    cut[, x] <- FALSE
    G$walk_cache[[key]] <- list(masks = .tf_walk_signs(G$directed, G$sign, G$k, x, held = TRUE),
                                r = .tf_reach(cut, G$k))
  }
  G$walk_cache[[key]]
}

.tf_effect <- function(G, x, y) {
  # An intervention on x replaces its own equation, so a walk that comes back
  # to x carries nothing to y. In an acyclic graph no walk does.
  h <- .tf_held(G, x)
  d <- .tf_derived(h$masks[[y]])
  on <- character(0)
  for (e in seq_along(G$edge_from)) {
    u <- G$edge_from[[e]]
    v <- G$edge_to[[e]]
    if (v != x && h$r[x, u] && h$r[v, y]) on <- c(on, G$edge_props[[e]])
  }
  list(derived = d[[1L]], basis = d[[2L]], via = .tf_ordered_props(G, on))
}

.tf_association <- function(G, x, y) {
  r <- G$r
  mask <- 0L
  for (t in seq_len(G$k)) {
    mask <- bitwOr(mask, .tf_sign_mul(.tf_walks(G, t)[[x]], .tf_walks(G, t)[[y]]))
  }
  na <- nrow(G$assoc)
  for (row in seq_len(na)) {
    a <- G$assoc[row, 1L]
    b <- G$assoc[row, 2L]
    if ((r[a, x] && r[b, y]) || (r[a, y] && r[b, x])) mask <- bitwOr(mask, .tf_UNK)
  }
  d <- .tf_derived(mask)
  common <- function(u, e) any(r[, u] & r[, e])
  on <- character(0)
  for (e in seq_along(G$edge_from)) {
    u <- G$edge_from[[e]]
    v <- G$edge_to[[e]]
    hit <- (r[v, x] && common(u, y)) || (r[v, y] && common(u, x))
    for (row in seq_len(na)) {
      for (pq in list(G$assoc[row, ], rev(G$assoc[row, ]))) {
        p <- pq[[1L]]
        q <- pq[[2L]]
        if (r[p, u] && ((r[v, x] && r[q, y]) || (r[v, y] && r[q, x]))) hit <- TRUE
      }
    }
    if (hit) on <- c(on, G$edge_props[[e]])
  }
  for (row in seq_len(na)) {
    a <- G$assoc[row, 1L]
    b <- G$assoc[row, 2L]
    if ((r[a, x] && r[b, y]) || (r[a, y] && r[b, x])) on <- c(on, G$assoc_props[[row]])
  }
  list(derived = d[[1L]], basis = d[[2L]], via = .tf_ordered_props(G, on))
}

# A smallest set of constructs whose adjustment identifies the effect of x on
# y, as vertex indices, or NULL. A set is valid when it holds no descendant of
# a vertex on a proper causal path from x to y and m-separates the two once the
# first edge of each such path is removed. The ancestors of x and y that meet
# the first condition form the canonical set, which is valid if any set is (van
# der Zander et al., 2019). Its subsets are tried by size and, within a size,
# in vertex order, and the first valid one is returned. A canonical set of more
# than .tf_ADJUSTMENT_SEARCH members is returned whole. A graph with feedback
# loops gets NULL, since the criterion is not established for it.
.tf_adjustment <- function(G, x, y) {
  if (length(G$feedback) > 0L) return(NULL)
  k <- G$k
  r <- G$r
  on_path <- which(seq_len(k) != x & r[x, ] & r[, y])
  forbidden <- unique(c(x, which(apply(r[on_path, , drop = FALSE], 2L, any))))
  canonical <- setdiff(which(r[, x] | r[, y]), c(forbidden, y))
  d <- G$directed
  d[x, on_path] <- FALSE
  rd <- .tf_reach(d, k)
  if (!.tf_m_separated(d, G$bidirected, rd, x, y, canonical)) return(NULL)
  if (length(canonical) > .tf_ADJUSTMENT_SEARCH) return(canonical)
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
      if (.tf_m_separated(d, G$bidirected, rd, x, y, z)) return(z)
    }
  }
  canonical
}

# The derivation of one claim: list(derived, verdict, basis, faithfulness, via,
# identified, adjustment). The last two are NA and NULL except for an evaluated
# effect claim on an acyclic graph.
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
    if (.tf_m_separated(G$sep_d, G$sep_b, G$sep_r, x, y, z)) {
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
  # nonzero only if they do not cancel exactly, which is faithfulness.
  faithful <- d$derived == "undetermined" && verdict != "undetermined"
  out(d$derived, verdict, d$basis, faithfulness = faithful, via = d$via, adjust = adjust)
}

.tf_check_cycles <- function(cycles, caller) {
  if (!is.character(cycles) || length(cycles) != 1L || is.na(cycles) ||
      !(cycles %in% c("refuse", "sigma"))) {
    stop(caller, " requires cycles to be 'refuse' or 'sigma'", call. = FALSE)
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
#' association the product along each trek, a pair of directed paths from a
#' common source to the two constructs. A trek through an association has no
#' fixed sign. When every path or trek has the same sign, the graph fixes the
#' sign of the quantity, and when none exists, the quantity is zero (Wright,
#' 1934). A conditional association is zero when the two constructs are
#' m-separated given the others and nonzero otherwise.
#'
#' Each claim is then \code{entailed}, \code{contradicted},
#' \code{undetermined} when the graph leaves the sign open, or
#' \code{not_evaluated} when the claim is incomplete, names a construct that no
#' directed relation names, or meets a feedback loop under
#' \code{cycles = "refuse"}. \code{faithfulness} is \code{TRUE} when the
#' verdict relies on routes of unknown or opposite signs not cancelling
#' exactly. The derivations assume a linear structural model, or at least that
#' each relation acts in one direction throughout (VanderWeele & Robins, 2010),
#' and that no common cause of two constructs is left out unless an
#' association stands for it. Under \code{cycles = "sigma"}, each feedback loop
#' is assumed to settle to a unique equilibrium, and the signs further assume
#' that the effects around each loop die out.
#'
#' @param theory A theory object.
#' @param cycles \code{"refuse"} (the default) or \code{"sigma"}, as in
#'   [tf_implications()].
#' @return A list with \code{theory_id}, \code{criterion}, \code{acyclic},
#'   \code{feedback}, \code{claims} and \code{counts}. Each claim is a list of
#'   \code{source}, \code{id}, \code{kind}, \code{x}, \code{y}, \code{given},
#'   \code{sign}, \code{derived}, \code{verdict}, \code{basis},
#'   \code{faithfulness} and \code{via}, the propositions on some path or trek
#'   between the two constructs. The predictions come first and then the
#'   phenomena, each in file order. \code{counts} tallies the verdicts.
#' @references
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
# otherwise list(theory, rivals). The checklist reads the graphs with cycles =
# "refuse", and a graph that would be refused gives no verdicts.
.tf_prediction_verdicts <- function(T, cycles = "refuse") {
  preds <- .tf_list(T, "predictions")
  focal <- tryCatch(
    .tf_prepare_graph(.tf_causal_graph(T, "check"), cycles, .tf_list(T, "propositions")),
    error = function(e) NULL)
  if (is.null(focal)) return(vector("list", length(preds)))
  rivals <- list()
  for (a in .tf_list(T, "alternatives")) {
    aid <- .tf_str(a, "id")
    props <- .tf_list(a, "propositions")
    if (!nzchar(aid) || length(props) == 0L || !is.null(rivals[[aid]])) next
    g <- tryCatch(
      .tf_prepare_graph(.tf_causal_graph(T, "check", propositions = props), cycles, props),
      error = function(e) NULL)
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

# A claim and what the causal graph says of it, in words, as the
# preregistration and the dossier print it (API_SPEC.md section 11).
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
  said <- switch(rec$verdict,
    entailed = paste0("entailed by the causal graph",
                      if (length(via)) paste0(" through ", paste(via, collapse = ", ")) else ""),
    contradicted = "contradicted by the causal graph",
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
  out <- matrix(integer(0), ncol = 3L)
  for (c in seq_len(k)) {
    for (a in seq_len(k)) {
      if (a == k) next
      for (b in (a + 1L):k) {
        if (directed[a, c] && directed[b, c] && !adj[a, b]) out <- rbind(out, c(a, c, b))
      }
    }
  }
  out
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
  undirected <- function(a, b) adj[a, b] && !comp[a, b] && !comp[b, a]
  changed <- TRUE
  while (changed) {
    changed <- FALSE
    for (x in seq_len(k)) {
      for (y in seq_len(k)) {
        if (!(directed[x, y] && undirected(x, y))) next
        others <- setdiff(seq_len(k), y)
        r1 <- any(vapply(others, function(z) comp[z, x] && !adj[z, y], logical(1)))
        r2 <- any(comp[x, ] & comp[, y])
        r3 <- FALSE
        if (k >= 2L) {
          for (z1 in seq_len(k - 1L)) {
            for (z2 in (z1 + 1L):k) {
              if (undirected(x, z1) && undirected(x, z2) && comp[z1, y] && comp[z2, y] &&
                  !adj[z1, z2]) r3 <- TRUE
            }
          }
        }
        if (r1 || r2 || r3) {
          comp[x, y] <- TRUE
          changed <- TRUE
        }
      }
    }
  }
  comp
}

#' Report which causal directions observational data cannot test
#'
#' Two causal graphs that imply the same conditional independencies are Markov
#' equivalent, and no observational study can tell them apart (Verma & Pearl,
#' 1990/2022). For an acyclic graph of directed relations, they are the graphs with
#' the same skeleton and the same unshielded colliders. An edge is
#' \code{compelled} when it points the same way in every graph equivalent to
#' the theory's, and \code{reversible} when some equivalent graph reverses it,
#' so that testing its direction needs an intervention, a temporal order or
#' another assumption. The same problem in structural equation modelling is
#' that of equivalent models (MacCallum et al., 1993).
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
#' Verma, T., & Pearl, J. (2022). Equivalence and synthesis of causal models.
#' In \emph{Probabilistic and causal inference: The works of Judea Pearl}
#' (pp. 221-236). Association for Computing Machinery.
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
  down <- function(s) {
    found <- integer(0)
    seen <- s
    stack <- s
    while (length(stack) > 0L) {
      v <- stack[[length(stack)]]
      stack <- stack[-length(stack)]
      for (w in which(G$directed[v, ])) {
        if (w %in% seen) next
        seen <- c(seen, w)
        if (is_kept[[w]]) found <- c(found, w) else stack <- c(stack, w)
      }
    }
    found
  }
  reach_kept <- lapply(seq_len(G$k), function(v) if (is_kept[[v]]) v else down(v))
  n <- length(kept)
  d <- matrix(FALSE, nrow = n, ncol = n)
  b <- matrix(FALSE, nrow = n, ncol = n)
  for (v in kept) {
    for (w in down(v)) d[match(v, kept), match(w, kept)] <- TRUE
  }
  for (t in seq_len(G$k)) {
    if (is_kept[[t]]) next
    ends <- reach_kept[[t]]
    for (i in ends) for (j in ends) if (i != j) b[match(i, kept), match(j, kept)] <- TRUE
  }
  for (row in seq_len(nrow(G$assoc))) {
    for (i in reach_kept[[G$assoc[row, 1L]]]) {
      for (j in reach_kept[[G$assoc[row, 2L]]]) {
        if (i != j) {
          b[match(i, kept), match(j, kept)] <- TRUE
          b[match(j, kept), match(i, kept)] <- TRUE
        }
      }
    }
  }
  list(directed = d, bidirected = b)
}

# The parents of both, or failing that all their other ancestors, when that set
# separates i and j; NULL otherwise.
.tf_separating_set <- function(d, bd, r, i, j) {
  if (d[i, j] || d[j, i] || bd[i, j]) return(NULL)
  parents <- which(d[, i] | d[, j])
  ancestors <- setdiff(which(r[, i] | r[, j]), c(i, j))
  for (s in list(parents, ancestors)) {
    if (.tf_m_separated(d, bd, r, i, j, s)) return(s)
  }
  NULL
}

.tf_discriminating_independencies <- function(shared, views) {
  n <- length(shared)
  reaches <- lapply(views, function(v) .tf_reach(v$directed, n))
  out <- list()
  if (n < 2L) return(out)
  for (i in seq_len(n - 1L)) {
    for (j in (i + 1L):n) {
      for (side in list(list("theory", 1L, 2L), list("rival", 2L, 1L))) {
        mine <- side[[2L]]
        theirs <- side[[3L]]
        sep <- .tf_separating_set(views[[mine]]$directed, views[[mine]]$bidirected,
                                  reaches[[mine]], i, j)
        if (is.null(sep)) next
        if (!.tf_m_separated(views[[theirs]]$directed, views[[theirs]]$bidirected,
                             reaches[[theirs]], i, j, sep)) {
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
      a <- .tf_effect(focal, match(x, focal$nodes), match(y, focal$nodes))$derived
      b <- .tf_effect(other, match(x, other$nodes), match(y, other$nodes))$derived
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
        a <- .tf_association(focal, match(x, focal$nodes), match(y, focal$nodes))$derived
        b <- .tf_association(other, match(x, other$nodes), match(y, other$nodes))$derived
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
#' by id. The graphs are compared on the constructs that both name in a
#' directed relation.
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
#' observational test of independence separates them, and \code{NA} when that
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
    if (is.null(alt)) stop("discriminate found no alternative '", rival, "' in the theory", call. = FALSE)
    props <- .tf_list(alt, "propositions")
    if (length(props) == 0L) {
      stop("discriminate requires alternative '", rival, "' to state propositions", call. = FALSE)
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
