# The R app's glue code (BOOT_R in apps/r/r-runtime.js) run under native R.
#
# The app loads a theory and validates it in one call, so the sidebar can say
# whether the theory is valid before any operation runs. The Python suite checks
# the Pyodide glue the same way in test_app_glue.py. The glue is read out of the
# app source, which sits at the repository root outside the package, so these
# checks run only from a source checkout.

app_glue <- function() {
  path <- testthat::test_path("..", "..", "..", "..", "apps", "r", "r-runtime.js")
  if (!file.exists(path)) {
    testthat::skip("apps/r is not reachable from this test run")
  }
  js <- paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  m <- regmatches(js, regexpr("(?s)const BOOT_R = String\\.raw`(.*?)`;", js, perl = TRUE))
  expect_length(m, 1L)
  boot <- sub("`;$", "", sub("(?s)^const BOOT_R = String\\.raw`", "", m, perl = TRUE))
  # The first lines source the vendored package and seed its caches from the
  # in-browser file system. The package is already loaded here, so only the
  # app's own definitions are evaluated, in an environment that sees the
  # package's internals as the sourced code does in the browser.
  exprs <- parse(text = boot, keep.source = FALSE)
  keep <- !vapply(exprs, function(e) {
    any(grepl("\"/tf/(R|schema)|[.]tf_app_files", deparse(e)))
  }, logical(1))
  env <- new.env(parent = asNamespace("theoryforge"))
  for (e in exprs[keep]) eval(e, env)
  env
}

write_theory <- function(text) {
  f <- tempfile(fileext = ".theory.yaml")
  writeLines(text, f, useBytes = TRUE)
  f
}

test_that("the app's load reports a valid theory as valid", {
  app <- app_glue()
  summary <- jsonlite::fromJSON(app$.tf_load(tf_fixture_path("panic-network.theory.yaml")),
                                simplifyVector = FALSE)
  expect_identical(summary$id, "panic-network-2026")
  expect_identical(summary$validation, list(ok = TRUE))
})

test_that("the app's load keeps an invalid theory and names its problems", {
  app <- app_glue()
  cases <- list(
    list(text = "{}", problem = "missing/empty required field: id"),
    list(text = "schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\npredicitions: []",
         problem = "unknown top-level field: predicitions"),
    list(text = "schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\nconstructs: [arousal, threat]",
         problem = "construct[0] missing/empty id")
  )
  for (cs in cases) {
    summary <- jsonlite::fromJSON(app$.tf_load(write_theory(cs$text)), simplifyVector = FALSE)
    expect_false(isTRUE(summary$validation$ok), info = cs$problem)
    expect_match(summary$validation$message, "^invalid theory object: ", info = cs$problem)
    expect_match(summary$validation$message, cs$problem, fixed = TRUE, info = cs$problem)
    expect_identical(jsonlite::fromJSON(app$.tf_run("validate", list()), simplifyVector = FALSE),
                     summary$validation, info = cs$problem)
  }
})

test_that("a file the app cannot read leaves the previous theory loaded", {
  app <- app_glue()
  app$.tf_load(tf_fixture_path("panic-network.theory.yaml"))
  expect_error(app$.tf_load(write_theory("- id: x")), "mapping")
  expect_identical(app$.tf_app$theory$id, "panic-network-2026")
})
