# Validate a theory object

Checks a theory against the package's schema, `theory.schema.json`,
without a JSON Schema engine, so that it runs wherever R does, webR
included.

## Usage

``` r
tf_validate(theory, full = FALSE)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- full:

  When `TRUE`, also check ids, cross-references and the rest of the
  schema.

## Value

`TRUE` (invisibly) on success; otherwise stops with
`"invalid theory object: "` followed by every problem found, joined by
`"; "`.

## Details

The default (`full = FALSE`) checks structure. It covers the required
top-level fields, the `maturity` and `theory_form` enums, the top-level
field names and the required fields and enums of each construct,
proposition and prediction. It also checks that every collection is a
list. A field that is absent, `NULL` or blank is reported as missing,
and one that holds another type as such (`id must be a string`).

With `full = TRUE` it also checks that every id is unique within its
collection and that every cross-reference (proposition endpoints,
prediction derivations and diagnostics, and assumption, evidence and
test-outcome targets) points to a declared id. It then checks the rest
of the schema. That covers the required fields of assumptions,
alternatives, evidence and test outcomes, a logical `passed`, the
evidence direction and formal-model type enums, the version block and
the `schema_version` pattern. It also covers numbers within \[0, 1\]
where the schema asks for them and the type of every other field and of
every entry of a string array.

The Python twin's test suite compares the result with a JSON Schema
2020-12 validator. Besides the ids and references, which the schema
cannot express, the pass is stricter in two ways, since a blank string
counts as missing and an entry of a string array must be a nonempty
string. It is more lenient in three ways, which API_SPEC.md section 2
documents. A `NULL` optional field is absent and a single string stands
for a one-element array of strings. An empty
[`list()`](https://rdrr.io/r/base/list.html) stands for an empty mapping
as well as an empty sequence. A single `NA`, which
[`tf_write()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_write.md)
writes as null, reads as absent.

Both passes are deterministic, and the Python twin's `Theory.validate()`
reports the same problems in the same order with the same text.

## Examples

``` r
theory <- tf_read(system.file("fixtures", "panic-network.theory.yaml",
                              package = "theoryforge"))
isTRUE(tf_validate(theory))              # required fields and enums
#> [1] TRUE
isTRUE(tf_validate(theory, full = TRUE)) # also ids, cross-references and the rest of the schema
#> [1] TRUE

# The failure path is the more informative one. Point a prediction at a
# proposition that was never declared.
broken <- theory
broken$predictions[[1]]$derives_from <- "p_missing"
tryCatch(tf_validate(broken, full = TRUE), error = conditionMessage)
#> [1] "invalid theory object: prediction[0] derives_from 'p_missing' is not a known proposition"
```
