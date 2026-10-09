# The R app's glue code (BOOT_R in apps/r/r-runtime.js) run under native R.
#
# The app loads a theory and validates it in one call, so the sidebar can say
# whether the theory is valid before any operation runs. Each load also reports
# the theory's version record, from which the app picks the declared parent as
# the appraisal's prior, and an uploaded prior is kept apart from the theory.
# The Python suite checks the Pyodide glue the same way in test_app_glue.py. The
# glue is read out of the app source, which sits at the repository root outside
# the package, so these checks run only from a source checkout.

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

# The appraisal's prior defaults to the version the loaded theory declares as
# its parent, which the app decides from the lineage each load reports.
test_that("the app's load reports the theory's version lineage", {
  app <- app_glue()
  v2 <- jsonlite::fromJSON(app$.tf_load(tf_fixture_path("panic-network-2026-v2.theory.yaml")),
                           simplifyVector = FALSE)
  expect_identical(v2$version, list(id = "v2", parent_id = "v1"))
  # A theory without a version record reads as one with empty fields.
  weak <- jsonlite::fromJSON(app$.tf_load(tf_fixture_path("weak-theory.theory.yaml")),
                             simplifyVector = FALSE)
  expect_identical(weak$version, list(id = "", parent_id = ""))
})

test_that("the app reads candidate priors' lineage without loading them", {
  app <- app_glue()
  app$.tf_load(tf_fixture_path("panic-network-2026-v2.theory.yaml"))
  out <- jsonlite::fromJSON(app$.tf_lineage(c(tf_fixture_path("panic-network.theory.yaml"),
                                              write_theory("- id: x"))),
                            simplifyVector = FALSE)
  expect_identical(out, list(
    list(id = "panic-network-2026", title = "Network theory of panic disorder",
         version = list(id = "v1", parent_id = "")),
    NULL))
  expect_identical(app$.tf_app$theory$id, "panic-network-2026-v2")
})

test_that("an uploaded prior is kept apart from the theory", {
  app <- app_glue()
  v1 <- tf_fixture_path("panic-network.theory.yaml")
  v2 <- tf_fixture_path("panic-network-2026-v2.theory.yaml")
  app$.tf_load(v2)
  expect_error(app$.tf_run("appraise", list(prior = "upload")), "No prior version uploaded")
  lineage <- jsonlite::fromJSON(app$.tf_load_prior(v1), simplifyVector = FALSE)
  expect_identical(lineage$id, "panic-network-2026")
  expect_identical(lineage$version, list(id = "v1", parent_id = ""))
  expect_identical(app$.tf_app$theory$id, "panic-network-2026-v2")
  direct <- tf_appraise_amendment(tf_read(v2), tf_read(v1))
  expect_identical(
    app$.tf_run("appraise", list(prior = "upload")),
    as.character(jsonlite::toJSON(direct, auto_unbox = TRUE, digits = NA, null = "null")))
  # A prior that cannot be read leaves the one uploaded before it.
  expect_error(app$.tf_load_prior(write_theory("- id: x")), "mapping")
  expect_identical(app$.tf_app$prior$id, "panic-network-2026")
})

test_that("implied independencies and their refusal are both results", {
  app <- app_glue()
  app$.tf_load(tf_fixture_path("panic-network.theory.yaml"))
  refused <- app$.tf_run("implications", list(cycles = "refuse"))
  expect_identical(jsonlite::fromJSON(refused, simplifyVector = FALSE), list(
    ok = FALSE,
    message = paste0("implications requires an acyclic causal graph; cycle found: ",
                     "c_arousal -> c_perceived_threat -> c_arousal; set cycles to 'sigma' ",
                     "to derive sigma-separation statements")))
  # The default is the package's own.
  expect_identical(app$.tf_run("implications", list()), refused)
  sigma <- jsonlite::fromJSON(app$.tf_run("implications", list(cycles = "sigma")),
                              simplifyVector = FALSE)$result
  expect_identical(sigma$criterion, "sigma")
  expect_identical(sigma$feedback, list(list("c_arousal", "c_perceived_threat")))
  expect_identical(vapply(sigma$implications, function(s) s$statement, ""),
                   "c_arousal _||_ c_avoidance | c_perceived_threat")
})

test_that("the acyclic example implies its basis set", {
  app <- app_glue()
  app$.tf_load(tf_fixture_path("modality-switching.theory.yaml"))
  res <- jsonlite::fromJSON(app$.tf_run("implications", list(cycles = "refuse")),
                            simplifyVector = FALSE)$result
  expect_identical(res$n_implications, 6L)
  marginal <- Filter(function(s) length(s$given) == 0L, res$implications)
  expect_identical(vapply(marginal, function(s) s$statement, ""),
                   "c_sensorimotor_experience _||_ c_lexical_familiarity")
})
