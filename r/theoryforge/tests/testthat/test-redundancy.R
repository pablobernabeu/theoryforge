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
  expect_identical(names(df), c("a", "b", "similarity", "overlap", "flag", "reason"))
  # 3 constructs -> 3 unordered pairs
  expect_equal(nrow(df), 3L)
  # sorted by descending similarity
  expect_true(all(diff(df$similarity) <= 0))
  expect_true(all(df$flag %in% c("ok", "review")))
})

test_that("weak-demo's deliberately redundant pair is flagged for review", {
  df <- tf_redundancy_check(tf_read(tf_fixture_path("weak-theory.theory.yaml")))
  expect_equal(nrow(df), 1L)
  # The Jaccard similarity, 0.8, is under 0.85, but one definition is contained
  # in the other: the overlap coefficient is 1.
  expect_equal(df$similarity[[1]], 0.8)
  expect_equal(df$overlap[[1]], 1.0)
  expect_identical(df$flag[[1]], "review")
})

# A theory of n constructs whose definitions share three words, as generated
# definitions do, and hold four words of their own and their number. Python's
# test_diagram_redundancy.py builds the same theory.
screen_theory <- function(n) {
  cons <- lapply(seq_len(n) - 1L, function(i) {
    own <- sprintf("word%d", 4L * i + 0:3)
    list(id = sprintf("c%04d", i), label = sprintf("Construct %d", i),
         definition = paste("The degree of", paste(own, collapse = " "), "relative to the number", i),
         measurement = list(sprintf("scale %d", i)))
  })
  list(schema_version = "1.1", id = "screen", title = "Screen", maturity = "draft", constructs = cons)
}

test_that("the checklist's screen agrees with the full screen", {
  thr <- tf_checklist()$thresholds
  agrees <- function(t) {
    flagged <- any(tf_redundancy_check(t)$flag == "review")
    expect_identical(theoryforge:::.tf_redundancy_flagged(t, thr), flagged)
    flagged
  }
  t <- screen_theory(300L)
  expect_false(agrees(t))
  # Each of the four reasons, planted in one pair far apart.
  near <- t
  near$constructs[[290]]$definition <- t$constructs[[6]]$definition
  expect_true(agrees(near))
  contained <- t
  contained$constructs[[290]]$definition <- "The word20 word21 word22."
  expect_true(agrees(contained))
  label <- t
  label$constructs[[290]]$label <- " construct  5"
  expect_true(agrees(label))
  measure <- t
  measure$constructs[[290]]$measurement <- list("Scale 5", "scale 289")
  expect_true(agrees(measure))
})

test_that("a theory of 2000 constructs is screened and checked", {
  t <- screen_theory(2000L)
  items <- tf_check(t)$items
  item <- items[[which(vapply(items, function(i) i$id, "") == "non_redundancy")]]
  expect_identical(item$status, "pass")
  t$constructs[[1990]]$definition <- t$constructs[[3]]$definition
  items <- tf_check(t)$items
  item <- items[[which(vapply(items, function(i) i$id, "") == "non_redundancy")]]
  expect_identical(item$status, "warn")
  expect_identical(nrow(tf_redundancy_check(screen_theory(400L))), 79800L)
})
