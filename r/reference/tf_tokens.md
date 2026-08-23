# Tokenise a string into a set of content tokens

Lowercases, replaces every run of non-`[a-z0-9]` characters with a
single space, splits, drops tokens shorter than 3 characters and the
canonical stopwords, then returns the unique set.

## Usage

``` r
tf_tokens(s)
```

## Arguments

- s:

  A single string (or `NULL`, treated as "").

## Value

A character vector of unique tokens (possibly empty).

## Examples

``` r
tf_tokens("The physiological arousal response to a threat")
#> [1] "physiological" "arousal"       "response"      "threat"       
```
