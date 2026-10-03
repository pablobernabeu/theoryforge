# One reading of a file in both twins (API_SPEC.md section 3, "Reading and
# writing files"). The Python suite (test_io.py) reads the same documents and
# asserts the same values.

io_file <- function(text, ext = ".yaml", bom = FALSE) {
  path <- tempfile(fileext = ext)
  bytes <- charToRaw(enc2utf8(text))
  if (bom) bytes <- c(as.raw(c(0xef, 0xbb, 0xbf)), bytes)
  writeBin(bytes, path)
  path
}

yn_theory <- 'schema_version: "1.0"
id: yn-ids
title: Constructs named X, M, Y, y and n
maturity: building
constructs:
  - id: X
    label: Exposure
    definition: The exposure.
  - id: M
    label: Mediator
    definition: The mediator.
  - id: Y
    label: Outcome
    definition: The outcome.
  - id: y
    label: Lower-case y
    definition: A construct whose id YAML 1.1 reads as true.
  - id: n
    label: Lower-case n
    definition: A construct whose id YAML 1.1 reads as false.
propositions:
  - id: p1
    from: X
    to: M
    relation: increases
  - id: p2
    from: M
    to: Y
    relation: increases
'

test_that("y and n stay strings", {
  theory <- tf_read(io_file(yn_theory))
  ids <- vapply(theory$constructs, function(c) c$id, character(1))
  expect_identical(ids, c("X", "M", "Y", "y", "n"))
  expect_identical(theory$propositions[[2]]$to, "Y")
  expect_true(tf_validate(theory, full = TRUE))
})

merge_theory <- 'schema_version: "1.0"
id: merge-key
title: A construct merged from another
maturity: building
constructs:
  - &base
    id: c1
    label: Shared label
    definition: A construct whose fields a second one reuses.
  - <<: *base
    id: c2
'

test_that("a merge key lets the explicit key win", {
  theory <- tf_read(io_file(merge_theory))
  ids <- vapply(theory$constructs, function(c) c$id, character(1))
  expect_identical(ids, c("c1", "c2"))
  expect_identical(theory$constructs[[2]], list(
    id = "c2", label = "Shared label",
    definition = "A construct whose fields a second one reuses."
  ))
  expect_true(tf_validate(theory, full = TRUE))
})

merge_order <- "a: &a {p: 1, q: 1}
b: &b {p: 2, r: 2}
item:
  s: 0
  <<: [*a, *b]
  q: 3
twice:
  <<: *a
  <<: *b
"

test_that("merged keys follow the explicit ones and the first merge wins", {
  d <- tf_read(io_file(merge_order))
  expect_identical(d$item, list(s = 0L, q = 3L, p = 1L, r = 2L))
  expect_identical(d$twice, list(p = 1L, q = 1L, r = 2L))
})

date_theory <- 'schema_version: "1.0"
id: unquoted-date
title: A test outcome dated without quotes
maturity: testing
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct.
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1]
test_outcomes:
  - prediction_id: h1
    passed: true
    registered: 2026-04-01
    date: 2026-05-01
'

test_that("an unquoted date stays a string and writes to JSON", {
  theory <- tf_read(io_file(date_theory))
  expect_identical(theory$test_outcomes[[1]]$date, "2026-05-01")
  expect_identical(theory$test_outcomes[[1]]$registered, "2026-04-01")
  out <- tempfile(fileext = ".json")
  tf_write(theory, out)
  expect_identical(tf_read(out), theory)
})

test_that("a byte-order mark is ignored", {
  panic <- tf_fixture_path("panic-network.theory.yaml")
  plain <- tf_read(panic)
  yaml_bom <- io_file(tf_read_golden(panic), bom = TRUE)
  expect_warning(from_yaml <- tf_read(yaml_bom), NA)
  expect_identical(from_yaml, plain)
  json_text <- as.character(jsonlite::toJSON(plain, auto_unbox = TRUE, digits = NA, null = "null"))
  json_bom <- io_file(json_text, ext = ".json", bom = TRUE)
  # jsonlite warned "JSON string contains (illegal) UTF8 byte-order-mark!".
  expect_warning(from_json <- tf_read(json_bom), NA)
  expect_identical(from_json$id, plain$id)
  expect_identical(length(from_json$predictions), length(plain$predictions))
})

test_that("a missing final newline reads the same, without a warning", {
  panic <- tf_fixture_path("panic-network.theory.yaml")
  text <- sub("\n+$", "", tf_read_golden(panic))
  expect_warning(theory <- tf_read(io_file(text)), NA)
  expect_identical(theory, tf_read(panic))
})

dup_top <- 'schema_version: "1.0"
id: dup-top
title: Two predictions blocks
maturity: building
predictions:
  - id: h1
    statement: The first block.
    type: directional
predictions:
  - id: h2
    statement: The second block.
    type: directional
'

dup_item <- 'schema_version: "1.0"
id: dup-item
title: A construct defined twice
maturity: building
constructs:
  - id: c1
    label: Alpha
    definition: The first definition.
    definition: The second definition.
'

dup_json <- paste0('{"schema_version": "1.0", "id": "dup-json", "title": "A title",',
                   ' "maturity": "building", "title": "Another title"}')

# A repeated top-level key that comes first in the text and a repeated item key
# after it. Each mapping is checked as it closes, and the item closes before the
# document does, so the item key is the one reported.
dup_nested <- "id: first
id: second
constructs:
  - id: c1
    label: Alpha
    label: Beta
"

test_that("a duplicate key is refused with one message in YAML and JSON", {
  cases <- list(
    list(dup_top, ".yaml", "predictions"),
    list(dup_item, ".yaml", "definition"),
    list(dup_json, ".json", "title"),
    list(dup_nested, ".yaml", "label")
  )
  for (case in cases) {
    path <- io_file(case[[1]], ext = case[[2]])
    expect_error(tf_read(path), sprintf("(%s) Duplicate map key: '%s'", path, case[[3]]),
                 fixed = TRUE)
  }
})

test_that("a corpus reads through the same reader", {
  corpus <- 'schema_version: "1.0"
id: yn-corpus
records:
  - id: w1
    keywords: [y, n, arousal]
  - id: w2
    keywords: [y, n, arousal]
'
  c <- tf_read_corpus(io_file(corpus))
  expect_identical(c$records[[1]]$keywords, list("y", "n", "arousal"))
  expect_identical(unlist(one_theme(tf_litmap(c))$keywords), c("arousal", "n", "y"))
  expect_error(tf_read_corpus(io_file("id: a\nid: b\n")), "Duplicate map key: 'id'", fixed = TRUE)
})

test_that("an empty sequence is not a theory, and an empty mapping is", {
  expect_error(tf_read(io_file("[]\n")), "Theory data must be a mapping", fixed = TRUE)
  expect_length(tf_read(io_file("{}\n")), 0L)
})

test_that("a YAML sequence is a list, so a one-element enum sequence is refused", {
  text <- sub("maturity: building", "maturity: [draft]", yn_theory, fixed = TRUE)
  text <- sub("relation: increases\n  - id: p2", "relation: [increases]\n  - id: p2", text,
              fixed = TRUE)
  theory <- tf_read(io_file(text))
  expect_identical(theory$maturity, list("draft"))
  expect_error(
    tf_validate(theory),
    paste(
      "invalid theory object: maturity must be a string; maturity must be one of",
      "building, developing, draft, testing; proposition[0] relation must be a string"
    ),
    fixed = TRUE
  )
  shapes <- tf_read(io_file("a: [x]\nb: []\nc: [{d: 1}]\n"))
  expect_identical(shapes, list(a = list("x"), b = list(), c = list(list(d = 1L))))
})

# The scalar table of API_SPEC.md section 3. Each entry is (YAML text, value).
scalar_table <- list(
  # strings, whatever an older YAML resolver would make of them
  list("1:30", "1:30"), list("190:20:30", "190:20:30"), list("1:30.5", "1:30.5"),
  list("1_000", "1_000"), list("1_000.5", "1_000.5"), list("0.1_0", "0.1_0"),
  list("0b101", "0b101"), list("0o17", "0o17"), list("0X1F", "0X1F"), list("1e3", "1e3"),
  list("1e+3", "1e+3"), list("1.0e3", "1.0e3"), list("0.5e3", "0.5e3"), list("08", "08"),
  list("tRUE", "tRUE"), list("2026-05-01", "2026-05-01"),
  list("2026-05-01 10:00:00", "2026-05-01 10:00:00"), list("y", "y"), list("Y", "Y"),
  list("n", "n"), list("N", "N"), list("=", "="), list(".na", ".na"),
  list(".na.real", ".na.real"), list(".na.integer", ".na.integer"),
  list(".na.character", ".na.character"),
  # integers: decimal, octal and hexadecimal only
  list("0x1F", 31L), list("-0x1F", -31L), list("0755", 493L), list("+0755", 493L),
  list("007", 7L), list("+12", 12L),
  # floats, a signed leading dot included
  list("1.0e+3", 1000), list("1.5E-3", 0.0015), list(".5", 0.5), list("-.5", -0.5),
  list("+.5", 0.5), list("1.", 1), list("0.", 0), list(".inf", Inf), list("-.Inf", -Inf),
  list(".nan", NaN),
  # booleans and nulls
  list("yes", TRUE), list("No", FALSE), list("on", TRUE), list("OFF", FALSE),
  list("True", TRUE), list("~", NULL), list("null", NULL), list("Null", NULL),
  # what yaml takes for a number and then cannot convert (it read NA, with a
  # warning): a comma or no digit makes text, and a large integer is a double
  list("1,000", "1,000"), list("0,5", "0,5"), list("1,000.5", "1,000.5"), list(".", "."),
  list("2147483648", 2147483648), list("-2147483649", -2147483649),
  list("0x80000000", 2147483648), list("0777777777777", 68719476735), list("1.0e+400", Inf),
  # read as yaml and Python read it, although as.numeric() and R's own parser
  # put it one unit in the last place away (-527.86795299999994)
  list("-527.867953", -0x1.07ef19157abb9p+9)
)

test_that("the scalar table", {
  text <- paste0(sprintf("k%d: %s\n", seq_along(scalar_table) - 1L,
                         vapply(scalar_table, function(s) s[[1]], character(1))),
                 collapse = "")
  expect_warning(d <- tf_read(io_file(text)), NA)
  for (i in seq_along(scalar_table)) {
    key <- paste0("k", i - 1L)
    expect_true(key %in% names(d), info = scalar_table[[i]][[1]])
    expect_identical(d[[key]], scalar_table[[i]][[2]], info = scalar_table[[i]][[1]])
  }
})

# Serialise a theory the way the parity check compares JSON, so that a written
# and re-read theory can be compared on its content: a list from the reader and
# the character vector a builder holds are the same array here.
io_normalise <- function(x) {
  as.character(jsonlite::toJSON(x, auto_unbox = TRUE, digits = NA, null = "null"))
}

writer_theory <- function() {
  t <- tf_theory("writer-test", "Writer test") |>
    tf_add_construct("c1", "Alpha", "The first construct.", measurement = "m1") |>
    tf_add_construct("c2", "Beta", "The second construct.") |>
    tf_add_proposition("p1", "c1", "c2", "increases") |>
    tf_add_prediction("h1", "Beta rises with Alpha.", "directional", derives_from = "p1") |>
    tf_add_assumption("a1", "Measurement is reliable.", protects = "h1")
  t$predictions[[1]]$severity <- 0.49996
  t$predictions[[1]]$risk_score <- 0.123456789
  t$test_outcomes <- list(list(prediction_id = "h1", passed = TRUE),
                          list(prediction_id = "h1", passed = FALSE))
  t
}

test_that("tf_write keeps numbers, logicals and one-element arrays", {
  theory <- writer_theory()
  for (ext in c(".yaml", ".json")) {
    path <- tempfile(fileext = ext)
    tf_write(theory, path)
    back <- tf_read(path)
    expect_identical(back$predictions[[1]]$severity, 0.49996, info = ext)
    expect_identical(back$predictions[[1]]$risk_score, 0.123456789, info = ext)
    expect_identical(back$test_outcomes[[1]]$passed, TRUE, info = ext)
    expect_identical(back$test_outcomes[[2]]$passed, FALSE, info = ext)
    expect_identical(back$predictions[[1]]$derives_from, list("p1"), info = ext)
    expect_identical(back$auxiliary_assumptions[[1]]$protects, list("h1"), info = ext)
    expect_identical(back$constructs[[1]]$measurement, list("m1"), info = ext)
    expect_identical(io_normalise(back), io_normalise(theory), info = ext)
  }
  yaml_path <- tempfile(fileext = ".yaml")
  tf_write(theory, yaml_path)
  yaml_text <- tf_read_golden(yaml_path)
  expect_true(grepl("passed: true", yaml_text, fixed = TRUE))
  expect_true(grepl("passed: false", yaml_text, fixed = TRUE))
  expect_false(grepl("passed: yes", yaml_text, fixed = TRUE))
  expect_true(grepl("derives_from:\\s*\\n\\s*- p1", yaml_text))
})

test_that("tf_write writes a string array held as one string as an array", {
  # A hand-built theory can hold a one-element character vector where the
  # schema wants an array. jsonlite and yaml both write that as a scalar, which
  # fails the package's own schema, so the writer boxes every such field.
  theory <- writer_theory()
  theory$predictions[[1]]$derives_from <- "p1"
  theory$predictions[[1]]$diagnostic_vs <- "alt1"
  theory$alternatives <- list(list(id = "alt1", label = "Alternative", key_constructs = "c2"))
  theory$constructs[[2]]$boundary_conditions <- "adults"
  theory$boundary_conditions <- "laboratory tasks"
  json <- tempfile(fileext = ".json")
  tf_write(theory, json)
  text <- tf_read_golden(json)
  for (field in c("derives_from", "diagnostic_vs", "key_constructs", "boundary_conditions",
                  "protects", "measurement")) {
    expect_true(grepl(sprintf('"%s": \\[\\s*"', field), text), info = field)
  }
  back <- tf_read(json)
  expect_identical(back$boundary_conditions, list("laboratory tasks"))
  expect_identical(back$constructs[[2]]$boundary_conditions, list("adults"))
  expect_identical(back$alternatives[[1]]$key_constructs, list("c2"))
  expect_identical(back$predictions[[1]]$diagnostic_vs, list("alt1"))
})

test_that("tf_write writes NA as null and numbers with 15 significant digits", {
  # yaml wrote NA as R's own .na forms and jsonlite wrote "NA" for a number,
  # which both readers take for text. yaml's precision counts decimal places,
  # so 15 of them wrote 21.3 as 21.300000000000001.
  theory <- writer_theory()
  theory$predictions[[1]]$severity <- NA_real_
  theory$test_outcomes[[2]]$passed <- NA
  theory$constructs[[1]]$n_items <- NA_integer_
  theory$constructs[[1]]$source <- NA_character_
  theory$constructs[[1]]$scores <- c(0.5, NA)
  theory$constructs[[1]]$mean_age <- 21.3
  theory$constructs[[1]]$small <- 0.000123456789012345
  theory$constructs[[1]]$large <- 1e20
  for (ext in c(".yaml", ".json")) {
    path <- tempfile(fileext = ext)
    tf_write(theory, path)
    text <- tf_read_golden(path)
    expect_false(grepl("\\.na|\\bNA\\b", text), info = ext)
    expect_true(grepl(if (ext == ".yaml") "mean_age: 21.3\n" else '"mean_age": 21.3,', text,
                      fixed = TRUE), info = ext)
    back <- tf_read(path)
    expect_true("severity" %in% names(back$predictions[[1]]), info = ext)
    expect_null(back$predictions[[1]]$severity, info = ext)
    expect_null(back$test_outcomes[[2]]$passed, info = ext)
    expect_null(back$constructs[[1]]$n_items, info = ext)
    expect_null(back$constructs[[1]]$source, info = ext)
    expect_identical(back$constructs[[1]]$scores, list(0.5, NULL), info = ext)
    expect_identical(back$constructs[[1]]$mean_age, 21.3, info = ext)
    expect_equal(back$constructs[[1]]$small, 0.000123456789012345, tolerance = 1e-14, info = ext)
    expect_identical(back$constructs[[1]]$large, 1e20, info = ext)
  }
})

test_that("the string-array paths come from the schema", {
  paths <- vapply(theoryforge:::.tf_string_array_paths(), paste, character(1), collapse = "/")
  expect_setequal(paths, c(
    "constructs/[]/measurement", "constructs/[]/boundary_conditions", "boundary_conditions",
    "predictions/[]/derives_from", "predictions/[]/diagnostic_vs",
    "auxiliary_assumptions/[]/protects", "alternatives/[]/key_constructs"
  ))
})
