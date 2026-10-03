#' Testable implications derived from the graph a theory's propositions state.
#'
#' Every proposition is read through the relation table: the directed relations
#' are edges and `associates` is a bidirected edge. Each pair of constructs that
#' no edge joins is independent given some set of other constructs whenever a
#' set m-separates the pair.
#' @name implications
#' @keywords internal
NULL

# Render one independence in the notation dagitty prints.
.tf_ci_statement <- function(a, b, given) {
  if (length(given) == 0L) {
    return(paste0(a, " _||_ ", b))
  }
  paste0(a, " _||_ ", b, " | ", paste(given, collapse = ", "))
}

#' Derive a theory's implied conditional independencies
#'
#' Reads every proposition through the relation table (API_SPEC.md section
#' 28). A directed relation (\code{"increases"}, \code{"decreases"},
#' \code{"causes"}, \code{"mediates"} or \code{"moderates"}) is an edge from
#' \code{from} to \code{to}, and \code{"associates"} is a bidirected edge,
#' covariance the theory leaves unexplained, as a latent common cause of the two
#' constructs would. The constructs that a directed relation names are the
#' vertices, and an association is an edge only between two of them. The
#' function checks that the directed edges form no cycle and then takes every
#' pair of vertices that no edge joins. The pair is stated independent given
#' the parents of both when those m-separate it (Richardson, 2003), and
#' otherwise given all the other ancestors of the two when those do. A pair
#' that neither set separates is separated by no set of constructs (Richardson
#' & Spirtes, 2002, Theorem 4.2), so the theory implies no independence for it,
#' and it is listed under \code{inseparable}. These are the conditional
#' independencies the causal graph implies, each one a claim that data could
#' refute. When every relation is directed, they are the basis set of Pearl
#' (1988) and Shipley (2000), from which every other independence the graph
#' implies follows.
#'
#' Constructs that no directed relation names are left out, because silence
#' about a construct is not a claim that it is independent of anything, and so
#' are constructs without an id, which no proposition can name. A construct
#' named only by associations would be a collider on every path through it, so
#' leaving it out loses no statement about the others. A theory with no
#' directed relations therefore comes back with no vertices and no error.
#'
#' @section Measurement:
#' The statements concern constructs, and a study measures them with error.
#' Error in a conditioning construct leaves part of the dependence that holding
#' it fixed should remove. A conditional statement tested on observed scores is
#' therefore rejected too often, and more often the larger the sample (Westfall
#' & Yarkoni, 2016). Take a chain whose two paths have standardised
#' coefficients of .5, with the middle construct measured at a reliability of
#' .8. A partial-correlation test at the 5 per cent level then rejects the true
#' statement in about 14, 29 and 51 per cent of studies of 200, 500 and 1,000
#' observations. Conditional statements are better tested with latent-variable
#' models, such as one built on the measurement model that [tf_compile_sem()]
#' writes (Thoemmes et al., 2018).
#'
#' @section Refusals:
#' The function stops in three cases. Two constructs sharing an id would give one
#' node two sets of parents, and a directed relation naming an undeclared
#' construct would shrink the graph and so imply independencies the theory never
#' claimed. A cycle among the directed edges is refused too, and the message
#' names a cycle that was found. A cyclic graph also implies independencies,
#' under sigma-separation, when each feedback loop has a unique equilibrium
#' (Bongers et al., 2021), but this function does not derive them.
#' The Python twin raises \code{ValueError} on the same three, with the same
#' message text.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @return A named list
#'   \code{list(theory_id, criterion, acyclic, constructs, n_edges,
#'   n_bidirected, feedback, implications, n_implications, inseparable)}.
#'   \code{criterion} names the separation criterion, \code{"m"}.
#'   \code{constructs} holds the vertices in file order. \code{n_edges} counts
#'   the directed edges and \code{n_bidirected} the bidirected ones, a pair
#'   stated twice counting once. \code{acyclic} is always \code{TRUE} and
#'   \code{feedback} always empty in a returned record, since a cyclic graph is
#'   refused, and both are carried so that a serialised record states the
#'   verdict. Each entry of \code{implications} is a list
#'   \code{list(a, b, given, statement)}, where \code{statement} renders the
#'   claim as \code{a _||_ b | z1, z2}, and each entry of \code{inseparable} is
#'   \code{list(a, b)}. Pairs come in construct file order, as do the members of
#'   \code{given}.
#' @references
#' Bongers, S., Forré, P., Peters, J., & Mooij, J. M. (2021). Foundations of
#'   structural causal models with cycles and latent variables. \emph{The Annals
#'   of Statistics}, 49(5), 2885-2915. \doi{10.1214/21-AOS2064}
#'
#' Pearl, J. (1988). \emph{Probabilistic reasoning in intelligent systems:
#'   Networks of plausible inference}. Morgan Kaufmann.
#'
#' Richardson, T. (2003). Markov properties for acyclic directed mixed graphs.
#'   \emph{Scandinavian Journal of Statistics}, 30(1), 145-157.
#'   \doi{10.1111/1467-9469.00323}
#'
#' Richardson, T., & Spirtes, P. (2002). Ancestral graph Markov models.
#'   \emph{The Annals of Statistics}, 30(4), 962-1030.
#'   \doi{10.1214/aos/1031689015}
#'
#' Shipley, B. (2000). A new inferential test for path models based on directed
#'   acyclic graphs. \emph{Structural Equation Modeling}, 7(2), 206-218.
#'   \doi{10.1207/S15328007SEM0702_4}
#'
#' Thoemmes, F., Rosseel, Y., & Textor, J. (2018). Local fit evaluation of
#'   structural equation models using graphical criteria. \emph{Psychological
#'   Methods}, 23(1), 27-41. \doi{10.1037/met0000147}
#'
#' Westfall, J., & Yarkoni, T. (2016). Statistically controlling for
#'   confounding constructs is harder than you think. \emph{PLOS ONE}, 11(3),
#'   e0152719. \doi{10.1371/journal.pone.0152719}
#' @seealso [tf_diagram()] with \code{type = "causal_dag"}, which exports the
#'   same graph as dagitty syntax without reading it, and the methodological
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
#'
#' # Stating that arousal and avoidance also covary for reasons the theory
#' # leaves open withdraws that claim: the pair is joined by an edge.
#' covary <- tf_add_proposition(theory, "p3", "c_arousal", "c_avoidance", "associates")
#' tf_implications(covary)$n_implications
#' @export
tf_implications <- function(theory) {
  T <- theory

  declared <- character(0)
  for (c in .tf_list(T, "constructs")) {
    cid <- .tf_str(c, "id")
    # A construct without an id cannot be the endpoint of a proposition, so it
    # takes no part in the graph, and two of them do not share an id.
    if (!nzchar(cid)) next
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
  assoc_from <- character(0)
  assoc_to <- character(0)
  for (p in .tf_list(T, "propositions")) {
    rel <- .tf_enum_str(p, "relation", .tf_RELATION)
    frm <- .tf_str(p, "from")
    to <- .tf_str(p, "to")
    if (rel %in% .tf_BIDIRECTED) {
      assoc_from <- c(assoc_from, frm)
      assoc_to <- c(assoc_to, to)
      next
    }
    if (!(rel %in% .tf_DIRECTED)) next
    pid <- .tf_str(p, "id")
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
  directed <- matrix(FALSE, nrow = k, ncol = k)
  for (e in seq_along(edge_from)) {
    directed[rank_of[[edge_from[[e]]]], rank_of[[edge_to[[e]]]]] <- TRUE
  }
  # An association is an edge only between two vertices. A construct that only
  # associations name is a collider on every path through it, so it closes them
  # all and leaving it out changes no statement about the others.
  bidirected <- matrix(FALSE, nrow = k, ncol = k)
  n_bidirected <- 0L
  for (e in seq_along(assoc_from)) {
    a <- match(assoc_from[[e]], nodes)
    b <- match(assoc_to[[e]], nodes)
    if (is.na(a) || is.na(b) || a == b || bidirected[a, b]) next
    bidirected[a, b] <- TRUE
    bidirected[b, a] <- TRUE
    n_bidirected <- n_bidirected + 1L
  }

  cycle <- .tf_first_cycle(directed, k)
  if (!is.null(cycle)) {
    stop("implications requires an acyclic causal graph; cycle found: ",
         paste(nodes[cycle], collapse = " -> "), call. = FALSE)
  }

  reach <- .tf_reach(directed, k)
  impl <- list()
  inseparable <- list()
  if (k >= 2L) {
    for (i in seq_len(k - 1L)) {
      for (j in (i + 1L):k) {
        if (directed[i, j] || directed[j, i] || bidirected[i, j]) next
        # The parents of the pair separate it in every DAG, so a theory of
        # directed relations alone gets the basis set. With bidirected edges, a
        # parent can be a collider that holding it fixed opens, and then the
        # ancestors of the pair are tried. When they fail, every vertex on a
        # path that connects the two is a collider and an ancestor of one of
        # them, an inducing path, so no set separates the pair (API_SPEC.md
        # section 27).
        parents <- which(directed[, i] | directed[, j])
        ancestors <- setdiff(which(reach[, i] | reach[, j]), c(i, j))
        given <- NULL
        for (s in list(parents, ancestors)) {
          if (.tf_m_separated(directed, bidirected, reach, i, j, s)) {
            given <- s
            break
          }
        }
        if (is.null(given)) {
          inseparable[[length(inseparable) + 1L]] <- list(a = nodes[[i]], b = nodes[[j]])
          next
        }
        names_given <- nodes[given]
        impl[[length(impl) + 1L]] <- list(
          a = nodes[[i]],
          b = nodes[[j]],
          given = as.list(names_given),
          statement = .tf_ci_statement(nodes[[i]], nodes[[j]], names_given)
        )
      }
    }
  }

  list(
    theory_id = .tf_str(T, "id"),
    criterion = "m",
    acyclic = TRUE,
    constructs = as.list(nodes),
    n_edges = length(edge_from),
    n_bidirected = n_bidirected,
    feedback = list(),
    implications = impl,
    n_implications = length(impl),
    inseparable = inseparable
  )
}
