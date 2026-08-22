# Render a literature-layer diagram intermediate representation

Produces a deterministic DOT string for the literature layer.

## Usage

``` r
tf_lit_diagram(obj, type = "keyword_cooccurrence")
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

## Value

A single string ending in a newline.

## Examples

``` r
corpus <- list(
  schema_version = "1.0", id = "demo-corpus",
  records = list(
    list(id = "w1", keywords = list("arousal", "threat")),
    list(id = "w2", keywords = list("arousal", "threat"))
  )
)
cat(tf_lit_diagram(tf_litmap(corpus), "keyword_cooccurrence"))
#> graph keyword_cooccurrence {
#>   graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
#>   node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
#>   edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
#>   node [shape=ellipse, style="filled", fillcolor="#E4F1F1", color="#1E7B7B"];
#>   "arousal";
#>   "threat";
#>   "arousal" -- "threat" [label="2"];
#> }
```
