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
  lm <- one_theme(tf_litmap(corpus))
  expect_equal(unlist(lm$keywords), c("Zeta", "alpha"))
  expect_equal(lm$keyword_cooccurrence[[1]]$a, "Zeta")
  expect_equal(lm$keyword_cooccurrence[[1]]$b, "alpha")
  expect_equal(unlist(lm$themes[[1]]$keywords), c("Zeta", "alpha"))
  expect_identical(
    tf_lit_diagram(lm, "keyword_cooccurrence"),
    paste0('graph keyword_cooccurrence {\n',
           '  graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", ',
           'fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];\n',
           '  node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", ',
           'color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, ',
           'margin="0.16,0.1"];\n',
           '  edge [fontname="Helvetica", fontsize=10, color="#7B909F", ',
           'fontcolor="#0F6E6E", arrowsize=0.7];\n',
           '  node [shape=ellipse, style="filled", fillcolor="#E4F1F1", color="#1E7B7B"];\n',
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

# -- validated arguments and corpora (API_SPEC.md section 14) -----------------
# The Python suite runs the same cases and expects the same messages.

bool_hint <- "(an unquoted no, yes, on or off is read as a boolean; quote it)"

# The message of the error `expr` raises, compared whole.
expect_refusal <- function(expr, message) {
  got <- tryCatch({ expr; NULL }, error = function(e) conditionMessage(e))
  expect_identical(got, message)
}

# A corpus of two records holding the same `values` under `field`.
two_records <- function(field, values) {
  rec <- function(id) stats::setNames(list(id, values), c("id", field))
  list(schema_version = "1.0", id = "c", records = list(rec("w1"), rec("w2")))
}

write_corpus <- function(text, ext = ".yaml") {
  path <- tempfile(fileext = ext)
  writeBin(charToRaw(text), path)
  path
}

edge_strings <- function(edges) {
  vapply(edges, function(e) paste(e$a, e$b, e$count, sep = "|"), character(1))
}

test_that("tf_litmap refuses a min_link that is not a positive integer", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  for (bad in list(2.5, NA, NA_real_, "2", c(2, 3), 0, -1, TRUE, NaN, Inf, NULL, list(2))) {
    expect_refusal(tf_litmap(corpus, min_link = bad), "min_link must be a positive integer")
  }
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_refusal(tf_landscape(theory, corpus, min_link = 2.5),
                 "min_link must be a positive integer")
  expect_identical(tf_litmap(corpus, min_link = 2L), tf_litmap(corpus, min_link = 2))
})

test_that("a threshold beyond R's integer range is accepted as Python accepts it", {
  # as.integer() made 1e10 NA, which gave an empty map with a warning and made
  # tf_lit_diagram() fail on a missing value.
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  lm <- expect_silent(tf_litmap(corpus, min_link = 1e10, min_cocitation = 3e9))
  expect_length(lm$keyword_cooccurrence, 0L)
  expect_length(lm$co_citation, 0L)
  full <- tf_litmap(corpus)
  for (kind in c("keyword_cooccurrence", "co_citation")) {
    expect_identical(expect_silent(tf_lit_diagram(full, kind, max_edges = 1e10)),
                     tf_lit_diagram(full, kind))
  }
})

test_that("min_cocitation thresholds the co-citation map alone", {
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  for (bad in list(0, 1.5, "3", TRUE)) {
    expect_refusal(tf_litmap(corpus, min_cocitation = bad),
                   "min_cocitation must be a positive integer")
  }
  lm <- tf_litmap(corpus, min_link = 2, min_cocitation = 3)
  expect_identical(edge_strings(lm$co_citation), "barlow2002|clark1986|3")
  expect_identical(lm$keyword_cooccurrence, tf_litmap(corpus)$keyword_cooccurrence)
  expect_identical(tf_litmap(corpus, min_link = 3),
                   tf_litmap(corpus, min_link = 3, min_cocitation = 3))
})

test_that("a corpus without a records list is refused", {
  bad <- list(
    list(schema_version = "1.0", id = "c", recrods = list(list(id = "w1"))),
    list(schema_version = "1.0", id = "c", records = list(w1 = list(id = "w1"))),
    list(schema_version = "1.0", id = "c", records = NULL),
    list(schema_version = "1.0", id = "c", records = "w1"),
    list("not", "a", "corpus")
  )
  for (corpus in bad) {
    expect_refusal(tf_litmap(corpus), "invalid corpus: missing records list")
  }
  # A misspelt key read from a file, and records written as a mapping.
  expect_refusal(tf_litmap(tf_read_corpus(write_corpus(
    'schema_version: "1.0"\nid: c\nrecrods:\n  - id: w1\n'))),
    "invalid corpus: missing records list")
  expect_refusal(tf_litmap(tf_read_corpus(write_corpus(
    'schema_version: "1.0"\nid: c\nrecords:\n  w1: {id: w1}\n  w2: {id: w2}\n'))),
    "invalid corpus: missing records list")
})

test_that("an empty records list is an empty corpus", {
  lm <- tf_litmap(list(schema_version = "1.0", id = "c", records = list()))
  expect_identical(lm$n_records, 0L)
  expect_length(lm$keywords, 0L)
  expect_length(lm$keyword_cooccurrence, 0L)
  expect_length(lm$co_citation, 0L)
})

test_that("a record that is not a mapping is refused", {
  corpus <- list(schema_version = "1.0", id = "c", records = list(list(id = "w1"), "w2"))
  expect_refusal(tf_litmap(corpus), "invalid corpus: record[1] is not a mapping")
  expect_refusal(tf_litmap(tf_read_corpus(write_corpus(
    'schema_version: "1.0"\nid: c\nrecords: [r1, r2]\n'))),
    "invalid corpus: record[0] is not a mapping")
})

test_that("an unquoted YAML boolean keyword is refused with a hint", {
  for (text in c("[NO, cGMP, vasodilation]", "[ON, retina]")) {
    path <- write_corpus(paste0('schema_version: "1.0"\nid: c\nrecords:\n  - id: w1\n    keywords: ',
                                text, "\n"))
    expect_refusal(tf_litmap(tf_read_corpus(path)),
                   paste("invalid corpus: record[0] keywords must be strings", bool_hint))
  }
})

test_that("a reference that is not a string or an integer is refused", {
  for (bad in list(1.5, TRUE, list("nested"), list(k = "v"), NaN)) {
    corpus <- list(schema_version = "1.0", id = "c", records = list(
      list(id = "w1", references = list("ok")),
      list(id = "w2", references = list("ok", bad))
    ))
    expect_refusal(tf_litmap(corpus),
                   paste("invalid corpus: record[1] references must be strings", bool_hint))
  }
  corpus <- list(schema_version = "1.0", id = "c",
                 records = list(list(id = "w1", keywords = list(a = "b"))))
  expect_refusal(tf_litmap(corpus),
                 paste("invalid corpus: record[0] keywords must be strings", bool_hint))
})

test_that("integer references become decimal strings beside DOIs", {
  lm <- tf_litmap(two_records("references", list(12345L, "10.1000/xyz", 2)))
  expect_identical(edge_strings(lm$co_citation), c(
    "10.1000/xyz|12345|2", "10.1000/xyz|2|2", "12345|2|2"
  ))
  # as.character() would have written 1e+05.
  lm <- tf_litmap(two_records("references", list(100000, "a")))
  expect_identical(edge_strings(lm$co_citation), "100000|a|2")
  kw <- one_theme(tf_litmap(two_records("keywords", list(7L, "seven"))))
  expect_identical(unlist(kw$keywords), c("7", "seven"))
})

test_that("null, missing and empty entries are dropped", {
  lm <- one_theme(tf_litmap(two_records("keywords", list("a", NULL, NA, "", "b"))))
  expect_identical(unlist(lm$keywords), c("a", "b"))
  expect_identical(edge_strings(lm$keyword_cooccurrence), "a|b|2")
})

test_that("Scopus-style integer ids map alike from YAML and JSON", {
  # FAM-12: an unquoted integer beyond the 32-bit range was read as NA, so the
  # co-citation map was empty where Python found the edge.
  yaml_path <- write_corpus(paste0(
    'schema_version: "1.0"\nid: c\nrecords:\n',
    "  - id: w1\n    references: [85000000001, 85000000002]\n",
    "  - id: w2\n    references: [85000000001, 85000000002]\n"))
  json_path <- write_corpus(paste0(
    '{"schema_version": "1.0", "id": "c", "records": [',
    '{"id": "w1", "references": [85000000001, 85000000002]},',
    '{"id": "w2", "references": [85000000001, 85000000002]}]}'), ".json")
  for (path in c(yaml_path, json_path)) {
    lm <- tf_litmap(tf_read_corpus(path))
    expect_identical(edge_strings(lm$co_citation), "85000000001|85000000002|2")
  }
})

test_that("an integer too large to hold exactly is refused", {
  for (big in list(2^53, -(2^53), 1e300)) {
    expect_refusal(tf_litmap(two_records("references", list("a", big))), paste(
      "invalid corpus: record[0] references entry 1 is a number too large to be an",
      "exact identifier; quote it"))
  }
  path <- write_corpus(paste0('schema_version: "1.0"\nid: c\nrecords:\n',
                              "  - id: w1\n    references: [a, 9007199254740993]\n"))
  expect_refusal(tf_litmap(tf_read_corpus(path)), paste(
    "invalid corpus: record[0] references entry 1 is a number too large to be an",
    "exact identifier; quote it"))
  lm <- tf_litmap(two_records("references", list(2^53 - 1, "a")))
  expect_identical(edge_strings(lm$co_citation), "9007199254740991|a|2")
})

test_that("pair counting matches a direct count on random corpora", {
  # A slow, obviously correct count: one environment entry per pair.
  direct <- function(values, min_link) {
    counts <- new.env(parent = emptyenv())
    for (vals in values) {
      vals <- sort(unique(vals), method = "radix")
      n <- length(vals)
      if (n < 2L) next
      for (i in seq_len(n - 1L)) for (j in (i + 1L):n) {
        # \001 sorts below every character in the pool, so the keys sort as
        # the (a, b) pairs do.
        key <- paste(vals[[i]], vals[[j]], sep = "\001")
        counts[[key]] <- (if (is.null(counts[[key]])) 0L else counts[[key]]) + 1L
      }
    }
    keys <- sort(ls(counts, sorted = FALSE), method = "radix")
    keys <- keys[vapply(keys, function(k) counts[[k]] >= min_link, logical(1))]
    vapply(keys, function(k) paste(sub("\001", "|", k, fixed = TRUE), counts[[k]], sep = "|"),
           character(1), USE.NAMES = FALSE)
  }
  set.seed(17)
  pool <- c(letters, LETTERS, "été", "a b", "10.1000/x")
  for (rep in 1:5) {
    values <- lapply(1:40, function(i) sample(pool, sample(0:12, 1L), replace = TRUE))
    records <- lapply(seq_along(values), function(i) list(id = paste0("w", i), references = as.list(values[[i]])))
    corpus <- list(schema_version = "1.0", id = "c", records = records)
    for (min_link in 1:3) {
      got <- edge_strings(tf_litmap(corpus, min_link = min_link)$co_citation)
      expect_identical(unname(got), direct(values, min_link))
    }
  }
})

test_that("a record with 300 references maps in seconds", {
  # 44,850 pairs. The count grew one vector element at a time, so this took
  # about a minute; it now takes a fraction of a second.
  skip_on_cran()
  refs <- as.list(sprintf("W%04d", 1:300))
  corpus <- list(schema_version = "1.0", id = "c", records = list(list(id = "w1", references = refs)))
  elapsed <- system.time(lm <- tf_litmap(corpus, min_link = 1))[["elapsed"]]
  expect_length(lm$co_citation, 44850L)
  expect_lt(elapsed, 20)
})

test_that("tf_landscape does not count co-citation", {
  original <- get(".tf_pair_counts", envir = asNamespace("theoryforge"))
  calls <- 0L
  local_mocked_bindings(.tf_pair_counts = function(values) {
    calls <<- calls + 1L
    original(values)
  })
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  tf_landscape(tf_read(tf_fixture_path("panic-network.theory.yaml")), corpus)
  expect_identical(calls, 1L)
  calls <- 0L
  tf_litmap(corpus)
  expect_identical(calls, 2L)
})

# -- landscape: matched terms, field and phenomenon words (API_SPEC.md section 15) --
# The Python suite runs the same cases and expects the same results.

# A corpus holding each keyword vector in two records, so each pair is linked.
paired <- function(...) {
  lists <- list(...)
  records <- list()
  for (i in seq_along(lists)) {
    for (j in 1:2) {
      records[[length(records) + 1L]] <- list(id = sprintf("r%d%d", i - 1L, j),
                                              keywords = as.list(lists[[i]]))
    }
  }
  list(schema_version = "1.0", id = "c", records = records)
}

# A theory with `title`, one construct per label and list(id, label, key
# constructs) rivals.
account <- function(title, labels = character(0), alternatives = list()) {
  list(
    schema_version = "1.0", id = "t", title = title, maturity = "draft",
    constructs = lapply(seq_along(labels), function(i) {
      list(id = paste0("c", i - 1L), label = labels[[i]], definition = "d")
    }),
    alternatives = lapply(alternatives, function(a) {
      list(id = a[[1L]], label = a[[2L]], key_constructs = as.list(a[[3L]]))
    })
  )
}

statuses <- function(ls) vapply(ls$themes, function(th) th$status, character(1))

test_that("tf_landscape reports the terms behind every match", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  ls <- tf_landscape(theory, tf_read_corpus(tf_fixture_path("panic-corpus.yaml")))
  expect_identical(names(ls), c("theory_id", "max_token_share", "field_tokens",
                                "phenomenon_tokens", "themes", "under_theorised_fronts",
                                "redundancy_risk"))
  expect_identical(ls$max_token_share, 0.5)
  expect_identical(ls$field_tokens, list())
  expect_identical(ls$phenomenon_tokens, list("disorder", "network", "panic", "theory"))
  expect_identical(names(ls$themes[[1]]), c("id", "keywords", "alternatives", "focal", "status",
                                            "focal_terms", "alternative_terms"))
  terms <- lapply(ls$themes, function(th) list(th$focal_terms, th$alternative_terms))
  expect_identical(terms, list(
    list(list(), list(list(id = "alt_cognitive", terms = list("catastrophic", "misinterpretation")))),
    list(list("arousal"), list(list(id = "alt_biological", terms = list("arousal")))),
    list(list("avoidance"), list()),
    list(list(), list())
  ))
  # One shared word is enough. A rule that wanted two left every theme of real
  # corpora under-theorised, so it was not adopted.
  expect_identical(statuses(ls), c("covered", "crowded", "covered", "under_theorised"))
})

test_that("a word of the title no longer crowds a theme", {
  # "panic disorder" on the two genetics records made theme_4 crowded through
  # "panic" and "disorder", words of the title that every account of panic
  # shares, and left the corpus with no under-theorised front.
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  for (i in 7:8) {
    corpus$records[[i]]$keywords <- c(corpus$records[[i]]$keywords, list("panic disorder"))
  }
  ls <- tf_landscape(tf_read(tf_fixture_path("panic-network.theory.yaml")), corpus)
  th4 <- ls$themes[[4]]
  expect_identical(unlist(th4$keywords), c("genetics", "heritability", "panic disorder"))
  expect_identical(list(th4$status, th4$focal, th4$alternatives),
                   list("under_theorised", FALSE, list()))
  expect_identical(list(th4$focal_terms, th4$alternative_terms), list(list(), list()))
  expect_identical(unlist(ls$under_theorised_fronts), "theme_4")
})

test_that("a construct word in the title counts as a phenomenon word", {
  ls <- tf_landscape(account("Arousal and threat", "Arousal"),
                     paired(c("arousal", "threat"), c("avoidance", "exposure")))
  expect_identical(ls$phenomenon_tokens, list("arousal", "threat"))
  expect_identical(vapply(ls$themes, function(th) th$focal, logical(1)), c(FALSE, FALSE))
  expect_identical(statuses(ls), c("under_theorised", "under_theorised"))
})

test_that("words that name a kind of account never match", {
  expect_identical(sort(.tf_THEORY_WORDS, method = "radix"), c(
    "account", "accounts", "approach", "approaches", "framework", "frameworks",
    "hypotheses", "hypothesis", "model", "models", "theories", "theory"))
  corpus <- paired(c("model fit", "structural equations"), c("updating", "working memory"))
  theory <- account("Executive control in ageing", c("Working memory capacity", "Mental model"),
                    list(list("alt_speed", "Processing-speed model", "slowing")))
  themes <- tf_landscape(theory, corpus)$themes
  # "model" made theme_1 crowded, through a construct label and a rival's label.
  expect_identical(list(themes[[1]]$status, themes[[1]]$focal, themes[[1]]$alternatives),
                   list("under_theorised", FALSE, list()))
  expect_identical(list(themes[[2]]$status, themes[[2]]$focal_terms),
                   list("covered", list("memory", "working")))
})

test_that("words most of the corpus shares are field tokens", {
  corpus <- paired(c("anxiety sensitivity", "interoception"), c("anxiety disorders", "exposure"),
                   c("genetics", "heritability"))
  theory <- account("Panic as a learned alarm", "Anxiety")
  # "anxiety" is in four of the six records, more than half.
  ls <- tf_landscape(theory, corpus)
  expect_identical(ls$field_tokens, list("anxiety"))
  expect_identical(statuses(ls), rep("under_theorised", 3L))
  # A rival's words meet the same theme tokens, so a field token matches neither.
  rival <- account("Panic as a learned alarm", character(0),
                   list(list("alt_anx", "Trait anxiety", character(0))))
  expect_identical(statuses(tf_landscape(rival, corpus)), rep("under_theorised", 3L))
  loose <- tf_landscape(theory, corpus, max_token_share = 0.7)
  expect_identical(list(loose$max_token_share, loose$field_tokens), list(0.7, list()))
  expect_identical(lapply(loose$themes, function(th) th$focal_terms),
                   list(list("anxiety"), list("anxiety"), list()))
  expect_identical(statuses(loose), c("covered", "covered", "under_theorised"))
  # A share equal to max_token_share is not more than it.
  two <- paired(c("anxiety sensitivity", "interoception"), c("anxiety disorders", "exposure"))
  expect_identical(tf_landscape(theory, two, max_token_share = 1)$field_tokens, list())
  expect_identical(tf_landscape(theory, two, max_token_share = 0)$field_tokens,
                   list("anxiety", "disorders", "exposure", "interoception", "sensitivity"))
})

test_that("alternative terms follow the alternative id order", {
  theory <- account("A theory of panic", character(0), list(
    list("alt_z", "Arousal account", character(0)),
    list("alt_a", "Interoceptive accuracy", "interoception")
  ))
  corpus <- paired(c("arousal", "interoception"), c("genetics", "heritability"))
  th1 <- tf_landscape(theory, corpus)$themes[[1]]
  expect_identical(th1$alternatives, list("alt_a", "alt_z"))
  expect_identical(th1$alternative_terms, list(list(id = "alt_a", terms = list("interoception")),
                                               list(id = "alt_z", terms = list("arousal"))))
  expect_identical(th1$status, "crowded")
})

test_that("tf_landscape refuses a max_token_share outside 0 to 1", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  corpus <- tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))
  for (bad in list(-0.1, 1.5, "0.5", TRUE, NULL, NA, NA_real_, NaN, Inf, c(0.2, 0.3), list(0.5))) {
    expect_refusal(tf_landscape(theory, corpus, max_token_share = bad),
                   "max_token_share must be a number between 0 and 1")
  }
})

test_that("tf_landscape checks min_link, then max_token_share, then the corpus", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  misspelt <- list(schema_version = "1.0", id = "c", recrods = list())
  expect_refusal(tf_landscape(theory, misspelt, min_link = 0, max_token_share = 2),
                 "min_link must be a positive integer")
  expect_refusal(tf_landscape(theory, misspelt, max_token_share = 2),
                 "max_token_share must be a number between 0 and 1")
  expect_refusal(tf_landscape(theory, misspelt), "invalid corpus: missing records list")
})

giant_theme <- function(p, n) {
  sprintf(paste("litmap: one theme holds %s per cent of the %d linked keywords; connected",
                "components cannot separate themes in a corpus this connected, so the themes",
                "and any landscape built on them are not informative"), p, n)
}

# The messages of the warnings that evaluating `expr` gives.
warnings_of <- function(expr) {
  got <- character(0)
  withCallingHandlers(expr, warning = function(w) {
    got <<- c(got, conditionMessage(w))
    invokeRestart("muffleWarning")
  })
  got
}

test_that("tf_litmap warns when one theme holds most linked keywords", {
  corpus <- paired(c("k1", "k2", "k3", "k4"), c("m1", "m2"))
  expect_identical(warnings_of(lm <- tf_litmap(corpus)), giant_theme("66.7", 6L))
  expect_identical(vapply(lm$themes, function(th) th$size, integer(1)), c(4L, 2L))
  # tf_landscape() is built on the same themes and warns alike.
  expect_identical(warnings_of(tf_landscape(account("A theory of panic"), corpus)),
                   giant_theme("66.7", 6L))
  expect_identical(warnings_of(tf_litmap(paired(c("alpha", "Zeta")))), giant_theme("100.0", 2L))
  # The text is the whole message, with no call before it, as in Python.
  w <- tryCatch(tf_litmap(corpus), warning = function(w) w)
  expect_null(conditionCall(w))
})

test_that("tf_litmap is silent when no theme holds more than half", {
  expect_silent(tf_litmap(paired(c("a1", "hub"), c("b1", "b2"))))  # two of four keywords: half
  expect_silent(tf_litmap(tf_read_corpus(tf_fixture_path("panic-corpus.yaml"))))
  expect_silent(tf_litmap(paired()))
})

four_edges <- function() {
  list(keyword_cooccurrence = list(
    list(a = "a", b = "b", count = 2L),
    list(a = "a", b = "c", count = 5L),
    list(a = "b", b = "d", count = 5L),
    list(a = "c", b = "d", count = 3L)
  ))
}

# The node and edge lines of an undirected lit diagram.
diagram_body <- function(dot) {
  lines <- strsplit(dot, "\n", fixed = TRUE)[[1L]]
  trimws(lines[startsWith(lines, '  "')])
}

test_that("diagram nodes are sorted as written and escaped after", {
  # Escaped first, 'x\\"' would sort after 'x#'. The Python suite asserts the same.
  lm <- list(co_citation = list(list(a = 'x"', b = "x#", count = 2L)))
  expect_identical(diagram_body(tf_lit_diagram(lm, "co_citation")),
                   c('"x\\"";', '"x#";', '"x\\"" -- "x#" [label="2"];'))
})

test_that("max_edges keeps the strongest edges in list order", {
  dot <- tf_lit_diagram(four_edges(), "keyword_cooccurrence", max_edges = 2)
  expect_identical(diagram_body(dot), c('"a";', '"b";', '"c";', '"d";',
                                        '"a" -- "c" [label="5"];', '"b" -- "d" [label="5"];'))
  expect_identical(
    diagram_body(tf_lit_diagram(four_edges(), "keyword_cooccurrence", max_edges = 3)),
    c('"a";', '"b";', '"c";', '"d";', '"a" -- "c" [label="5"];', '"b" -- "d" [label="5"];',
      '"c" -- "d" [label="3"];'))
  expect_identical(
    diagram_body(tf_lit_diagram(four_edges(), "keyword_cooccurrence", max_edges = 1)),
    c('"a";', '"c";', '"a" -- "c" [label="5"];'))
  lm <- tf_litmap(tf_read_corpus(tf_fixture_path("panic-corpus.yaml")))
  for (kind in c("keyword_cooccurrence", "co_citation")) {
    expect_identical(tf_lit_diagram(lm, kind, max_edges = 100), tf_lit_diagram(lm, kind))
  }
  for (bad in list(0, -1, 2.5, "2", TRUE)) {
    expect_refusal(tf_lit_diagram(four_edges(), "keyword_cooccurrence", max_edges = bad),
                   "max_edges must be a positive integer")
  }
})

test_that("tf_fetch_corpus rejects an out-of-range per_page", {
  # The guard runs before any request, so this needs no network.
  for (bad in list(0, 201, -1, "25", NA_integer_)) {
    expect_error(tf_fetch_corpus("panic", per_page = bad),
                 "per_page must be between 1 and 200", fixed = TRUE)
  }
})
