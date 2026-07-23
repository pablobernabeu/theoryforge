# Mapping the literature

A theory is rarely built in isolation. It sits within a field that
already has crowded areas, sparse areas and recurring sets of
references. The literature layer of `theoryforge` gives a deterministic,
machine-checkable account of that field, so the placement of a theory
within it can be argued from evidence rather than from impression. This
article reads a small corpus, computes a bibliometric map, positions a
theory against the map, and emits a diagram. The analysis functions are
deterministic and require no optional dependency.

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
cited sources are linked when at least `min_link` records in the corpus
cite them together.

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
renders a deterministic Graphviz DOT string for the literature layer.
The keyword co-occurrence and co-citation maps render as undirected
graphs, and a landscape result renders as a directed theme map. The
output is a plain string, so it can be written to a `.dot` file or
passed to a Graphviz renderer.

``` r

cat(tf_lit_diagram(lm, type = "keyword_cooccurrence"))
```

    graph keyword_cooccurrence {
      graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      node [shape=ellipse, style="filled", fillcolor="#E4F1F1", color="#1E7B7B"];
      "appraisal";
      "arousal";
      "avoidance";
      "catastrophic misinterpretation";
      "exposure";
      "genetics";
      "heritability";
      "interoception";
      "appraisal" -- "catastrophic misinterpretation" [label="2"];
      "arousal" -- "interoception" [label="2"];
      "avoidance" -- "exposure" [label="2"];
      "genetics" -- "heritability" [label="2"];
    }

[`tf_render_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_render_diagram.md)
accepts a DOT string as well as a theory, so the literature diagrams
render the same way as the theory views.

``` r

cat('<div class="tf-figure tf-diagram">', tf_render_diagram(tf_lit_diagram(lm, type = "keyword_cooccurrence"), as = "svg"), '</div>', sep = "")
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iNDA4cHQiIGhlaWdodD0iMjQ3cHQiIHZpZXdib3g9IjAuMDAgMC4wMCA0MDguMjYgMjQ3LjI3IiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgMjMyLjg2NjYpIj48dGl0bGU+CmtleXdvcmRfY29vY2N1cnJlbmNlCjwvdGl0bGU+CjwhLS0gYXBwcmFpc2FsIC0tPjxnIGlkPSJub2RlMSIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KYXBwcmFpc2FsCjwvdGl0bGU+CjxlbGxpcHNlIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGN4PSI1Mi40MTgiIGN5PSItMTkuMjMzMyIgcng9IjQ4LjU0MDgiIHJ5PSIxOS40Njk1Ij48L2VsbGlwc2U+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTIuNDE4IiB5PSItMTUuOTMzMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hcHByYWlzYWw8L3RleHQ+PC9nPjwhLS0gY2F0YXN0cm9waGljIG1pc2ludGVycHJldGF0aW9uIC0tPjxnIGlkPSJub2RlNCIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KY2F0YXN0cm9waGljIG1pc2ludGVycHJldGF0aW9uCjwvdGl0bGU+CjxlbGxpcHNlIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGN4PSIyNjAuOTI4NCIgY3k9Ii0xOS4yMzMzIiByeD0iMTE4LjU2NjYiIHJ5PSIxOS40Njk1Ij48L2VsbGlwc2U+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjYwLjkyODQiIHk9Ii0xNS45MzMzIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmNhdGFzdHJvcGhpYwptaXNpbnRlcnByZXRhdGlvbjwvdGV4dD48L2c+PCEtLSBhcHByYWlzYWwmIzQ1OyYjNDU7Y2F0YXN0cm9waGljIG1pc2ludGVycHJldGF0aW9uIC0tPjxnIGlkPSJlZGdlMSIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KYXBwcmFpc2FsLS1jYXRhc3Ryb3BoaWMgbWlzaW50ZXJwcmV0YXRpb24KPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNMTAxLjA0MTMsLTE5LjIzMzNDMTEzLjU1NjUsLTE5LjIzMzMgMTI3LjU4NDMsLTE5LjIzMzMgMTQxLjk5MzgsLTE5LjIzMzMiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTIzLjYxNTYiIHk9Ii0yMi4yMzMzIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTAuMDAiIGZpbGw9IiMwZjZlNmUiPjI8L3RleHQ+PC9nPjwhLS0gYXJvdXNhbCAtLT48ZyBpZD0ibm9kZTIiIGNsYXNzPSJub2RlIj48dGl0bGU+CmFyb3VzYWwKPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iI2U0ZjFmMSIgc3Ryb2tlPSIjMWU3YjdiIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjUyLjQxOCIgY3k9Ii03OS4yMzMzIiByeD0iNDIuNDQxMSIgcnk9IjE5LjQ2OTUiPjwvZWxsaXBzZT48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI1Mi40MTgiIHk9Ii03NS45MzMzIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmFyb3VzYWw8L3RleHQ+PC9nPjwhLS0gaW50ZXJvY2VwdGlvbiAtLT48ZyBpZD0ibm9kZTgiIGNsYXNzPSJub2RlIj48dGl0bGU+CmludGVyb2NlcHRpb24KPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iI2U0ZjFmMSIgc3Ryb2tlPSIjMWU3YjdiIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjI2MC45Mjg0IiBjeT0iLTc5LjIzMzMiIHJ4PSI2MS40ODI2IiByeT0iMTkuNDY5NSI+PC9lbGxpcHNlPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI2MC45Mjg0IiB5PSItNzUuOTMzMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5pbnRlcm9jZXB0aW9uPC90ZXh0PjwvZz48IS0tIGFyb3VzYWwmIzQ1OyYjNDU7aW50ZXJvY2VwdGlvbiAtLT48ZyBpZD0iZWRnZTIiIGNsYXNzPSJlZGdlIj48dGl0bGU+CmFyb3VzYWwtLWludGVyb2NlcHRpb24KPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNOTUuMTE2NCwtNzkuMjMzM0MxMjUuMTQxLC03OS4yMzMzIDE2NS43Nzc5LC03OS4yMzMzIDE5OS4zMDcxLC03OS4yMzMzIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjEyMy42MTU2IiB5PSItODIuMjMzMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjEwLjAwIiBmaWxsPSIjMGY2ZTZlIj4yPC90ZXh0PjwvZz48IS0tIGF2b2lkYW5jZSAtLT48ZyBpZD0ibm9kZTMiIGNsYXNzPSJub2RlIj48dGl0bGU+CmF2b2lkYW5jZQo8L3RpdGxlPgo8ZWxsaXBzZSBmaWxsPSIjZTRmMWYxIiBzdHJva2U9IiMxZTdiN2IiIHN0cm9rZS13aWR0aD0iMS4xIiBjeD0iNTIuNDE4IiBjeT0iLTEzOS4yMzMzIiByeD0iNTIuMzM2MiIgcnk9IjE5LjQ2OTUiPjwvZWxsaXBzZT48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI1Mi40MTgiIHk9Ii0xMzUuOTMzMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hdm9pZGFuY2U8L3RleHQ+PC9nPjwhLS0gZXhwb3N1cmUgLS0+PGcgaWQ9Im5vZGU1IiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpleHBvc3VyZQo8L3RpdGxlPgo8ZWxsaXBzZSBmaWxsPSIjZTRmMWYxIiBzdHJva2U9IiMxZTdiN2IiIHN0cm9rZS13aWR0aD0iMS4xIiBjeD0iMjYwLjkyODQiIGN5PSItMTM5LjIzMzMiIHJ4PSI0OC45MTUxIiByeT0iMTkuNDY5NSI+PC9lbGxpcHNlPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI2MC45Mjg0IiB5PSItMTM1LjkzMzMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+ZXhwb3N1cmU8L3RleHQ+PC9nPjwhLS0gYXZvaWRhbmNlJiM0NTsmIzQ1O2V4cG9zdXJlIC0tPjxnIGlkPSJlZGdlMyIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KYXZvaWRhbmNlLS1leHBvc3VyZQo8L3RpdGxlPgo8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiM3YjkwOWYiIGQ9Ik0xMDUuMDM0LC0xMzkuMjMzM0MxMzcuODQ5LC0xMzkuMjMzMyAxNzkuNzk1NiwtMTM5LjIzMzMgMjExLjkxMDIsLTEzOS4yMzMzIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjEyMy42MTU2IiB5PSItMTQyLjIzMzMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMC4wMCIgZmlsbD0iIzBmNmU2ZSI+MjwvdGV4dD48L2c+PCEtLSBnZW5ldGljcyAtLT48ZyBpZD0ibm9kZTYiIGNsYXNzPSJub2RlIj48dGl0bGU+CmdlbmV0aWNzCjwvdGl0bGU+CjxlbGxpcHNlIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGN4PSI1Mi40MTgiIGN5PSItMTk5LjIzMzMiIHJ4PSI0NS44NjM3IiByeT0iMTkuNDY5NSI+PC9lbGxpcHNlPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjUyLjQxOCIgeT0iLTE5NS45MzMzIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmdlbmV0aWNzPC90ZXh0PjwvZz48IS0tIGhlcml0YWJpbGl0eSAtLT48ZyBpZD0ibm9kZTciIGNsYXNzPSJub2RlIj48dGl0bGU+Cmhlcml0YWJpbGl0eQo8L3RpdGxlPgo8ZWxsaXBzZSBmaWxsPSIjZTRmMWYxIiBzdHJva2U9IiMxZTdiN2IiIHN0cm9rZS13aWR0aD0iMS4xIiBjeD0iMjYwLjkyODQiIGN5PSItMTk5LjIzMzMiIHJ4PSI1MS45NDMyIiByeT0iMTkuNDY5NSI+PC9lbGxpcHNlPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjI2MC45Mjg0IiB5PSItMTk1LjkzMzMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+aGVyaXRhYmlsaXR5PC90ZXh0PjwvZz48IS0tIGdlbmV0aWNzJiM0NTsmIzQ1O2hlcml0YWJpbGl0eSAtLT48ZyBpZD0iZWRnZTQiIGNsYXNzPSJlZGdlIj48dGl0bGU+CmdlbmV0aWNzLS1oZXJpdGFiaWxpdHkKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNOTguNDM0NiwtMTk5LjIzMzNDMTMxLjA1NTYsLTE5OS4yMzMzIDE3NC44NzY4LC0xOTkuMjMzMyAyMDguNzkxNSwtMTk5LjIzMzMiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTIzLjYxNTYiIHk9Ii0yMDIuMjMzMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjEwLjAwIiBmaWxsPSIjMGY2ZTZlIj4yPC90ZXh0PjwvZz48L2c+PC9zdmc+)

The co-citation map links the references that the corpus cites together,
so tightly co-cited work stands out as the intellectual base the field
shares.

``` r

cat(tf_lit_diagram(lm, type = "co_citation"))
```

    graph co_citation {
      graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      node [shape=ellipse, style="filled", fillcolor="#E7EDF5", color="#33567A"];
      "barlow2002";
      "bouton2001";
      "clark1986";
      "craske2008";
      "barlow2002" -- "clark1986" [label="3"];
      "bouton2001" -- "craske2008" [label="2"];
    }

``` r

cat('<div class="tf-figure tf-diagram">', tf_render_diagram(tf_lit_diagram(lm, type = "co_citation"), as = "svg"), '</div>', sep = "")
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjk3cHQiIGhlaWdodD0iMTI3cHQiIHZpZXdib3g9IjAuMDAgMC4wMCAyOTYuNzkgMTI3LjI3IiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgMTEyLjg2NjYpIj48dGl0bGU+CmNvX2NpdGF0aW9uCjwvdGl0bGU+CjwhLS0gYmFybG93MjAwMiAtLT48ZyBpZD0ibm9kZTEiIGNsYXNzPSJub2RlIj48dGl0bGU+CmJhcmxvdzIwMDIKPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iI2U3ZWRmNSIgc3Ryb2tlPSIjMzM1NjdhIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjU4LjA0NzEiIGN5PSItMTkuMjMzMyIgcng9IjU3LjMzNjgiIHJ5PSIxOS40Njk1Ij48L2VsbGlwc2U+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTguMDQ3MSIgeT0iLTE1LjkzMzMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YmFybG93MjAwMjwvdGV4dD48L2c+PCEtLSBjbGFyazE5ODYgLS0+PGcgaWQ9Im5vZGUzIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgpjbGFyazE5ODYKPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iI2U3ZWRmNSIgc3Ryb2tlPSIjMzM1NjdhIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjIxMC44MjM3IiBjeT0iLTE5LjIzMzMiIHJ4PSI1MC44Njc3IiByeT0iMTkuNDY5NSI+PC9lbGxpcHNlPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjIxMC44MjM3IiB5PSItMTUuOTMzMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5jbGFyazE5ODY8L3RleHQ+PC9nPjwhLS0gYmFybG93MjAwMiYjNDU7JiM0NTtjbGFyazE5ODYgLS0+PGcgaWQ9ImVkZ2UxIiBjbGFzcz0iZWRnZSI+PHRpdGxlPgpiYXJsb3cyMDAyLS1jbGFyazE5ODYKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNMTE1LjM3MDEsLTE5LjIzMzNDMTI5LjkzMzQsLTE5LjIzMzMgMTQ1LjQ4NDIsLTE5LjIzMzMgMTU5LjcxNTcsLTE5LjIzMzMiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTM0Ljg3MzciIHk9Ii0yMi4yMzMzIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTAuMDAiIGZpbGw9IiMwZjZlNmUiPjM8L3RleHQ+PC9nPjwhLS0gYm91dG9uMjAwMSAtLT48ZyBpZD0ibm9kZTIiIGNsYXNzPSJub2RlIj48dGl0bGU+CmJvdXRvbjIwMDEKPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iI2U3ZWRmNSIgc3Ryb2tlPSIjMzM1NjdhIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjU4LjA0NzEiIGN5PSItNzkuMjMzMyIgcng9IjU4LjA5NDIiIHJ5PSIxOS40Njk1Ij48L2VsbGlwc2U+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNTguMDQ3MSIgeT0iLTc1LjkzMzMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+Ym91dG9uMjAwMTwvdGV4dD48L2c+PCEtLSBjcmFza2UyMDA4IC0tPjxnIGlkPSJub2RlNCIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KY3Jhc2tlMjAwOAo8L3RpdGxlPgo8ZWxsaXBzZSBmaWxsPSIjZTdlZGY1IiBzdHJva2U9IiMzMzU2N2EiIHN0cm9rZS13aWR0aD0iMS4xIiBjeD0iMjEwLjgyMzciIGN5PSItNzkuMjMzMyIgcng9IjU3LjM0MTUiIHJ5PSIxOS40Njk1Ij48L2VsbGlwc2U+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjEwLjgyMzciIHk9Ii03NS45MzMzIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmNyYXNrZTIwMDg8L3RleHQ+PC9nPjwhLS0gYm91dG9uMjAwMSYjNDU7JiM0NTtjcmFza2UyMDA4IC0tPjxnIGlkPSJlZGdlMiIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KYm91dG9uMjAwMS0tY3Jhc2tlMjAwOAo8L3RpdGxlPgo8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiM3YjkwOWYiIGQ9Ik0xMTYuMjQxMiwtNzkuMjMzM0MxMjguNDY4NCwtNzkuMjMzMyAxNDEuMzU1OSwtNzkuMjMzMyAxNTMuNTQ5MSwtNzkuMjMzMyIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIxMzQuODczNyIgeT0iLTgyLjIzMzMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMC4wMCIgZmlsbD0iIzBmNmU2ZSI+MjwvdGV4dD48L2c+PC9nPjwvc3ZnPg==)

The theme landscape diagram is produced from the
[`tf_landscape()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_landscape.md)
result rather than from the map, since it carries the focal theory and
the alternatives.

``` r

cat(tf_lit_diagram(landscape, type = "theme_landscape"))
```

    digraph theme_landscape {
      graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      "theme_1" [label="theme_1\nappraisal, catastrophic\nmisinterpretation\n(crowded)", fillcolor="#FBF1DC", color="#9C6B14"];
      "theme_2" [label="theme_2\narousal, interoception\n(covered)", fillcolor="#F1F1F1", color="#8A8A8A"];
      "theme_3" [label="theme_3\navoidance, exposure\n(under_theorised)", fillcolor="#E4F1F1", color="#1E7B7B"];
      "theme_4" [label="theme_4\ngenetics, heritability\n(under_theorised)", fillcolor="#E4F1F1", color="#1E7B7B"];
      "alt_cog" [label="alt_cog", shape=ellipse, fillcolor="#F1F1F1", color="#8A8A8A"];
      "focal" [label="focal", shape=ellipse, fillcolor="#12283A", color="#12283A", fontcolor="#FFFFFF"];
      "alt_cog" -> "theme_1";
      "focal" -> "theme_1";
      "focal" -> "theme_2";
    }

``` r

cat('<div class="tf-figure tf-diagram">', tf_render_diagram(tf_lit_diagram(landscape, type = "theme_landscape"), as = "svg"), '</div>', sep = "")
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMzIwcHQiIGhlaWdodD0iMzA4cHQiIHZpZXdib3g9IjAuMDAgMC4wMCAzMjAuMzAgMzA4LjQwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rIj48ZyBpZD0iZ3JhcGgwIiBjbGFzcz0iZ3JhcGgiIHRyYW5zZm9ybT0ic2NhbGUoMSAxKSByb3RhdGUoMCkgdHJhbnNsYXRlKDE0LjQgMjk0KSI+PHRpdGxlPgp0aGVtZV9sYW5kc2NhcGUKPC90aXRsZT4KPCEtLSB0aGVtZV8xIC0tPjxnIGlkPSJub2RlMSIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KdGhlbWVfMQo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZmJmMWRjIiBzdHJva2U9IiM5YzZiMTQiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMjc5LjUxNTIsLTE0Mi4xMDAzQzI3OS41MTUyLC0xNDIuMTAwMyAxNjkuNDY4OSwtMTQyLjEwMDMgMTY5LjQ2ODksLTE0Mi4xMDAzIDE2My40Njg5LC0xNDIuMTAwMyAxNTcuNDY4OSwtMTM2LjEwMDMgMTU3LjQ2ODksLTEzMC4xMDAzIDE1Ny40Njg5LC0xMzAuMTAwMyAxNTcuNDY4OSwtODcuNDk5NyAxNTcuNDY4OSwtODcuNDk5NyAxNTcuNDY4OSwtODEuNDk5NyAxNjMuNDY4OSwtNzUuNDk5NyAxNjkuNDY4OSwtNzUuNDk5NyAxNjkuNDY4OSwtNzUuNDk5NyAyNzkuNTE1MiwtNzUuNDk5NyAyNzkuNTE1MiwtNzUuNDk5NyAyODUuNTE1MiwtNzUuNDk5NyAyOTEuNTE1MiwtODEuNDk5NyAyOTEuNTE1MiwtODcuNDk5NyAyOTEuNTE1MiwtODcuNDk5NyAyOTEuNTE1MiwtMTMwLjEwMDMgMjkxLjUxNTIsLTEzMC4xMDAzIDI5MS41MTUyLC0xMzYuMTAwMyAyODUuNTE1MiwtMTQyLjEwMDMgMjc5LjUxNTIsLTE0Mi4xMDAzIiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjIyNC40OTIiIHk9Ii0xMjUuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj50aGVtZV8xPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjIyNC40OTIiIHk9Ii0xMTIuMSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hcHByYWlzYWwsCmNhdGFzdHJvcGhpYzwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyMjQuNDkyIiB5PSItOTguOSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5taXNpbnRlcnByZXRhdGlvbjwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyMjQuNDkyIiB5PSItODUuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj4oY3Jvd2RlZCk8L3RleHQ+PC9nPjwhLS0gdGhlbWVfMiAtLT48ZyBpZD0ibm9kZTIiIGNsYXNzPSJub2RlIj48dGl0bGU+CnRoZW1lXzIKPC90aXRsZT4KPHBhdGggZmlsbD0iI2YxZjFmMSIgc3Ryb2tlPSIjOGE4YThhIiBzdHJva2Utd2lkdGg9IjEuMSIgZD0iTTI3Ny4xMzAxLC01My40MDE1QzI3Ny4xMzAxLC01My40MDE1IDE3MS44NTQsLTUzLjQwMTUgMTcxLjg1NCwtNTMuNDAxNSAxNjUuODU0LC01My40MDE1IDE1OS44NTQsLTQ3LjQwMTUgMTU5Ljg1NCwtNDEuNDAxNSAxNTkuODU0LC00MS40MDE1IDE1OS44NTQsLTEyLjE5ODUgMTU5Ljg1NCwtMTIuMTk4NSAxNTkuODU0LC02LjE5ODUgMTY1Ljg1NCwtLjE5ODUgMTcxLjg1NCwtLjE5ODUgMTcxLjg1NCwtLjE5ODUgMjc3LjEzMDEsLS4xOTg1IDI3Ny4xMzAxLC0uMTk4NSAyODMuMTMwMSwtLjE5ODUgMjg5LjEzMDEsLTYuMTk4NSAyODkuMTMwMSwtMTIuMTk4NSAyODkuMTMwMSwtMTIuMTk4NSAyODkuMTMwMSwtNDEuNDAxNSAyODkuMTMwMSwtNDEuNDAxNSAyODkuMTMwMSwtNDcuNDAxNSAyODMuMTMwMSwtNTMuNDAxNSAyNzcuMTMwMSwtNTMuNDAxNSIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSIyMjQuNDkyIiB5PSItMzYuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj50aGVtZV8yPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjIyNC40OTIiIHk9Ii0yMy41IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPmFyb3VzYWwsCmludGVyb2NlcHRpb248L3RleHQ+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjI0LjQ5MiIgeT0iLTEwLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+KGNvdmVyZWQpPC90ZXh0PjwvZz48IS0tIHRoZW1lXzMgLS0+PGcgaWQ9Im5vZGUzIiBjbGFzcz0ibm9kZSI+PHRpdGxlPgp0aGVtZV8zCjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik0xMTMuNzIxNywtMjAzLjQwMTVDMTEzLjcyMTcsLTIwMy40MDE1IDExLjc1ODgsLTIwMy40MDE1IDExLjc1ODgsLTIwMy40MDE1IDUuNzU4OCwtMjAzLjQwMTUgLS4yNDEyLC0xOTcuNDAxNSAtLjI0MTIsLTE5MS40MDE1IC0uMjQxMiwtMTkxLjQwMTUgLS4yNDEyLC0xNjIuMTk4NSAtLjI0MTIsLTE2Mi4xOTg1IC0uMjQxMiwtMTU2LjE5ODUgNS43NTg4LC0xNTAuMTk4NSAxMS43NTg4LC0xNTAuMTk4NSAxMS43NTg4LC0xNTAuMTk4NSAxMTMuNzIxNywtMTUwLjE5ODUgMTEzLjcyMTcsLTE1MC4xOTg1IDExOS43MjE3LC0xNTAuMTk4NSAxMjUuNzIxNywtMTU2LjE5ODUgMTI1LjcyMTcsLTE2Mi4xOTg1IDEyNS43MjE3LC0xNjIuMTk4NSAxMjUuNzIxNywtMTkxLjQwMTUgMTI1LjcyMTcsLTE5MS40MDE1IDEyNS43MjE3LC0xOTcuNDAxNSAxMTkuNzIxNywtMjAzLjQwMTUgMTEzLjcyMTcsLTIwMy40MDE1IiAvPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjYyLjc0MDMiIHk9Ii0xODYuNyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj50aGVtZV8zPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjYyLjc0MDMiIHk9Ii0xNzMuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hdm9pZGFuY2UsCmV4cG9zdXJlPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjYyLjc0MDMiIHk9Ii0xNjAuMyIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj4odW5kZXJfdGhlb3Jpc2VkKTwvdGV4dD48L2c+PCEtLSB0aGVtZV80IC0tPjxnIGlkPSJub2RlNCIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KdGhlbWVfNAo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTRmMWYxIiBzdHJva2U9IiMxZTdiN2IiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNMTEwLjgxMTEsLTI3OS40MDE1QzExMC44MTExLC0yNzkuNDAxNSAxNC42Njk0LC0yNzkuNDAxNSAxNC42Njk0LC0yNzkuNDAxNSA4LjY2OTQsLTI3OS40MDE1IDIuNjY5NCwtMjczLjQwMTUgMi42Njk0LC0yNjcuNDAxNSAyLjY2OTQsLTI2Ny40MDE1IDIuNjY5NCwtMjM4LjE5ODUgMi42Njk0LC0yMzguMTk4NSAyLjY2OTQsLTIzMi4xOTg1IDguNjY5NCwtMjI2LjE5ODUgMTQuNjY5NCwtMjI2LjE5ODUgMTQuNjY5NCwtMjI2LjE5ODUgMTEwLjgxMTEsLTIyNi4xOTg1IDExMC44MTExLC0yMjYuMTk4NSAxMTYuODExMSwtMjI2LjE5ODUgMTIyLjgxMTEsLTIzMi4xOTg1IDEyMi44MTExLC0yMzguMTk4NSAxMjIuODExMSwtMjM4LjE5ODUgMTIyLjgxMTEsLTI2Ny40MDE1IDEyMi44MTExLC0yNjcuNDAxNSAxMjIuODExMSwtMjczLjQwMTUgMTE2LjgxMTEsLTI3OS40MDE1IDExMC44MTExLC0yNzkuNDAxNSIgLz48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI2Mi43NDAzIiB5PSItMjYyLjciIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+dGhlbWVfNDwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI2Mi43NDAzIiB5PSItMjQ5LjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+Z2VuZXRpY3MsCmhlcml0YWJpbGl0eTwvdGV4dD48dGV4dCB0ZXh0LWFuY2hvcj0ibWlkZGxlIiB4PSI2Mi43NDAzIiB5PSItMjM2LjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+KHVuZGVyX3RoZW9yaXNlZCk8L3RleHQ+PC9nPjwhLS0gYWx0X2NvZyAtLT48ZyBpZD0ibm9kZTUiIGNsYXNzPSJub2RlIj48dGl0bGU+CmFsdF9jb2cKPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iI2YxZjFmMSIgc3Ryb2tlPSIjOGE4YThhIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjYyLjc0MDMiIGN5PSItMTA4LjgiIHJ4PSI0Mi4wODU1IiByeT0iMTkuNDY5NSI+PC9lbGxpcHNlPjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjYyLjc0MDMiIHk9Ii0xMDUuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5hbHRfY29nPC90ZXh0PjwvZz48IS0tIGFsdF9jb2cmIzQ1OyZndDt0aGVtZV8xIC0tPjxnIGlkPSJlZGdlMSIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KYWx0X2NvZy0mZ3Q7dGhlbWVfMQo8L3RpdGxlPgo8cGF0aCBmaWxsPSJub25lIiBzdHJva2U9IiM3YjkwOWYiIGQ9Ik0xMDQuODE2NCwtMTA4LjhDMTE4LjY5NzEsLTEwOC44IDEzNC41NzYzLC0xMDguOCAxNTAuMTMxOCwtMTA4LjgiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjE1MC4yNDc5LC0xMTEuMjUwMSAxNTcuMjQ3OSwtMTA4LjggMTUwLjI0NzgsLTEwNi4zNTAxIDE1MC4yNDc5LC0xMTEuMjUwMSI+PC9wb2x5Z29uPjwvZz48IS0tIGZvY2FsIC0tPjxnIGlkPSJub2RlNiIgY2xhc3M9Im5vZGUiPjx0aXRsZT4KZm9jYWwKPC90aXRsZT4KPGVsbGlwc2UgZmlsbD0iIzEyMjgzYSIgc3Ryb2tlPSIjMTIyODNhIiBzdHJva2Utd2lkdGg9IjEuMSIgY3g9IjYyLjc0MDMiIGN5PSItMzcuOCIgcng9IjMzLjI5MDIiIHJ5PSIxOS40Njk1Ij48L2VsbGlwc2U+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNjIuNzQwMyIgeT0iLTM0LjUiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iI2ZmZmZmZiI+Zm9jYWw8L3RleHQ+PC9nPjwhLS0gZm9jYWwmIzQ1OyZndDt0aGVtZV8xIC0tPjxnIGlkPSJlZGdlMiIgY2xhc3M9ImVkZ2UiPjx0aXRsZT4KZm9jYWwtJmd0O3RoZW1lXzEKPC90aXRsZT4KPHBhdGggZmlsbD0ibm9uZSIgc3Ryb2tlPSIjN2I5MDlmIiBkPSJNODkuNDUwMywtNDkuNTI0MkMxMDYuMjc0LC01Ni45MDg5IDEyOC44ODUyLC02Ni44MzQgMTUwLjc4OTEsLTc2LjQ0ODUiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjE0OS44NTQzLC03OC43MTM4IDE1Ny4yNDg4LC03OS4yODQgMTUxLjgyMzgsLTc0LjIyNyAxNDkuODU0MywtNzguNzEzOCI+PC9wb2x5Z29uPjwvZz48IS0tIGZvY2FsJiM0NTsmZ3Q7dGhlbWVfMiAtLT48ZyBpZD0iZWRnZTMiIGNsYXNzPSJlZGdlIj48dGl0bGU+CmZvY2FsLSZndDt0aGVtZV8yCjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTk2LjI1NTMsLTM1LjUyMDhDMTEyLjU3MzQsLTM0LjQxMTEgMTMyLjg2MzEsLTMzLjAzMTMgMTUyLjQ1MjgsLTMxLjY5OTEiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjE1Mi44MTIyLC0zNC4xMzA0IDE1OS42Mjk4LC0zMS4yMTEgMTUyLjQ3OTYsLTI5LjI0MTcgMTUyLjgxMjIsLTM0LjEzMDQiPjwvcG9seWdvbj48L2c+PC9nPjwvc3ZnPg==)

## Building a corpus from OpenAlex

The corpus above was read from a file. A corpus can also be assembled
from the OpenAlex works API with
[`tf_fetch_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_fetch_corpus.md).
This adapter is assistive. It makes a live network call and its result
depends on an external service that changes over time, so it sits
outside the deterministic core of the package. The call is shown here
but not run, and the supplied email enters the OpenAlex polite pool.

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
without any further change. The file-read `corpus` used throughout this
article shows that shape.

``` r

str(corpus, max.level = 2, list.len = 4)
#> List of 3
#>  $ schema_version: chr "1.0"
#>  $ id            : chr "panic-corpus-demo"
#>  $ records       :List of 8
#>   ..$ :List of 5
#>   ..$ :List of 5
#>   ..$ :List of 5
#>   ..$ :List of 5
#>   .. [list output truncated]
```

The recommended pattern is to fetch once, write the result to disk, and
then work from the saved file so that later analyses remain
reproducible.

## Tracking new evidence with an external search

Locating a corpus is only one use of a literature search. A second,
recurring need is narrower: checking whether a search has turned up any
source the theory does not already cite.
[`tf_new_evidence_dois()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_new_evidence_dois.md)
answers that question deterministically, from a theory object and a
plain vector of candidate DOIs, regardless of where the DOIs came from.

The bundled panic theory records one DOI as evidence and one for each of
its two registered alternatives, and a DOI cited as an alternative
counts as cited just as an evidence DOI does. Those are the sources the
candidate list below is checked against.

``` r

panic <- tf_read(system.file("fixtures", "panic-network.theory.yaml",
                             package = "theoryforge"))

candidates <- c(
  "10.1016/j.brat.2015.10.002",                   # already cited as evidence
  "https://doi.org/10.1016/0005-7967(86)90011-2", # already cited as an alternative, in URL form
  "https://doi.org/10.1037/0033-2909.99.1.20"     # not yet cited
)

tf_new_evidence_dois(panic, candidates)
#> [1] "https://doi.org/10.1037/0033-2909.99.1.20"
```

The comparison is on a normalised form of each DOI (lowercased, with a
`doi.org`/`dx.doi.org` URL prefix stripped), so a plain DOI and a
resolvable URL for the same work are recognised as the same source. The
function takes no network dependency itself: the search is left entirely
to whichever tool supplies the candidate list.

### Combining it with scopusflow

[`scopusflow`](https://pablobernabeu.github.io/scopusflow/) is a
companion R package, by the same author, for querying the Elsevier
Scopus Search API. It is a natural source of candidate DOIs:
`scopus_fetch()` retrieves records for a query, and
`scopus_extract_dois()` reduces them to a plain DOI vector, which is
exactly the input
[`tf_new_evidence_dois()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_new_evidence_dois.md)
expects.

`scopusflow` is not a dependency of `theoryforge`, so the snippet below
is illustrative rather than executed by this vignette. Install
`scopusflow` and supply a Scopus API key (see its `scopus_has_key()`) to
run it.

``` r

library(scopusflow)

query <- scopus_query("panic disorder", "interoception", .op = "AND")
records <- scopus_fetch(query, years = 2015:2026)
candidates <- scopus_extract_dois(records)

tf_new_evidence_dois(panic, candidates)
```

`scopus_diff_dois()` extends this to tracking a search over time: it
compares an earlier and a later retrieval (either `scopus_records`
objects or DOI vectors) and reports which DOIs were added, removed or
unchanged. Re-running a saved query and passing the `"added"` DOIs into
[`tf_new_evidence_dois()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_new_evidence_dois.md)
gives a routine for revisiting a theory’s evidence base as the
literature grows.

``` r

records_2025 <- scopus_fetch(query, years = 2015:2025)
records_2026 <- scopus_fetch(query, years = 2015:2026)
diff <- scopus_diff_dois(records_2025, records_2026)
added <- diff$doi[diff$status == "added"]

tf_new_evidence_dois(panic, added)
```

The hand-off itself needs nothing from `scopusflow`:
`scopus_diff_dois()` returns one row per DOI with its status, which we
reproduce here so the last step runs. Only the newly added DOI comes
back as new evidence.

``` r

diff <- data.frame(
  doi = c("10.1016/j.brat.2015.10.002", "10.1037/0033-2909.99.1.20"),
  status = c("unchanged", "added")
)
added <- diff$doi[diff$status == "added"]

tf_new_evidence_dois(panic, added)
#> [1] "10.1037/0033-2909.99.1.20"
```

`scopusflow` also offers `scopus_compare_topics()`, which tracks the
relative publication share of several comparison terms against a
reference term across a range of years. This suits comparing a theory
against its registered alternatives on their standing in the literature,
using the alternatives’ labels as the comparison terms.

``` r

scopus_compare_topics(
  reference_query = "panic disorder",
  comparison_terms = c("cognitive appraisal account", "biological account"),
  years = 2015:2026
)
```

The comparison and its plot, with per-year stability bands, are shown in
scopusflow’s [Comparing
topics](https://pablobernabeu.github.io/scopusflow/articles/comparing-topics.html)
article.

### Using scopusflow for a Scopus-based corpus

[`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)
and
[`tf_landscape()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_landscape.md)
read the `keywords` and `references` fields of each corpus record, and
`scopusflow` supplies both. `scopus_corpus()` takes the records from
`scopus_fetch()` and enriches them, through Abstract Retrieval, into a
tibble of `id`, `title`, `year`, `keywords` (one character vector of
author keywords per record) and `references` (one data frame of cited
works per record, with `id`, `doi`, `title` and other fields).

[`tf_fetch_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_fetch_corpus.md)
(OpenAlex) stays the built-in default because OpenAlex is free and
keyless, so the literature layer works with no setup. Scopus needs an
institutional subscription and an API key, so `scopusflow` is an opt-in
source rather than a dependency. The two packages exchange plain data, a
DOI vector or a corpus written to a file, with no coupling in either
direction; that keeps theoryforge dependency-light and usable out of the
box, and lets a reader reach for whichever index they have access to.

The corpus format expects a top-level `{schema_version, id, records}`
envelope and, within each record, `references` as a flat list of id
strings, whereas `scopus_corpus()` returns a tibble whose `references`
entries are data frames. So build the envelope explicitly, reducing each
references data frame to one id string per cited work (the DOI where
present, the Scopus id otherwise), write the result to disk and read it
back with
[`tf_read_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read_corpus.md):

``` r

# illustrative: needs scopusflow and a configured Scopus API key
recs <- scopusflow::scopus_fetch(query, years = 2015:2026)
sc   <- scopusflow::scopus_corpus(recs)   # id, title, year, keywords, references

records <- lapply(seq_len(nrow(sc)), function(i) {
  refs <- sc$references[[i]]              # one data frame of cited works
  ref_ids <- ifelse(is.na(refs$doi), refs$id, refs$doi)
  list(id         = sc$id[[i]],
       title      = sc$title[[i]],
       year       = sc$year[[i]],
       keywords   = as.list(sc$keywords[[i]]),
       references = as.list(ref_ids[!is.na(ref_ids)]))
})
corpus <- list(schema_version = "1.0",
               id = "scopus:panic disorder",
               records = records)
jsonlite::write_json(corpus, "corpus.json", auto_unbox = TRUE)

lit <- tf_read_corpus("corpus.json")
tf_litmap(lit)
```
