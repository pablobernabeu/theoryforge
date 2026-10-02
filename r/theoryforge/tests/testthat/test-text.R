# Text normalisation shared with the Python twin (API_SPEC.md sections 3, 6, 18
# and 19): one whitespace set, ASCII-only case folding, the fold table in
# schema/fold.json and the DOI normaliser. test_text_normalisation.py holds the
# same cases for Python. Non-ASCII text is written with \u escapes, so the file
# reads the same in every locale; the NFD forms were produced with Python's
# unicodedata.normalize("NFD", ...).

# Unicode's White_Space property: 25 code points.
.ws_code_points <- c(0x09:0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000:0x200A,
                     0x2028, 0x2029, 0x202F, 0x205F, 0x3000)

.text_theory <- function(constructs = list(), propositions = list(),
                         provenance = list()) {
  list(schema_version = "1.0", id = "t", title = "T", maturity = "building",
       constructs = constructs, propositions = propositions,
       provenance = provenance)
}

.item <- function(rep, id) {
  for (it in rep$items) if (identical(it$id, id)) return(it)
  NULL
}

# -- whitespace ----------------------------------------------------------------

test_that("the whitespace set is Unicode's White_Space", {
  ne_str <- theoryforge:::.tf_ne_str
  expect_length(.ws_code_points, 25L)
  for (cp in .ws_code_points) {
    ch <- intToUtf8(cp)
    expect_false(ne_str(ch), info = sprintf("U+%04X", cp))
    expect_false(ne_str(paste0(" ", ch, "\t")), info = sprintf("U+%04X", cp))
  }
  # Format characters and the separators Python's str.isspace() adds are text.
  for (cp in c(0x200B, 0xFEFF, 0x180E, 0x1C, 0x1D, 0x1E, 0x1F)) {
    expect_true(ne_str(intToUtf8(cp)), info = sprintf("U+%04X", cp))
  }
})

test_that("a lone no-break space is an empty definition", {
  t <- .text_theory(list(list(id = "a", label = "A", definition = "\u00a0")))
  expect_error(tf_validate(t), "construct\\[0\\] missing/empty definition")
})

test_that("an information separator is text to tf_validate()", {
  # trimws() and str.strip() disagree on U+001C-001F; the whitespace set keeps them.
  t <- .text_theory(list(list(id = "a", label = "A", definition = "\u001c")))
  t$title <- "\u001f"
  expect_true(tf_validate(t))
})

test_that("a lone no-break space is no mechanism", {
  t <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  for (i in seq_along(t$propositions)) t$propositions[[i]]$mechanism <- "\u00a0"
  it <- .item(tf_check(t), "logical_why")
  expect_identical(it$status, "warn")
  expect_equal(it$score, 0)
})

test_that("a whitespace provenance detail is left out", {
  t <- .text_theory(provenance = list(
    list(step = "1", action = "tf_construct", detail = "\u00a0\u3000")))
  expect_true(grepl('"n1" [label="tf_construct"];', tf_diagram(t, "provenance"),
                    fixed = TRUE))
  expect_true(grepl("\n1. tf_construct\n", tf_dossier(t), fixed = TRUE))
})

# -- the fold table and tokens --------------------------------------------------

test_that("tf_tokens folds accented Latin letters", {
  expect_setequal(tf_tokens("na\u00efve r\u00f4le \u00e9lan caf\u00e9 M\u00fcller"),
                  c("naive", "role", "elan", "cafe", "muller"))
  expect_setequal(tf_tokens("\u00c9motion r\u00e9gulation"), c("emotion", "regulation"))
  expect_setequal(tf_tokens("Stra\u00dfe \u00c6r\u00f8 \u0152uvre \u00deorn"),
                  c("strasse", "aero", "oeuvre", "thorn"))
})

test_that("tf_tokens lowercases ASCII only", {
  expect_setequal(tf_tokens("\u0130stanbul D\u0130KKAT"), c("istanbul", "dikkat"))
  expect_equal(tf_jaccard(tf_tokens("\u0130stanbul arousal level measure."),
                          tf_tokens("istanbul arousal level measure.")), 1)
})

test_that("NFD and NFC input give the same tokens", {
  pairs <- list(
    c("\u00c9motion r\u00e9gulation of na\u00efve appraisal",
      "E\u0301motion re\u0301gulation of nai\u0308ve appraisal"),
    c("\u00c5ngstr\u00f6m \u0176 \u01d6 Vi\u1ec7t Nam",
      "A\u030angstro\u0308m Y\u0302 u\u0308\u0304 Vie\u0323\u0302t Nam"),
    c("\u0419\u043e\u0434 \u0438 \u0451\u043b\u043a\u0430",
      "\u0418\u0306\u043e\u0434 \u0438 \u0435\u0308\u043b\u043a\u0430"),
    c("\u039f\u0394\u038c\u03a3 \u1f00\u03c1\u03c7\u03ae \u1f85\u03b4\u03b7\u03c2",
      "\u039f\u0394\u039f\u0301\u03a3 \u03b1\u0313\u03c1\u03c7\u03b7\u0301 \u03b1\u0314\u0301\u0345\u03b4\u03b7\u03c2")
  )
  for (p in pairs) {
    expect_setequal(tf_tokens(p[[1]]), tf_tokens(p[[2]]))
    expect_gt(length(tf_tokens(p[[1]])), 0L)
  }
})

test_that("tf_tokens keeps every script", {
  expect_setequal(tf_tokens("\u0421\u0442\u0440\u0430\u0445 \u0438 \u0442\u0440\u0435\u0432\u043e\u0433\u0430"),
                  c("\u0441\u0442\u0440\u0430\u0445", "\u0442\u0440\u0435\u0432\u043e\u0433\u0430"))
  sigma <- "\u03bf\u03b4\u03bf\u03c3"
  expect_identical(tf_tokens("\u039f\u0394\u039f\u03a3"), sigma)
  expect_identical(tf_tokens("\u03bf\u03b4\u03cc\u03c2"), sigma)
  expect_identical(tf_tokens("\u0921\u0930 \u091a\u093f\u0902\u0924\u093e"),
                   "\u091a\u093f\u0902\u0924\u093e")
  # Text written without spaces is one token per run, and a run shorter than
  # three code points is dropped.
  expect_identical(tf_tokens("\u60ca\u6050\u969c\u788d \u6050\u60e7"),
                   "\u60ca\u6050\u969c\u788d")
})

test_that("identical Cyrillic definitions are flagged", {
  d <- paste("\u0421\u0442\u0440\u0430\u0445 \u043f\u0435\u0440\u0435\u0434",
             "\u0442\u0435\u043b\u0435\u0441\u043d\u044b\u043c\u0438",
             "\u043e\u0449\u0443\u0449\u0435\u043d\u0438\u044f\u043c\u0438.")
  t <- .text_theory(list(list(id = "a", label = "A", definition = d),
                         list(id = "b", label = "B", definition = d)))
  df <- tf_redundancy_check(t)
  expect_equal(df$similarity, 1)
  expect_identical(df$flag, "review")
})

test_that("an accented word no longer matches its tail", {
  corpus <- list(schema_version = "1.0", id = "c", records = list(
    list(id = "r1", keywords = list("motion perception", "visual motion")),
    list(id = "r2", keywords = list("motion perception", "visual motion"))))
  t <- .text_theory(list(list(id = "e", label = "\u00c9motion", definition = "d")))
  t$title <- "R\u00e9gulation des \u00e9motions"
  themes <- tf_landscape(t, corpus)$themes
  expect_length(themes, 1L)
  expect_false(isTRUE(themes[[1]]$focal))
})

test_that("the fold table is closed, so entries apply in any order", {
  fold <- theoryforge:::tf_fold_table()
  keys <- c(strsplit(fold$old, "")[[1L]], names(fold$multi))
  values <- c(strsplit(fold$new, "")[[1L]], unlist(fold$multi, use.names = FALSE))
  out <- unlist(strsplit(values, ""))
  expect_identical(intersect(out, keys), character(0))
  cps <- utf8ToInt(paste(out, collapse = ""))
  expect_false(any(cps >= 0x300 & cps <= 0x36F))
})

# -- tf_compile_sem -------------------------------------------------------------

test_that("tf_compile_sem folds measurement labels", {
  t <- .text_theory(list(
    list(id = "a", label = "A", definition = "d",
         measurement = list("M\u00fcller scale", "M\u00f6ller scale")),
    list(id = "b", label = "B", definition = "d",
         measurement = list("\u0130nterview score", "\u0421\u0442\u0440\u0430\u0445"))))
  sem <- tf_compile_sem(t)
  expect_true(grepl("a =~ muller_scale + moller_scale\n", sem, fixed = TRUE))
  # lavaan names stay ASCII, so a label in another script falls back to "x".
  expect_true(grepl("b =~ interview_score + x\n", sem, fixed = TRUE))
})

# -- tf_new_evidence_dois -------------------------------------------------------

.doi_variants <- c(
  "doi: 10.1016/j.brat.2015.10.002",
  "DOI: 10.1016/j.brat.2015.10.002",
  "DOI 10.1016/j.brat.2015.10.002",
  "doi.org/10.1016/j.brat.2015.10.002",
  "dx.doi.org/10.1016/j.brat.2015.10.002",
  "https://www.doi.org/10.1016/j.brat.2015.10.002",
  "info:doi/10.1016/j.brat.2015.10.002",
  "urn:doi:10.1016/j.brat.2015.10.002",
  "https://doi.org/10.1016%2Fj.brat.2015.10.002",
  "https://doi.org/10.1016/0005-7967%2886%2990011-2",
  "10.1016/j.brat.2015.10.002.",
  "10.1016/J.BRAT.2015.10.002\u00a0",
  "\u200910.1016/j.brat.2015.10.002\u3000"
)

test_that("DOI variants count as already cited", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  for (doi in .doi_variants) {
    expect_identical(tf_new_evidence_dois(theory, doi), character(0), info = doi)
  }
})

test_that("the DOI normaliser keeps what is not a DOI pattern", {
  t <- tf_theory("t", "T")
  # Too few registrant digits for the pattern: the 0.6.0 prefix rule applies,
  # and the remainder is trimmed again.
  expect_identical(tf_new_evidence_dois(t, "10.1/x"), "10.1/x")
  t$evidence <- list(list(supports = "h", source_doi = "doi: 10.1/x"))
  expect_identical(tf_new_evidence_dois(t, c("10.1/x", "DOI:10.1/X")), character(0))
  # Escapes outside printable ASCII stay encoded, and parentheses are kept.
  t2 <- tf_theory("t", "T")
  t2$evidence <- list(list(supports = "h", source_doi = "10.1000/a%20b(1)"))
  expect_identical(tf_new_evidence_dois(t2, c("10.1000/A%20B(1)", "10.1000/a b(1)")),
                   "10.1000/a b(1)")
})

test_that("the DOI golden is unchanged by the longer candidate list", {
  theory <- tf_read(tf_fixture_path("panic-network.theory.yaml"))
  base <- c("10.1016/j.brat.2015.10.002", "https://doi.org/10.1016/0005-7967(86)90011-2",
            "10.1176/AJP.146.2.148", "10.1037/0033-2909.99.1.20", "10.1037/0033-2909.99.1.20",
            "10.1016/j.cpr.2011.09.005")
  golden <- jsonlite::fromJSON(tf_expected_path("panic-network-2026.new_evidence_dois.json"))
  expect_identical(tf_new_evidence_dois(theory, c(base, .doi_variants)), golden)
})
