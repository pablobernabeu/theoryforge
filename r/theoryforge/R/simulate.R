#' Deterministic dynamical-system runner derived from a theory network.
#'
#' Each construct is a state variable; each directed proposition contributes a
#' signed linear coupling term. The system is integrated with fixed-step (Euler)
#' updates, so the trajectory is fully deterministic.
#' @name simulate
#' @keywords internal
NULL

.tf_SIM_POS <- c("increases", "causes", "mediates")
.tf_SIM_NEG <- c("decreases")

#' Simulate a theory's construct network as a linear dynamical system
#'
#' Treats each construct (in file order) as a state variable and each directed
#' proposition as a signed linear coupling term, then integrates
#' \code{dX/dt = A X - damping * X} with fixed-step (Euler) updates. The result
#' is fully deterministic.
#'
#' @param theory A theory object (named list), e.g. from [tf_read()].
#' @param steps Number of Euler steps (default \code{10}).
#' @param dt Integration step size (default \code{0.1}).
#' @param k Coupling gain applied to each signed edge (default \code{1.0}).
#' @param damping Per-state linear decay (default \code{0.5}).
#' @param init Initial value for every state (default \code{1.0}).
#' @return A named list \code{list(states, dt, steps, trajectory)}, where
#'   \code{states} are the construct ids in file order and \code{trajectory} is a
#'   list of \code{steps + 1} numeric vectors (row 0 = initial state), every
#'   value rounded to 6 decimals.
#' @examples
#' theory <- tf_theory("demo-1", "A demonstration theory") |>
#'   tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
#'   tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
#'   tf_add_proposition("p1", "c_arousal", "c_threat", "increases")
#' sim <- tf_simulate(theory, steps = 5)
#' sim$states
#' sim$trajectory[[1]]
#' @export
tf_simulate <- function(theory, steps = 10, dt = 0.1, k = 1.0,
                        damping = 0.5, init = 1.0) {
  T <- theory
  cons <- .tf_list(T, "constructs")
  states <- vapply(cons, function(c) .tf_str(c, "id"), character(1))
  n <- length(states)
  idx <- stats::setNames(seq_along(states), states)

  # n x n coupling matrix (zeros). Explicit loops mirror the Python reference
  # exactly to guarantee identical floating-point results.
  A <- matrix(0.0, nrow = n, ncol = n)
  props <- .tf_list(T, "propositions")
  for (p in props) {
    f <- .tf_str(p, "from")
    t <- .tf_str(p, "to")
    rel <- .tf_str(p, "relation")
    if (nzchar(f) && nzchar(t) && f %in% states && t %in% states) {
      sign <- if (rel %in% .tf_SIM_POS) 1.0 else if (rel %in% .tf_SIM_NEG) -1.0 else 0.0
      ti <- idx[[t]]
      fi <- idx[[f]]
      A[ti, fi] <- A[ti, fi] + sign * k
    }
  }

  X <- rep(as.numeric(init), n)
  traj <- vector("list", steps + 1L)
  traj[[1L]] <- if (n == 0L) numeric(0) else .tf_rnd(X, 6)
  for (s in seq_len(steps)) {
    dX <- numeric(n)
    if (n > 0L) {
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
    traj[[s + 1L]] <- if (n == 0L) numeric(0) else .tf_rnd(X, 6)
  }

  list(states = as.list(states), dt = dt, steps = steps, trajectory = traj)
}
