test_that("tf_render_report writes a .qmd containing the dossier", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  path <- tempfile(fileext = ".qmd")
  out <- tf_render_report(theory, path)
  expect_identical(out, path)
  expect_true(file.exists(out))

  text <- readChar(out, file.info(out)$size, useBytes = TRUE)
  # YAML header with title and format.
  expect_match(text, "^---\\ntitle: ", perl = TRUE)
  expect_match(text, "format: html", fixed = TRUE)
  # Body is the deterministic dossier (verbatim).
  expect_true(grepl(tf_dossier(theory), text, fixed = TRUE))
})

test_that("tf_render_report forces a .qmd suffix and escapes quotes in the title", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  base <- tempfile(fileext = ".txt")
  out <- tf_render_report(theory, base, title = 'A "quoted" title', to = "pdf")
  expect_identical(tolower(tools::file_ext(out)), "qmd")
  expect_true(file.exists(out))

  text <- readChar(out, file.info(out)$size, useBytes = TRUE)
  expect_match(text, "title: \"A 'quoted' title\"", fixed = TRUE)
  expect_match(text, "format: pdf", fixed = TRUE)
})
