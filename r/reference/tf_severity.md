# Per-prediction claim-form riskiness

A pre-data rubric of the form of each prediction's claim. `risk_score`
is the base riskiness of the declared type: existence 0.1, directional
0.4, interval 0.7 and point 0.9. `computed_severity` discounts a
directional prediction by 25 per cent, adds 0.1 when `diagnostic_vs`
names a registered alternative and is capped at 1. The order of the
types follows Popper (1959, sections 31-33) for nested claims about one
quantity, and the directional penalty follows Meehl's (1967, 1990b)
argument that a sign alone risks little. The base values, the discount
and the bonus are the package's conventions, and neither source gives
them.

## Usage

``` r
tf_severity(theory)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

## Value

A `data.frame` with columns `prediction_id`, `type`, `risk_score`,
`computed_severity`, one row per prediction in file order.

## Details

How severely a claim is tested depends on the design and the data, which
the rubric does not read. A prediction scores the same however it is
tested, and a failed test leaves the value where it was.

## References

Meehl, P. E. (1967). Theory-testing in psychology and physics: A
methodological paradox. *Philosophy of Science*, 34(2), 103-115.
[doi:10.1086/288135](https://doi.org/10.1086/288135)

Meehl, P. E. (1990b). Why summaries of research on psychological
theories are often uninterpretable. *Psychological Reports*, 66(1),
195-244.
[doi:10.2466/pr0.1990.66.1.195](https://doi.org/10.2466/pr0.1990.66.1.195)

Popper, K. R. (1959). *The logic of scientific discovery*. Hutchinson.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_prediction("h1", "Effect is exactly 0.30.", "point") |>
  tf_add_prediction("h2", "Effect is positive.", "directional")
tf_severity(theory)
#>   prediction_id        type risk_score computed_severity
#> 1            h1       point        0.9               0.9
#> 2            h2 directional        0.4               0.3
```
