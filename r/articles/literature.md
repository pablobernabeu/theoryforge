# Mapping the literature

A theory is rarely built in isolation. It sits within a field that
already has crowded areas, sparse areas and recurring sets of
references. The literature layer of `theoryforge` gives a deterministic,
machine-checkable account of that field, so the placement of a theory
within it can be argued from evidence rather than from impression. This
article reads a small corpus, computes a bibliometric map, positions a
theory against the map, and emits a diagram. The analysis functions are
parity-tested against [the Python
twin](https://pablobernabeu.github.io/theoryforge/python/) and require
no optional dependency.

``` r

library(theoryforge)
```

## Reading a corpus

A corpus is a simple object of the form `{schema_version, id, records}`,
where each record carries an `id` and may carry `title`, `year`,
`keywords` and `references`. The package ships a small fixture corpus
around panic and anxiety research. The format is chosen by file
extension, so the same reader handles YAML and JSON.

``` r

corpus_path <- system.file("fixtures/panic-corpus.yaml", package = "theoryforge")
corpus <- tf_read_corpus(corpus_path)

corpus$id
#> [1] "panic-corpus-demo"
length(corpus$records)   # number of works in the corpus
#> [1] 8
corpus$records[[1]]       # first record
#> $id
#> [1] "r1"
#> 
#> $title
#> [1] "Interoceptive accuracy and panic"
#> 
#> $year
#> [1] 2018
#> 
#> $keywords
#> [1] "arousal"       "interoception"
#> 
#> $references
#> [1] "clark1986"  "barlow2002"
```

## Building a literature map

[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)
computes three things from the records. It counts keyword co-occurrence
within records, groups co-occurring keywords into thematic components,
and counts reference co-citation. An edge is kept only when its
co-occurrence count reaches `min_link` (default `2`), which suppresses
incidental pairings. Records are read in file order and every result is
sorted, so the map is fully deterministic.

``` r

lm <- tf_litmap(corpus, min_link = 2)

lm$n_records
#> [1] 8
unlist(lm$keywords)                 # the vocabulary of the corpus
#> [1] "appraisal"                      "arousal"                       
#> [3] "avoidance"                      "catastrophic misinterpretation"
#> [5] "exposure"                       "genetics"                      
#> [7] "heritability"                   "interoception"
lm$keyword_cooccurrence[[1]]        # first kept co-occurrence edge
#> $a
#> [1] "appraisal"
#> 
#> $b
#> [1] "catastrophic misinterpretation"
#> 
#> $count
#> [1] 2
```

The thematic components are the connected groups of co-occurring
keywords. The fixture is constructed so that the threshold-two graph
separates cleanly into four themes.

``` r

for (theme in lm$themes) {
  cat(theme$id, ":", paste(unlist(theme$keywords), collapse = ", "), "\n")
}
#> theme_1 : appraisal, catastrophic misinterpretation 
#> theme_2 : arousal, interoception 
#> theme_3 : avoidance, exposure 
#> theme_4 : genetics, heritability
```

Co-citation is computed the same way over the `references` field. Two
works are linked when they cite the same pair of sources at least
`min_link` times.

``` r

lm$co_citation
#> [[1]]
#> [[1]]$a
#> [1] "barlow2002"
#> 
#> [[1]]$b
#> [1] "clark1986"
#> 
#> [[1]]$count
#> [1] 3
#> 
#> 
#> [[2]]
#> [[2]]$a
#> [1] "bouton2001"
#> 
#> [[2]]$b
#> [1] "craske2008"
#> 
#> [[2]]$count
#> [1] 2
```

## Positioning a theory against the field

[`tf_landscape()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_landscape.md)
maps a theory’s focal constructs and its registered alternatives onto
the themes from
[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md).
A theme is tagged `"under_theorised"` when neither the focal theory nor
any alternative touches it, `"covered"` when exactly one does, and
`"crowded"` when two or more do. Matching is by shared tokens between
the theme keywords and the text of the construct labels, the theory
title and the alternatives.

We build a small theory whose constructs speak to arousal and to
appraisal, and register one alternative that also speaks to appraisal.
This leaves the arousal theme covered, the appraisal theme crowded and
the remaining themes untouched.

``` r

theory <- tf_theory("panic-appraisal", "Arousal and appraisal in panic") |>
  tf_add_construct("c_arousal", "Physiological arousal",
                   "Bodily activation in response to a stressor.") |>
  tf_add_construct("c_appraisal", "Threat appraisal",
                   "Catastrophic appraisal of bodily sensations.") |>
  tf_add_alternative("alt_cog", "Cognitive appraisal account",
                     key_constructs = c("appraisal"))

landscape <- tf_landscape(theory, corpus, min_link = 2)
landscape$theory_id
#> [1] "panic-appraisal"
```

Each theme in the result records which alternatives land on it, whether
the focal theory lands on it, and the resulting status.

``` r

for (theme in landscape$themes) {
  cat(theme$id,
      "| status:", theme$status,
      "| focal:", theme$focal,
      "| alternatives:", paste(unlist(theme$alternatives), collapse = ", "),
      "\n")
}
#> theme_1 | status: crowded | focal: TRUE | alternatives: alt_cog 
#> theme_2 | status: covered | focal: TRUE | alternatives:  
#> theme_3 | status: under_theorised | focal: FALSE | alternatives:  
#> theme_4 | status: under_theorised | focal: FALSE | alternatives:
```

Two summaries draw out the practical reading. The under-theorised fronts
are themes that the field around this theory has not yet engaged, and so
are candidates for new work. The redundancy risk lists crowded themes,
where a new contribution would have to distinguish itself from existing
accounts.

``` r

unlist(landscape$under_theorised_fronts)
#> [1] "theme_3" "theme_4"
unlist(landscape$redundancy_risk)
#> [1] "theme_1"
```

## Emitting a literature diagram

[`tf_lit_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_lit_diagram.md)
renders a byte-identical Graphviz DOT string for the literature layer.
The keyword co-occurrence and co-citation maps render as undirected
graphs, and a landscape result renders as a directed theme map. The
output is a plain string, so it can be written to a `.dot` file or
passed to a Graphviz renderer.

``` r

cat(tf_lit_diagram(lm, type = "keyword_cooccurrence"))
#> graph keyword_cooccurrence {
#>   node [shape=ellipse];
#>   "appraisal";
#>   "arousal";
#>   "avoidance";
#>   "catastrophic misinterpretation";
#>   "exposure";
#>   "genetics";
#>   "heritability";
#>   "interoception";
#>   "appraisal" -- "catastrophic misinterpretation" [label="2"];
#>   "arousal" -- "interoception" [label="2"];
#>   "avoidance" -- "exposure" [label="2"];
#>   "genetics" -- "heritability" [label="2"];
#> }
```

The theme landscape diagram is produced from the
[`tf_landscape()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_landscape.md)
result rather than from the map, since it carries the focal theory and
the alternatives.

``` r

cat(tf_lit_diagram(landscape, type = "theme_landscape"))
#> digraph theme_landscape {
#>   rankdir=LR;
#>   node [shape=box];
#>   "theme_1" [label="theme_1: appraisal, catastrophic misinterpretation (crowded)"];
#>   "theme_2" [label="theme_2: arousal, interoception (covered)"];
#>   "theme_3" [label="theme_3: avoidance, exposure (under_theorised)"];
#>   "theme_4" [label="theme_4: genetics, heritability (under_theorised)"];
#>   "alt_cog" [label="alt_cog", shape=ellipse];
#>   "focal" [label="focal", shape=ellipse, style=bold];
#>   "alt_cog" -> "theme_1";
#>   "focal" -> "theme_1";
#>   "focal" -> "theme_2";
#> }
```

These strings are compared byte-for-byte against the Python reference
outputs in the package tests, which guarantees that an R analysis and a
Python analysis of the same corpus agree exactly.

## Building a corpus from OpenAlex

The corpus above was read from a file. A corpus can also be assembled
from the OpenAlex works API with
[`tf_fetch_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_fetch_corpus.md).
This adapter is assistive and parity-exempt. It makes a live network
call, its result depends on an external service that changes over time,
and it is therefore excluded from the deterministic core, the parity
tests and continuous integration. The call is shown here but not run,
and the supplied email enters the OpenAlex polite pool.

``` r

fetched <- tf_fetch_corpus("panic disorder interoception",
                           per_page = 25,
                           mailto = "me@example.org")
fetched_map <- tf_litmap(fetched)
```

Once fetched, the corpus object has the same shape as a file-read
corpus, so it flows into
[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md),
[`tf_landscape()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_landscape.md)
and
[`tf_lit_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_lit_diagram.md)
without any further change. The recommended pattern is to fetch once,
write the result to disk, and then work from the saved file so that
later analyses remain reproducible.
