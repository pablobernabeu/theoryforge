# Pairwise lexical similarity of construct definitions

Compares the definitions of every unordered pair of constructs and
returns a data frame with one row per pair, sorted by descending
similarity then `(a, b)` ascending. `similarity` is the Jaccard index of
the two definitions' token sets and `overlap` their overlap coefficient,
the shared tokens over the tokens of the shorter definition. `flag` is
`"review"` for a near-duplicate, a similarity at or above the
checklist's `redundancy_similarity_max`, and for a definition contained
in the other, an overlap at or above `redundancy_overlap_max` when both
definitions hold at least three tokens. It is `"ok"` otherwise.

## Usage

``` r
tf_redundancy_check(theory)
```

## Arguments

- theory:

  A theory object (named list).

## Value

A data frame with columns `a`, `b`, `similarity`, `overlap`, `flag`.

## Details

The screen compares words, so it cannot detect empirical redundancy, two
differently defined constructs that correlate almost perfectly once
measurement error is corrected for (Le et al., 2010). Sibling constructs
(Lawson & Robins, 2021) may share vocabulary without being redundant.

## References

Le, H., Schmidt, F. L., Harter, J. K., & Lauver, K. J. (2010). The
problem of empirical redundancy of constructs in organizational
research: An empirical investigation. *Organizational Behavior and Human
Decision Processes*, 112(2), 112-125.
[doi:10.1016/j.obhdp.2010.02.003](https://doi.org/10.1016/j.obhdp.2010.02.003)

Lawson, K. M., & Robins, R. W. (2021). Sibling constructs: What are
they, why do they matter, and how should you handle them? *Personality
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
#>           a        b similarity overlap flag
#> 1 c_arousal c_threat      0.333     0.5   ok
```
