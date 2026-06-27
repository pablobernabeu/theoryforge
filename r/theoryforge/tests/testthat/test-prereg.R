# Preregistration document (API_SPEC.md section 11): byte-identical to goldens.

test_that("tf_preregister is byte-identical to the golden markdown", {
  cases <- list(
    list(fixture = "panic-network.theory.yaml", id = "panic-network-2026"),
    list(fixture = "panic-network-2026-v2.theory.yaml", id = "panic-network-2026-v2"),
    list(fixture = "weak-theory.theory.yaml", id = "weak-demo")
  )
  for (cs in cases) {
    theory <- tf_read(tf_fixture_path(cs$fixture))
    got <- tf_preregister(theory)
    golden <- tf_read_golden(tf_expected_path(paste0(cs$id, ".prereg.md")))
    expect_identical(got, golden, info = cs$id)
  }
})

test_that(".tf_fmt strips trailing zeros but keeps one decimal", {
  expect_identical(theoryforge:::.tf_fmt(1.0), "1.0")
  expect_identical(theoryforge:::.tf_fmt(0.9), "0.9")
  expect_identical(theoryforge:::.tf_fmt(0.667), "0.667")
  expect_identical(theoryforge:::.tf_fmt(0.3), "0.3")
})

test_that("tf_preregister writes the file when a path is given", {
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  p <- tempfile(fileext = ".md")
  txt <- tf_preregister(theory, p)
  raw <- readBin(p, "raw", n = file.info(p)$size)
  expect_false(any(raw == as.raw(13L)))  # LF only
  expect_identical(rawToChar(raw), txt)
})

test_that("derivation chain verified reflects the rigour item status", {
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  weak <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  expect_true(grepl("Derivation chain verified: yes", tf_preregister(panic), fixed = TRUE))
  expect_true(grepl("Derivation chain verified: no", tf_preregister(weak), fixed = TRUE))
})

test_that("a theory with no predictions emits the placeholder", {
  t <- tf_theory("nopred", "No predictions")
  out <- tf_preregister(t)
  expect_true(grepl("_No predictions specified._", out, fixed = TRUE))
})
