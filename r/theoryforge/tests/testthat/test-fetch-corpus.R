# tf_fetch_corpus() against a stand-in transport: errors, the API key,
# provenance and paging (API_SPEC.md section 17). No test here reaches the
# network. Each one replaces .tf_http(), through which the adapter sends every
# request, or calls a helper directly. The Python suite's test_fetch_corpus.py
# asserts the same messages and the same corpus.

# The message of the error `expr` raises, or NULL when it raises none.
refusal <- function(expr) {
  tryCatch({
    expr
    NULL
  }, error = function(e) conditionMessage(e))
}

rate_limit_message <- paste(
  "Anonymous search is temporarily rate-limited while the search cluster is",
  "under elevated load. Please retry in 38s, or use a free API key for",
  "uninterrupted access: https://openalex.org/rest-api."
)
rate_limit_body <- as.character(jsonlite::toJSON(
  list(error = "Rate limit exceeded", message = rate_limit_message, retryAfter = 38),
  auto_unbox = TRUE
))

key_message <- "api_key must be a string of visible ASCII characters"

as_json <- function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE, null = "null"))

# A stand-in for .tf_http() that answers each request with
# `answer(url, headers)`, a list(status, body), and keeps what it was sent.
fake_openalex <- function(answer) {
  fake <- new.env()
  fake$sent <- list()
  fake$http <- function(method, url, headers = NULL, body = NULL, timeout = 30) {
    fake$sent[[length(fake$sent) + 1L]] <- list(method = method, url = url, headers = headers)
    answer(url, headers)
  }
  fake
}

query_param <- function(url, name) {
  pairs <- strsplit(sub("^[^?]*\\?", "", url), "&", fixed = TRUE)[[1L]]
  hit <- pairs[startsWith(pairs, paste0(name, "="))]
  if (length(hit) == 0L) NULL else utils::URLdecode(sub("^[^=]*=", "", hit[[1L]]))
}

openalex_work <- function(i) {
  list(
    id = sprintf("https://openalex.org/W%d", i),
    doi = if (i == 3L) NULL else sprintf("https://doi.org/10.1/w%d", i),
    title = sprintf("t%d", i),
    publication_year = 2020L + i,
    keywords = list(list(display_name = "panic", score = 0.9),
                    list(display_name = sprintf("k%d", i), score = 0.5)),
    referenced_works = list(sprintf("https://openalex.org/R%d", i))
  )
}

# Five works over cursor pages of two: the last page holds one work, and the
# cursor after it gives an empty page with no further cursor, as OpenAlex does.
openalex_pages <- list("*" = list(ids = 1:2, nxt = "c2"), c2 = list(ids = 3:4, nxt = "c3"),
                       c3 = list(ids = 5L, nxt = "c4"), c4 = list(ids = integer(0), nxt = NULL))

paged_answer <- function(url, headers) {
  page <- openalex_pages[[query_param(url, "cursor")]]
  list(status = 200L, body = as_json(list(
    meta = list(count = 5L, per_page = 2L, next_cursor = page$nxt),
    results = lapply(page$ids, openalex_work)
  )))
}

# OPENALEX_API_KEY as it was, to restore after a test that sets or unsets it.
restore_env_key <- function(old) {
  if (is.na(old)) Sys.unsetenv("OPENALEX_API_KEY") else Sys.setenv(OPENALEX_API_KEY = old)
}

test_that(".tf_http_check passes a success and stops with the status and OpenAlex's message", {
  expect_null(refusal(.tf_http_check(200L, rate_limit_body)))
  expect_null(refusal(.tf_http_check(399L, "")))
  expect_identical(refusal(.tf_http_check(429L, rate_limit_body)),
                   paste0("OpenAlex request failed with HTTP 429: ", rate_limit_message))
  expect_identical(refusal(.tf_http_check(403L, '{"error": "Forbidden"}')),
                   "OpenAlex request failed with HTTP 403: Forbidden")
  expect_identical(refusal(.tf_http_check(404L, '{"message": " ", "error": "Not found"}')),
                   "OpenAlex request failed with HTTP 404: Not found")
  # A body that base R's url() could not read is NULL: the status alone.
  expect_identical(refusal(.tf_http_check(429L, NULL)), "OpenAlex request failed with HTTP 429")
  expect_identical(refusal(.tf_http_check(429, NULL)), "OpenAlex request failed with HTTP 429")
})

test_that("only a JSON message or error adds a suffix to the status", {
  for (body in list("<html><body>Internal Server Error</body></html>", '"a JSON string"',
                    '{"message": ["not", "text"]}', "")) {
    expect_identical(refusal(.tf_http_check(500L, body)), "OpenAlex request failed with HTTP 500")
  }
  # jsonlite::fromJSON() reads a file or downloads a URL that a body names, so
  # a body holding a path must be parsed as text and found not to be JSON.
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeLines('{"message": "read from a file"}', path)
  expect_identical(refusal(.tf_http_check(500L, path)), "OpenAlex request failed with HTTP 500")
})

test_that("base R's url() failures are reported without the URL", {
  url <- "https://api.openalex.org/works?search=panic&cursor=%2A"
  expect_identical(
    .tf_url_failure(paste0("cannot open URL '", url, "': HTTP status was '429 Unknown Error'")),
    list(status = 429L, body = NULL)
  )
  expect_identical(
    refusal(.tf_url_failure(paste0("URL '", url, "': status was 'Could not connect to server'"))),
    "cannot open the connection: Could not connect to server"
  )
  # Older libcurl writes "Couldn't", whose apostrophe must not end the reason.
  expect_identical(
    refusal(.tf_url_failure(paste0("URL '", url, "': status was 'Couldn't resolve host name'"))),
    "cannot open the connection: Couldn't resolve host name"
  )
  expect_identical(refusal(.tf_url_failure(character(0))), "cannot open the connection")
})

test_that(".tf_http reads a body with base R's url() when curl is missing", {
  local_mocked_bindings(.tf_has_curl = function() FALSE)
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw(enc2utf8('{"results": [], "note": "naïve"}')), path)
  url <- paste0("file:///", sub("^/", "", normalizePath(path, winslash = "/")))
  timeout <- getOption("timeout")
  res <- .tf_http("GET", url, headers = c(Authorization = "Bearer k"))
  expect_identical(res$status, 200L)
  expect_identical(res$body, enc2utf8('{"results": [], "note": "naïve"}'))
  expect_identical(getOption("timeout"), timeout)
  # A connection that cannot be opened is reported without its URL.
  missing <- paste0(url, ".missing")
  msg <- refusal(suppressWarnings(.tf_http("GET", missing)))
  expect_identical(substr(msg, 1L, 26L), "cannot open the connection")
  expect_false(grepl("missing", msg, fixed = TRUE))
  expect_identical(refusal(.tf_http("PUT", url, body = "x")),
                   "an HTTP PUT request needs the curl package")
})

test_that(".tf_http reads a body with curl", {
  skip_if_not_installed("curl")
  path <- tempfile(fileext = ".json")
  on.exit(unlink(path), add = TRUE)
  writeBin(charToRaw(enc2utf8('{"results": []}')), path)
  url <- paste0("file:///", sub("^/", "", normalizePath(path, winslash = "/")))
  res <- .tf_http("GET", url, headers = c(Authorization = "Bearer k"))
  expect_identical(res$body, '{"results": []}')
  expect_true(res$status < 400L)
})

test_that("tf_fetch_corpus stops when OpenAlex refuses a request", {
  fake <- fake_openalex(function(url, headers) list(status = 429L, body = rate_limit_body))
  local_mocked_bindings(.tf_http = fake$http)
  msg <- refusal(tf_fetch_corpus("panic disorder", mailto = "me@example.org"))
  expect_identical(msg, paste0("OpenAlex request failed with HTTP 429: ", rate_limit_message))
  expect_false(grepl("api.openalex.org", msg, fixed = TRUE))
  expect_false(grepl("me@example.org", msg, fixed = TRUE))

  fake <- fake_openalex(function(url, headers) {
    list(status = 500L, body = "<html><body>Internal Server Error</body></html>")
  })
  local_mocked_bindings(.tf_http = fake$http)
  expect_identical(refusal(tf_fetch_corpus("panic disorder")),
                   "OpenAlex request failed with HTTP 500")
})

test_that("a response without a results list is refused and an empty one is a corpus", {
  for (body in list('{"meta": {"count": 0}, "error": "weird"}', '{"results": {}}',
                    '{"results": null}', '{"results": "W1"}', "[]",
                    "<html><body>maintenance</body></html>", "")) {
    fake <- fake_openalex(function(url, headers) list(status = 200L, body = body))
    local_mocked_bindings(.tf_http = fake$http)
    expect_identical(refusal(tf_fetch_corpus("panic disorder")),
                     "OpenAlex response has no results list")
  }
  fake <- fake_openalex(function(url, headers) {
    list(status = 200L, body = '{"meta": {"count": 0, "next_cursor": null}, "results": []}')
  })
  local_mocked_bindings(.tf_http = fake$http)
  corpus <- tf_fetch_corpus("nothing matches", max_records = 50)
  expect_identical(corpus$records, list())
  expect_identical(corpus$source$total_count, 0L)
  expect_identical(corpus$source$n_records, 0L)
  expect_length(fake$sent, 1L)
})

test_that("the default is one request of per_page works", {
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  corpus <- tf_fetch_corpus("panic", per_page = 2, mailto = "me@example.org")
  expect_length(fake$sent, 1L)
  expect_identical(vapply(corpus$records, function(r) r$id, ""),
                   c("https://openalex.org/W1", "https://openalex.org/W2"))
  url <- fake$sent[[1L]]$url
  expect_identical(fake$sent[[1L]]$method, "GET")
  expect_true(startsWith(url, "https://api.openalex.org/works?"))
  expect_identical(query_param(url, "search"), "panic")
  expect_identical(query_param(url, "per-page"), "2")
  expect_identical(query_param(url, "mailto"), "me@example.org")
  expect_identical(query_param(url, "cursor"), "*")
})

test_that("cursor paging stops once max_records are collected", {
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  corpus <- tf_fetch_corpus("panic", per_page = 2, max_records = 3)
  # Two pages give four works, cut to three.
  expect_identical(vapply(corpus$records, function(r) r$id, ""),
                   sprintf("https://openalex.org/W%d", 1:3))
  expect_identical(vapply(fake$sent, function(s) query_param(s$url, "cursor"), ""), c("*", "c2"))
  expect_identical(vapply(fake$sent, function(s) query_param(s$url, "per-page"), ""), c("2", "2"))

  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  expect_length(tf_fetch_corpus("panic", per_page = 2, max_records = 5)$records, 5L)
  expect_length(fake$sent, 3L)
})

test_that("cursor paging stops at an empty page or without a cursor", {
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  corpus <- tf_fetch_corpus("panic", per_page = 2, max_records = 50)
  expect_identical(vapply(corpus$records, function(r) r$id, ""),
                   sprintf("https://openalex.org/W%d", 1:5))
  expect_identical(vapply(fake$sent, function(s) query_param(s$url, "cursor"), ""),
                   c("*", "c2", "c3", "c4"))

  # A page that gives no next cursor ends the run, whatever max_records asks for.
  fake <- fake_openalex(function(url, headers) {
    list(status = 200L, body = as_json(list(meta = list(count = 9L), results = list(openalex_work(1L)))))
  })
  local_mocked_bindings(.tf_http = fake$http)
  expect_length(tf_fetch_corpus("panic", per_page = 2, max_records = 50)$records, 1L)
  expect_length(fake$sent, 1L)
})

test_that("the corpus records where and when it was fetched", {
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  corpus <- tf_fetch_corpus("panic", per_page = 2, max_records = 3)
  expect_identical(names(corpus), c("schema_version", "id", "source", "records"))
  expect_identical(corpus$schema_version, "1.0")
  expect_identical(corpus$id, "openalex:panic")
  source <- corpus$source
  expect_identical(names(source), c("service", "endpoint", "query", "retrieved", "total_count",
                                    "n_records", "per_page", "sort"))
  expect_identical(source[names(source) != "retrieved"], list(
    service = "OpenAlex",
    endpoint = "https://api.openalex.org/works",
    query = "panic",
    total_count = 5L,
    n_records = 3L,
    per_page = 2L,
    sort = "relevance_score:desc"
  ))
  expect_match(source$retrieved, "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")

  # A missing count is recorded as null.
  fake <- fake_openalex(function(url, headers) {
    list(status = 200L, body = as_json(list(results = list(openalex_work(1L)))))
  })
  local_mocked_bindings(.tf_http = fake$http)
  corpus <- tf_fetch_corpus("panic")
  expect_true("total_count" %in% names(corpus$source))
  expect_null(corpus$source$total_count)
})

test_that("each record keeps its DOI as returned", {
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  records <- tf_fetch_corpus("panic", per_page = 2, max_records = 4)$records
  expect_identical(lapply(records, function(r) r$doi),
                   list("https://doi.org/10.1/w1", "https://doi.org/10.1/w2", NULL,
                        "https://doi.org/10.1/w4"))
  expect_identical(names(records[[3L]]), c("id", "doi", "title", "year", "keywords", "references"))
  expect_identical(records[[1L]]$keywords, list("panic", "k1"))
  expect_identical(records[[1L]]$references, list("https://openalex.org/R1"))
})

test_that("the API key travels only in the Authorization header", {
  old <- Sys.getenv("OPENALEX_API_KEY", unset = NA)
  on.exit(restore_env_key(old), add = TRUE)
  Sys.unsetenv("OPENALEX_API_KEY")
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  corpus <- tf_fetch_corpus("panic", per_page = 2, max_records = 3, api_key = "s3cr3t-key")
  expect_length(fake$sent, 2L)
  for (s in fake$sent) {
    expect_identical(s$headers, c(Authorization = "Bearer s3cr3t-key"))
    expect_false(grepl("s3cr3t", s$url, fixed = TRUE))
  }
  expect_false(grepl("s3cr3t", as_json(corpus), fixed = TRUE))

  # The key defaults to OPENALEX_API_KEY, and an empty key or NULL sends none.
  Sys.setenv(OPENALEX_API_KEY = "from-env")
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  tf_fetch_corpus("panic", per_page = 2)
  tf_fetch_corpus("panic", per_page = 2, api_key = "")
  tf_fetch_corpus("panic", per_page = 2, api_key = NULL)
  expect_identical(lapply(fake$sent, function(s) s$headers),
                   list(c(Authorization = "Bearer from-env"), NULL, NULL))
})

test_that("a key is trimmed, and a server that repeats it is redacted", {
  fake <- fake_openalex(function(url, headers) {
    list(status = 401L, body = as_json(list(error = "Unauthorized",
                                            message = paste("bad", headers[["Authorization"]]))))
  })
  local_mocked_bindings(.tf_http = fake$http)
  msg <- refusal(tf_fetch_corpus("panic", api_key = " s3cr3t\n"))
  expect_identical(fake$sent[[1L]]$headers, c(Authorization = "Bearer s3cr3t"))
  expect_identical(msg, "OpenAlex request failed with HTTP 401: bad Bearer <api_key>")
})

test_that("redaction leaves the status and any message readable", {
  # A Latin-1 error page is not UTF-8, so it carries no message, but the status
  # stands. .tf_http() marks every body UTF-8, as here.
  latin1 <- rawToChar(c(charToRaw('{"message": "d'), as.raw(0xe9), charToRaw('lai s3cr3t"}')))
  Encoding(latin1) <- "UTF-8"
  utf8 <- enc2utf8('{"message": "délai dépassé, s3cr3t"}')
  for (case in list(list(latin1, "OpenAlex request failed with HTTP 403"),
                    list(utf8, enc2utf8("OpenAlex request failed with HTTP 403: délai dépassé, <api_key>")))) {
    fake <- fake_openalex(function(url, headers) list(status = 403L, body = case[[1L]]))
    local_mocked_bindings(.tf_http = fake$http)
    expect_identical(refusal(tf_fetch_corpus("panic", api_key = "s3cr3t")), case[[2L]])
  }
})

test_that("the arguments are checked before any request", {
  fake <- fake_openalex(paged_answer)
  local_mocked_bindings(.tf_http = fake$http)
  for (bad in list("two words", "café", "tab\tinside", 42, c("a", "b"), NA_character_, TRUE)) {
    expect_identical(refusal(tf_fetch_corpus("panic", api_key = bad)), key_message)
  }
  for (bad in list(0, -1, 2.5, "3", TRUE, NA, c(2, 3))) {
    expect_identical(refusal(tf_fetch_corpus("panic", max_records = bad)),
                     "max_records must be a positive integer")
  }
  expect_identical(refusal(tf_fetch_corpus("panic", per_page = 0, max_records = 0, api_key = "a b")),
                   "per_page must be between 1 and 200")
  expect_identical(refusal(tf_fetch_corpus("panic", max_records = 0, api_key = "a b")),
                   "max_records must be a positive integer")
  expect_length(fake$sent, 0L)
})
