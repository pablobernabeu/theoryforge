# The methodology article's table of rigour checks quotes each criterion from
# the checklist the package ships, read when the article is built, so the table
# changes with the checklist. These tests evaluate the article's `criteria`
# chunk, which .Rbuildignore leaves out of the built package with the rest of
# vignettes/articles, so they are skipped wherever the article is absent.

methodology_article <- function() {
  path <- testthat::test_path("..", "..", "vignettes", "articles",
                              "methodology.Rmd")
  skip_if_not(file.exists(path), "methodology article not available")
  path
}

# What the `criteria` chunk prints, as lines of Markdown.
criteria_output <- function(path) {
  code <- chunk_code(path, "criteria")
  utils::capture.output(eval(parse(text = code, keep.source = FALSE),
                             envir = new.env(parent = globalenv())))
}

# The body rows of the Markdown table in some lines, split into cells.
table_rows <- function(lines) {
  rows <- grep("^\\s*\\|", lines, value = TRUE)[-(1:2)]
  lapply(strsplit(gsub("^\\s*\\||\\|\\s*$", "", rows), "|", fixed = TRUE),
         trimws)
}

test_that("the methodology article quotes every criterion from the checklist", {
  path <- methodology_article()
  rows <- table_rows(criteria_output(path))
  items <- tf_checklist()$items
  expect_identical(vapply(rows, `[[`, character(1), 2L),
                   vapply(items, `[[`, character(1), "criterion"))
  expect_identical(sub("^.*\\(`(\\w+)`\\).*$", "\\1",
                       vapply(rows, `[[`, character(1), 1L)),
                   vapply(items, `[[`, character(1), "id"))
  # No copy of a criterion is left in a table written into the article itself.
  written <- grep("^\\s*\\|", readLines(path, encoding = "UTF-8", warn = FALSE),
                  value = TRUE)
  for (item in items) {
    expect_false(any(grepl(item$criterion, written, fixed = TRUE)),
                 info = item$id)
  }
})

test_that("the methodology table stops at a check it cannot name", {
  # A check the checklist gains has no name or supporting work in the article
  # yet, so the chunk refuses it and the site build fails until the article is
  # brought up to date.
  path <- methodology_article()
  spec <- tf_checklist()
  spec$items <- c(spec$items, list(list(
    id = "new_check", criterion = "A criterion the article does not know",
    weight = 0, severity_if_fail = "warning", citation = ""
  )))
  local_mocked_bindings(tf_checklist = function() spec)
  expect_error(criteria_output(path), "new_check")
})
