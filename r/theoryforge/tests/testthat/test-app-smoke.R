# scripts/app_smoke.R: the R app's glue run on the files its manifest lists.
#
# The script copies the files the webR app fetches into a temporary tree and
# sources BOOT_R there in a fresh R whose library holds jsonlite and yaml
# alone, the two packages the app installs, then calls every operation on every
# example. These tests build a small app tree of their own, as apps/build.mjs
# would, so they need no Node build. A tree whose manifest leaves out a source
# file must fail, and so must a boot that stops pre-seeding a cache, even where
# theoryforge is installed: the browser has no installed copy for system.file()
# to find. The Python suite checks scripts/app_smoke.py the same way in
# test_app_smoke.py. Both run only from a source checkout.

smoke_root <- function() {
  root <- testthat::test_path("..", "..", "..", "..")
  if (!file.exists(file.path(root, "apps", "r", "r-runtime.js"))) {
    testthat::skip("apps/r is not reachable from this test run")
  }
  normalizePath(root, winslash = "/")
}

# v1 is v2's declared parent, so the appraisal runs against it for v2 and
# against an uploaded prior for v1.
smoke_examples <- c("panic-network.theory.yaml", "panic-network-2026-v2.theory.yaml")

smoke_apps <- function(root) {
  apps <- file.path(tempfile("tf-smoke-"), "apps")
  vendor <- file.path(apps, "r", "vendor")
  dir.create(file.path(vendor, "R"), recursive = TRUE)
  dir.create(file.path(vendor, "schema"))
  dir.create(file.path(vendor, "fixtures"))
  pkg <- file.path(root, "r", "theoryforge")
  r_files <- sort(list.files(file.path(pkg, "R"), pattern = "[.][Rr]$"))
  file.copy(file.path(pkg, "R", r_files), file.path(vendor, "R"))
  schema <- c(theory = "theory.schema.json", checklist = "rigor_checklist.yaml", fold = "fold.json")
  file.copy(file.path(pkg, "inst", "schema", schema), file.path(vendor, "schema"))
  file.copy(file.path(root, "fixtures", c(smoke_examples, "panic-corpus.yaml")),
            file.path(vendor, "fixtures"))
  manifest <- list(
    rFiles = paste0("R/", r_files),
    schema = as.list(stats::setNames(paste0("schema/", schema), names(schema))),
    examples = lapply(smoke_examples, function(n) list(name = n, path = paste0("fixtures/", n))),
    corpora = list(list(name = "corpus", path = "fixtures/panic-corpus.yaml")))
  jsonlite::write_json(manifest, file.path(vendor, "manifest.json"), auto_unbox = TRUE)
  file.copy(file.path(root, "apps", "r", "r-runtime.js"), file.path(apps, "r"))
  apps
}

run_smoke <- function(root, apps) {
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  out <- suppressWarnings(system2(rscript, c(shQuote(file.path(root, "scripts", "app_smoke.R")),
                                             shQuote(apps)), stdout = TRUE, stderr = TRUE))
  list(status = if (is.null(attr(out, "status"))) 0L else attr(out, "status"),
       text = paste(out, collapse = "\n"))
}

test_that("every operation runs on every example through the R app's glue", {
  skip_on_cran()
  root <- smoke_root()
  apps <- smoke_apps(root)
  on.exit(unlink(dirname(apps), recursive = TRUE), add = TRUE)
  res <- run_smoke(root, apps)
  expect_identical(res$status, 0L, info = res$text)
  cases <- jsonlite::fromJSON(file.path(root, "scripts", "app_smoke_cases.json"),
                              simplifyVector = FALSE)$cases
  expect_match(res$text, sprintf("2 examples x %d operations", length(cases)), fixed = TRUE)
  expect_match(res$text, ", 0 failures", fixed = TRUE)
})

test_that("a source file the manifest leaves out is not sourced", {
  skip_on_cran()
  root <- smoke_root()
  apps <- smoke_apps(root)
  on.exit(unlink(dirname(apps), recursive = TRUE), add = TRUE)
  # The file stays in the vendor directory, which the browser never sees
  # whole: it fetches only what the manifest lists.
  path <- file.path(apps, "r", "vendor", "manifest.json")
  manifest <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  manifest$rFiles <- Filter(function(f) f != "R/resources.R", manifest$rFiles)
  jsonlite::write_json(manifest, path, auto_unbox = TRUE)
  expect_true(file.exists(file.path(apps, "r", "vendor", "R", "resources.R")))
  res <- run_smoke(root, apps)
  expect_false(identical(res$status, 0L))
  expect_match(res$text, ".tf_cache", fixed = TRUE)
})

test_that("an installed theoryforge cannot stand in for a cache the boot leaves unseeded", {
  skip_on_cran()
  root <- smoke_root()
  apps <- smoke_apps(root)
  on.exit(unlink(dirname(apps), recursive = TRUE), add = TRUE)
  runtime <- file.path(apps, "r", "r-runtime.js")
  js <- readLines(runtime, encoding = "UTF-8", warn = FALSE)
  seed <- grepl("^[.]tf_cache[$]fold <- ", js)
  expect_identical(sum(seed), 1L)
  writeLines(js[!seed], runtime, useBytes = TRUE)
  res <- run_smoke(root, apps)
  expect_false(identical(res$status, 0L))
  expect_match(res$text, "could not locate vendored fold.json", fixed = TRUE)
})
