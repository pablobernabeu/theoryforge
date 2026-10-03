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

test_that("tf_osf_push filename falls back to theory when the id is null or empty", {
  # Mirrors the Python osf_push test: a null id must not stringify into the
  # filename, and an empty one must not produce '.dossier.md'.
  for (theory in list(list(id = NULL, title = "T"), list(id = "", title = "T"),
                      list(title = "T"))) {
    res <- tf_osf_push(theory)
    expect_identical(res$request$filename, "theory.dossier.md")
  }
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
  expect_error(tf_osf_push(theory, token = "t", node = "", dry_run = FALSE), "token.+node")
})

# The dry-run request is the contract the Python twin's tests pin too
# (test_osf_report.py), so these expectations are written out in full.
osf_base <- "https://files.osf.io/v1/resources/"

test_that("tf_osf_push dry run treats an empty node or filename as absent, as Python does", {
  theory <- tf_theory("t", "T")
  expect_null(tf_osf_push(theory, node = "")$request$url)
  expect_identical(tf_osf_push(theory, filename = "")$request$filename, "t.dossier.md")
})

test_that("tf_osf_push encodes a filename that already holds a percent sequence", {
  # URLencode(repeated = FALSE) returned any string containing %XX unchanged,
  # spaces, '&' and '#' included, so the request URL was malformed.
  theory <- tf_theory("t", "T")
  res <- tf_osf_push(theory, node = "abc12", filename = "dossier%20v2.md")
  expect_identical(
    res$request$url,
    paste0(osf_base, "abc12/providers/osfstorage/?kind=file&name=dossier%2520v2.md")
  )
  res <- tf_osf_push(theory, node = "abc12", filename = "a b&c%41#.md")
  expect_identical(
    res$request$url,
    paste0(osf_base, "abc12/providers/osfstorage/?kind=file&name=a%20b%26c%2541%23.md")
  )
})

test_that("the overwrite dry run lists the folder lookup that precedes the PUT", {
  theory <- tf_theory("t", "T")
  res <- tf_osf_push(theory, node = "abc12", overwrite = TRUE)
  expect_identical(names(res), c("dry_run", "request", "lookup", "note"))
  expect_identical(res$lookup,
                   list(method = "GET", url = paste0(osf_base, "abc12/providers/osfstorage/")))
  expect_identical(res$request$url,
                   paste0(osf_base, "abc12/providers/osfstorage/?kind=file&name=t.dossier.md"))
  expect_match(res$note, "upload link", fixed = TRUE)
  expect_null(tf_osf_push(theory, overwrite = TRUE)$lookup$url)
  # Without overwrite the dry run keeps its 0.6.0 shape.
  expect_identical(names(tf_osf_push(theory, node = "abc12")),
                   c("dry_run", "request", "note"))
})

test_that("tf_osf_push refuses an overwrite that is not TRUE or FALSE", {
  theory <- tf_theory("t", "T")
  for (bad in list(NA, "yes", c(TRUE, FALSE), 1)) {
    expect_error(tf_osf_push(theory, overwrite = bad),
                 "overwrite must be TRUE or FALSE", fixed = TRUE)
  }
})

# A stand-in for .tf_http(), the transport the OSF deposit shares with
# tf_fetch_corpus(): it answers each request with the next queued response and
# records what was sent.
osf_mock <- function(...) {
  state <- new.env()
  state$queue <- list(...)
  state$calls <- list()
  state$fn <- function(method, url, headers = NULL, body = NULL, timeout = 30) {
    state$calls[[length(state$calls) + 1L]] <- list(method = method, url = url,
                                                    headers = headers, body = body)
    reply <- state$queue[[1L]]
    state$queue <- state$queue[-1L]
    reply
  }
  state
}

test_that("a live push stops when OSF answers 409, and says how to add a version", {
  mock <- osf_mock(list(status = 409L, body = '{"message": "Conflict"}'))
  local_mocked_bindings(.tf_http = mock$fn)
  expect_error(
    tf_osf_push(tf_theory("t", "T"), token = "secret", node = "abc12", dry_run = FALSE),
    paste0("OSF upload failed with HTTP 409; a file of that name already exists in this ",
           "project: pass a different filename, or overwrite = TRUE to add a new version"),
    fixed = TRUE
  )
  expect_length(mock$calls, 1L)
  expect_identical(mock$calls[[1L]]$method, "PUT")
})

test_that("a live push stops on any status outside 2xx, a 501 included", {
  for (code in c(401L, 403L, 404L, 500L, 501L)) {
    mock <- osf_mock(list(status = code, body = ""))
    local_mocked_bindings(.tf_http = mock$fn)
    err <- tryCatch(
      tf_osf_push(tf_theory("t", "T"), token = "secret", node = "abc12", dry_run = FALSE),
      error = function(e) conditionMessage(e)
    )
    expect_identical(err, sprintf("OSF upload failed with HTTP %d", code))
  }
})

test_that("a live push that OSF accepts returns the upload record", {
  mock <- osf_mock(list(status = 201L, body = "{}"))
  local_mocked_bindings(.tf_http = mock$fn)
  theory <- tf_theory("t", "T")
  res <- tf_osf_push(theory, token = "secret", node = "abc12", dry_run = FALSE)
  expect_identical(res, list(dry_run = FALSE, status = 201L, filename = "t.dossier.md"))
  call <- mock$calls[[1L]]
  expect_identical(call$url,
                   paste0(osf_base, "abc12/providers/osfstorage/?kind=file&name=t.dossier.md"))
  expect_identical(call$headers,
                   c(Authorization = "Bearer secret", `Content-Type` = "text/markdown"))
  expect_identical(call$body, tf_dossier(theory))
})

osf_listing <- paste0(
  '{"data": [',
  '{"type": "files", "attributes": {"kind": "folder", "name": "t.dossier.md"},',
  ' "links": {"upload": "https://files.example/folder"}},',
  '{"type": "files", "attributes": {"kind": "file", "name": "other.md"},',
  ' "links": {"upload": "https://files.example/other"}},',
  '{"type": "files", "attributes": {"kind": "file", "name": "t.dossier.md"},',
  ' "links": {"upload": "https://files.example/v1/resources/abc12/providers/osfstorage/f1"}}',
  ']}'
)

test_that("overwrite = TRUE puts a new version to the existing file's upload link", {
  mock <- osf_mock(list(status = 200L, body = osf_listing), list(status = 200L, body = "{}"))
  local_mocked_bindings(.tf_http = mock$fn)
  res <- tf_osf_push(tf_theory("t", "T"), token = "secret", node = "abc12",
                     dry_run = FALSE, overwrite = TRUE)
  expect_identical(res$status, 200L)
  expect_length(mock$calls, 2L)
  expect_identical(mock$calls[[1L]][c("method", "url", "headers")],
                   list(method = "GET", url = paste0(osf_base, "abc12/providers/osfstorage/"),
                        headers = c(Authorization = "Bearer secret")))
  expect_null(mock$calls[[1L]]$body)
  expect_identical(mock$calls[[2L]]$method, "PUT")
  expect_identical(mock$calls[[2L]]$url,
                   "https://files.example/v1/resources/abc12/providers/osfstorage/f1?kind=file")
})

test_that("overwrite = TRUE creates the file when the folder has none of that name", {
  mock <- osf_mock(list(status = 200L, body = '{"data": []}'), list(status = 201L, body = "{}"))
  local_mocked_bindings(.tf_http = mock$fn)
  res <- tf_osf_push(tf_theory("t", "T"), token = "secret", node = "abc12",
                     dry_run = FALSE, overwrite = TRUE)
  expect_identical(res$status, 201L)
  expect_identical(mock$calls[[2L]]$url,
                   paste0(osf_base, "abc12/providers/osfstorage/?kind=file&name=t.dossier.md"))
})

test_that("overwrite = TRUE stops when the folder listing fails or cannot be read", {
  mock <- osf_mock(list(status = 403L, body = ""))
  local_mocked_bindings(.tf_http = mock$fn)
  expect_error(tf_osf_push(tf_theory("t", "T"), token = "secret", node = "abc12",
                           dry_run = FALSE, overwrite = TRUE),
               "OSF folder listing failed with HTTP 403", fixed = TRUE)
  expect_length(mock$calls, 1L)
  # '{"dataset": []}' guards against `$` matching a prefix of another field.
  for (body in c("<html>", '{"data": 1}', "[]", '{"dataset": []}')) {
    mock <- osf_mock(list(status = 200L, body = body))
    local_mocked_bindings(.tf_http = mock$fn)
    expect_error(tf_osf_push(tf_theory("t", "T"), token = "secret", node = "abc12",
                             dry_run = FALSE, overwrite = TRUE),
                 "OSF folder listing could not be read", fixed = TRUE)
  }
  bare <- '{"data": [{"attributes": {"kind": "file", "name": "t.dossier.md"}, "links": {}}]}'
  mock <- osf_mock(list(status = 200L, body = bare))
  local_mocked_bindings(.tf_http = mock$fn)
  expect_error(tf_osf_push(tf_theory("t", "T"), token = "secret", node = "abc12",
                           dry_run = FALSE, overwrite = TRUE),
               "OSF lists t.dossier.md without an upload link", fixed = TRUE)
})
