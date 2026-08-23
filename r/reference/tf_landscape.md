# Map a theory and its alternatives onto a literature landscape (deterministic)

Maps a theory's focal constructs and its registered alternatives onto
the thematic structure of a corpus (computed by
[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)).
Each theme is tagged `"under_theorised"`, `"covered"`, or `"crowded"`.

## Usage

``` r
tf_landscape(theory, corpus, min_link = 2)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- corpus:

  A corpus object (named list), e.g. from
  [`tf_read_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read_corpus.md).

- min_link:

  Minimum co-occurrence count passed to
  [`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)
  (default `2`).

## Value

A named list with elements `theory_id`, `themes` (each
`{id, keywords, alternatives, focal, status}`),
`under_theorised_fronts`, and `redundancy_risk`.

## Examples

``` r
theory <- tf_theory("demo-1", "Arousal and threat") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
corpus <- list(
  schema_version = "1.0", id = "demo-corpus",
  records = list(
    list(id = "w1", keywords = list("arousal", "threat")),
    list(id = "w2", keywords = list("arousal", "threat"))
  )
)
tf_landscape(theory, corpus)
#> $theory_id
#> [1] "demo-1"
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
#> $themes[[1]]$alternatives
#> list()
#> 
#> $themes[[1]]$focal
#> [1] TRUE
#> 
#> $themes[[1]]$status
#> [1] "covered"
#> 
#> 
#> 
#> $under_theorised_fronts
#> list()
#> 
#> $redundancy_risk
#> list()
#> 
```
