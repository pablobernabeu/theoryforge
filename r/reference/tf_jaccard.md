# Jaccard similarity of two token sets

Returns 0.0 if both sets are empty, otherwise the size of the
intersection divided by the size of the union, rounded to 3 decimals.

## Usage

``` r
tf_jaccard(a, b)
```

## Arguments

- a, b:

  Character vectors of tokens (treated as sets).

## Value

A numeric similarity in `[0, 1]`.

## Examples

``` r
tf_jaccard(tf_tokens("arousal threat response"),
           tf_tokens("threat appraisal response"))
#> [1] 0.5
```
