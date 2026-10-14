# The shipped schemas compile under a strict validator and describe what the
# package does. Ajv, the most widely used JavaScript validator, refuses by
# default to compile a schema with a keyword JSON Schema does not define, and
# theory.schema.json carried one, a plain `comment`. The first tests walk every
# subschema of both schemas the package ships and fail on any such keyword,
# which is the check of Ajv's strict mode that CI also runs. The others hold
# three field descriptions to the behaviour they describe, as
# tests/test_schema_document.py does in Python.

# Every keyword of the JSON Schema 2020-12 vocabularies: core, applicator,
# unevaluated, validation, meta-data, format annotation and content.
schema_keywords <- c(
  "$schema", "$id", "$ref", "$anchor", "$dynamicRef", "$dynamicAnchor",
  "$vocabulary", "$comment", "$defs",
  "prefixItems", "items", "contains", "additionalProperties", "properties",
  "patternProperties", "dependentSchemas", "propertyNames", "if", "then",
  "else", "allOf", "anyOf", "oneOf", "not",
  "unevaluatedItems", "unevaluatedProperties",
  "type", "const", "enum", "multipleOf", "maximum", "exclusiveMaximum",
  "minimum", "exclusiveMinimum", "maxLength", "minLength", "pattern",
  "maxItems", "minItems", "uniqueItems", "maxContains", "minContains",
  "maxProperties", "minProperties", "required", "dependentRequired",
  "title", "description", "default", "deprecated", "readOnly", "writeOnly",
  "examples", "format", "contentEncoding", "contentMediaType", "contentSchema"
)
# Keywords whose value is a schema, a list of schemas or a mapping of names to
# schemas.
one_schema <- c("items", "contains", "additionalProperties", "propertyNames",
                "if", "then", "else", "not", "unevaluatedItems",
                "unevaluatedProperties", "contentSchema")
schema_lists <- c("prefixItems", "allOf", "anyOf", "oneOf")
schema_maps <- c("properties", "patternProperties", "$defs", "dependentSchemas")

shipped_schema <- function(name) {
  path <- system.file("schema", name, package = "theoryforge")
  expect_true(nzchar(path))
  jsonlite::fromJSON(path, simplifyVector = FALSE)
}

# The JSON pointer of every key in a schema object that is not a keyword. A
# parsed JSON object is a named list, and true and false are schemas too.
unknown_keywords <- function(schema, where = "#") {
  if (!is.list(schema) || is.null(names(schema))) return(character())
  found <- sprintf("%s/%s", where, setdiff(names(schema), schema_keywords))
  for (key in intersect(one_schema, names(schema))) {
    found <- c(found, unknown_keywords(schema[[key]], paste0(where, "/", key)))
  }
  for (key in intersect(schema_lists, names(schema))) {
    subs <- schema[[key]]
    for (i in seq_along(subs)) {
      found <- c(found, unknown_keywords(subs[[i]], sprintf("%s/%s/%d", where, key, i - 1L)))
    }
  }
  for (key in intersect(schema_maps, names(schema))) {
    subs <- schema[[key]]
    for (name in names(subs)) {
      found <- c(found, unknown_keywords(subs[[name]], sprintf("%s/%s/%s", where, key, name)))
    }
  }
  found
}

test_that("the walk finds an unknown keyword at any depth", {
  schema <- list(properties = list(a = list(items = list(type = "string", nullable = TRUE))),
                 anyOf = list(list(comment = "x")), additionalProperties = FALSE)
  expect_identical(sort(unknown_keywords(schema)),
                   c("#/anyOf/0/comment", "#/properties/a/items/nullable"))
})

test_that("every key of a shipped schema is a JSON Schema keyword", {
  for (name in c("theory.schema.json", "corpus.schema.json")) {
    expect_identical(unknown_keywords(shipped_schema(name)), character(), info = name)
  }
})

schema_description <- function(field) {
  shipped_schema("theory.schema.json")$properties[[field]]$description
}

theory_variant <- function(name, ...) {
  t <- tf_read(tf_example_path(name))
  fields <- list(...)
  for (key in names(fields)) t[[key]] <- fields[[key]]
  t
}

test_that("schema_version is checked but gates nothing", {
  # A version the package has never heard of reads, validates and scores as
  # the current one does. Only full validation looks at the version, and only
  # at its major.minor form.
  current <- tf_check(tf_read(tf_example_path("panic-network.theory.yaml")))
  future <- theory_variant("panic-network.theory.yaml", schema_version = "9.0")
  expect_true(tf_validate(future, full = TRUE))
  report <- tf_check(future)
  expect_identical(report$aggregate_score, current$aggregate_score)
  expect_identical(report$gate, current$gate)
  off_pattern <- theory_variant("panic-network.theory.yaml", schema_version = "v1")
  expect_true(tf_validate(off_pattern))
  expect_error(tf_validate(off_pattern, full = TRUE),
               "schema_version must match major.minor", fixed = TRUE)
  expect_identical(tf_check(off_pattern)$aggregate_score, current$aggregate_score)
  description <- schema_description("schema_version")
  expect_match(description, "validate(full) checks its pattern", fixed = TRUE)
  expect_match(description, "neither package gates loading", fixed = TRUE)
})

test_that("draft maturity changes the gate and nothing else", {
  building <- tf_check(theory_variant("weak-theory.theory.yaml", maturity = "building"))
  draft <- tf_check(theory_variant("weak-theory.theory.yaml", maturity = "draft"))
  expect_identical(building$gate, "blocked")
  expect_identical(draft$gate, "advisory")
  # The blockers still fail and still count in the score.
  expect_gt(building$n_blockers_failed, 0L)
  expect_identical(draft$n_blockers_failed, building$n_blockers_failed)
  expect_identical(draft$items, building$items)
  expect_identical(draft$aggregate_score, building$aggregate_score)
  description <- schema_description("maturity")
  expect_match(description, "still reported as fail", fixed = TRUE)
  expect_match(description, "still count in the aggregate score", fixed = TRUE)
  expect_match(description, "never reads blocked", fixed = TRUE)
})

test_that("theory_form leaves the checklist unchanged", {
  reports <- lapply(c("variance", "network", "typology", "process"), function(form) {
    tf_check(theory_variant("panic-network.theory.yaml", theory_form = form))
  })
  for (r in reports) {
    expect_length(r$items, 12L)
    expect_identical(r, reports[[1]])
  }
  expect_match(schema_description("theory_form"),
               "the checklist applies the same twelve items to every form", fixed = TRUE)
})
