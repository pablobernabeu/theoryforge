# Bibliometric / literature layer (API_SPEC.md Part C).

test_that("tf_read_corpus round-trips the fixture corpus", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  expect_equal(corpus$id, "panic-corpus-demo")
  expect_equal(corpus$schema_version, "1.0")
  expect_equal(length(corpus$records), 8L)
  expect_equal(corpus$records[[1]]$id, "r1")
  expect_equal(as.character(unlist(corpus$records[[1]]$keywords)),
               c("arousal", "interoception"))
})

test_that("tf_litmap finds the four expected themes", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  lm <- tf_litmap(corpus)
  expect_equal(lm$n_records, 8L)

  theme_kw <- lapply(lm$themes, function(th) unlist(th$keywords, use.names = FALSE))
  ids <- vapply(lm$themes, function(th) th$id, character(1))
  expect_equal(ids, c("theme_1", "theme_2", "theme_3", "theme_4"))
  expect_equal(theme_kw[[1]], c("appraisal", "catastrophic misinterpretation"))
  expect_equal(theme_kw[[2]], c("arousal", "interoception"))
  expect_equal(theme_kw[[3]], c("avoidance", "exposure"))
  expect_equal(theme_kw[[4]], c("genetics", "heritability"))
  expect_true(all(vapply(lm$themes, function(th) th$size, integer(1)) == 2L))
})

test_that("tf_litmap counts keyword co-occurrence and co-citation edges", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  lm <- tf_litmap(corpus)

  kw_pairs <- vapply(lm$keyword_cooccurrence,
                     function(e) paste(e$a, e$b, e$count, sep = "|"), character(1))
  expect_setequal(kw_pairs, c(
    "appraisal|catastrophic misinterpretation|2",
    "arousal|interoception|2",
    "avoidance|exposure|2",
    "genetics|heritability|2"
  ))

  cocit <- vapply(lm$co_citation,
                  function(e) paste(e$a, e$b, e$count, sep = "|"), character(1))
  expect_equal(cocit, c("barlow2002|clark1986|3", "bouton2001|craske2008|2"))
  # counts are integers, not doubles
  expect_true(all(vapply(lm$co_citation, function(e) is.integer(e$count), logical(1))))
})

test_that("tf_litmap honours min_link", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  lm3 <- tf_litmap(corpus, min_link = 3)
  cocit <- vapply(lm3$co_citation,
                  function(e) paste(e$a, e$b, e$count, sep = "|"), character(1))
  expect_equal(cocit, "barlow2002|clark1986|3")
})

test_that("tf_landscape assigns the expected theme statuses", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  ls <- tf_landscape(theory, corpus)

  expect_equal(ls$theory_id, "panic-network-2026")
  status <- vapply(ls$themes, function(th) th$status, character(1))
  names(status) <- vapply(ls$themes, function(th) th$id, character(1))

  expect_equal(unname(status["theme_2"]), "crowded")
  expect_equal(unname(status["theme_4"]), "under_theorised")

  theme2 <- Filter(function(th) th$id == "theme_2", ls$themes)[[1]]
  expect_equal(unlist(theme2$alternatives, use.names = FALSE), "alt_biological")
  expect_true(theme2$focal)

  expect_equal(unlist(ls$redundancy_risk, use.names = FALSE), "theme_2")
  expect_equal(unlist(ls$under_theorised_fronts, use.names = FALSE), "theme_4")
})

test_that("literature diagrams are byte-identical to the golden files", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  lm <- tf_litmap(corpus)
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  ls <- tf_landscape(theory, corpus)

  cid <- "panic-corpus-demo"
  cases <- list(
    list(obj = lm, type = "keyword_cooccurrence"),
    list(obj = lm, type = "co_citation"),
    list(obj = ls, type = "theme_landscape")
  )
  for (cs in cases) {
    got <- tf_lit_diagram(cs$obj, cs$type)
    golden <- tf_read_golden(tf_expected_path(paste0(cid, ".", cs$type, ".dot")))
    expect_identical(got, golden, info = cs$type)
  }
})

test_that("tf_lit_diagram rejects unknown types", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  lm <- tf_litmap(corpus)
  expect_error(tf_lit_diagram(lm, "mindmap"), "unknown lit diagram type")
})
