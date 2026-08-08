test_that("tf_read reads a YAML theory into a named list", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_type(theory, "list")
  expect_identical(theory$id, "panic-network-2026")
  expect_identical(theory$maturity, "developing")
  expect_length(theory$constructs, 3L)
})

test_that("tf_validate accepts valid fixtures", {
  expect_true(tf_validate(tf_read(tf_fixture_path("panic-network.theory.yaml"))))
  expect_true(tf_validate(tf_read(tf_fixture_path("weak-theory.theory.yaml"))))
})

test_that("tf_validate rejects missing required fields and bad enums", {
  bad <- list(schema_version = "1.0", id = "x", title = "t", maturity = "draft")
  bad$maturity <- "nonsense"
  expect_error(tf_validate(bad), "maturity must be one of")

  missing <- list(schema_version = "1.0", title = "t", maturity = "draft")
  expect_error(tf_validate(missing), "missing/empty required field: id")
})

test_that("tf_write round-trips YAML and JSON", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))

  y <- tempfile(fileext = ".yaml")
  tf_write(theory, y)
  back_y <- tf_read(y)
  expect_identical(back_y$id, theory$id)
  expect_identical(back_y$maturity, theory$maturity)
  expect_length(back_y$constructs, length(theory$constructs))
  expect_true(tf_validate(back_y))

  j <- tempfile(fileext = ".json")
  tf_write(theory, j)
  back_j <- tf_read(j)
  expect_identical(back_j$id, theory$id)
  expect_length(back_j$predictions, length(theory$predictions))
  expect_true(tf_validate(back_j))
})

test_that("written files use LF line endings only", {
  theory <- tf_read(tf_fixture_path("weak-theory.theory.yaml"))
  no_cr <- function(path) {
    raw <- readBin(path, "raw", n = file.info(path)$size)
    !any(raw == as.raw(13L))
  }

  y <- tempfile(fileext = ".yaml")
  tf_write(theory, y)
  expect_true(no_cr(y))

  j <- tempfile(fileext = ".json")
  tf_write(theory, j)
  expect_true(no_cr(j))

  # Every writer goes through .tf_write_lf, so the prereg and report paths are
  # covered by the same guarantee.
  md <- tempfile(fileext = ".md")
  tf_preregister(theory, md)
  expect_true(no_cr(md))

  qmd <- tf_render_report(theory, tempfile(fileext = ".qmd"))
  expect_true(no_cr(qmd))
})

test_that("the writer re-encodes to UTF-8 rather than passing bytes through", {
  # tf_write used charToRaw() without enc2utf8(), unlike its two sibling
  # writers, so on a non-UTF-8 locale it emitted native-encoding bytes that
  # tf_read (reading UTF-8) would then mis-decode. A latin1-marked string
  # exercises that on any locale: U+00E9 is one byte in latin1, two in UTF-8.
  latin1 <- "\xe9"
  Encoding(latin1) <- "latin1"
  path <- tempfile()
  theoryforge:::.tf_write_lf(path, latin1)
  expect_identical(readBin(path, "raw", n = 10L), as.raw(c(0xc3, 0xa9)))
})

test_that("tf_write round-trips accented text through UTF-8", {
  accented <- "Th\u00e9orie d\u00e9velopp\u00e9e"
  theory <- tf_theory("demo-accents", accented)
  y <- tempfile(fileext = ".yaml")
  tf_write(theory, y)
  raw <- readBin(y, "raw", n = file.info(y)$size)
  # U+00E9 is 0xC3 0xA9 in UTF-8 and a single byte in any Latin-1 codepage.
  # The literal is written with escapes so this file stays pure ASCII.
  expect_true(length(grepRaw(as.raw(c(0xc3, 0xa9)), raw, fixed = TRUE)) > 0L)
  expect_identical(tf_read(y)$title, accented)
})

test_that("packaged examples are reachable and match the repository copies", {
  # The Python twin ships the same files and reaches them with example_path();
  # scripts/gen_golden.py writes both copies, and CI fails on any difference.
  names <- tf_example_names()
  expect_true("panic-network.theory.yaml" %in% names)
  for (name in names) {
    packaged <- tf_example_path(name)
    expect_identical(tf_read_golden(packaged),
                     tf_read_golden(tf_fixture_path(name)), info = name)
  }
  expect_identical(tf_read(tf_example_path("panic-network.theory.yaml"))$id,
                   "panic-network-2026")
})

test_that("tf_example_path rejects an unknown name", {
  expect_error(tf_example_path("no-such-theory.yaml"), "no packaged example")
})
