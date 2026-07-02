# Compute the rigour checklist report

Runs the full rigour checklist (12 items) over a theory object and
returns a report. Mirrors the Python `theory.check()` dict, including
key order and item order. See API_SPEC.md section 4.

## Usage

``` r
tf_check(theory)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

## Value

A named list with elements `theory_id`, `schema_version`, `maturity`,
`aggregate_score`, `gate`, `n_blockers_failed`, and `items` (a list of
per-item lists).

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "causes",
                     mechanism = "Activation raises salience of threat cues.") |>
  tf_add_prediction("h1", "Arousal precedes threat appraisal.", "point")
report <- tf_check(theory)
report$aggregate_score
#> [1] 57
report$gate
#> [1] "blocked"
```
