# Pairwise lexical similarity of construct definitions

Computes Jaccard similarity for every unordered pair of construct
definitions. Returns a data frame with one row per pair, sorted by
descending similarity then `(a, b)` ascending. The `flag` column is
`"review"` when similarity meets or exceeds the configured
`redundancy_similarity_max` threshold, otherwise `"ok"`.

## Usage

``` r
tf_redundancy_check(theory)
```

## Arguments

- theory:

  A theory object (named list).

## Value

A data frame with columns `a`, `b`, `similarity`, `flag`.

## References

Le, H., Schmidt, F. L., Harter, J. K., & Lauver, K. J. (2010). The
problem of empirical redundancy of constructs. *Organizational Behavior
and Human Decision Processes*, 112(2), 112-125.
[doi:10.1016/j.obhdp.2010.02.003](https://doi.org/10.1016/j.obhdp.2010.02.003)

Lawson, K. M., & Robins, R. W. (2021). Sibling constructs. *Personality
and Social Psychology Review*, 25(4), 344-366.
[doi:10.1177/10888683211047101](https://doi.org/10.1177/10888683211047101)

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal",
                   "Bodily activation in response to a stressor.") |>
  tf_add_construct("c_threat", "Perceived threat",
                   "Appraised danger in response to a stressor.")
tf_redundancy_check(theory)
#>           a        b similarity flag
#> 1 c_arousal c_threat      0.333   ok
```
