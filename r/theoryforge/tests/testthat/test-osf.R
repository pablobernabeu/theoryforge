test_that("tf_osf_push dry-run returns the planned PUT request and default filename", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  res <- tf_osf_push(theory)
  expect_true(res$dry_run)
  expect_identical(res$request$method, "PUT")
  expect_identical(res$request$filename, "panic-network-2026.dossier.md")
  # no node -> url is NULL.
  expect_null(res$request$url)
  # content_bytes is the UTF-8 byte length of the dossier.
  expected_bytes <- length(charToRaw(enc2utf8(tf_dossier(theory))))
  expect_equal(res$request$content_bytes, expected_bytes)
  expect_true(is.character(res$note) && nzchar(res$note))
})

test_that("tf_osf_push builds the OSF storage URL when a node is given", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  res <- tf_osf_push(theory, node = "abc12")
  expect_identical(
    res$request$url,
    paste0("https://files.osf.io/v1/resources/abc12/providers/osfstorage/",
           "?kind=file&name=panic-network-2026.dossier.md")
  )
})

test_that("tf_osf_push honours a custom filename", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  res <- tf_osf_push(theory, node = "abc12", filename = "custom.md")
  expect_identical(res$request$filename, "custom.md")
  expect_match(res$request$url, "name=custom.md", fixed = TRUE)
})

test_that("tf_osf_push percent-encodes the filename in the upload URL", {
  # Mirrors the Python osf_push test so the dry-run request dicts stay
  # parity-identical for filenames with reserved characters.
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  res <- tf_osf_push(theory, node = "abc12", filename = "my theory&notes.md")
  expect_match(res$request$url, "name=my%20theory%26notes.md", fixed = TRUE)
  expect_identical(res$request$filename, "my theory&notes.md")
})

test_that("tf_osf_push live mode requires both token and node", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  expect_error(tf_osf_push(theory, dry_run = FALSE), "token.+node")
  expect_error(tf_osf_push(theory, token = "t", dry_run = FALSE), "token.+node")
  expect_error(tf_osf_push(theory, node = "n", dry_run = FALSE), "token.+node")
})
