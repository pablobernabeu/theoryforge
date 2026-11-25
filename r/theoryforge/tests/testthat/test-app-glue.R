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
    # The problems also come as a list, which joined gives the message.
    problems <- unlist(summary$validation$problems)
    expect_identical(summary$validation$message,
                     paste0("invalid theory object: ", paste(problems, collapse = "; ")), info = cs$problem)
  }
})

test_that("a problem that quotes a semicolon stays one problem", {
  # A message quotes the value it concerns, and a value can hold "; ", so the
  # app reads the list rather than split the joined message. A single problem
  # stays a list in the JSON. The Python glue gives the same list.
  app <- app_glue()
  text <- paste0("schema_version: '1.0'\nid: x\ntitle: X\nmaturity: draft\n",
                 "constructs:\n  - {id: a, label: A, definition: D}\n",
                 "propositions:\n  - {id: p1, from: a, to: 'avoidance; escape', relation: increases}")
  v <- jsonlite::fromJSON(app$.tf_load(write_theory(text)), simplifyVector = FALSE)$validation
  expect_identical(v$problems, list("proposition[0] to 'avoidance; escape' is not a known construct"))
  ok <- jsonlite::fromJSON(app$.tf_load(write_theory(sub("avoidance; escape", "a", text, fixed = TRUE))),
                           simplifyVector = FALSE)$validation
  expect_identical(ok, list(ok = TRUE))
})

test_that(".tf_validation_problems() lists what tf_validate() joins on every edge case", {
  edge <- testthat::test_path("..", "..", "..", "..", "fixtures", "edge")
  paths <- sort(Sys.glob(file.path(edge, "*.theory.*")))
  if (!length(paths)) testthat::skip("fixtures/edge is not reachable from this test run")
  for (path in paths) {
    t <- tryCatch(tf_read(path), error = function(e) NULL)
    if (is.null(t)) next
    problems <- .tf_validation_problems(t, TRUE)
    msg <- tryCatch({ tf_validate(t, full = TRUE); NULL }, error = conditionMessage)
    if (is.null(msg)) {
      expect_identical(problems, character(0), info = basename(path))
    } else {
      expect_identical(msg, paste0("invalid theory object: ", paste(problems, collapse = "; ")),
                       info = basename(path))
    }
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

# -- the editor, the new operations and the uploads ---------------------------

app_run <- function(app, op, ...) {
  jsonlite::fromJSON(app$.tf_run(op, list(...)), simplifyVector = FALSE)
}
as_app_json <- function(x) {
  jsonlite::fromJSON(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null")),
                     simplifyVector = FALSE)
}

test_that("the summary lists constructs, rivals, the score and the hash", {
  app <- app_glue()
  path <- tf_fixture_path("modality-switching.theory.yaml")
  s <- jsonlite::fromJSON(app$.tf_load(path), simplifyVector = FALSE)
  t <- tf_read(path)
  expect_identical(vapply(s$constructs, function(c) c$id, ""),
                   vapply(t$constructs, function(c) c$id, ""))
  expect_identical(s$alternatives, list(
    list(id = "alt_grounding_by_interaction", label = "Grounding by interaction", propositions = 4L),
    list(id = "alt_symbol_interdependency", label = "Symbol interdependency", propositions = 5L)))
  expect_identical(s$check$score, tf_check(t)$aggregate_score)
  # The hash is a call of its own, so a slow hash cannot hold up a load.
  expect_null(s$hash)
  expect_identical(jsonlite::fromJSON(app$.tf_hash_call(), simplifyVector = FALSE),
                   list(hash = tf_content_hash(t)))
  expect_identical(s$counts$phenomena, 1L)
})

test_that("the editor reads back what the writer writes", {
  app <- app_glue()
  app$.tf_load(tf_fixture_path("panic-network.theory.yaml"))
  loaded <- jsonlite::fromJSON(app$.tf_hash_call(), simplifyVector = FALSE)
  written <- tempfile(fileext = ".json")
  writeBin(charToRaw(enc2utf8(app$.tf_write_text("json"))), written)
  out <- jsonlite::fromJSON(app$.tf_edit(written, c("yaml", "json")), simplifyVector = FALSE)
  expect_identical(jsonlite::fromJSON(app$.tf_hash_call(), simplifyVector = FALSE)$hash, loaded$hash)
  expect_setequal(names(out$texts), c("yaml", "json"))
  back <- tempfile(fileext = ".yaml")
  writeBin(charToRaw(enc2utf8(out$texts$yaml)), back)
  expect_identical(tf_content_hash(tf_read(back)), loaded$hash)
  # A source that cannot be read leaves the theory as it was.
  bad <- write_theory("id: x\nfoo: bar: baz")
  expect_error(app$.tf_edit(bad, character(0)))
  expect_identical(tf_content_hash(app$.tf_app$theory), loaded$hash)
})

test_that("the new operations give what the package gives", {
  app <- app_glue()
  path <- tf_fixture_path("modality-switching.theory.yaml")
  app$.tf_load(path)
  t <- tf_read(path)
  expect_identical(app_run(app, "entailments", cycles = "refuse"), as_app_json(list(result = tf_entailments(t))))
  expect_identical(app_run(app, "equivalent"), as_app_json(list(result = tf_equivalent_models(t))))
  expect_identical(app_run(app, "post_severity"), as_app_json(list(result = tf_post_data_severity(t))))
  rival <- "alt_symbol_interdependency"
  expect_identical(app_run(app, "discriminate", rival = rival, cycles = "sigma"),
                   as_app_json(list(result = tf_discriminate(t, rival, cycles = "sigma"))))
  expect_identical(app_run(app, "preregister", cycles = "sigma")$text, tf_preregister(t, cycles = "sigma"))
  expect_identical(app_run(app, "dossier", cycles = "refuse")$hash, tf_content_hash(t))
})

test_that("a rival is an alternative or an uploaded theory", {
  app <- app_glue()
  modality <- tf_fixture_path("modality-switching.theory.yaml")
  app$.tf_load(modality)
  expect_error(app_run(app, "discriminate", rival = "upload"), "No rival theory uploaded")
  expect_error(app_run(app, "discriminate", rival = ""), "No rival chosen")
  rival <- jsonlite::fromJSON(app$.tf_load_rival(modality), simplifyVector = FALSE)
  expect_identical(rival$constructs, 5L)
  expect_false(app_run(app, "discriminate", rival = "alt_none")$ok)
  app$.tf_load(tf_fixture_path("panic-network.theory.yaml"))
  out <- app_run(app, "discriminate", rival = "upload")$result
  expect_identical(list(out$evaluated, out$reason), list(FALSE, "feedback_loop"))
})

test_that("an impulse starts one construct at 1", {
  app <- app_glue()
  app$.tf_load(tf_fixture_path("panic-network.theory.yaml"))
  res <- app_run(app, "simulate", method = "exact", start = "impulse", impulse = "c_perceived_threat",
                 steps = 2, dt = 0.1, k = 1, damping = 0.5, init = 1)$result
  expect_equal(unlist(res$initial_state), c(0, 1, 0))
  expect_identical(unlist(res$assumed_positive), "p3")
  expect_false(app_run(app, "simulate", method = "exact", start = "impulse", impulse = "c_none",
                       steps = 2, dt = 0.1, k = 1, damping = 0.5, init = 1)$ok)
})

test_that("the literature map takes its method and an uploaded corpus", {
  app <- app_glue()
  app$.tf_load(tf_fixture_path("panic-network.theory.yaml"))
  corpus <- tf_fixture_path("openalex-panic-2026.corpus.yaml")
  res <- app_run(app, "litmap", corpus = corpus, method = "simple_centres", min_link = 2, min_df = 2, max_df = 0.5)
  direct <- tf_litmap(tf_read_corpus(corpus), min_link = 2, method = "simple_centres", min_df = 2, max_df = 0.5)
  expect_identical(res$result, as_app_json(direct))
  expect_null(res$warning)
  warned <- app_run(app, "litmap", corpus = corpus, method = "components", min_link = 2, min_df = 1, max_df = 1)
  expect_match(warned$warning, "^litmap: one theme holds")
  expect_error(app_run(app, "landscape", corpus = "upload", method = "components", min_link = 2), "No corpus uploaded")
  up <- jsonlite::fromJSON(app$.tf_load_corpus(tf_fixture_path("panic-corpus.yaml"), "upload"), simplifyVector = FALSE)
  expect_identical(up, list(id = "panic-corpus-demo", n_records = 8L))
  expect_identical(app_run(app, "landscape", corpus = "upload", method = "simple_centres", min_link = 2)$result$method,
                   "simple_centres")
  expect_false(app_run(app, "litmap", corpus = "upload", method = "simple_centres", min_link = 2, min_df = 0, max_df = 1)$ok)
})

test_that("the DAGitty import passes on the settings the user gives", {
  # The reader stands in for tf_read_dagitty(text, id, title, relation), so
  # the test reads the glue alone.
  app <- app_glue()
  seen <- NULL
  app$tf_read_dagitty <- function(text, ...) {
    seen <<- list(text = text, args = list(...))
    a <- list(...)
    rel <- if (is.null(a$relation)) "causes" else a$relation
    tf_theory(if (is.null(a$id)) "dagitty-import" else a$id, "T", maturity = "draft") |>
      tf_add_construct("a", "a", "") |> tf_add_construct("b", "b", "") |>
      tf_add_proposition("p1", "a", "b", rel)
  }
  model <- tempfile(fileext = ".txt")
  writeBin(charToRaw("dag { a -> b }\n"), model)
  out <- jsonlite::fromJSON(app$.tf_import_dagitty(model, list(id = "mine", title = "", relation = "increases",
                                                               formats = "yaml")), simplifyVector = FALSE)
  expect_identical(seen, list(text = "dag { a -> b }\n", args = list(id = "mine", relation = "increases")))
  expect_identical(out$id, "mine")
  expect_match(out$texts$yaml, "relation: increases", fixed = TRUE)
  expect_identical(app$.tf_app$theory$id, "mine")
})

test_that("the DAGitty import runs the package reader", {
  if (!exists("tf_read_dagitty", mode = "function")) {
    testthat::skip("this version of the package has no tf_read_dagitty()")
  }
  app <- app_glue()
  model <- tempfile(fileext = ".txt")
  writeBin(charToRaw("dag {\n  a -> b -> c\n  a <-> c [latent]\n}\n"), model)
  out <- jsonlite::fromJSON(app$.tf_import_dagitty(model, list(relation = "increases", formats = "json")),
                            simplifyVector = FALSE)
  data <- jsonlite::fromJSON(out$texts$json, simplifyVector = FALSE)
  expect_identical(vapply(data$constructs, function(c) c$id, ""), c("a", "b", "c"))
  expect_identical(vapply(data$propositions, function(p) paste(p$from, p$relation, p$to), ""),
                   c("a increases b", "b increases c", "a associates c"))
})
