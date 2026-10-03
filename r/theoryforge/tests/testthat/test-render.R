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
  expect_match(text, 'title: "A \\"quoted\\" title"', fixed = TRUE)
  expect_match(text, "format: pdf", fixed = TRUE)
})

# The Python twin's test_osf_report.py pins the same header line for the same
# title, so the two twins write one YAML header.
test_that("tf_render_report escapes the title as a YAML double-quoted scalar", {
  theory <- tf_theory("t", "T")
  # R refuses Unicode and octal escapes in one literal, hence the paste0().
  title <- paste0("Effects of A\\B on \"C\": \\emph{fluency}, $\\alpha$\nline\ttwo\001\177",
                  "é\u0085")
  out <- tf_render_report(theory, tempfile(fileext = ".qmd"), title = title)
  lines <- strsplit(readChar(out, file.info(out)$size, useBytes = TRUE), "\n", fixed = TRUE)[[1L]]
  expected <- paste0(
    'title: "Effects of A\\\\B on \\"C\\": \\\\emph{fluency}, $\\\\alpha$',
    '\\nline\\ttwo\\x01\\x7Fé\\x85"'
  )
  got <- lines[[2L]]
  Encoding(got) <- "UTF-8"
  expect_identical(got, enc2utf8(expected))
  # A YAML parser reads back exactly the title that was passed.
  header <- yaml::yaml.load(paste(lines[2:3], collapse = "\n"))
  expect_identical(header$title, enc2utf8(title))
})

test_that("tf_render_report escapes the noncharacters U+FFFE and U+FFFF", {
  # YAML forbids both raw, as it does the control characters.
  title <- paste0("a", intToUtf8(0xFFFE), "b", intToUtf8(0xFFFF))
  out <- tf_render_report(tf_theory("t", "T"), tempfile(fileext = ".qmd"), title = title)
  lines <- strsplit(readChar(out, file.info(out)$size, useBytes = TRUE), "\n", fixed = TRUE)[[1L]]
  expect_identical(lines[[2L]], 'title: "a\\uFFFEb\\uFFFF"')
  header <- yaml::yaml.load(paste(lines[2:3], collapse = "\n"))
  expect_identical(utf8ToInt(header$title), utf8ToInt(title))
})

test_that("tf_render_report treats an empty title as absent, as Python does", {
  for (title in list("", NA_character_)) {
    out <- tf_render_report(tf_theory("the-id", ""), tempfile(fileext = ".qmd"), title = title)
    text <- readChar(out, file.info(out)$size, useBytes = TRUE)
    expect_match(text, 'title: "theoryforge report: the-id"', fixed = TRUE)
  }
})

# tf_render_diagram() is a language-native convenience over the deterministic
# IR, so these tests cover the wrapper contract (dispatch, guard rails), not the
# rendering engine itself.

render_demo_theory <- function() {
  tf_theory("demo-1", "A demonstration theory") |>
    tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
    tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
    tf_add_proposition("p1", "c_arousal", "c_threat", "causes")
}

test_that("digraph views render to a grViz widget", {
  skip_if_not_installed("DiagrammeR")
  w <- tf_render_diagram(render_demo_theory(), "nomological_net")
  expect_s3_class(w, "grViz")
  expect_s3_class(w, "htmlwidget")
})

test_that("as = 'svg' returns standalone SVG that draws the theory", {
  skip_if_not_installed("DiagrammeR")
  skip_if_not_installed("DiagrammeRsvg")
  svg <- tf_render_diagram(render_demo_theory(), "workflow", as = "svg")
  expect_type(svg, "character")
  expect_match(svg, "<svg", fixed = TRUE)
  expect_match(svg, "Arousal", fixed = TRUE)
})

test_that("a raw DOT string renders, so literature diagrams render too", {
  skip_if_not_installed("DiagrammeR")
  dot <- tf_diagram(render_demo_theory(), "pipeline")
  w <- tf_render_diagram(dot)
  expect_s3_class(w, "grViz")
})

test_that("the SVG chart views pass through as = 'svg' unchanged", {
  th <- render_demo_theory()
  svg <- tf_diagram(th, "venn")
  expect_identical(tf_render_diagram(th, "venn", as = "svg"), svg)
  expect_identical(tf_render_diagram(svg, as = "svg"), svg)
})

test_that("causal_dag and unknown types are refused with guidance", {
  th <- render_demo_theory()
  expect_error(tf_render_diagram(th, "causal_dag"), "dagitty")
  expect_error(tf_render_diagram(tf_diagram(th, "causal_dag")), "dagitty")
  expect_error(tf_render_diagram(th, "no_such_view"), "unknown diagram type")
})
