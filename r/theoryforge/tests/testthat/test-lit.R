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

test_that("tf_new_evidence_dois excludes DOIs already cited by the theory", {
  # The fixture already cites 10.1016/j.brat.2015.10.002 (evidence) and
  # 10.1016/0005-7967(86)90011-2 / 10.1176/ajp.146.2.148 (alternatives).
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  candidates <- c(
    "10.1016/j.brat.2015.10.002",                     # already cited (evidence), exact
    "https://doi.org/10.1016/0005-7967(86)90011-2",   # already cited (alternative), URL form
    "10.1176/AJP.146.2.148",                          # already cited (alternative), different case
    "10.1037/0033-2909.99.1.20",                      # new
    "10.1037/0033-2909.99.1.20",                      # new, duplicated in the candidate list itself
    "10.1016/j.cpr.2011.09.005"                       # new
  )
  new <- tf_new_evidence_dois(theory, candidates)
  expect_equal(new, c("10.1016/j.cpr.2011.09.005", "10.1037/0033-2909.99.1.20"))
})

test_that("tf_new_evidence_dois handles a theory with no evidence or alternatives", {
  theory <- tf_theory("demo", "Demo")
  expect_equal(tf_new_evidence_dois(theory, "10.1000/xyz"), "10.1000/xyz")
  expect_equal(tf_new_evidence_dois(theory, character(0)), character(0))
  expect_equal(tf_new_evidence_dois(theory, c(NA, "")), character(0))
})

test_that("tf_new_evidence_dois matches the golden JSON semantically", {
  # Same theory and candidate list as scripts/gen_golden.py.
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  candidates <- c(
    "10.1016/j.brat.2015.10.002",
    "https://doi.org/10.1016/0005-7967(86)90011-2",
    "10.1176/AJP.146.2.148",
    "10.1037/0033-2909.99.1.20",
    "10.1037/0033-2909.99.1.20",
    "10.1016/j.cpr.2011.09.005"
  )
  got <- tf_new_evidence_dois(theory, candidates)
  golden <- jsonlite::fromJSON(
    tf_expected_path("panic-network-2026.new_evidence_dois.json"),
    simplifyVector = FALSE
  )
  expect_equal(got, vapply(golden, as.character, character(1)))
})

test_that("keyword sorting is codepoint-ordered regardless of locale", {
  # Radix sorts mirror Python's ordering: uppercase (Z) before lowercase (a).
  # The Python suite runs the same corpus and asserts the same order.
  corpus <- list(
    schema_version = "1.0", id = "mixed-case",
    records = list(
      list(id = "w1", keywords = list("alpha", "Zeta")),
      list(id = "w2", keywords = list("Zeta", "alpha"))
    )
  )
  lm <- tf_litmap(corpus)
  expect_equal(unlist(lm$keywords), c("Zeta", "alpha"))
  expect_equal(lm$keyword_cooccurrence[[1]]$a, "Zeta")
  expect_equal(lm$keyword_cooccurrence[[1]]$b, "alpha")
  expect_equal(unlist(lm$themes[[1]]$keywords), c("Zeta", "alpha"))
  expect_identical(
    tf_lit_diagram(lm, "keyword_cooccurrence"),
    paste0('graph keyword_cooccurrence {\n  node [shape=ellipse];\n',
           '  "Zeta";\n  "alpha";\n',
           '  "Zeta" -- "alpha" [label="2"];\n}\n')
  )
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
