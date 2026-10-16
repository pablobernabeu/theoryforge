# Map a theory and its alternatives onto a literature landscape (deterministic)

Maps a theory's focal constructs and its registered alternatives onto
the thematic structure of a corpus (computed by
[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)).
Each theme is tagged `"under_theorised"`, `"covered"`, or `"crowded"`.

## Usage

``` r
tf_landscape(
  theory,
  corpus,
  min_link = 2,
  max_token_share = 0.5,
  method = "components"
)
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
  (default `2`). The co-citation map, which the landscape does not use,
  is not computed.

- max_token_share:

  A number from 0 to 1 (default `0.5`). A word in the keywords of more
  than this share of the records is a field token and never matches.

- method:

  How
  [`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)
  builds the themes: `"components"` (the default) or `"simple_centres"`.

## Value

A named list with elements `theory_id`, `max_token_share`,
`field_tokens`, `phenomenon_tokens`, `themes`, `under_theorised_fronts`
and `redundancy_risk`. Each theme holds `id`, `keywords`,
`alternatives`, `focal`, `status`, `focal_terms` and
`alternative_terms`, the last a list of `{id, terms}` in the order of
`alternatives`.

## Details

A theme is matched by the words its keywords share with the focal
theory's construct labels, or with an alternative's label and key
constructs, and every match reports those words (`focal_terms` and
`alternative_terms`). Three kinds of word never match. Field tokens, the
words most of the corpus shares, are those in the keywords of more than
`max_token_share` of the records. Phenomenon tokens are the words of the
theory's title, which names the phenomenon that the focal theory and its
rivals all explain. A construct word that also appears in the title does
not match either. The third kind is a fixed list of words that name a
kind of account: theory, model, account, hypothesis, framework and
approach, with their plurals. One shared word is enough for a match.

The statuses count the registered accounts, the focal theory and its
registered alternatives, that address a theme. A theme is
`"under_theorised"` when none of them addresses it, which says nothing
of accounts the theory does not register, `"covered"` when one does and
`"crowded"` when two or more do. A crowded theme calls for predictions
that discriminate between the accounts, and is not a finding of
redundancy. The two lists keep their 0.6.0 names,
`under_theorised_fronts` and `redundancy_risk`.

The arguments are checked in the order `min_link`, `max_token_share`,
`method`, then the corpus, with the Python twin's messages. The themes
are those of
[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md),
built by `method` with its other defaults. With `"components"`,
`tf_landscape()` gives the warning of
[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)
when one theme holds most of the linked keywords. With
`"simple_centres"`, the result gains `method` after `theory_id`, and
each theme its `centrality`, `density` and `quadrant`.

## Examples

``` r
theory <- tf_theory("demo-1", "A theory of panic") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.")
corpus <- list(
  schema_version = "1.0", id = "demo-corpus",
  records = list(
    list(id = "w1", keywords = list("arousal", "threat")),
    list(id = "w2", keywords = list("arousal", "threat")),
    list(id = "w3", keywords = list("avoidance", "exposure")),
    list(id = "w4", keywords = list("avoidance", "exposure"))
  )
)
tf_landscape(theory, corpus)
#> $theory_id
#> [1] "demo-1"
#> 
#> $max_token_share
#> [1] 0.5
#> 
#> $field_tokens
#> list()
#> 
#> $phenomenon_tokens
#> $phenomenon_tokens[[1]]
#> [1] "panic"
#> 
#> $phenomenon_tokens[[2]]
#> [1] "theory"
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
#> $themes[[1]]$alternatives
#> list()
#> 
#> $themes[[1]]$focal
#> [1] TRUE
#> 
#> $themes[[1]]$status
#> [1] "covered"
#> 
#> $themes[[1]]$focal_terms
#> $themes[[1]]$focal_terms[[1]]
#> [1] "arousal"
#> 
#> 
#> $themes[[1]]$alternative_terms
#> list()
#> 
#> 
#> $themes[[2]]
#> $themes[[2]]$id
#> [1] "theme_2"
#> 
#> $themes[[2]]$keywords
#> $themes[[2]]$keywords[[1]]
#> [1] "avoidance"
#> 
#> $themes[[2]]$keywords[[2]]
#> [1] "exposure"
#> 
#> 
#> $themes[[2]]$alternatives
#> list()
#> 
#> $themes[[2]]$focal
#> [1] FALSE
#> 
#> $themes[[2]]$status
#> [1] "under_theorised"
#> 
#> $themes[[2]]$focal_terms
#> list()
#> 
#> $themes[[2]]$alternative_terms
#> list()
#> 
#> 
#> 
#> $under_theorised_fronts
#> $under_theorised_fronts[[1]]
#> [1] "theme_2"
#> 
#> 
#> $redundancy_risk
#> list()
#> 
```
