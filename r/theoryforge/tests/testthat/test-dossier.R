# Audit dossier (API_SPEC.md section 20): byte-identical to goldens.

test_that("tf_dossier includes the expected header, table row, and prereg", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- tf_dossier(panic)
  expect_true(grepl("# theoryforge dossier: Network theory of panic disorder",
                    out, fixed = TRUE))
  expect_true(grepl("- Aggregate rigour score: 84.8/100", out, fixed = TRUE))
  expect_true(grepl("| falsifiability | pass | 1.0 | 0.15 |", out, fixed = TRUE))
  expect_true(grepl("## Preregistration", out, fixed = TRUE))
  expect_true(grepl("# Preregistration: Network theory of panic disorder",
                    out, fixed = TRUE))
})

test_that("tf_dossier emits the table header and one row per checklist item", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- tf_dossier(panic)
  expect_true(grepl("| item | status | score | weight |", out, fixed = TRUE))
  expect_true(grepl("| --- | --- | --- | --- |", out, fixed = TRUE))
  rep <- tf_check(panic)
  for (it in rep$items) {
    row <- sprintf("| %s | %s | %s | %s |",
                   it$id, it$status,
                   theoryforge:::.tf_fmt(it$score),
                   theoryforge:::.tf_fmt(it$weight))
    expect_true(grepl(row, out, fixed = TRUE), info = it$id)
  }
})

test_that("tf_dossier reflects severity and provenance placeholders", {
  weak <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  out <- tf_dossier(weak)
  expect_true(grepl("- w1: severity 0.1, risk 0.1", out, fixed = TRUE))
  expect_true(grepl("_No provenance recorded._", out, fixed = TRUE))
  expect_true(grepl("Gate: blocked", out, fixed = TRUE))
})

test_that("tf_dossier names the rubric for what it is", {
  # Once in the dossier's own severity list and once in the preregistration
  # appended to it.
  out <- tf_dossier(tf_read(tf_fixture_path("panic-network.theory.yaml")))
  heading <- "\n## Severity (pre-data rubric of claim form)\n"
  expect_identical(lengths(regmatches(out, gregexpr(heading, out, fixed = TRUE))), 2L)
  expect_false(grepl("\n## Severity\n", out, fixed = TRUE))
  expect_true(grepl("- pred1: severity 1.0, risk 0.9\n", out, fixed = TRUE))
})

test_that("tf_dossier output ends with a single trailing newline (LF)", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  out <- tf_dossier(panic)
  expect_false(grepl("\r", out, fixed = TRUE))
  expect_true(endsWith(out, "\n"))
  expect_false(endsWith(out, "\n\n"))
})

test_that("tf_dossier is byte-identical to the golden markdown files", {
  cases <- list(
    list(fixture = "panic-network.theory.yaml", id = "panic-network-2026"),
    list(fixture = "panic-network-2026-v2.theory.yaml", id = "panic-network-2026-v2"),
    list(fixture = "weak-theory.theory.yaml", id = "weak-demo")
  )
  for (cs in cases) {
    theory <- tf_read(tf_fixture_path(cs$fixture))
    got <- tf_dossier(theory)
    golden <- tf_read_golden(tf_expected_path(paste0(cs$id, ".dossier.md")))
    expect_identical(got, golden, info = cs$id)
  }
})
