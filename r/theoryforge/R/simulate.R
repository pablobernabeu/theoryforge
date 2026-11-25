#' Deterministic dynamical-system runner derived from a theory network.
#'
#' Each construct is a state variable, and each proposition whose relation is
#' \code{increases}, \code{decreases}, \code{causes} or \code{mediates}
#' contributes a linear coupling term with the sign the relation table gives
#' it. \code{causes} and \code{mediates} state no sign and are coupled
#' positively, an assumption the result records. The system is propagated
#' either with fixed-step (Euler) updates or exactly, with the matrix
#' exponential of the coupling matrix, so the trajectory is deterministic.
#' @name simulate
#' @noRd
#' @keywords internal
NULL

.tf_SIM_METHODS <- c("euler", "exact")
# Degree of the Taylor polynomial of the propagator, after scaling the matrix
# to an infinity norm of at most 0.5 (API_SPEC section 22).
.tf_SIM_TAYLOR_DEGREE <- 18L
# The Euler run warns once a state departs from the exact one by more than
# this fraction of max(1, |exact|).
.tf_SIM_DEPARTURE <- 0.05
.tf_SIM_EULER_WARNING <- paste0(
  "simulate: the Euler steps depart from the exact solution by more than ",
  "5 per cent; use method 'exact' or a smaller dt")
.tf_SIM_INIT_FORM <- paste0("simulate requires init to be a finite number or a mapping from ",
                            "construct ids to finite numbers")
.tf_SIM_INIT_UNKNOWN <- "simulate requires init to name declared constructs; unknown construct id: "

#' Simulate a theory's construct network as a linear dynamical system
#'
#' Treats each construct (in file order) as a state variable and each
#' proposition between two declared constructs whose relation is
#' \code{increases}, \code{decreases}, \code{causes} or \code{mediates} as a
#' linear coupling term. It then propagates \code{dX/dt = A X - damping * X}
#' either with fixed-step (Euler) updates or exactly, with the matrix
#' exponential of \code{(A - damping * I) * dt}. The result is deterministic.
#' Construct ids must be unique, and duplicates are refused rather than
#' assigned to an arbitrary state. A construct without an id is a state with no
#' couplings, and two of them do not count as duplicates.
#'
#' @section Couplings:
#' Each such proposition adds \code{k} times the sign of its relation to the
#' coupling from \code{from} to \code{to}. The signs are those of the relation
#' table (API_SPEC.md section 28): +1 for \code{increases} and -1 for
#' \code{decreases}. \code{causes} and \code{mediates} state no sign, and they
#' are coupled at \code{+k} by assumption. \code{assumed_positive} lists their
#' ids, in file order, since that choice alone can decide whether a feedback
#' loop grows or settles. \code{moderates} and \code{associates} couple
#' nothing, and \code{ignored} lists them.
#'
#' @section Initial state:
#' \code{init} is either one finite number, the value every state starts from,
#' or a mapping from construct ids to finite numbers, given as a named numeric
#' vector or a named list, in which case each state it does not name starts
#' from 0. A mapping with one entry gives the response to an impulse in that
#' construct. A name that is not a declared construct id is refused.
#'
#' @section Methods:
#' With \code{method = "exact"}, each step multiplies the state by the matrix
#' exponential, computed by scaling and squaring a degree-18 Taylor polynomial
#' (Moler and Van Loan, 2003, method 3), so the trajectory is the solution of
#' the linear system at times \code{0, dt, 2 * dt, ...} whatever \code{dt} is.
#'
#' With \code{method = "euler"}, the default for this release, the explicit
#' step is stable only when \eqn{|1 + dt \lambda| < 1} for every eigenvalue
#' \eqn{\lambda} of \code{A - damping * I}. A theory that decays at rate
#' \code{damping} therefore grows without bound, alternating in sign, once
#' \code{dt * damping} exceeds 2, and the steps turn a sustained oscillation
#' into growth. Raising \code{damping} can cause a divergence as well as fail
#' to stop one. The function warns when the Euler trajectory departs from the
#' exact one, at any step, by more than 5 per cent of the larger of
#' \code{|exact|} and the largest absolute starting value (1 when every
#' starting value is 0), so that the warning does not depend on the unit of
#' \code{init}. The default will change to \code{"exact"} in the next minor
#' release.
#'
#' When a state grows so large that a million times it is not a finite number,
#' the function stops with a message naming the step and the state. The initial
#' state is tested as step 0, so a starting value beyond about 1.8e302 in
#' absolute value stops there.
#'
#' The model is deliberately simple: one gain \code{k} for every coupling,
#' \code{causes} and \code{mediates} taken as positive, \code{moderates} and
#' \code{associates} coupling nothing and \code{functional_form} not read. A
#' linear system has one equilibrium, or a continuum of them when its matrix is
#' singular, and never two separate ones, so it cannot show bistability.
#'
#' @param theory A theory object (named list), such as one from [tf_read()].
#' @param steps Number of steps, a whole number of at least 0 (default
#'   \code{10}).
#' @param dt Time between rows, a finite number greater than 0 (default
#'   \code{0.1}).
#' @param k Coupling gain applied to each signed edge, a finite number (default
#'   \code{1.0}).
#' @param damping Per-state linear decay, a finite number (default
#'   \code{0.5}).
#' @param init Initial value of every state, a single finite number (default
#'   \code{1.0}), or a named numeric vector or named list giving the initial
#'   value of the constructs it names, the others starting from 0.
#' @param method \code{"euler"} (the default for this release) or
#'   \code{"exact"}.
#' @return A named list
#'   \code{list(states, dt, steps, k, damping, init, initial_state, method,
#'   ignored, assumed_positive, opposed, trajectory)}, where \code{states} are
#'   the construct ids in file order and \code{trajectory} is a list of
#'   \code{steps + 1} numeric vectors (row 0 is the initial state), every value
#'   rounded to 6 decimals. The settings and the method are returned as given
#'   (a mapping \code{init} as a named list), because the trajectory cannot be
#'   reproduced without them, and \code{initial_state} gives the value each
#'   state starts from, in the order of \code{states}. \code{ignored} lists the
#'   ids of the propositions that couple nothing (moderates, associates, a
#'   relation outside the schema's set or an endpoint that is not a declared
#'   construct), \code{assumed_positive} the ids of the \code{causes} and
#'   \code{mediates} propositions coupled at \code{+k}, and \code{opposed} the
#'   \code{c(from, to)} pairs that carry couplings of both signs, which offset
#'   each other. An invalid setting is refused with an error.
#' @references Moler, C., & Van Loan, C. (2003). Nineteen dubious ways to
#'   compute the exponential of a matrix, twenty-five years later. \emph{SIAM
#'   Review, 45}(1), 3-49. \doi{10.1137/S00361445024180}
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases")
#' sim <- tf_simulate(theory, steps = 5, method = "exact")
#' sim$states
#' sim$trajectory[[1]] # the common initial state
#' sim$trajectory[[length(sim$trajectory)]] # at time 5 * dt
#' # The response to an impulse in arousal, threat starting from 0
#' impulse <- tf_simulate(theory, steps = 5, init = c(c_arousal = 1), method = "exact")
#' impulse$initial_state
#' @export
tf_simulate <- function(theory, steps = 10, dt = 0.1, k = 1.0,
                        damping = 0.5, init = 1.0, method = "euler") {
  .tf_sim_check_knobs(steps, dt, k, damping, init, method)
  T <- theory
  cons <- .tf_list(T, "constructs")
  states <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  n <- length(states)
  # Duplicate construct ids have no defensible reading here: `[[` on a named
  # vector takes the first index and Python's dict comprehension the last, so
  # the two engines would give two plausible trajectories for the same file.
  # Refuse instead of picking a winner.
  # Constructs without ids share no id: no proposition can name them, so each
  # is a state with no couplings.
  seen <- character(0)
  for (s in states) {
    if (nzchar(s) && s %in% seen) {
      stop("simulate requires unique construct ids; duplicate construct id: ", s,
           call. = FALSE)
    }
    seen <- c(seen, s)
  }
  idx <- stats::setNames(seq_along(states), states)
  mapping <- .tf_sim_init_is_mapping(init)
  if (mapping) {
    for (key in names(init)) {
      if (!(key %in% states)) stop(.tf_SIM_INIT_UNKNOWN, key, call. = FALSE)
    }
    X <- numeric(n)
    for (i in seq_len(n)) {
      if (nzchar(states[[i]]) && states[[i]] %in% names(init)) {
        X[i] <- as.numeric(init[[states[[i]]]])
      }
    }
    init <- as.list(init)
  } else {
    X <- rep(as.numeric(init), n)
  }

  # n x n coupling matrix (zeros). Explicit loops mirror the Python reference
  # exactly to guarantee identical floating-point results.
  A <- matrix(0.0, nrow = n, ncol = n)
  ignored <- character(0)
  assumed <- character(0)
  # The signs each ordered pair carries, in the order the pairs first couple.
  pair_from <- character(0)
  pair_to <- character(0)
  pair_pos <- logical(0)
  pair_neg <- logical(0)
  props <- .tf_list(T, "propositions")
  for (p in props) {
    f <- .tf_str(p, "from")
    t <- .tf_str(p, "to")
    rel <- .tf_enum_str(p, "relation", .tf_RELATION)
    coupled <- rel %in% .tf_PATHS && nzchar(f) && nzchar(t) && f %in% states &&
      t %in% states
    if (!coupled) {
      ignored <- c(ignored, .tf_str(p, "id"))
      next
    }
    stated <- .tf_RELATIONS[[rel]]$sign
    sign <- if (is.na(stated)) 1.0 else as.numeric(stated)
    if (is.na(stated)) assumed <- c(assumed, .tf_str(p, "id"))
    ti <- idx[[t]]
    fi <- idx[[f]]
    A[ti, fi] <- A[ti, fi] + sign * k
    at <- which(pair_from == f & pair_to == t)
    if (length(at) == 0L) {
      pair_from <- c(pair_from, f)
      pair_to <- c(pair_to, t)
      pair_pos <- c(pair_pos, FALSE)
      pair_neg <- c(pair_neg, FALSE)
      at <- length(pair_from)
    }
    if (sign > 0) pair_pos[at] <- TRUE else pair_neg[at] <- TRUE
  }
  both <- which(pair_pos & pair_neg)
  opposed <- lapply(both, function(i) c(pair_from[[i]], pair_to[[i]]))

  # The exact propagator, which method "exact" steps with and the Euler run is
  # checked against. Neither needs it when nothing moves.
  E <- NULL
  if (n > 0L && steps > 0) {
    J <- A
    for (i in seq_len(n)) J[i, i] <- A[i, i] - damping
    E <- .tf_sim_propagator(J, dt)
  }
  # A smaller dt cures an Euler divergence that the step causes, but it does
  # not change the exact solution, which grows only when the system does.
  # Raising damping shifts every eigenvalue of J to the left, so it tames the
  # exact solution, while it can make the Euler steps diverge.
  remedy <- if (method == "exact") {
    "raise damping, reduce k or take fewer steps"
  } else {
    "reduce dt or k"
  }

  initial <- X
  # Row 0 is tested as every update is. A finite init can be too large to
  # round (about 1.8e302 or more), and only init shapes this row.
  .tf_sim_check_finite(X, states, 0L, "reduce init")
  Y <- X # the exact state the Euler run is compared with
  # The departure is measured against the larger of |exact| and the largest
  # absolute starting value, so that it does not depend on the unit of init. A
  # run that starts at 0 everywhere takes 1. Python computes the same scale.
  dep_scale <- if (n > 0L) max(abs(X)) else 0
  if (dep_scale == 0) dep_scale <- 1
  departed <- FALSE
  traj <- vector("list", steps + 1L)
  traj[[1L]] <- if (n == 0L) numeric(0) else .tf_rnd(X, 6)
  for (s in seq_len(steps)) {
    if (n > 0L) {
      if (method == "exact") {
        X <- .tf_sim_apply(E, X)
      } else {
        dX <- numeric(n)
        for (i in seq_len(n)) {
          acc <- 0.0
          for (j in seq_len(n)) {
            acc <- acc + A[i, j] * X[j]
          }
          dX[i] <- acc - damping * X[i]
        }
        for (i in seq_len(n)) {
          X[i] <- X[i] + dt * dX[i]
        }
      }
      .tf_sim_check_finite(X, states, s, remedy)
      if (method == "euler" && !departed) {
        Y <- .tf_sim_apply(E, Y)
        for (i in seq_len(n)) {
          # An exact state beyond the double range is a departure too, since
          # the Euler state is still finite here.
          if (!is.finite(Y[i]) ||
              abs(X[i] - Y[i]) > .tf_SIM_DEPARTURE * max(dep_scale, abs(Y[i]))) {
            departed <- TRUE
            break
          }
        }
      }
    }
    traj[[s + 1L]] <- if (n == 0L) numeric(0) else .tf_rnd(X, 6)
  }

  if (departed) warning(.tf_SIM_EULER_WARNING, call. = FALSE)
  list(states = as.list(states), dt = dt, steps = steps, k = k,
       damping = damping, init = init, initial_state = initial, method = method,
       ignored = as.list(ignored), assumed_positive = as.list(assumed),
       opposed = opposed, trajectory = traj)
}

# A times B by explicit loops, the inner index last, each sum a left fold, as
# the Python twin's _matmul(). %*% would hand the sums to BLAS, whose order
# and fused operations differ between builds.
.tf_sim_matmul <- function(A, B) {
  n <- nrow(A)
  out <- matrix(0.0, n, n)
  for (i in seq_len(n)) {
    for (j in seq_len(n)) {
      acc <- 0.0
      for (m in seq_len(n)) acc <- acc + A[i, m] * B[m, j]
      out[i, j] <- acc
    }
  }
  out
}

# Stops the run at the first state, in file order, that cannot be rounded, as
# the Python twin's _check_finite(). Rounding scales by 10^6, so the scaled
# value is tested: a state can stay finite for a few steps after that product
# overflows, and .tf_rnd() would then write Inf into the trajectory.
.tf_sim_check_finite <- function(X, states, step, remedy) {
  for (i in seq_along(X)) {
    if (!is.finite(X[i] * 1e6)) {
      stop("simulate diverged at step ", step, ": state '", states[[i]],
           "' is not finite; ", remedy, call. = FALSE)
    }
  }
  invisible(NULL)
}

# E times X, each sum a left-to-right loop, as the Python twin's _apply().
.tf_sim_apply <- function(E, X) {
  n <- length(X)
  out <- numeric(n)
  for (i in seq_len(n)) {
    acc <- 0.0
    for (j in seq_len(n)) acc <- acc + E[i, j] * X[j]
    out[i] <- acc
  }
  out
}

# expm(dt * J) by scaling and squaring a degree-18 Taylor polynomial (Moler
# and Van Loan, 2003, method 3), in the Python twin's order so that both give
# the same bits. The matrix is halved s times until its infinity norm (the
# largest absolute row sum) is at most 0.5, the series is summed as
# term = term * A / k for k = 1..18, and the sum is squared s times. The
# element-wise steps are vectorised, which changes no bits, and every sum is
# an explicit loop. A matrix with a row sum that is not finite has no computable
# propagator, and the result is NaN throughout, so the first step diverges.
.tf_sim_propagator <- function(J, dt) {
  n <- nrow(J)
  M <- dt * J
  norm <- 0.0
  for (i in seq_len(n)) {
    r <- 0.0
    for (j in seq_len(n)) r <- r + abs(M[i, j])
    if (!is.finite(r)) return(matrix(NaN, n, n))
    if (r > norm) norm <- r
  }
  s <- 0L
  while (norm > 0.5) {
    norm <- norm / 2.0
    s <- s + 1L
  }
  scale <- 1.0
  for (q in seq_len(s)) scale <- scale / 2.0
  A <- M * scale
  E <- diag(1.0, n)
  term <- E
  for (kk in seq_len(.tf_SIM_TAYLOR_DEGREE)) {
    term <- .tf_sim_matmul(term, A) / kk
    E <- E + term
  }
  for (q in seq_len(s)) E <- .tf_sim_matmul(E, E)
  E
}

# Refuses invalid knobs with the Python twin's messages (API_SPEC section 22).
# Logicals are refused, as Python refuses bool. A whole double such as 3 counts
# as a number of steps, as an integral float does in Python.
.tf_sim_check_knobs <- function(steps, dt, k, damping, init, method = "euler") {
  finite1 <- function(x) is.numeric(x) && length(x) == 1L && is.finite(x)
  if (!(finite1(steps) && steps >= 0 && steps == floor(steps))) {
    stop("simulate requires steps to be a whole number of at least 0", call. = FALSE)
  }
  if (!(finite1(dt) && dt > 0)) {
    stop("simulate requires dt to be a finite number greater than 0", call. = FALSE)
  }
  if (!finite1(k)) stop("simulate requires k to be a finite number", call. = FALSE)
  if (!finite1(damping)) {
    stop("simulate requires damping to be a finite number", call. = FALSE)
  }
  if (!(finite1(init) && is.null(names(init))) && !.tf_sim_init_is_mapping(init)) {
    stop(.tf_SIM_INIT_FORM, call. = FALSE)
  }
  if (!(is.character(method) && length(method) == 1L && !is.na(method) &&
        method %in% .tf_SIM_METHODS)) {
    stop("simulate requires method to be one of: euler, exact", call. = FALSE)
  }
  invisible(NULL)
}

# Whether `init` is a mapping from construct ids to finite numbers: a named
# numeric vector, or a list whose elements are each one finite number, with
# names that are not NA, empty or repeated. An empty list is the empty mapping,
# since R holds an empty mapping and an empty sequence alike. Logicals are
# refused, as Python refuses bool.
.tf_sim_init_is_mapping <- function(init) {
  if (is.list(init) && length(init) == 0L) return(TRUE)
  nm <- names(init)
  if (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(nm) > 0L) return(FALSE)
  if (is.list(init)) {
    return(all(vapply(init, function(v) is.numeric(v) && length(v) == 1L && is.finite(v),
                      logical(1))))
  }
  is.numeric(init) && all(is.finite(init))
}
