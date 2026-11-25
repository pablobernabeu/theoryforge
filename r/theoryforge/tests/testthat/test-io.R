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

# A theory whose aliases repeat a 1000-item sequence `repeats` times. The
# document holds 1008 + 1001 * repeats + tail values once its aliases are
# expanded: the mapping, its four header scalars, the three keyed sequences,
# 1000 scalars in the first, its repeats in the second and `tail` scalars in
# the third.
aliased <- function(repeats, tail) {
  paste0("schema_version: '1.1'\nid: b\ntitle: B\nmaturity: draft\n",
         "a: &a [", paste(rep("s", 1000L), collapse = ", "), "]\n",
         "b: [", paste(rep("*a", repeats), collapse = ", "), "]\n",
         "c: [", paste(rep("s", tail), collapse = ", "), "]\n")
}

test_that("aliases that expand past the limit refuse the file", {
  # 1008 + 1001 * 997 + 995 is the limit itself, and one more value passes it.
  # The Python twin counts the same values and gives the same message.
  expect_identical(tf_read(io_file(aliased(997L, 995L)))$id, "b")
  path <- io_file(aliased(997L, 996L))
  expect_error(tf_read(path),
               sprintf("(%s) the document holds more than 1000000 values once its aliases are expanded",
                       path), fixed = TRUE)
  # A file of about a kilobyte that stands for ten billion values is refused at
  # once, as a theory and as a corpus, and merge keys still read.
  bomb <- paste0("x0: &a0 [", paste(rep("ha", 10L), collapse = ", "), "]\n",
                 paste0(sprintf("x%d: &a%d [%s]\n", 1:9, 1:9,
                                vapply(0:8, function(i) paste(rep(sprintf("*a%d", i), 10L), collapse = ", "), "")),
                        collapse = ""))
  expect_error(tf_read(io_file(bomb)), "once its aliases are expanded", fixed = TRUE)
  expect_error(tf_read_corpus(io_file(bomb)), "once its aliases are expanded", fixed = TRUE)
  ids <- vapply(tf_read(io_file(merge_theory))$constructs, function(c) c$id, "")
  expect_identical(ids, c("c1", "c2"))
})

test_that("an alias that names no node and an anchor given twice are refused", {
  # yaml read the first two aliases as "_yaml.bad-anchor_" with a warning and
  # bound an alias to the first of two anchors, where PyYAML refused the file
  # or read a cycle (API_SPEC.md section 3). The Python suite reads the same
  # texts.
  bs <- "\\"
  cases <- list(
    list("id: x\na: *u\n", "the alias 'u' names no node that ends before it"),
    list("id: x\na: &p [*p]\n", "the alias 'p' names no node that ends before it"),
    list("id: x\na: &p {b: *p}\n", "the alias 'p' names no node that ends before it"),
    list("id: x\na: &x 1\nb: &x 2\nc: *x\n", "the anchor 'x' names two nodes"),
    list("id: x\na: &x [&x 1]\n", "the anchor 'x' names two nodes"),
    list("id: x\na: !!str &x 1\nb: &x 2\n", "the anchor 'x' names two nodes"),
    list("id: x\na: &x 1 # &x\nb: '&x'\nc: R &x\nd: |\n  &x\ne: *x\n", NULL),
    # As both readers meet them: a repeated key or an alias that names no
    # node, whichever comes first, then U+0000, then an anchor given twice.
    list("id: x\nk: {a: 1, a: 2}\nz: *u\n", "Duplicate map key: 'a'"),
    list("id: x\nz: *u\nk: {a: 1, a: 2}\n", "the alias 'u' names no node that ends before it"),
    list(paste0("id: x\nz: *u\nt: \"a", bs, "0b\"\n"), "the alias 'u' names no node that ends before it"),
    list(paste0("id: x\nt: \"a", bs, "0b\"\na: &x 1\nb: &x 2\n"),
         "a string holds U+0000, which theoryforge cannot read"),
    list("id: x\na: &x 1\nb: &x 2\nc: *u\n", "the alias 'u' names no node that ends before it")
  )
  for (case in cases) {
    path <- io_file(case[[1]])
    if (is.null(case[[2]])) {
      expect_identical(expect_silent(tf_read(path))$e, 1L, info = case[[1]])
    } else {
      expect_error(tf_read(path), sprintf("(%s) %s", path, case[[2]]), fixed = TRUE, info = case[[1]])
    }
  }
})

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

test_that("a string R cannot hold is refused with one message", {
  # R cuts a string at U+0000 and reads a lone surrogate escape as "?" or as
  # bytes that are not UTF-8, while Python kept both (API_SPEC.md section 3).
  # The Python suite reads the same texts.
  bs <- "\\"
  cases <- list(
    list(".json", paste0('{"id": "x", "title": "a', bs, 'u0000b"}'), "U+0000"),
    list(".json", paste0('{"id": "x", "title": "a', bs, 'ud800b"}'), "a lone surrogate"),
    list(".json", paste0('{"id": "x", "title": "a', bs, 'udc00b"}'), "a lone surrogate"),
    list(".json", paste0('{"id": "x", "title": "', bs, 'ud800', bs, 'ud800', bs, 'udc00"}'),
         "a lone surrogate"),
    list(".json", paste0('{"t": "', bs, 'udbff", "u": "', bs, 'u0000"}'), "a lone surrogate"),
    list(".json", paste0('{"a', bs, 'u0000b": 1, "a', bs, 'u0000c": 2}'), "U+0000"),
    list(".json", paste0('{"a', bs, 'u0000b": 1, "a', bs, 'u0000b": 2}'), "U+0000"),
    list(".yaml", paste0('id: x\ntitle: "before', bs, '0after"\n'), "U+0000"),
    list(".yaml", paste0('id: x\ntitle: "before', bs, 'x00after"\n'), "U+0000"),
    list(".yaml", paste0('id: x\ntitle: "before', bs, 'u0000after"\n'), "U+0000"),
    list(".yaml", paste0('"a', bs, '0b": 1\n"a', bs, '0c": 2\n'), "U+0000"),
    list(".yaml", paste0('"a', bs, '0b": 1\n"a', bs, '0b": 2\n'), "U+0000"),
    # A paired surrogate escape is one character, an escaped backslash is no
    # escape, and only a double-quoted YAML scalar has escapes.
    list(".json", paste0('{"id": "x", "title": "a', bs, 'uD83D', bs, 'uDE00b"}'), NULL),
    list(".json", paste0('{"id": "x", "title": "a', bs, bs, 'u0000b"}'), NULL),
    list(".yaml", paste0('id: x\ntitle: "a', bs, bs, '0b"\n'), NULL),
    list(".yaml", paste0("id: x\ntitle: a", bs, "0b\n"), NULL),
    list(".yaml", paste0("id: x\ntitle: 'a", bs, "0b'\n"), NULL),
    list(".yaml", paste0("id: x\ntitle: |\n  a", bs, "0b\n"), NULL)
  )
  for (case in cases) {
    path <- io_file(case[[2]], ext = case[[1]])
    if (is.null(case[[3]])) {
      expect_identical(tf_read(path)$id, "x", info = case[[2]])
    } else {
      expect_error(tf_read(path), sprintf("(%s) a string holds %s, which theoryforge cannot read",
                                          path, case[[3]]), fixed = TRUE, info = case[[2]])
    }
  }
  expect_identical(tf_read(io_file(paste0('{"id": "x", "t": "a', bs, 'uD83D', bs, 'uDE00b"}'),
                                   ext = ".json"))$t, "a\U0001F600b")
  # As both readers meet them: the repeated key while parsing, the string after.
  expect_error(tf_read(io_file(paste0('{"k": {"a": 1, "a": 2}, "t": "', bs, 'u0000"}'), ext = ".json")),
               "Duplicate map key: 'a'", fixed = TRUE)
  expect_error(tf_read(io_file(paste0('k: {a: 1, a: 2}\nt: "', bs, '0"\n'))),
               "Duplicate map key: 'a'", fixed = TRUE)
})

test_that("JSON comments are refused, as Python's json module refuses them", {
  # jsonlite's parser accepts comments, so the text is validated first.
  path <- io_file('{\n  // exported by hand\n  "id": "x"\n}\n', ext = ".json")
  expect_error(tf_read(path), "comments are not enabled", fixed = TRUE)
  expect_error(tf_read(io_file('{"id": "x" /* end */}', ext = ".json")), "comments are not enabled",
               fixed = TRUE)
})

test_that("a tab reads as libyaml reads it, in both twins", {
  # The Python twin parses YAML with libyaml, which R's yaml package bundles,
  # since PyYAML's pure-Python scanner refused a tab that YAML allows as
  # separating white space. The Python suite reads the same text.
  tab <- "\t"
  text <- paste0('schema_version: "1.1"', tab, '
id: tabs
title: A title', tab, '
maturity: building
constructs:
  - {id: c1,', tab, 'label: Alpha, definition: Bodily', tab, 'activation.}', tab, '# a comment
  - {', tab, 'id: c2, label:', tab, 'Beta, definition: Appraised danger.}
predictions:
  - id: h1
    statement: Beta rises.
    type: directional
    derives_from: [', tab, 'p1,', tab, 'p2]
')
  t <- tf_read(io_file(text))
  expect_identical(t$schema_version, "1.1")
  expect_identical(t$title, "A title")
  expect_identical(t$constructs, list(
    list(id = "c1", label = "Alpha", definition = "Bodily\tactivation."),
    list(id = "c2", label = "Beta", definition = "Appraised danger.")))
  expect_identical(t$predictions[[1]]$derives_from, list("p1", "p2"))
  # A tab that indents a line, or follows the dash of a sequence entry, is refused.
  for (bad in c("id: a\nconstructs:\n\t- id: c1\n", "id: a\nconstructs:\n  -\t{id: c1}\n")) {
    expect_error(tf_read(io_file(bad)), "found character that cannot start any token", fixed = TRUE)
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
  expect_identical(unlist(tf_litmap(c)$keywords), c("arousal", "n", "y"))
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
  # beyond 2^53 an octal or hexadecimal integer is the nearest double, rounded
  # once (2^57 + 17 is 2^57 + 32), where a sum digit by digit gave 2^57
  list("0x200000000000011", 2^57 + 32), list("-0x200000000000011", -(2^57 + 32)),
  list("010000000000000000021", 2^57 + 32),
  # subnormal and underflowing floats, which R's own parser misreads on a build
  # without long double
  list("2.5e-324", 2^-1074), list("2.1e-322", 43 * 2^-1074), list("1.0e-400", 0),
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

test_that("tf_write escapes a next-line character", {
  # YAML counts U+0085, U+2028 and U+2029 as line breaks. yaml writes the
  # first in double quotes as the escape \N, as the Python twin now writes
  # it, and the escapes of the other two follow in such a string. Alone, those
  # two are written as they are, and read back.
  theory <- list(schema_version = "1.1", id = "w", title = "Panic\u0085disorder",
                 maturity = "building",
                 constructs = list(list(id = "c1", label = "a\u2028b", definition = "c\u2029d\u0085")))
  path <- tempfile(fileext = ".yaml")
  tf_write(theory, path)
  text <- tf_read_golden(path)
  expect_true(grepl('title: "Panic\\Ndisorder"', text, fixed = TRUE))
  expect_true(grepl('definition: "c\\Pd\\N"', text, fixed = TRUE))
  back <- tf_read(path)
  expect_identical(back$title, "Panic\u0085disorder")
  expect_identical(back$constructs, theory$constructs)
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

test_that("tf_write writes NA as null and every number so that it reads back exactly", {
  # yaml wrote NA as R's own .na forms and jsonlite wrote "NA" for a number,
  # which both readers take for text. yaml's precision counts decimal places,
  # so 15 of them wrote 21.3 as 21.300000000000001. Fifteen significant digits
  # changed a number that needs 16 or 17, such as 6/sqrt(2), and the 15 digits
  # %g gives a subnormal number are 14 more than it needs.
  theory <- writer_theory()
  theory$predictions[[1]]$severity <- NA_real_
  theory$test_outcomes[[2]]$passed <- NA
  theory$constructs[[1]]$n_items <- NA_integer_
  theory$constructs[[1]]$source <- NA_character_
  theory$constructs[[1]]$scores <- c(0.5, NA)
  theory$constructs[[1]]$mean_age <- 21.3
  theory$constructs[[1]]$small <- 0.000123456789012345
  theory$constructs[[1]]$large <- 1e20
  theory$constructs[[1]]$long <- c(6 / sqrt(2), 41 / 3)
  theory$constructs[[1]]$power <- 2^-24
  theory$constructs[[1]]$tiny <- 2^-1074
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
    expect_identical(back$constructs[[1]]$small, theory$constructs[[1]]$small, info = ext)
    expect_identical(back$constructs[[1]]$large, 1e20, info = ext)
    expect_identical(unlist(back$constructs[[1]]$long), c(6 / sqrt(2), 41 / 3), info = ext)
    expect_identical(back$constructs[[1]]$power, 2^-24, info = ext)
    expect_identical(back$constructs[[1]]$tiny, 2^-1074, info = ext)
    # The digits Python's repr() writes: 16 for 2^-24 and one for 2^-1074.
    expect_true(grepl("5.960464477539063e-08", text, fixed = TRUE), info = ext)
    expect_true(grepl("5(\\.0)?e-324", text), info = ext)
  }
})

test_that("tf_write keeps dates as text, the shape of an array and the digits beside Inf", {
  # The JSON writer took a Date or a POSIXct for a bare number and stopped, wrote
  # a matrix as one flat array, kept 15 digits of a number in a vector that also
  # held Inf, and wrote -0, which JSON reads as the integer 0. yaml wrote a Date
  # as the number of days since 1970.
  theory <- tf_theory("demo-1", "A demonstration theory") |>
    tf_add_construct("c1", "C", "A construct.") |>
    tf_add_prediction("h1", "C rises.", "directional") |>
    tf_add_test_outcome("h1", TRUE, observed = "ok", date = as.Date("2026-11-20"))
  theory$constructs[[1]]$x_seen <- as.POSIXct("2026-11-20 10:00:00", tz = "UTC")
  theory$constructs[[1]]$x_m <- matrix(c(6 / sqrt(2), -0.25, 0.125, 1), 2)
  theory$constructs[[1]]$x_inf <- c(6 / sqrt(2), Inf)
  theory$constructs[[1]]$x_zero <- -0
  for (ext in c(".yaml", ".json")) {
    path <- tempfile(fileext = ext)
    tf_write(theory, path)
    back <- tf_read(path)
    expect_identical(back$test_outcomes[[1]]$date, "2026-11-20", info = ext)
    expect_identical(back$constructs[[1]]$x_seen, "2026-11-20 10:00:00", info = ext)
    expect_identical(back$constructs[[1]]$x_inf[[1]], 6 / sqrt(2), info = ext)
    expect_identical(1 / back$constructs[[1]]$x_zero, -Inf, info = ext)
    expect_true(tf_validate(back, full = TRUE), info = ext)
  }
  path <- tempfile(fileext = ".json")
  tf_write(theory, path)
  expect_identical(jsonlite::fromJSON(path)$constructs$x_m[[1]], theory$constructs[[1]]$x_m)
})

test_that("a recorded content hash survives tf_write in both formats", {
  # A number that needs 17 digits, written with 15, read back as another
  # number, so the theory's hash changed and tf_validate(full = TRUE) refused
  # the hash it had recorded. A single string in a string array, which
  # tf_write() writes as an array, changed the hash too, and NA there was
  # written as an array holding null.
  theory <- tf_read(tf_example_path("modality-switching.theory.yaml"))
  theory$constructs[[1]]$x_scale <- c(6 / sqrt(2), 41.123456789012344)
  theory$constructs[[1]]$measurement <- "self-report scale"
  theory$constructs[[2]]$measurement <- NA
  theory$predictions[[1]]$derives_from <- "p1"
  theory$version$content_hash <- tf_content_hash(theory)
  for (ext in c(".yaml", ".json")) {
    path <- tempfile(fileext = ext)
    tf_write(theory, path)
    back <- tf_read(path)
    expect_identical(back$constructs[[1]]$measurement, list("self-report scale"), info = ext)
    expect_true("measurement" %in% names(back$constructs[[2]]), info = ext)
    expect_null(back$constructs[[2]]$measurement, info = ext)
    expect_identical(tf_content_hash(back), theory$version$content_hash, info = ext)
    expect_true(tf_validate(back, full = TRUE), info = ext)
  }
})

test_that("the string-array paths come from the schema", {
  paths <- vapply(theoryforge:::.tf_string_array_paths(), paste, character(1), collapse = "/")
  expect_setequal(paths, c(
    "constructs/[]/measurement", "constructs/[]/boundary_conditions", "boundary_conditions",
    "predictions/[]/derives_from", "predictions/[]/diagnostic_vs",
    "auxiliary_assumptions/[]/protects", "alternatives/[]/key_constructs",
    "phenomena/[]/claim/given", "predictions/[]/claim/given"
  ))
})
