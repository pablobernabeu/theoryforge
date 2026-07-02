# Appraise an amendment as progressive, degenerating, or neutral

Compares an amended theory `new` against its `prior` version and returns
a Lakatosian verdict. Mirrors the Python
`theory.appraise_amendment(prior)`. See API_SPEC.md section 10.

## Usage

``` r
tf_appraise_amendment(new, prior)
```

## Arguments

- new:

  The amended theory object (named list).

- prior:

  The prior theory object (named list).

## Value

A named list with `verdict` (one of `"progressive"`, `"degenerating"`,
`"neutral"`) and the ascending-sorted character vectors
`new_predictions`, `corroborated_new`, `ad_hoc_assumptions`.

## References

Lakatos, I. (1970). Falsification and the methodology of scientific
research programmes. In *Criticism and the Growth of Knowledge* (pp.
91-196). Cambridge University Press.
[doi:10.1017/cbo9781139171434.009](https://doi.org/10.1017/cbo9781139171434.009)

Meehl, P. E. (1990). Appraising and amending theories. *Psychological
Inquiry*, 1(2), 108-141.
[doi:10.1207/s15327965pli0102_1](https://doi.org/10.1207/s15327965pli0102_1)

## Examples

``` r
prior <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_prediction("h1", "Effect is positive.", "directional")
new <- prior |>
  tf_add_prediction("h2", "Effect is exactly 0.30.", "point")
new$test_outcomes <- list(list(prediction_id = "h2", passed = TRUE))
tf_appraise_amendment(new, prior)
#> $verdict
#> [1] "progressive"
#> 
#> $new_predictions
#> [1] "h2"
#> 
#> $corroborated_new
#> [1] "h2"
#> 
#> $ad_hoc_assumptions
#> character(0)
#> 
```
