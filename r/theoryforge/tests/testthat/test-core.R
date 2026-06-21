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
  y <- tempfile(fileext = ".yaml")
  tf_write(theory, y)
  raw <- readBin(y, "raw", n = file.info(y)$size)
  expect_false(any(raw == as.raw(13L)))  # no CR bytes
})
