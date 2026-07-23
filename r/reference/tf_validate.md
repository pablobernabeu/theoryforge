# Validate a theory object

Built-in validation. The default (`full = FALSE`) checks required fields
and enum membership. With `full = TRUE` it additionally checks
referential integrity: that every id is unique within its collection and
that every cross-reference (proposition endpoints, prediction
derivations and diagnostics, and assumption, evidence and test-outcome
targets) points to a declared id. The `full` checks are deterministic.

## Usage

``` r
tf_validate(theory, full = FALSE)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- full:

  When `TRUE`, also run the referential-integrity checks.

## Value

`TRUE` (invisibly) on success; otherwise stops with a message listing
every problem found.

## Examples

``` r
theory <- tf_read(system.file("fixtures", "panic-network.theory.yaml",
                              package = "theoryforge"))
isTRUE(tf_validate(theory))              # required fields and enums
#> [1] TRUE
isTRUE(tf_validate(theory, full = TRUE)) # also ids and cross-references
#> [1] TRUE

# The failure path is the more informative one. Point a prediction at a
# proposition that was never declared.
broken <- theory
broken$predictions[[1]]$derives_from <- "p_missing"
tryCatch(tf_validate(broken, full = TRUE), error = conditionMessage)
#> [1] "invalid theory object: prediction[0] derives_from 'p_missing' is not a known proposition"
```
