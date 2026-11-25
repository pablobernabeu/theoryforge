test_that("tf_render_report writes a .qmd containing the dossier", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  path <- tempfile(fileext = ".qmd")
  out <- tf_render_report(theory, path)
  expect_identical(out, path)
  expect_true(file.exists(out))

  text <- tf_read_golden(out)
  # YAML header with title, format, engine and reader.
  expect_match(text, "^---\\ntitle: ", perl = TRUE)
  expect_match(text, "\nformat: html\nengine: markdown\nfrom: markdown-raw_html-raw_attribute-raw_tex\n---\n\n",
               fixed = TRUE)
  # The body is the dossier, line for line, with its text escaped.
  body <- strsplit(text, "\n", fixed = TRUE)[[1L]][-(1:7)]
  expect_identical(length(body), length(strsplit(tf_dossier(theory), "\n", fixed = TRUE)[[1L]]))
  expect_true("- Theory ID\\: panic\\-network\\-2026" %in% body)
})

test_that("tf_render_report writes the golden report of each fixture", {
  # The Python twin wrote the goldens, so the two twins write one file.
  for (cs in list(c("panic-network.theory.yaml", "panic-network-2026"),
                  c("panic-network-2026-v2.theory.yaml", "panic-network-2026-v2"),
                  c("modality-switching.theory.yaml", "modality-switching-2026"),
                  c("weak-theory.theory.yaml", "weak-demo"))) {
    out <- tf_render_report(tf_read(tf_fixture_path(cs[[1L]])), tempfile(fileext = ".qmd"))
    expect_identical(tf_read_golden(out), tf_read_golden(tf_expected_path(paste0(cs[[2L]], ".dossier.qmd"))))
  }
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
  # R refuses Unicode and octal escapes in one literal, hence the paste0(). The
  # é and U+0085 come from intToUtf8(), since R's parser garbles them, written
  # as one literal, in a Latin-9 session.
  title <- paste0("Effects of A\\B on \"C\": \\emph{fluency}, $\\alpha$\nline\ttwo\001\177",
                  intToUtf8(c(0xE9L, 0x85L)))
  out <- tf_render_report(theory, tempfile(fileext = ".qmd"), title = title)
  lines <- strsplit(readChar(out, file.info(out)$size, useBytes = TRUE), "\n", fixed = TRUE)[[1L]]
  # The file is UTF-8 whatever the session's charset, and yaml.load() reads an
  # unmarked string in that charset.
  Encoding(lines) <- "UTF-8"
  expected <- paste0(
    'title: "Effects of A\\\\B on \\"C\\": \\\\emph{fluency}, $\\\\alpha$',
    '\\nline\\ttwo\\x01\\x7Fé\\x85"'
  )
  got <- lines[[2L]]
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
    # The id is escaped as Markdown text, and the backslash then for YAML.
    expect_match(text, 'title: "theoryforge report: the\\\\-id"', fixed = TRUE)
  }
})

# A theory whose ids, label, statement, date and registration hold line
# breaks, code fences, knitr and Jupyter chunks, inline R code, YAML header
# lines, a shortcode, a link and a span with an event handler. It validates
# and passes the gate, and rendering its report ran the chunks. The Python
# twin's test_osf_report.py reads the same text.
hostile_theory <- function() {
  path <- tempfile(fileext = ".yaml")
  writeBin(charToRaw(r"---(schema_version: "1.1"
id: |-
  edge-markdown-injection
  ```{r}
  writeLines("ran", "PWNED.txt")
  ```
  ---
  engine: knitr
  ---
title: "Injection `r writeLines('ran', 'PWNED.txt')` {{< env HOME >}} <b>bold</b>"
maturity: developing
constructs:
  - id: c_a
    label: |-
      Arousal `r 1 + 1`
      ---
      title: injected
    definition: First construct.
  - id: c_b
    label: Threat
    definition: Second construct.
  - id: "r writeLines('ran', 'PWNED.txt')"
    label: Avoidance
    definition: Third construct.
propositions:
  - id: "p1\n```{python}\nopen('PWNED.txt', 'w')\n```"
    from: c_a
    to: c_b
    relation: increases
  - id: p2
    from: c_b
    to: "r writeLines('ran', 'PWNED.txt')"
    relation: increases
predictions:
  - id: "h1\n```{r}\nstop('ran')\n```"
    derives_from: ["p1\n```{python}\nopen('PWNED.txt', 'w')\n```"]
    statement: |-
      Arousal raises threat.
      ```{r}
      stop("ran")
      ```
      ---
      `{r} 1 + 1` and [link](javascript:alert(1)){onmouseover="alert(2)"}
    type: directional
test_outcomes:
  - prediction_id: "h1\n```{r}\nstop('ran')\n```"
    passed: true
    date: "2026-05-01\n---"
    registered: "osf.io/abcde\n```{r}\nstop('ran')\n```\n{{< include secret.txt >}}"
)---"), path)
  t <- tf_read(path)
  expect_true(tf_validate(t))
  expect_identical(tf_check(t)$gate, "pass")
  t
}

fence_lines <- function(lines) {
  lines[grepl("^[\t >]*(```|~~~)|^ {0,3}(```|~~~)", lines) | lines == "---"]
}

test_that("tf_dossier and tf_preregister write every value on one line", {
  t <- hostile_theory()
  for (doc in list(tf_dossier(t), tf_preregister(t))) {
    lines <- strsplit(doc, "\n", fixed = TRUE)[[1L]]
    expect_identical(fence_lines(lines), character(0))
    expect_true(paste0("- Theory ID: edge-markdown-injection ```{r} writeLines(\"ran\", \"PWNED.txt\") ",
                       "``` --- engine: knitr ---") %in% lines)
  }
  prereg <- strsplit(tf_preregister(t), "\n", fixed = TRUE)[[1L]]
  expect_true(paste0("   - Test record: already tested: passed (2026-05-01 ---, registered osf.io/abcde ",
                     "```{r} stop('ran') ``` {{< include secret.txt >}})") %in% prereg)
})

test_that("tf_render_report writes the theory's text as text", {
  # The header runs no engine and reads no raw markup, and the body escapes
  # every punctuation character of the text, so Quarto runs no chunk and
  # expands no shortcode.
  t <- hostile_theory()
  out <- tf_render_report(t, tempfile(fileext = ".qmd"))
  lines <- strsplit(tf_read_golden(out), "\n", fixed = TRUE)[[1L]]
  expect_identical(lines[c(1L, 3:6)], c("---", "format: html", "engine: markdown",
                                        "from: markdown-raw_html-raw_attribute-raw_tex", "---"))
  expect_identical(yaml::yaml.load(lines[[2L]])$title, paste0(
    r"---(theoryforge report: Injection &#96;r writeLines\(\'ran\'\, \'PWNED\.txt\'\)&#96; )---",
    r"---(\{\{\{\< env HOME \>\}\}\} \<b\>bold\<\/b\>)---"))
  body <- lines[-(1:7)]
  expect_identical(length(body), length(strsplit(tf_dossier(t), "\n", fixed = TRUE)[[1L]]))
  expect_identical(fence_lines(body), character(0))
  expect_false(any(grepl("`", body, fixed = TRUE) | grepl("{{<", body, fixed = TRUE) |
                     grepl("](", body, fixed = TRUE)))
  theory_id <- paste0(r"---(- Theory ID\: edge\-markdown\-injection &#96;&#96;&#96;\{r\} )---",
                      r"---(writeLines\(\"ran\"\, \"PWNED\.txt\"\) &#96;&#96;&#96; \-\-\- engine\: knitr \-\-\-)---")
  expect_identical(sum(body == theory_id), 2L)
  expect_true(r"---(- c\_a \_\|\|\_ r writeLines\(\'ran\'\, \'PWNED\.txt\'\) \| c\_b)---" %in% body)
  expect_true(paste0(r"---(   - Test record\: already tested\: passed \(2026\-05\-01 \-\-\-\, registered )---",
                     r"---(osf\.io\/abcde &#96;&#96;&#96;\{r\} stop\(\'ran\'\) &#96;&#96;&#96; )---",
                     r"---(\{\{\< include secret\.txt \>\}\}\))---") %in% body)
  expect_true("_No alternative states propositions\\._" %in% body)
  expect_true("| item | criterion | status | score | weight |" %in% body)
})

test_that("tf_render_report refuses a format that is not a name", {
  # A format was written into the header and passed to the shell as it stood.
  # The Python twin pins the same message.
  for (to in c("html; echo ran > ran.txt", "html\nengine: knitr", "-o", "", "pdf ")) {
    path <- tempfile(fileext = ".qmd")
    expect_error(tf_render_report(tf_theory("t", "T"), path, to = to),
                 paste0("render_report requires `to` to be a Quarto format name of letters, digits, ",
                        "'_', '+' and '-' that starts with a letter or digit, not '", to, "'"),
                 fixed = TRUE)
    expect_false(file.exists(path))
  }
  expect_error(tf_render_report(tf_theory("t", "T"), tempfile(), to = NULL), "not NULL$")
  expect_error(tf_render_report(tf_theory("t", "T"), tempfile(), to = c("html", "pdf")),
               'not c("html", "pdf")', fixed = TRUE)
  for (to in c("pdf", "gfm+tex_math_dollars", "acm-pdf")) {
    out <- tf_render_report(tf_theory("t", "T"), tempfile(), to = to)
    expect_identical(strsplit(tf_read_golden(out), "\n", fixed = TRUE)[[1L]][[3L]],
                     paste0("format: ", to))
  }
})

test_that("tf_render_report quotes each argument it hands the shell", {
  skip_on_os("windows")
  skip_on_cran()
  # A stand-in for quarto that writes the arguments it was given.
  bin <- tempfile("bin")
  dir.create(bin)
  args_file <- file.path(bin, "args.txt")
  writeLines(c("#!/bin/sh", sprintf("printf '%%s\\n' \"$@\" > '%s'", args_file)),
             file.path(bin, "quarto"))
  Sys.chmod(file.path(bin, "quarto"), "0755")
  old <- Sys.getenv("PATH")
  on.exit(Sys.setenv(PATH = old), add = TRUE)
  Sys.setenv(PATH = paste(bin, old, sep = .Platform$path.sep))
  dir <- tempfile("a dir with 'quotes'")
  dir.create(dir)
  path <- tf_render_report(tf_theory("t", "T"), file.path(dir, "r.qmd"), render = TRUE, to = "pdf")
  expect_identical(readLines(args_file), c("render", path, "--to", "pdf"))
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
  expect_error(tf_render_diagram(th, "no_such_view"), "unknown diagram type 'no_such_view'; ",
               fixed = TRUE)
  # NULL stopped with "argument is of length zero" before the message.
  expect_error(tf_render_diagram(th, NULL), "unknown diagram type NULL; ", fixed = TRUE)
})

test_that("the report path ends in .qmd by the rule Python follows", {
  # test_osf_report.py checks the same pairs against Python's _qmd_path().
  pairs <- c("report.md" = "report.qmd", "report" = "report.qmd", ".hidden" = ".hidden.qmd",
             "a.tar.gz" = "a.tar.qmd", "d/x.QMD" = "d/x.QMD", "d.v/report" = "d.v/report.qmd",
             "report." = "report.qmd", "report.my-file" = "report.qmd")
  expect_identical(vapply(names(pairs), .tf_qmd_path, character(1), USE.NAMES = FALSE),
                   unname(pairs))
})
