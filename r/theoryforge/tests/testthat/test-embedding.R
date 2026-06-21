# A deterministic fake embedder: bag-of-words counts over a fixed vocabulary,
# so the test is reproducible without any model dependency.
fake_embedder <- function(vocab) {
  function(def) {
    words <- strsplit(tolower(as.character(def)), "[^a-z0-9]+")[[1L]]
    words <- words[nzchar(words)]
    vapply(vocab, function(w) sum(words == w), numeric(1))
  }
}

test_that("tf_embedding_redundancy returns a sorted data.frame with expected columns", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  vocab <- c("bodily", "activation", "appraised", "danger", "acts", "exposure",
             "feared", "sensations", "internal", "external")
  df <- tf_embedding_redundancy(theory, fake_embedder(vocab))
  expect_s3_class(df, "data.frame")
  expect_identical(names(df), c("a", "b", "cosine", "flag"))
  # 3 constructs -> 3 unordered pairs.
  expect_equal(nrow(df), 3L)
  # sorted by descending cosine.
  expect_true(all(diff(df$cosine) <= 0))
  expect_true(all(df$flag %in% c("ok", "review")))
  # cosine rounded to 6 decimals and within [0, 1].
  expect_equal(df$cosine, round(df$cosine, 6))
  expect_true(all(df$cosine >= 0 & df$cosine <= 1 + 1e-9))
})

test_that("tf_embedding_redundancy flags identical definitions for review", {
  theory <- tf_theory("demo", "Demo") |>
    tf_add_construct("c1", "One", "shared overlapping definition text") |>
    tf_add_construct("c2", "Two", "shared overlapping definition text") |>
    tf_add_construct("c3", "Three", "completely different unrelated wording")
  vocab <- c("shared", "overlapping", "definition", "text", "completely",
             "different", "unrelated", "wording")
  df <- tf_embedding_redundancy(theory, fake_embedder(vocab))
  expect_equal(nrow(df), 3L)
  # the identical pair has cosine 1 and is first (descending sort).
  expect_equal(df$cosine[[1L]], 1.0)
  expect_identical(df$flag[[1L]], "review")
})

test_that("tf_embedding_redundancy respects a custom threshold", {
  theory <- tf_theory("demo", "Demo") |>
    tf_add_construct("c1", "One", "alpha beta") |>
    tf_add_construct("c2", "Two", "alpha gamma")
  vocab <- c("alpha", "beta", "gamma")
  # cosine of (1,1,0) and (1,0,1) = 0.5.
  df_low <- tf_embedding_redundancy(theory, fake_embedder(vocab), threshold = 0.4)
  df_high <- tf_embedding_redundancy(theory, fake_embedder(vocab), threshold = 0.9)
  expect_equal(df_low$cosine[[1L]], 0.5)
  expect_identical(df_low$flag[[1L]], "review")
  expect_identical(df_high$flag[[1L]], "ok")
})
