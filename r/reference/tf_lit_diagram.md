# Render a literature-layer diagram intermediate representation

Produces a byte-identical DOT string for the literature layer. See
API_SPEC.md section 16. Mirrors the Python `theoryforge.lit_diagram`.

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
#>   node [shape=ellipse];
#>   "arousal";
#>   "threat";
#>   "arousal" -- "threat" [label="2"];
#> }
```
