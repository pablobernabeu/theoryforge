# Bibliometric map of a literature corpus (deterministic)

Computes keyword co-occurrence, thematic components, and reference
co-citation for a corpus. Records iterate in file order.

## Usage

``` r
tf_litmap(corpus, min_link = 2)
```

## Arguments

- corpus:

  A corpus object (named list), e.g. from
  [`tf_read_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read_corpus.md).

- min_link:

  Minimum co-occurrence count for an edge to be kept (default `2`).

## Value

A named list with elements `n_records`, `keywords`,
`keyword_cooccurrence`, `themes`, and `co_citation`.

## Examples

``` r
corpus <- list(
  schema_version = "1.0", id = "demo-corpus",
  records = list(
    list(id = "w1", keywords = list("arousal", "threat")),
    list(id = "w2", keywords = list("arousal", "threat"))
  )
)
tf_litmap(corpus)
#> $n_records
#> [1] 2
#> 
#> $keywords
#> $keywords[[1]]
#> [1] "arousal"
#> 
#> $keywords[[2]]
#> [1] "threat"
#> 
#> 
#> $keyword_cooccurrence
#> $keyword_cooccurrence[[1]]
#> $keyword_cooccurrence[[1]]$a
#> [1] "arousal"
#> 
#> $keyword_cooccurrence[[1]]$b
#> [1] "threat"
#> 
#> $keyword_cooccurrence[[1]]$count
#> [1] 2
#> 
#> 
#> 
#> $themes
#> $themes[[1]]
#> $themes[[1]]$id
#> [1] "theme_1"
#> 
#> $themes[[1]]$keywords
#> $themes[[1]]$keywords[[1]]
#> [1] "arousal"
#> 
#> $themes[[1]]$keywords[[2]]
#> [1] "threat"
#> 
#> 
#> $themes[[1]]$size
#> [1] 2
#> 
#> 
#> 
#> $co_citation
#> list()
#> 
```
