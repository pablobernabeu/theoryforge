# Compute the rigour checklist report

Runs the full rigour checklist (12 items) over a theory object and
returns a report, with the items in checklist order.

## Usage

``` r
tf_check(theory)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

## Value

A named list with elements `theory_id`, `schema_version` (the theory's),
`checklist_version` (the rigour checklist's, which is what the weights
and thresholds came from), `maturity`, `aggregate_score`, `coverage`,
`gate`, `n_blockers_failed`, and `items` (a list of per-item lists). An
error is raised for a prediction severity that is not a finite number or
is below 0 or above 1.

## Details

Each item has a status (`"pass"`, `"warn"` or `"fail"`) and a score from
0 to 1. An item with nothing to assess has the status `"n/a"` and a
`NULL` score: the redundancy screen with fewer than two constructs, the
derivation chain with no prediction and parsimony when no auxiliary
assumption was added in response to an anomaly. The aggregate score is
the weighted mean of the applicable items' scores, times 100, and
`coverage` is the share of the checklist's weight that was applicable.

Two values are refused before anything is scored, since no score built
on them would be defensible. One is a test outcome whose `passed` is
present and not `TRUE` or `FALSE`, such as the quoted string `"true"`.
The other is a prediction `severity` that is present and not a number.
Both stop with the message the Python twin raises, and
[`tf_validate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_validate.md)
with `full = TRUE` reports both.

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
#> [1] 63
report$gate
#> [1] "blocked"
```
