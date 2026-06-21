test_that("tf_simulate returns states, dt, steps, and trajectory of the right shape", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  sim <- tf_simulate(theory)
  expect_named(sim, c("states", "dt", "steps", "trajectory"))
  expect_equal(unlist(sim$states),
               c("c_arousal", "c_perceived_threat", "c_avoidance"))
  expect_equal(sim$dt, 0.1)
  expect_equal(sim$steps, 10)
  # trajectory has steps + 1 rows; row 0 = initial state (all init = 1.0).
  expect_length(sim$trajectory, 11L)
  expect_equal(sim$trajectory[[1L]], c(1, 1, 1))
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
