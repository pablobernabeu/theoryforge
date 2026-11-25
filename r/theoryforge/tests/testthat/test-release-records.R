# The version is written by hand in DESCRIPTION, python/pyproject.toml,
# python/mkdocs.yml and API_SPEC.md. In a release, all four give the same
# version. Between releases, mkdocs.yml still gives the newest release,
# DESCRIPTION gives that version followed by .9000, pyproject.toml a .devN
# version of a later release and API_SPEC.md '(development version)'. In both,
# CITATION.cff cites the newest release that CHANGELOG.md dates, no later than
# the newest release. test_release_docs.py checks the same records in Python.
# The files other than DESCRIPTION sit outside the R package, so the test is
# skipped wherever the repository is absent.

repo_file <- function(...) {
  path <- testthat::test_path("..", "..", "..", "..", ...)
  skip_if_not(file.exists(path), paste(basename(path), "not available"))
  path
}

# The first group that pattern captures in the lines of a file.
first_match <- function(path, pattern) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  hit <- regmatches(lines, regexec(pattern, lines, perl = TRUE))
  hit <- Filter(length, hit)
  if (length(hit) == 0L) NA_character_ else hit[[1L]][2L]
}

test_that("every record of the version agrees", {
  versions <- c(
    pyproject = first_match(repo_file("python", "pyproject.toml"),
                            '^version = "([^"]+)"'),
    description = first_match(repo_file("r", "theoryforge", "DESCRIPTION"),
                              "^Version: (\\S+)"),
    mkdocs = first_match(repo_file("python", "mkdocs.yml"),
                         '^  version: "([^"]+)"'),
    spec = first_match(repo_file("API_SPEC.md"),
                       "^# .*\\((v[^)]+|development version)\\)$")
  )
  expect_false(anyNA(versions), info = paste(names(versions)[is.na(versions)]))
  changelog <- readLines(repo_file("CHANGELOG.md"), encoding = "UTF-8",
                         warn = FALSE)
  # mkdocs.yml shows the newest release beside the site's title, so it names
  # the release in both states.
  released <- versions[["mkdocs"]]
  if (endsWith(versions[["description"]], ".9000")) {
    # The development line after a release, which CHANGELOG.md records.
    expect_true(any(startsWith(changelog, paste0("## [", released, "]"))))
    expect_identical(versions[["description"]], paste0(released, ".9000"))
    dev <- regmatches(versions[["pyproject"]],
                      regexec("^(\\d+(?:\\.\\d+)*)\\.dev\\d+$",
                              versions[["pyproject"]], perl = TRUE))[[1L]]
    expect_length(dev, 2L)
    # Trailing zeros are dropped, so 0.7.1.0 ranks with 0.7.1, as in PEP 440.
    expect_gt(utils::compareVersion(sub("(\\.0)+$", "", dev[2L]),
                                    sub("(\\.0)+$", "", released)), 0)
    expect_identical(versions[["spec"]], "development version")
  } else {
    versions[["spec"]] <- sub("^v", "", versions[["spec"]])
    expect_identical(unique(unname(versions)), versions[["description"]])
  }
  # CITATION.cff cites the newest published release, the newest that
  # CHANGELOG.md dates, and moves to a new version only once that version is
  # published.
  cited <- as.character(yaml::read_yaml(repo_file("CITATION.cff"))$version)
  dated <- sub("^## \\[([^]]+)\\] - .*$", "\\1",
               grep("^## \\[[^]]+\\] - \\d{4}-\\d{2}-\\d{2}[ \\t]*$", changelog,
                    value = TRUE, perl = TRUE))
  expect_identical(cited, dated[1L])
  expect_lte(utils::compareVersion(cited, released), 0)
})
