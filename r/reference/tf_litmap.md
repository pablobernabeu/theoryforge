# Bibliometric map of a literature corpus (deterministic)

Computes keyword co-occurrence, thematic components, and reference
co-citation for a corpus. Records iterate in file order.

## Usage

``` r
tf_litmap(
  corpus,
  min_link = 2,
  method = "components",
  min_cocitation = NULL,
  min_theme_size = 2,
  max_theme_size = 10,
  max_df = 1
)
```

## Arguments

- corpus:

  A corpus object (named list), e.g. from
  [`tf_read_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read_corpus.md).

- min_link:

  Minimum co-occurrence count for a keyword pair to be kept (default
  `2`). A positive integer.

- method:

  `"components"` (the default) or `"simple_centres"`.

- min_cocitation:

  Minimum count for a reference pair to be kept in `co_citation`. `NULL`
  (the default) uses `min_link`.

- min_theme_size, max_theme_size:

  The smallest theme kept (default `2`) and the largest a theme may grow
  (default `10`) with `"simple_centres"`. A positive integer, and an
  integer of at least 2 no smaller than `min_theme_size`.

- max_df:

  A number from 0 to 1 (default `1`). With `"simple_centres"`, a keyword
  in more than this share of the records is a field term, left out of
  the map and listed in `field_terms`. The three theme settings are
  checked with either method, although only `"simple_centres"` reads
  them.

## Value

A named list with elements `n_records`, `keywords`,
`keyword_cooccurrence`, `themes`, and `co_citation`. With
`"simple_centres"`, each theme also holds `centrality`, `density` and
`quadrant`, and the list ends with `method`, `parameters` (the five
settings used) and `field_terms`.

## Details

The corpus is checked before anything is counted, with the Python twin's
messages. It must hold a `records` list of mappings (an empty list is an
empty corpus). A keyword or reference that is an integer becomes its
decimal string, so an unquoted PubMed or Scopus id keys the same work in
both languages; one of \\2^{53}\\ or more is refused, since R cannot
hold it exactly. A logical, a fraction or a nested value is refused: an
unquoted `NO` (nitric oxide) or `on` in YAML is read as a logical, so
quote it.

Co-citation maps of real corpora are large. 200 OpenAlex records give
about 11,000 reference pairs that share two or more citing records, so
`min_cocitation` can be set above `min_link`, and
[`tf_lit_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_lit_diagram.md)
can draw only the strongest edges.

`method` chooses how keywords are grouped into themes. With
`"components"`, the default, a theme is a connected component of the
keyword map, and on a real corpus a few keywords shared by most records
join nearly every keyword into one. When the largest theme holds more
than half the linked keywords, a warning says so: such themes, and any
landscape built on them, do not describe the field. The result is
returned unchanged.

`"simple_centres"` is the co-word clustering of Coulter et al. (1998)
and Cobo et al. (2011). Each link is weighted by the equivalence index
\\c^2 / (df_a df_b)\\, where \\c\\ counts the records holding both
keywords and \\df\\ the records holding each. The strongest link between
two unassigned keywords seeds a theme, which takes its strongest
unassigned neighbour until it holds `max_theme_size` keywords, ties
going to the keyword first in code-point order. A keyword whose links
all reach keywords already in themes joins none. Themes smaller than
`min_theme_size` are dropped. Each theme gains its centrality (ten times
the summed index of its links to the keywords of other themes) and its
density (100 times the summed index of its internal links, over its
size), the measures of Callon et al. (1991) as Cobo et al. (2011) scale
them. It also gains its quadrant in the strategic diagram, split here at
the median of each: `"motor"` (both high), `"basic"` (central but not
dense), `"niche"` (dense but not central) or `"emerging_or_declining"`
(both low). On real corpora, this gives bounded themes where components
give one. Components remain the default for this release.

## References

Callon, M., Courtial, J. P., & Laville, F. (1991). Co-word analysis as a
tool for describing the network of interactions between basic and
technological research: The case of polymer chemistry. *Scientometrics,
22*(1), 155-205.
[doi:10.1007/BF02019280](https://doi.org/10.1007/BF02019280)

Coulter, N., Monarch, I., & Konda, S. (1998). Software engineering as
seen through its research literature: A study in co-word analysis.
*Journal of the American Society for Information Science, 49*(13),
1206-1223.

Cobo, M. J., López-Herrera, A. G., Herrera-Viedma, E., & Herrera, F.
(2011). An approach for detecting, quantifying, and visualizing the
evolution of a research field: A practical application to the Fuzzy Sets
Theory field. *Journal of Informetrics, 5*(1), 146-166.
[doi:10.1016/j.joi.2010.10.002](https://doi.org/10.1016/j.joi.2010.10.002)

## Examples

``` r
corpus <- list(
  schema_version = "1.0", id = "demo-corpus",
  records = list(
    list(id = "w1", keywords = list("arousal", "threat")),
    list(id = "w2", keywords = list("arousal", "threat")),
    list(id = "w3", keywords = list("avoidance", "exposure")),
    list(id = "w4", keywords = list("avoidance", "exposure"))
  )
)
tf_litmap(corpus)
#> $n_records
#> [1] 4
#> 
#> $keywords
#> $keywords[[1]]
#> [1] "arousal"
#> 
#> $keywords[[2]]
#> [1] "avoidance"
#> 
#> $keywords[[3]]
#> [1] "exposure"
#> 
#> $keywords[[4]]
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
#> $keyword_cooccurrence[[2]]
#> $keyword_cooccurrence[[2]]$a
#> [1] "avoidance"
#> 
#> $keyword_cooccurrence[[2]]$b
#> [1] "exposure"
#> 
#> $keyword_cooccurrence[[2]]$count
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
#> $themes[[2]]$size
#> [1] 2
#> 
#> 
#> 
#> $co_citation
#> list()
#> 

# Simple centres on the frozen OpenAlex corpus, where components give one
# theme.
openalex <- tf_read_corpus(tf_example_path("openalex-panic-2026.corpus.yaml"))
lm <- tf_litmap(openalex, method = "simple_centres")
table(vapply(lm$themes, function(th) th$quadrant, character(1)))
#> 
#>                 basic emerging_or_declining                 motor 
#>                     5                     3                     4 
#>                 niche 
#>                     5 
```
