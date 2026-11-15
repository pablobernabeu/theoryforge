# Render a literature-layer diagram intermediate representation

Produces a deterministic DOT string for the literature layer.

## Usage

``` r
tf_lit_diagram(obj, type = "keyword_cooccurrence", max_edges = NULL)
```

## Arguments

- obj:

  A
  [`tf_litmap()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_litmap.md)
  result (for `"keyword_cooccurrence"` / `"co_citation"`) or a
  [`tf_landscape()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_landscape.md)
  result (for `"theme_landscape"`).

- type:

  One of `"keyword_cooccurrence"` (default), `"co_citation"`, or
  `"theme_landscape"`.

- max_edges:

  A positive integer that caps a `"keyword_cooccurrence"` or
  `"co_citation"` diagram at that many edges: the highest counts are
  kept, ties going to the earlier pair in `(a, b)` order, and only their
  endpoints are drawn. `NULL` (the default) draws every edge.
  `"theme_landscape"` ignores it.

## Value

A single string ending in a newline.

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
cat(tf_lit_diagram(tf_litmap(corpus), "keyword_cooccurrence"))
#> graph keyword_cooccurrence {
#>   graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
#>   node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
#>   edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
#>   node [shape=ellipse, style="filled", fillcolor="#E4F1F1", color="#1E7B7B"];
#>   "arousal";
#>   "avoidance";
#>   "exposure";
#>   "threat";
#>   "arousal" -- "threat" [label="2"];
#>   "avoidance" -- "exposure" [label="2"];
#> }

# On a large map, draw only the strongest edges.
fixture <- tf_read_corpus(system.file("fixtures", "panic-corpus.yaml",
                                      package = "theoryforge"))
cat(tf_lit_diagram(tf_litmap(fixture), "co_citation", max_edges = 1))
#> graph co_citation {
#>   graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
#>   node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
#>   edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
#>   node [shape=ellipse, style="filled", fillcolor="#E7EDF5", color="#33567A"];
#>   "barlow2002";
#>   "clark1986";
#>   "barlow2002" -- "clark1986" [label="3"];
#> }
```
