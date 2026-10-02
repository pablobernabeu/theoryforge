#' Deterministic dynamical-system runner derived from a theory network.
#'
#' Each construct is a state variable; each directed proposition contributes a
#' signed linear coupling term. The system is propagated either with fixed-step
#' (Euler) updates or exactly, with the matrix exponential of the coupling
#' matrix, so the trajectory is fully deterministic.
#' @name simulate
#' @keywords internal
NULL

.tf_SIM_POS <- c("increases", "causes", "mediates")
.tf_SIM_NEG <- c("decreases")
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

#' Simulate a theory's construct network as a linear dynamical system
#'
#' Treats each construct (in file order) as a state variable and each directed
#' proposition as a signed linear coupling term, then propagates
#' \code{dX/dt = A X - damping * X} either with fixed-step (Euler) updates or
#' exactly, with the matrix exponential of \code{(A - damping * I) * dt}. The
#' result is fully deterministic. Construct ids must be unique; duplicates are
#' refused rather than resolved to an arbitrary state slot. A construct without
#' an id is a state with no couplings, and two of them do not count as
#' duplicates.
#'
#' With \code{method = "exact"} each step multiplies the state by the matrix
#' exponential, computed by scaling and squaring a degree-18 Taylor polynomial
#' (Moler and Van Loan, 2003, method 3), so the trajectory is the solution of
#' the linear system at times \code{0, dt, 2 * dt, ...} whatever \code{dt} is.
#'
#' With \code{method = "euler"}, the default for this release, the explicit
#' step is stable only when \eqn{|1 + dt \lambda| < 1} for every eigenvalue
#' \eqn{\lambda} of \code{A - damping * I}. A theory that decays at rate
#' \code{damping} therefore explodes with alternating sign once
#' \code{dt * damping} exceeds 2, and the steps inflate a sustained oscillation
#' into growth. Raising \code{damping} can cause a divergence as well as fail
#' to cure one. The function warns when the Euler trajectory departs from the
#' exact one by more than 5 per cent of \code{max(1, |exact|)} at any step. The
#' default will change to \code{"exact"} in the next minor release.
#'
#' When a state grows so large that a million times it is not a finite number,
#' the function stops with a message naming the step and the state.
#'
#' The model is deliberately simple: one gain \code{k} for every coupling,
#' \code{causes} and \code{mediates} taken as positive, \code{moderates} and
#' \code{associates} coupling nothing, \code{functional_form} not read and a
#' common initial value for every state. A linear system has one equilibrium,
#' or a continuum of them when its matrix is singular, and never two separate
#' ones, so it cannot show bistability.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param steps Number of steps, a whole number of at least 0 (default
#'   \code{10}).
#' @param dt Time between rows, a finite number greater than 0 (default
#'   \code{0.1}).
#' @param k Coupling gain applied to each signed edge, a finite number (default
#'   \code{1.0}).
#' @param damping Per-state linear decay, a finite number (default
#'   \code{0.5}).
#' @param init Initial value for every state, a single finite number (default
#'   \code{1.0}).
#' @param method \code{"euler"} (the default for this release) or
#'   \code{"exact"}.
#' @return A named list
#'   \code{list(states, dt, steps, k, damping, init, method, ignored, opposed,
#'   trajectory)}, where \code{states} are the construct ids in file order and
#'   \code{trajectory} is a list of \code{steps + 1} numeric vectors (row 0 =
#'   initial state), every value rounded to 6 decimals. The knobs and the method
#'   are echoed back as given, because the trajectory cannot be reproduced
#'   without them. \code{ignored} lists the ids of the propositions that couple
#'   nothing (moderates, associates, a relation outside the schema's set, or an
#'   endpoint that is not a declared construct), and \code{opposed} the
#'   \code{c(from, to)} pairs that carry couplings of both signs, which offset
#'   each other. Invalid knobs are refused with the Python twin's messages.
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
#' @export
tf_simulate <- function(theory, steps = 10, dt = 0.1, k = 1.0,
                        damping = 0.5, init = 1.0, method = "euler") {
  .tf_sim_check_knobs(steps, dt, k, damping, init, method)
  T <- theory
  cons <- .tf_list(T, "constructs")
  states <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  n <- length(states)
  # Duplicate construct ids have no defensible reading here, and the two engines
  # resolved them differently by accident (`[[` on a named vector takes the
  # first index, Python's dict comprehension the last), so the same file
  # produced two plausible trajectories. Refuse instead of picking a winner.
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

  # n x n coupling matrix (zeros). Explicit loops mirror the Python reference
  # exactly to guarantee identical floating-point results.
  A <- matrix(0.0, nrow = n, ncol = n)
  ignored <- character(0)
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
    sign <- if (rel %in% .tf_SIM_POS) 1.0 else if (rel %in% .tf_SIM_NEG) -1.0 else 0.0
    coupled <- nzchar(f) && nzchar(t) && f %in% states && t %in% states
    if (coupled) {
      ti <- idx[[t]]
      fi <- idx[[f]]
      A[ti, fi] <- A[ti, fi] + sign * k
    }
    if (coupled && sign != 0) {
      at <- which(pair_from == f & pair_to == t)
      if (length(at) == 0L) {
        pair_from <- c(pair_from, f)
        pair_to <- c(pair_to, t)
        pair_pos <- c(pair_pos, FALSE)
        pair_neg <- c(pair_neg, FALSE)
        at <- length(pair_from)
      }
      if (sign > 0) pair_pos[at] <- TRUE else pair_neg[at] <- TRUE
    } else {
      ignored <- c(ignored, .tf_str(p, "id"))
    }
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

  X <- rep(as.numeric(init), n)
  Y <- X # the exact state the Euler run is compared with
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
      # Rounding scales by 10^6, and Python's rounding raises OverflowError
      # once that product leaves the double range, a few steps before the
      # state itself does. Both twins stop at the same step for that reason.
      for (i in seq_len(n)) {
        if (!is.finite(X[i] * 1e6)) {
          stop("simulate diverged at step ", s, ": state '", states[[i]],
               "' is not finite; ", remedy, call. = FALSE)
        }
      }
      if (method == "euler" && !departed) {
        Y <- .tf_sim_apply(E, Y)
        for (i in seq_len(n)) {
          # An exact state beyond the double range is a departure too, since
          # the Euler state is still finite here.
          if (!is.finite(Y[i]) ||
              abs(X[i] - Y[i]) > .tf_SIM_DEPARTURE * max(1, abs(Y[i]))) {
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
       damping = damping, init = init, method = method,
       ignored = as.list(ignored), opposed = opposed, trajectory = traj)
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
  if (!finite1(init)) {
    stop("simulate requires init to be a single finite number", call. = FALSE)
  }
  if (!(is.character(method) && length(method) == 1L && !is.na(method) &&
        method %in% .tf_SIM_METHODS)) {
    stop("simulate requires method to be one of: euler, exact", call. = FALSE)
  }
  invisible(NULL)
}
