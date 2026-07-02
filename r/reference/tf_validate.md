# Validate a theory object

Built-in validation mirroring the Python `Theory.validate`. The default
(`full = FALSE`) checks required fields and enum membership. With
`full = TRUE` it additionally checks referential integrity: that every
id is unique within its collection and that every cross-reference
(proposition endpoints, prediction derivations and diagnostics, and
assumption, evidence and test-outcome targets) points to a declared id.
The `full` checks are deterministic and identical to the Python
`theory.validate(full=True)`. See API_SPEC.md section 2.

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
theory <- tf_theory("demo-1", "A demonstration theory")
tf_validate(theory)
tf_validate(theory, full = TRUE)
```
