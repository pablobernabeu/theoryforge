# Per-prediction risk and computed severity

Computes, for each prediction (in file order), the riskiness of the
claim form and the discounted/bonus-adjusted severity. Mirrors the
Python `theory.severity()`. See API_SPEC.md section 9.

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

## References

Mayo, D. G. (2018). *Statistical Inference as Severe Testing*. Cambridge
University Press.
[doi:10.1017/9781107286184](https://doi.org/10.1017/9781107286184)

Meehl, P. E. (1990). Why summaries of research on psychological theories
are often uninterpretable. *Psychological Reports*, 66, 195-244.
[doi:10.2466/pr0.1990.66.1.195](https://doi.org/10.2466/pr0.1990.66.1.195)

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
