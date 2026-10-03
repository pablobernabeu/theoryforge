# The literature article shows how to turn a scopusflow corpus into a
# theoryforge corpus. The recipe is not run when the article is built, because
# scopusflow is not a dependency, so this test runs it instead: it evaluates the
# article's `scopus-adapter` chunk on a stand-in shaped like scopus_corpus()
# output and checks that the written corpus maps as it should. The article sits
# in vignettes/articles, which .Rbuildignore leaves out of the built package, so
# the test is skipped wherever the article is absent.

article_path <- function() {
  testthat::test_path("..", "..", "vignettes", "articles", "literature.Rmd")
}

# The lines of one knitr chunk, found by its label.
chunk_code <- function(path, label) {
  lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  start <- grep(sprintf("^```\\{r %s[,}]", label), lines)
  if (length(start) != 1L) {
    stop(sprintf("expected one `%s` chunk in %s, found %d",
                 label, basename(path), length(start)), call. = FALSE)
  }
  fences <- grep("^```\\s*$", lines)
  end <- fences[fences > start][1L]
  lines[(start + 1L):(end - 1L)]
}

# Three citing records cite the same two works. The first work's DOI arrives
# upper-case, lower-case and not at all; keywords differ only in case and in
# surrounding space; the third record has no year. The empty data frame and
# the NULL entry stand for a record without resolvable references and a failed
# lookup, both of which scopus_corpus() can return.
scopus_stand_in <- function() {
  refs <- function(id, doi) {
    data.frame(position = as.character(seq_along(id)), id = id, doi = doi,
               title = NA_character_, stringsAsFactors = FALSE)
  }
  sc <- data.frame(id = c("10.1/a", "10.1/b", "10.1/c", "10.1/d", "10.1/e"),
                   title = c("A", "B", "C", "D", NA),
                   year = c(2020L, 2021L, NA, 2022L, 2023L),
                   stringsAsFactors = FALSE)
  sc$keywords <- list(c("Panic disorder", "Interoception"),
                      c("panic disorder", " interoception "),
                      c("Panic Disorder", "Interoception", ""),
                      character(),
                      character())
  sc$references <- list(
    refs(c("84900000001", "84900000002"),
         c("10.1016/J.BRAT.2015.10.002", "10.1037/0033-295X.108.1.4")),
    refs(c("84900000001", NA),
         c("https://doi.org/10.1016/j.brat.2015.10.002", "10.1037/0033-295x.108.1.4")),
    refs(c("84900000001", "84900000002", "84900000002", NA),
         c(NA, NA, NA, NA)),
    data.frame(),
    NULL
  )
  sc
}

test_that("the article's Scopus adapter yields co-citation edges and themes", {
  path <- article_path()
  skip_if_not(file.exists(path), "literature article not available")
  code <- chunk_code(path, "scopus-adapter")

  env <- new.env(parent = globalenv())
  eval(parse(text = code, keep.source = FALSE), envir = env)
  expect_true(is.function(env$scopus_corpus_to_tf))

  lit <- env$scopus_corpus_to_tf(scopus_stand_in(), "scopus:panic disorder")
  out <- tempfile(fileext = ".json")
  on.exit(unlink(out), add = TRUE)
  jsonlite::write_json(lit, out, auto_unbox = TRUE, null = "null", na = "null")

  json <- paste(readLines(out, encoding = "UTF-8", warn = FALSE), collapse = "")
  expect_false(grepl('"NA"', json, fixed = TRUE))
  read <- tf_read_corpus(out)
  years <- lapply(read$records, `[[`, "year")
  expect_identical(years, list(2020L, 2021L, NULL, 2022L, 2023L))
  expect_false("title" %in% names(read$records[[5]]))

  expect_identical(
    unlist(read$records[[1]]$references),
    c("scopus:84900000001", "scopus:84900000002")
  )
  # The DOI-only reference takes the Scopus id another record pairs it with,
  # and the duplicate and empty references of record 3 fall away.
  expect_identical(read$records[[2]]$references,
                   read$records[[1]]$references)
  expect_identical(read$records[[3]]$references,
                   read$records[[1]]$references)
  expect_identical(read$records[[4]]$references, list())
  expect_identical(read$records[[5]]$references, list())
  expect_identical(unlist(read$records[[2]]$keywords),
                   c("panic disorder", "interoception"))

  lm <- one_theme(tf_litmap(read, min_link = 2))
  expect_length(lm$co_citation, 1L)
  expect_identical(lm$co_citation[[1]]$count, 3L)
  expect_length(lm$keyword_cooccurrence, 1L)
  expect_length(lm$themes, 1L)
  expect_identical(unlist(lm$themes[[1]]$keywords),
                   c("interoception", "panic disorder"))
})

test_that("the adapter keys a work with no Scopus id by its folded DOI", {
  path <- article_path()
  skip_if_not(file.exists(path), "literature article not available")
  env <- new.env(parent = globalenv())
  eval(parse(text = chunk_code(path, "scopus-adapter"), keep.source = FALSE),
       envir = env)

  sc <- data.frame(id = c("r1", "r2"), title = c("A", "B"), year = c(2020L, 2021L),
                   stringsAsFactors = FALSE)
  sc$keywords <- list("x", "y")
  sc$references <- list(
    data.frame(id = NA_character_, doi = "10.5555/ABC", stringsAsFactors = FALSE),
    data.frame(id = NA_character_, doi = " doi:10.5555/abc", stringsAsFactors = FALSE)
  )
  lit <- env$scopus_corpus_to_tf(sc, "doi-only")
  expect_identical(as.character(lit$records[[1]]$references), "doi:10.5555/abc")
  expect_identical(as.character(lit$records[[2]]$references), "doi:10.5555/abc")
})
