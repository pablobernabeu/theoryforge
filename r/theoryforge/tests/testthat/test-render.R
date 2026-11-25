test_that("tf_render_report writes a .qmd containing the dossier", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  path <- tempfile(fileext = ".qmd")
  out <- tf_render_report(theory, path)
  expect_identical(out, path)
  expect_true(file.exists(out))

  text <- tf_read_golden(out)
  # YAML header with title, format, engine and reader.
  expect_match(text, "^---\\ntitle: ", perl = TRUE)
  expect_match(text, paste0("\nformat: html\nengine: markdown\nojs-engine: false\nhtml-math-method: plain\n",
                            "from: markdown-raw_html-raw_attribute-raw_tex\n",
                            "menu:\n  title-selector: \"\"\n---\n\n"),
               fixed = TRUE)
  # The body is the dossier, line for line, with its text escaped.
  body <- strsplit(text, "\n", fixed = TRUE)[[1L]][-(1:11)]
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
# lines, a shortcode, a link and a span with an event handler. Its scope
# holds the form in which Quarto encodes {{< env HOME >}}, which is left out
# unless `encoded` is TRUE. It validates and passes the gate, and rendering its
# report ran the chunks. The Python twin's test_osf_report.py reads the same
# text.
encoded_shortcode <- "b58fc729-690b-4000-b19f-365a4093b2ff;7B7B3C20656E7620484F4D45203E7D7D;"

hostile_theory <- function(encoded = FALSE) {
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
boundary_conditions:
  - "b58fc729-690b-4000-b19f-365a4093b2ff;7B7B3C20656E7620484F4D45203E7D7D;"
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
  if (!encoded) t$boundary_conditions <- NULL
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
  # every punctuation character of the text but the quotation marks, so
  # Quarto runs no chunk and expands no shortcode.
  t <- hostile_theory()
  out <- tf_render_report(t, tempfile(fileext = ".qmd"))
  lines <- strsplit(tf_read_golden(out), "\n", fixed = TRUE)[[1L]]
  expect_identical(lines[c(1L, 3:10)], c("---", "format: html", "engine: markdown", "ojs-engine: false",
                                         "html-math-method: plain",
                                         "from: markdown-raw_html-raw_attribute-raw_tex", "menu:",
                                         '  title-selector: ""', "---"))
  expect_identical(yaml::yaml.load(lines[[2L]])$title, paste0(
    r"---(theoryforge report: Injection &#96;r writeLines\('ran'\, 'PWNED\.txt'\)&#96; )---",
    r"---(\{\{\{\< env HOME \>\}\}\} \<b\>bold\<\/b\>)---"))
  body <- lines[-(1:11)]
  expect_identical(length(body), length(strsplit(tf_dossier(t), "\n", fixed = TRUE)[[1L]]))
  # The dossier's title has a fixed identifier, so that no script reads one
  # made from the theory's title.
  expect_true(startsWith(body[[1L]], "# theoryforge dossier\\: Injection "))
  expect_true(endsWith(body[[1L]], " {#theoryforge-dossier}"))
  expect_identical(fence_lines(body), character(0))
  expect_false(any(grepl("`", body, fixed = TRUE) | grepl("{{<", body, fixed = TRUE) |
                     grepl("](", body, fixed = TRUE)))
  theory_id <- paste0(r"---(- Theory ID\: edge\-markdown\-injection &#96;&#96;&#96;\{r\} )---",
                      r"---(writeLines\("ran"\, "PWNED\.txt"\) &#96;&#96;&#96; \-\-\- engine\: knitr \-\-\-)---")
  expect_identical(sum(body == theory_id), 2L)
  expect_true(r"---(- c\_a \_\|\|\_ r writeLines\('ran'\, 'PWNED\.txt'\) \| c\_b)---" %in% body)
  expect_true(paste0(r"---(   - Test record\: already tested\: passed \(2026\-05\-01 \-\-\-\, registered )---",
                     r"---(osf\.io\/abcde &#96;&#96;&#96;\{r\} stop\('ran'\) &#96;&#96;&#96; )---",
                     r"---(\{\{\< include secret\.txt \>\}\}\))---") %in% body)
  expect_true("_No alternative states propositions\\._" %in% body)
  expect_true("| item | criterion | status | score | weight |" %in% body)
})

test_that("tf_render_report keeps the code span of a plain implied independence", {
  # An implied conditional independence of ordinary construct ids opens
  # nothing in a code span, so it keeps the span. The Python twin pins the
  # same lines.
  out <- tf_render_report(tf_read(tf_fixture_path("modality-switching.theory.yaml")), tempfile())
  lines <- strsplit(tf_read_golden(out), "\n", fixed = TRUE)[[1L]]
  expect_true("- `c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation`" %in% lines)
  t <- tf_theory("t", "T")
  for (cid in c("r x", "a", "b", "c")) t <- tf_add_construct(t, cid, toupper(cid), "A construct.")
  t <- tf_add_proposition(t, "p1", "a", "b", "causes")
  t <- tf_add_proposition(t, "p2", "b", "c", "causes")
  t <- tf_add_proposition(t, "p3", "r x", "b", "causes")
  body <- strsplit(tf_read_golden(tf_render_report(t, tempfile())), "\n", fixed = TRUE)[[1L]]
  expect_true("- `a _||_ c | b`" %in% body)
  # A text that begins with 'r ' could be knitr's inline code.
  expect_true(r"---(- r x \_\|\|\_ a)---" %in% body)
  expect_true(r"---(- r x \_\|\|\_ c \| b)---" %in% body)
})

test_that("tf_render_report refuses text that Quarto reads as an encoded shortcode", {
  # Quarto's reader decodes such a run and runs the shortcode once Pandoc has
  # removed the escapes, so it leaked environment values and passed on a
  # script. The Python twin pins the same messages.
  message <- paste0("render_report refuses text that Quarto reads as an encoded shortcode: '",
                    encoded_shortcode, "'")
  path <- tempfile(fileext = ".qmd")
  expect_error(tf_render_report(hostile_theory(encoded = TRUE), path), message, fixed = TRUE)
  expect_false(file.exists(path))
  for (field in c("id", "title", "label", "registered")) {
    t <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
    if (identical(field, "label")) {
      t$constructs[[1L]]$label <- paste("x", encoded_shortcode)
    } else if (identical(field, "registered")) {
      t$test_outcomes[[1L]]$registered <- paste0("osf.io/x\n", encoded_shortcode)
    } else {
      t[[field]] <- paste("x", encoded_shortcode)
    }
    expect_error(tf_render_report(t, path), message, fixed = TRUE)
    expect_false(file.exists(path))
  }
  # Any UUID counts, in either letter case.
  panic <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  other <- "0A1B2C3D-0000-4000-8000-00000000ABCD;41;"
  scoped <- function(value) {
    t <- panic
    t$boundary_conditions <- list(value)
    t
  }
  expect_error(tf_render_report(scoped(other), path),
               paste0("encoded shortcode: '", other, "'"), fixed = TRUE)
  # Without the closing semicolon nothing is decoded, and the report is written.
  expect_true(file.exists(tf_render_report(scoped(sub(";$", "", encoded_shortcode)), path)))
})

# modality-switching with a construct id that holds 'ojs_define', which turned
# on Quarto's OJS compiler, a title with an OJS expression and a tag, which the
# slide menu of revealjs wrote back as HTML, and a label with TeX that MathJax,
# which revealjs ran over every slide, made a javascript: link of. The Python
# twin builds the same theory.
ojs_theory <- function() {
  text <- readLines(tf_fixture_path("modality-switching.theory.yaml"), encoding = "UTF-8")
  text <- gsub("c_lexical_familiarity", "c_ojs_define", text, fixed = TRUE)
  first <- grep("^title: ", text)[[1L]]
  text[[first]] <- 'title: "Modality ${alert(1)} <img src=x onerror=alert(2)>"'
  label <- grep("^    label: ", text)[[1L]]
  text[[label]] <- r"(    label: '\(\href{javascript:alert(3)}{x}\)')"
  path <- tempfile(fileext = ".yaml")
  writeBin(charToRaw(enc2utf8(paste0(paste(text, collapse = "\n"), "\n"))), path)
  tf_read(path)
}

test_that("tf_render_report keeps ojs_define out of the text Quarto reads", {
  # Quarto turns on its OJS compiler when 'ojs_define' is anywhere in the text
  # it reads, and the code span of a plain implied independence kept the
  # construct id as it stood. The Python twin pins the same text.
  text <- tf_read_golden(tf_render_report(ojs_theory(), tempfile()))
  expect_false(grepl("ojs_define", text, fixed = TRUE))
  expect_match(text, "\nojs-engine: false\nhtml-math-method: plain\n", fixed = TRUE)
  expect_match(text, '\nmenu:\n  title-selector: ""\n', fixed = TRUE)
  expect_true(r"---(- c\_sensorimotor\_experience \_\|\|\_ c\_ojs\_define)---" %in%
                strsplit(text, "\n", fixed = TRUE)[[1L]])
})

test_that("Quarto renders the hostile reports as text in html, revealjs and dashboard", {
  skip_on_cran()
  skip_if(!nzchar(Sys.which("quarto")), "Quarto is not installed")
  # Rendered through Quarto, the report runs no code, compiles no OJS, loads
  # no MathJax, expands no shortcode and passes on no script, event handler or
  # link of the theory's. revealjs is told to take its menu titles from the
  # escaped text.
  dir <- tempfile("quarto")
  dir.create(dir)
  writeLines("SECRET-FILE-CONTENTS", file.path(dir, "secret.txt"))
  old <- Sys.getenv("TF_SECRET_TOKEN", NA)
  on.exit(if (is.na(old)) Sys.unsetenv("TF_SECRET_TOKEN") else Sys.setenv(TF_SECRET_TOKEN = old),
          add = TRUE)
  Sys.setenv(TF_SECRET_TOKEN = "s3cr3t-env-value")
  wd <- setwd(dir)
  on.exit(setwd(wd), add = TRUE)
  theories <- list(hostile = hostile_theory(), ojs = ojs_theory())
  for (to in c("html", "revealjs", "dashboard")) {
    for (name in names(theories)) {
      tf_render_report(theories[[name]], paste0(name, "-", to, ".qmd"), render = TRUE, to = to)
      html <- tf_read_golden(file.path(dir, paste0(name, "-", to, ".html")))
      expect_length(Sys.glob(file.path(dir, "PWNED*")), 0L)
      for (leaked in c("s3cr3t-env-value", "SECRET-FILE-CONTENTS", path.expand("~"))) {
        expect_false(grepl(leaked, html, fixed = TRUE))
      }
      for (live in c("ojs-element-id", "ojs-module-contents", "quarto-ojs-runtime", "<script>alert",
                     '<img src="x"', "<b>", "RevealMath")) {
        expect_false(grepl(live, html, fixed = TRUE))
      }
      expect_false(grepl("mathjax", tolower(html), fixed = TRUE))
      expect_true(grepl('id="theoryforge-dossier"', html, fixed = TRUE))
      expect_false(grepl("<[a-zA-Z][^>]*\\son[a-z]+\\s*=", html, perl = TRUE))
      expect_false(grepl("(?:href|src)\\s*=\\s*[\"']?\\s*javascript:", html, perl = TRUE))
      if (identical(to, "revealjs")) expect_true(grepl('"titleSelector":""', html, fixed = TRUE))
    }
  }
})

test_that("tf_render_report refuses a format that is not a name or a writer", {
  # A format was written into the header and passed to the shell as it stood.
  # The Python twin pins the same message.
  for (to in c("html; echo ran > ran.txt", "html\nengine: knitr", "-o", "", "pdf ", ".lua")) {
    path <- tempfile(fileext = ".qmd")
    expect_error(tf_render_report(tf_theory("t", "T"), path, to = to),
                 paste0("render_report requires `to` to be a Quarto format or writer of letters, ",
                        "digits, '_', '.', '+', '/' and '-' that starts with a letter or digit, not '",
                        to, "'"),
                 fixed = TRUE)
    expect_false(file.exists(path))
  }
  expect_error(tf_render_report(tf_theory("t", "T"), tempfile(), to = NULL), "not NULL$")
  expect_error(tf_render_report(tf_theory("t", "T"), tempfile(), to = c("html", "pdf")),
               'not c("html", "pdf")', fixed = TRUE)
  for (to in c("pdf", "gfm+tex_math_dollars", "acm-pdf", "plainw.lua", "writers/plain.lua")) {
    out <- tf_render_report(tf_theory("t", "T"), tempfile(), to = to)
    expect_identical(strsplit(tf_read_golden(out), "\n", fixed = TRUE)[[1L]][[3L]],
                     paste0("format: ", to))
  }
})

test_that("tf_render_report quotes, expands and makes absolute the path it hands the shell", {
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
  expect_identical(readLines(args_file), c("render", normalizePath(path), "--to", "pdf"))
  # The shell does not expand a quoted ~, and Quarto read a path beginning with
  # - as an option, rendered nothing and exited with status 0.
  home <- Sys.getenv("HOME")
  on.exit(Sys.setenv(HOME = home), add = TRUE)
  Sys.setenv(HOME = dir)
  expect_identical(tf_render_report(tf_theory("t", "T"), "~/home", render = TRUE), "~/home.qmd")
  expect_identical(readLines(args_file),
                   c("render", normalizePath(file.path(dir, "home.qmd")), "--to", "html"))
  wd <- setwd(dir)
  on.exit(setwd(wd), add = TRUE)
  expect_identical(tf_render_report(tf_theory("t", "T"), "-dash", render = TRUE), "-dash.qmd")
  expect_identical(readLines(args_file),
                   c("render", normalizePath(file.path(dir, "-dash.qmd")), "--to", "html"))
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
