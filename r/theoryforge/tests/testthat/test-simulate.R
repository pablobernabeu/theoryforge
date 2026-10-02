test_that("tf_simulate returns states, dt, steps, and trajectory of the right shape", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sim <- tf_simulate(theory)
  expect_named(sim, c("states", "dt", "steps", "k", "damping", "init", "trajectory"))
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
  other <- tf_simulate(theory, steps = 3L, dt = 0.2, k = 1.5, damping = 0.25,
                       init = 2.0)
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
  sim <- tf_simulate(theory, steps = 227, dt = 2, k = 10, damping = 0, init = 10)
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
  sim <- tf_simulate(theory, steps = 500, k = 1, dt = 0.1)
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
  for (id in c("panic-network-2026", "panic-network-2026-v2", "weak-demo")) {
    fixture <- if (id == "weak-demo") "weak-theory.theory.yaml" else
      if (id == "panic-network-2026") "panic-network.theory.yaml" else
        "panic-network-2026-v2.theory.yaml"
    theory <- tf_read(tf_fixture_path(fixture))
    sim <- tf_simulate(theory)

    golden <- jsonlite::fromJSON(tf_expected_path(paste0(id, ".simulate.json")),
                                 simplifyVector = TRUE)

    expect_equal(unlist(sim$states), as.character(golden$states), info = id)
    expect_equal(sim$dt, golden$dt, info = id)
    expect_equal(sim$steps, golden$steps, info = id)

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
