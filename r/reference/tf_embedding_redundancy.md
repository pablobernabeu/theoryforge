# Embedding-based pairwise construct-redundancy screen

For every unordered pair of constructs, embeds each definition with the
supplied `embedder` and computes the cosine similarity (rounded to 6
decimals). Returns a data frame sorted by descending cosine then
`(a, b)`, flagging pairs at or above `threshold` for review. This
assistive screen complements the deterministic lexical
[`tf_redundancy_check()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_redundancy_check.md),
and its results are only as reproducible as the supplied `embedder`.

## Usage

``` r
tf_embedding_redundancy(theory, embedder, threshold = NULL)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- embedder:

  A function mapping a definition string to a numeric vector.

- threshold:

  Cosine threshold for the `"review"` flag; defaults to the checklist's
  `redundancy_similarity_max`.

## Value

A data frame with columns `a`, `b`, `cosine`, `flag`.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "bodily activation") |>
  tf_add_construct("c_threat", "Threat", "appraised danger")
# A toy deterministic embedder: bag-of-words counts over a fixed vocabulary.
vocab <- c("bodily", "activation", "appraised", "danger")
embedder <- function(def) {
  words <- strsplit(tolower(def), "\\s+")[[1]]
  vapply(vocab, function(w) sum(words == w), numeric(1))
}
tf_embedding_redundancy(theory, embedder)
#>           a        b cosine flag
#> 1 c_arousal c_threat      0   ok
```
