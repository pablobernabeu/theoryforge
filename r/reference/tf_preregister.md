# Render a preregistration document

Produces a byte-identical preregistration markdown string for a theory
and, if `path` is given, writes it (LF, single trailing newline).
Mirrors the Python `theory.preregister(path)`. See API_SPEC.md section
11.

## Usage

``` r
tf_preregister(theory, path = NULL)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- path:

  Optional destination path; when given, the markdown is written with LF
  line endings.

## Value

The preregistration markdown as a single string.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_prediction("h1", "Effect is exactly 0.30.", "point")
cat(tf_preregister(theory))
#> # Preregistration: A demonstration theory
#> 
#> - Theory ID: demo-1
#> - Schema version: 1.0
#> - Maturity: building
#> - Derivation chain verified: no
#> 
#> ## Hypotheses
#> 1. [point] Effect is exactly 0.30. (derives from: —)
#> 
#> ## Severity
#> - h1: severity 0.9, risk 0.9
```
