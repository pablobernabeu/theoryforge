test_that("tf_tokens follows the spec tokenisation", {
  expect_setequal(tf_tokens("The quick brown FOX!"), c("quick", "brown", "fox"))
  # drop <3 chars, lowercase, stopwords removed, set semantics (unique)
  expect_setequal(tf_tokens("drive drive towards goals"), c("drive", "goals"))
  expect_length(tf_tokens(""), 0L)
  expect_length(tf_tokens(NULL), 0L)
})

test_that("tf_jaccard rounds to 3dp and handles empty sets", {
  expect_equal(tf_jaccard(character(0), character(0)), 0.0)
  expect_equal(tf_jaccard(c("a", "b"), c("b", "c")), round(1 / 3, 3))
  expect_equal(tf_jaccard(c("a"), c("a")), 1.0)
})

test_that("tf_redundancy_check returns a sorted data.frame with expected columns", {
  df <- tf_redundancy_check(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  expect_s3_class(df, "data.frame")
  expect_identical(names(df), c("a", "b", "similarity", "flag"))
  # 3 constructs -> 3 unordered pairs
  expect_equal(nrow(df), 3L)
  # sorted by descending similarity
  expect_true(all(diff(df$similarity) <= 0))
  expect_true(all(df$flag %in% c("ok", "review")))
})

test_that("weak-demo redundancy reflects non_redundancy score (max_sim = 0.8)", {
  df <- tf_redundancy_check(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_equal(nrow(df), 1L)
  expect_equal(df$similarity[[1]], 0.8)
  expect_identical(df$flag[[1]], "ok")  # 0.8 < 0.85 threshold
})
