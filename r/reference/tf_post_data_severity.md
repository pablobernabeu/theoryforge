# Post-data severity of each bounded prediction

How severely each bounded claim passed its test, from the test outcome's
estimate and standard error.

## Usage

``` r
tf_post_data_severity(theory)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

## Value

A `data.frame` with one row per test outcome, in file order, that
carries both an estimate and a standard error and whose prediction
declares bounds. Its columns are `prediction_id`, `outcome` (the
outcome's 0-based index among the test outcomes), `lower` and `upper`
(`NA` for an open bound), `estimate`, `se` and `severity`.

## Details

A prediction states the region its claim allows in `bounds`, a mapping
of `lower` and `upper`, either of which may be null (or infinite) for an
open side. A test outcome records the `estimate` it observed and its
standard error `se`. For an outcome with both, whose prediction declares
bounds, the severity with which the claim passed is the smallest of
\\\Phi((estimate - lower) / se)\\ and \\\Phi((upper - estimate) / se)\\
over the finite bounds, rounded to three decimals (Mayo & Spanos, 2006,
2011). It is the probability that the test would have given a result
less in accord with the claim, had the claim been false at the bound. A
one-sided claim, such as an effect above a smallest effect of interest,
is a lower bound with the upper one open.

The computation is a normal approximation to the sampling distribution
of the estimate. With two finite bounds, the value equals 1 minus the p
value of the two one-sided tests (TOST) of equivalence. A point claim
with lower equal to upper can pass with a severity of at most 0.5, so it
needs a tolerance around its value. Unlike
[`tf_severity()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_severity.md),
which grades the form of a claim before any data, this value depends on
the design and the data. The rigour checklist does not read it.
[`tf_dossier()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_dossier.md)
gives each value in its test record.

The function stops at the first outcome, in file order, that cannot be
read, with the Python twin's text:
`post_data_severity requires both estimate and se; test_outcome[<i>]`,
`... requires a finite se greater than 0; ...` and
`... requires a finite estimate; ...`, and for its prediction's bounds
`... requires bounds with numeric or null lower and upper; prediction '<id>'`,
`... requires at least one finite bound; ...` and
`... requires lower <= upper; ...`.
[`tf_validate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_validate.md)
with `full = TRUE` reports each of these.

## References

Mayo, D. G., & Spanos, A. (2006). Severe testing as a basic concept in a
Neyman-Pearson philosophy of induction. *The British Journal for the
Philosophy of Science*, 57(2), 323-357.
[doi:10.1093/bjps/axl003](https://doi.org/10.1093/bjps/axl003)

Mayo, D. G., & Spanos, A. (2011). Error statistics. In P. S.
Bandyopadhyay & M. R. Forster (Eds.), *Philosophy of statistics* (pp.
153-198). Elsevier.
[doi:10.1016/B978-0-444-51862-0.50005-8](https://doi.org/10.1016/B978-0-444-51862-0.50005-8)

## Examples

``` r
theory <- tf_read(tf_example_path("modality-switching.theory.yaml"))
tf_post_data_severity(theory)
#>   prediction_id outcome lower upper estimate se severity
#> 1         pred2       0    20    60       41  6    0.999

# A claim that |r| <= .10, tested with an estimate of 0 and a standard error
# of .10, passes with a severity of .841.
theory$predictions[[4]]$bounds <- list(lower = -0.10, upper = 0.10)
theory$test_outcomes <- list(list(prediction_id = "pred4", passed = TRUE,
                                  estimate = 0, se = 0.10))
tf_post_data_severity(theory)
#>   prediction_id outcome lower upper estimate  se severity
#> 1         pred4       0  -0.1   0.1        0 0.1    0.841
```
