test_that("tf_simulate returns states, dt, steps, and trajectory of the right shape", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sim <- tf_simulate(theory)
  expect_named(sim, c("states", "dt", "steps", "k", "damping", "init", "method",
                      "ignored", "opposed", "trajectory"))
  expect_equal(unlist(sim$states),
               c("c_arousal", "c_perceived_threat", "c_avoidance"))
  expect_equal(sim$dt, 0.1)
  expect_equal(sim$steps, 10)
  # trajectory has steps + 1 rows; row 0 = initial state (all init = 1.0).
  expect_length(sim$trajectory, 11L)
  expect_equal(sim$trajectory[[1L]], c(1, 1, 1))
})

test_that("tf_simulate echoes back every knob that shapes the trajectory", {
  # Two runs differing only in k produce different numbers, so a record that
  # omitted k could not be reproduced from what it reports.
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sim <- tf_simulate(theory, steps = 3L, dt = 0.2, k = 0.75, damping = 0.25,
                     init = 2.0)
  expect_equal(sim$dt, 0.2)
  expect_equal(sim$steps, 3L)
  expect_equal(sim$k, 0.75)
  expect_equal(sim$damping, 0.25)
  expect_equal(sim$init, 2.0)
  # At k = 1.5 the feedback loop grows fast enough for three Euler steps of
  # 0.2 to fall short of the exact solution by more than 5 per cent.
  expect_warning(other <- tf_simulate(theory, steps = 3L, dt = 0.2, k = 1.5,
                                      damping = 0.25, init = 2.0),
                 "depart from the exact solution", fixed = TRUE)
  expect_false(isTRUE(all.equal(sim$trajectory, other$trajectory)))
})

test_that("tf_simulate refuses duplicate construct ids", {
  # R used to index the first occurrence and Python the last, so the same file
  # gave two different trajectories.
  theory <- tf_theory("dupe", "Duplicated ids") |>
    tf_add_construct("c1", "One", "d") |>
    tf_add_construct("c1", "One again", "d")
  expect_error(tf_simulate(theory),
               "simulate requires unique construct ids; duplicate construct id: c1",
               fixed = TRUE)
})

test_that("tf_simulate refuses invalid knobs with the Python twin's messages", {
  # R ran two steps for 2.5 and echoed 2.5, stopped on -1 with a message from
  # seq_len(), returned NaN rows for NaN knobs, accepted a negative dt and
  # recycled init = c(1, 2, 3) into nine-value rows. The Python suite asserts
  # the same messages for the same knobs.
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  steps_msg <- "simulate requires steps to be a whole number of at least 0"
  dt_msg <- "simulate requires dt to be a finite number greater than 0"
  cases <- list(
    list(list(steps = 2.5), steps_msg),
    list(list(steps = -1), steps_msg),
    list(list(steps = TRUE), steps_msg),
    list(list(steps = NaN), steps_msg),
    list(list(steps = Inf), steps_msg),
    list(list(steps = "3"), steps_msg),
    list(list(steps = NA_integer_), steps_msg),
    list(list(steps = c(1, 2)), steps_msg),
    list(list(dt = 0), dt_msg),
    list(list(dt = -0.1), dt_msg),
    list(list(dt = NaN), dt_msg),
    list(list(dt = Inf), dt_msg),
    list(list(dt = TRUE), dt_msg),
    list(list(k = NaN), "simulate requires k to be a finite number"),
    list(list(k = -Inf), "simulate requires k to be a finite number"),
    list(list(k = "1"), "simulate requires k to be a finite number"),
    list(list(damping = NaN), "simulate requires damping to be a finite number"),
    list(list(damping = NULL), "simulate requires damping to be a finite number"),
    list(list(init = c(1, 2, 3)), "simulate requires init to be a single finite number"),
    list(list(init = NaN), "simulate requires init to be a single finite number"),
    list(list(init = FALSE), "simulate requires init to be a single finite number")
  )
  for (case in cases) {
    expect_error(do.call(tf_simulate, c(list(theory), case[[1]])), case[[2]],
                 fixed = TRUE, info = deparse(case[[1]]))
  }
})

test_that("tf_simulate accepts whole steps of either numeric type", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  ref <- tf_simulate(theory, steps = 3L)$trajectory
  sim <- tf_simulate(theory, steps = 3)
  expect_identical(sim$trajectory, ref)
  expect_identical(sim$steps, 3) # echoed as given
  expect_identical(tf_simulate(theory, steps = 0)$trajectory, list(c(1, 1, 1)))
})

test_that("tf_simulate stops with the step and state where it diverges", {
  # Within the app's own ranges. R returned rows of Inf and then NaN, which
  # the app reported as a divergence, while Python raised OverflowError from
  # its rounding at step 228, where 1e6 times the state first exceeds the
  # double range. Both twins now stop at that step.
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_error(
    tf_simulate(theory, steps = 240, dt = 2, k = 10, damping = 0, init = 10),
    "simulate diverged at step 228: state 'c_arousal' is not finite; reduce dt or k",
    fixed = TRUE)
  # One step fewer runs to completion, and warns that the Euler steps have
  # left the exact solution.
  expect_warning(
    sim <- tf_simulate(theory, steps = 227, dt = 2, k = 10, damping = 0, init = 10),
    "depart from the exact solution", fixed = TRUE)
  expect_length(sim$trajectory, 228L)
  expect_true(all(is.finite(unlist(sim$trajectory))))
})

test_that("tf_simulate sums each product left to right, as Python does", {
  # CPython 3.12+'s sum() compensated rounding error where R added left to
  # right, so in fast-growing regimes the twins drifted apart beyond the 1e-9
  # parity tolerance. Python now uses the same loop, and its suite asserts the
  # same value.
  theory <- tf_theory("fb", "Feedback")
  for (c in c("a", "b", "c", "d", "e")) {
    theory <- tf_add_construct(theory, c, toupper(c), "d")
  }
  edges <- list(c("a", "b", "increases"), c("b", "c", "causes"),
                c("c", "a", "increases"), c("a", "c", "increases"),
                c("a", "d", "increases"), c("b", "d", "increases"),
                c("c", "d", "decreases"), c("e", "d", "increases"),
                c("d", "a", "decreases"), c("d", "e", "increases"))
  for (i in seq_along(edges)) {
    e <- edges[[i]]
    theory <- tf_add_proposition(theory, paste0("p", i), e[[1]], e[[2]], e[[3]])
  }
  expect_warning(sim <- tf_simulate(theory, steps = 500, k = 1, dt = 0.1),
                 "depart from the exact solution", fixed = TRUE)
  expect_identical(sim$trajectory[[342L]][[4L]], -69972264.681408)
})

test_that("tf_simulate honours custom steps and init", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sim <- tf_simulate(theory, steps = 3L, init = 2.0)
  expect_length(sim$trajectory, 4L)
  expect_equal(sim$trajectory[[1L]], c(2, 2, 2))
  # every value is rounded to 6 decimals.
  flat <- unlist(sim$trajectory)
  expect_equal(flat, round(flat, 6))
})

test_that("tf_simulate matches the Python golden semantically (tol 1e-9)", {
  runs <- expand.grid(id = c("panic-network-2026", "panic-network-2026-v2", "weak-demo",
                             "modality-switching-2026"),
                      method = c("euler", "exact"), stringsAsFactors = FALSE)
  for (run in seq_len(nrow(runs))) {
    id <- runs$id[[run]]
    method <- runs$method[[run]]
    fixture <- switch(id,
      "weak-demo" = "weak-theory.theory.yaml",
      "panic-network-2026" = "panic-network.theory.yaml",
      "panic-network-2026-v2" = "panic-network-2026-v2.theory.yaml",
      "modality-switching-2026" = "modality-switching.theory.yaml")
    theory <- tf_read(tf_fixture_path(fixture))
    sim <- tf_simulate(theory, method = method)

    golden_file <- paste0(id, if (method == "exact") ".simulate_exact.json" else ".simulate.json")
    golden <- jsonlite::fromJSON(tf_expected_path(golden_file), simplifyVector = TRUE)
    id <- paste(id, method)

    expect_equal(unlist(sim$states), as.character(golden$states), info = id)
    expect_equal(sim$dt, golden$dt, info = id)
    expect_equal(sim$steps, golden$steps, info = id)
    expect_identical(sim$method, golden$method, info = id)
    expect_equal(as.character(unlist(sim$ignored)), as.character(golden$ignored), info = id)
    expect_length(sim$opposed, length(golden$opposed))

    # golden$trajectory parses to a matrix (rows = steps + 1).
    g_traj <- golden$trajectory
    expect_equal(length(sim$trajectory), nrow(g_traj), info = id)
    for (r in seq_along(sim$trajectory)) {
      expect_equal(as.numeric(sim$trajectory[[r]]),
                   as.numeric(g_traj[r, ]), tolerance = 1e-9,
                   info = paste(id, "row", r))
    }
  }
})

test_that("tf_simulate panic trajectory reproduces the documented first rows", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sim <- tf_simulate(theory)
  expect_equal(sim$trajectory[[1L]], c(1, 1, 1))
  expect_equal(sim$trajectory[[2L]], c(1.05, 1.05, 1.05))
  expect_equal(sim$trajectory[[3L]], c(1.1025, 1.1025, 1.1025))
  expect_equal(sim$trajectory[[4L]], c(1.157625, 1.157625, 1.157625))
})

# simulate(method = ...): the exact propagator, the Euler departure warning and
# the record of what the coupling matrix leaves out (API_SPEC section 22). The
# Python suite (test_simulate_methods.py) asserts the same values and messages.

euler_warning <- paste0("simulate: the Euler steps depart from the exact solution by ",
                        "more than 5 per cent; use method 'exact' or a smaller dt")

# Pinned from the Python twin, whose suite asserts the same values. The panic
# network at k = 10 has an eigenvalue of +10, so the exact solution itself grows
# by exp(20) per step and leaves the double range at step 35.
exact_fb_row_40 <- c(-60572.780936, -56901.703303, -110132.328974, -45888.470406,
                     -42217.392773)
exact_fb_row_7_d <- 3.837653
exact_divergence <- paste0("simulate diverged at step 35: state 'c_arousal' is not finite; ",
                           "raise damping, reduce k or take fewer steps")

regulation_theory <- function() {
  # The example of workflow-modes.md: J has eigenvalues -1.5 and +-0.866i, a
  # sustained oscillation with period 7.26.
  tf_theory("regulation_demo", "Arousal regulated by avoidance") |>
    tf_add_construct("arousal", "Physiological arousal", "bodily activation") |>
    tf_add_construct("threat", "Perceived threat", "appraised danger") |>
    tf_add_construct("avoidance", "Avoidance behaviour", "protective withdrawal") |>
    tf_add_proposition("p1", "arousal", "threat", "increases") |>
    tf_add_proposition("p2", "threat", "avoidance", "increases") |>
    tf_add_proposition("p3", "avoidance", "arousal", "decreases")
}

feedback_theory <- function() {
  theory <- tf_theory("fb", "Feedback")
  for (c in c("a", "b", "c", "d", "e")) {
    theory <- tf_add_construct(theory, c, toupper(c), "d")
  }
  edges <- list(c("a", "b", "increases"), c("b", "c", "causes"),
                c("c", "a", "increases"), c("a", "c", "increases"),
                c("a", "d", "increases"), c("b", "d", "increases"),
                c("c", "d", "decreases"), c("e", "d", "increases"),
                c("d", "a", "decreases"), c("d", "e", "increases"))
  for (i in seq_along(edges)) {
    e <- edges[[i]]
    theory <- tf_add_proposition(theory, paste0("p", i), e[[1]], e[[2]], e[[3]])
  }
  theory
}

test_that("tf_simulate refuses an unknown method with the Python twin's message", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  for (method in list("rk4", "Exact", "", NULL, 1, c("euler", "exact"), NA_character_)) {
    expect_error(tf_simulate(theory, method = method),
                 "simulate requires method to be one of: euler, exact",
                 fixed = TRUE, info = deparse(method))
  }
})

test_that("tf_simulate records the method and what the coupling leaves out", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sim <- tf_simulate(theory, steps = 2)
  expect_identical(sim$method, "euler")
  expect_identical(sim$ignored, list())
  expect_identical(sim$opposed, list())
  expect_identical(tf_simulate(theory, steps = 2, method = "exact")$method, "exact")
})

test_that("tf_simulate's exact method decays where Euler explodes", {
  # weak-demo decays at rate 2.5. With dt = 1 the Euler step multiplies each
  # state by 1 - 2.5 = -1.5, while the exact solution is exp(-2.5 t).
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  exact <- tf_simulate(theory, steps = 3, dt = 1, damping = 2.5, method = "exact")
  expect_identical(vapply(exact$trajectory, `[[`, numeric(1), 1L),
                   c(1, 0.082085, 0.006738, 0.000553))
  expect_warning(euler <- tf_simulate(theory, steps = 3, dt = 1, damping = 2.5),
                 euler_warning, fixed = TRUE)
  expect_identical(vapply(euler$trajectory, `[[`, numeric(1), 1L),
                   c(1, -1.5, 2.25, -3.375))
})

test_that("tf_simulate's exact method keeps the oscillation that Euler inflates", {
  # dt * ||J||_inf is 0.15 here, so a step-size rule would not catch it, but
  # Euler inflates the oscillatory mode by 1.0037 per step.
  theory <- regulation_theory()
  exact <- tf_simulate(theory, steps = 500, method = "exact")
  expect_lt(max(abs(unlist(utils::tail(exact$trajectory, 73L)))), 1.4)
  expect_warning(euler <- tf_simulate(theory, steps = 500), euler_warning, fixed = TRUE)
  expect_gt(max(abs(unlist(utils::tail(euler$trajectory, 73L)))), 8)
})

test_that("tf_simulate's Euler steps do not warn while they track the exact solution", {
  expect_no_warning(tf_simulate(tf_read(tf_fixture_path("panic-network.theory.yaml"))))
  expect_no_warning(tf_simulate(regulation_theory(), steps = 5))
})

test_that("tf_simulate's exact method has no step-size limit", {
  # Inside the app's ranges (dt 2, damping 5), where Euler multiplies by -9.
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  sim <- tf_simulate(theory, steps = 4, dt = 2, damping = 5, method = "exact")
  expect_identical(sim$trajectory[[2L]][[1L]], 4.5e-05)
  expect_identical(sim$trajectory[[5L]], c(0, 0))
})

test_that("tf_simulate's exact trajectory is pinned bit for bit", {
  # The Python suite asserts the same numbers with ==.
  sim <- tf_simulate(feedback_theory(), steps = 40, dt = 0.5, method = "exact")
  expect_identical(sim$trajectory[[41L]], exact_fb_row_40)
  expect_identical(sim$trajectory[[8L]][[4L]], exact_fb_row_7_d)
})

test_that("tf_simulate's exact method stops where the system itself diverges", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_error(tf_simulate(theory, steps = 240, dt = 2, k = 10, damping = 0, init = 10,
                           method = "exact"),
               exact_divergence, fixed = TRUE)
  # Damping beyond the largest eigenvalue of A, the remedy the message names
  # first, makes the same run decay to zero.
  sim <- tf_simulate(theory, steps = 240, dt = 2, k = 10, damping = 11, init = 10,
                     method = "exact")
  expect_identical(sim$trajectory[[241L]], c(0, 0, 0))
})

test_that("tf_simulate's exact method handles zero steps and an empty theory", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_identical(tf_simulate(theory, steps = 0, method = "exact")$trajectory,
                   list(c(1, 1, 1)))
  empty <- tf_simulate(tf_theory("empty", "No constructs"), steps = 2, method = "exact")
  expect_identical(empty$trajectory, list(numeric(0), numeric(0), numeric(0)))
})

test_that("tf_simulate names ignored propositions and opposed pairs", {
  theory <- tf_theory("rec", "Record") |>
    tf_add_construct("a", "A", "d") |>
    tf_add_construct("b", "B", "d") |>
    tf_add_construct("c", "C", "d") |>
    tf_add_proposition("p1", "a", "b", "increases") |>
    tf_add_proposition("p2", "a", "b", "decreases") |>
    tf_add_proposition("p3", "a", "c", "moderates") |>
    tf_add_proposition("p4", "b", "c", "associates") |>
    tf_add_proposition("p5", "a", "zz", "increases") |>
    tf_add_proposition("p6", "b", "c", "causes") |>
    tf_add_proposition("p7", "b", "c", "decreases") |>
    tf_add_proposition("p8", "a", "b", "increases") |>
    tf_add_proposition("p9", "c", "b", "mediates")
  sim <- tf_simulate(theory, steps = 1)
  expect_identical(sim$ignored, list("p3", "p4", "p5"))
  expect_identical(sim$opposed, list(c("a", "b"), c("b", "c")))
})

test_that("tf_simulate's propagator agrees with Matrix::expm", {
  skip_if_not_installed("Matrix")
  J <- matrix(c(-0.5, 0, -1, 1, -0.5, 0, 0, 1, -0.5), nrow = 3, byrow = TRUE)
  for (dt in c(0.001, 0.1, 2, 37)) {
    E <- .tf_sim_propagator(J, dt)
    ref <- as.matrix(Matrix::expm(Matrix::Matrix(J * dt)))
    expect_lt(max(abs(E - ref)) / max(1, max(abs(ref))), 1e-13)
  }
})

test_that("tf_simulate's propagator of a non-finite matrix is NaN", {
  # dt * k beyond the double range: no halving brings the norm down, so the
  # propagator is NaN and the first step diverges.
  E <- .tf_sim_propagator(matrix(c(0, 1e308, 1e308, 0), nrow = 2), 10)
  expect_true(all(is.nan(E)))
})
