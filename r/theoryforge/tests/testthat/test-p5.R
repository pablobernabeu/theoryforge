# P5: causal-structure implications, structured version diff, archive bundle.

test_that("tf_implications flags the panic network's feedback loop", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  imp <- tf_implications(theory)
  expect_false(imp$acyclic)
  expect_length(imp$order, 0L)
  expect_length(imp$implications, 0L)
  expect_equal(imp$n_implications, 0L)
  expect_equal(imp$feedback_loops,
               list(list("c_arousal", "c_perceived_threat")))
  expect_length(imp$exogenous, 0L)
  expect_setequal(unlist(imp$endogenous), unlist(imp$constructs))
})

test_that("tf_implications derives the mediation independence on an acyclic chain", {
  theory <- tf_read(tf_fixture_path("mediation-demo.theory.yaml"))
  imp <- tf_implications(theory)
  expect_true(imp$acyclic)
  expect_equal(unlist(imp$order), c("m_stressor", "m_appraisal", "m_anxiety"))
  expect_equal(unlist(imp$exogenous), "m_stressor")
  expect_length(imp$feedback_loops, 0L)
  expect_equal(imp$implications,
               list(list(a = "m_anxiety", b = "m_stressor", given = list("m_appraisal"))))
  expect_equal(imp$n_implications, 1L)
})

test_that("tf_implications ignores non-causal relations", {
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  imp <- tf_implications(theory)
  expect_equal(unlist(imp$exogenous), c("k_motivation", "k_drive"))
  expect_equal(imp$implications,
               list(list(a = "k_motivation", b = "k_drive", given = list())))
})

test_that("tf_implications treats a self-loop as a cycle", {
  theory <- tf_theory("t", "T") |>
    tf_add_construct("a", "A", "a.") |>
    tf_add_proposition("p1", "a", "a", "increases")
  imp <- tf_implications(theory)
  expect_false(imp$acyclic)
  expect_equal(imp$feedback_loops, list(list("a")))
})

test_that("tf_implications matches the Python goldens semantically", {
  fixtures <- list.files(tf_fixtures_dir(), pattern = "\\.theory\\.yaml$", full.names = TRUE)
  expect_gt(length(fixtures), 0L)
  for (fx in fixtures) {
    theory <- tf_read(fx)
    golden <- jsonlite::fromJSON(tf_expected_path(paste0(theory$id, ".implications.json")),
                                 simplifyVector = FALSE)
    got <- jsonlite::fromJSON(
      jsonlite::toJSON(tf_implications(theory), auto_unbox = TRUE),
      simplifyVector = FALSE)
    expect_equal(got, golden, info = fx)
  }
})

test_that("tf_diff reports the amended pair's editorial record and matches the golden", {
  v1 <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  v2 <- tf_read(tf_fixture_path("panic-network-2026-v2.theory.yaml"))
  d <- tf_diff(v2, v1)
  expect_equal(d$prior_id, "panic-network-2026")
  expect_equal(d$new_id, "panic-network-2026-v2")
  expect_equal(unlist(d$changed_fields), "maturity")
  expect_equal(unlist(d$predictions$added), "pred4")
  expect_equal(d$summary$n_added, 1L)
  golden <- jsonlite::fromJSON(tf_expected_path("panic-network-2026-v2.diff.json"),
                               simplifyVector = FALSE)
  got <- jsonlite::fromJSON(jsonlite::toJSON(d, auto_unbox = TRUE), simplifyVector = FALSE)
  expect_equal(got, golden)
})

test_that("tf_diff on identical theories reports nothing", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  d <- tf_diff(theory, theory)
  expect_length(d$changed_fields, 0L)
  expect_equal(d$summary, list(n_added = 0L, n_removed = 0L, n_modified = 0L))
  for (coll in c("constructs", "propositions", "predictions",
                 "auxiliary_assumptions", "alternatives")) {
    expect_length(d[[coll]]$added, 0L)
    expect_length(d[[coll]]$removed, 0L)
    expect_length(d[[coll]]$modified, 0L)
  }
})

test_that("tf_diff detects added, removed, and modified elements", {
  prior <- tf_theory("t", "T") |>
    tf_add_construct("a", "A", "a.") |>
    tf_add_construct("b", "B", "b.")
  new <- tf_theory("t", "T") |>
    tf_add_construct("a", "A", "a (refined).") |>
    tf_add_construct("c", "C", "c.")
  d <- tf_diff(new, prior)
  expect_equal(unlist(d$constructs$added), "c")
  expect_equal(unlist(d$constructs$removed), "b")
  expect_equal(unlist(d$constructs$modified), "a")
})

test_that("the canonical serialisation treats a singleton as its scalar", {
  expect_identical(.tf_canon(list("p1")), .tf_canon("p1"))
  expect_identical(.tf_canon(TRUE), "true")
  expect_identical(.tf_canon(0.5), "0.5")
  expect_identical(.tf_canon(2), "2")
})

test_that("tf_fair_export renders the bundle and matches the golden byte-for-byte", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  files <- tf_fair_export(theory, authors = "Doe, Jane")
  expect_named(files, c("README.md", "CITATION.cff", "metadata.json", "dossier.md"))
  expect_match(files[["README.md"]], "^# Network theory of panic disorder\n")
  expect_match(files[["CITATION.cff"]], "authors:\n  - name: Doe, Jane", fixed = TRUE)
  expect_identical(files[["dossier.md"]], tf_dossier(theory))
  meta <- jsonlite::fromJSON(files[["metadata.json"]], simplifyVector = FALSE)
  expect_equal(meta$upload_type, "dataset")
  expect_equal(unlist(meta$keywords),
               c("scientific-theory", "theoryforge", "panic-network-2026"))
  ids <- vapply(meta$related_identifiers, function(r) r$identifier, character(1))
  expect_setequal(ids, c("10.1016/j.brat.2015.10.002",
                         "10.1016/0005-7967(86)90011-2",
                         "10.1176/ajp.146.2.148"))
  golden <- jsonlite::fromJSON(tf_expected_path("panic-network-2026.fair.json"),
                               simplifyVector = FALSE)
  for (name in names(golden)) {
    expect_identical(files[[name]], golden[[name]], info = name)
  }
})

test_that("tf_fair_export defaults cover the empty cases", {
  theory <- tf_theory("demo-x", "A demo")
  files <- tf_fair_export(theory)
  expect_match(files[["CITATION.cff"]], "authors: []", fixed = TRUE)
  expect_match(files[["README.md"]], "- Version: unversioned", fixed = TRUE)
  meta <- jsonlite::fromJSON(files[["metadata.json"]], simplifyVector = FALSE)
  expect_length(meta$creators, 0L)
  expect_length(meta$related_identifiers, 0L)
})

test_that("tf_fair_export writes the bundle plus theory.yaml when a path is given", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- file.path(tempdir(), "tf-fair-bundle")
  on.exit(unlink(out, recursive = TRUE), add = TRUE)
  files <- tf_fair_export(theory, path = out, authors = "Doe, Jane")
  for (name in names(files)) {
    expect_identical(tf_read_golden(file.path(out, name)), files[[name]])
  }
  reread <- tf_read(file.path(out, "theory.yaml"))
  expect_equal(reread$id, theory$id)
})
