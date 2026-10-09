# Render a diagram in the viewer or as SVG

Renders a digraph view of a theory without leaving R. Where
[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
returns the deterministic Graphviz DOT string, `tf_render_diagram()`
passes that string to the DiagrammeR engine and returns either an
interactive widget, which displays in the RStudio viewer and in R
Markdown documents, or a standalone SVG string, ready to embed in a page
or save to a file.

## Usage

``` r
tf_render_diagram(x, type = "nomological_net", as = c("widget", "svg"))
```

## Arguments

- x:

  A theory object (named list), or a diagram IR string from
  [`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
  or
  [`tf_lit_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_lit_diagram.md),
  so literature diagrams render the same way.

- type:

  The diagram type, as in
  [`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md).
  Ignored when `x` is already an IR string.

- as:

  Either `"widget"` (default), an htmlwidget for the viewer and for R
  Markdown, or `"svg"`, a standalone SVG string.

## Value

An htmlwidget when `as = "widget"`; a single SVG string when
`as = "svg"`.

## Details

The three chart views (`venn`, `rigour` and `severity`) are already SVG,
so they are returned as-is under `as = "svg"` and wrapped for display
under `as = "widget"`. The `causal_dag` view emits dagitty syntax rather
than DOT, so it is not rendered here; paste it into a dagitty tool or
the dagitty R package instead.

## See also

[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
for the intermediate representation itself, which needs no optional
packages and stays byte-identical across the R and Python
implementations.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "causes")
tf_render_diagram(theory, "nomological_net")

{"x":{"diagram":"digraph nomological_net {\n  graph [rankdir=LR, bgcolor=\"transparent\", fontname=\"Helvetica\", fontsize=11, pad=\"0.2\", nodesep=\"0.3\", ranksep=\"0.45\"];\n  node [fontname=\"Helvetica\", fontsize=11, shape=box, style=\"rounded,filled\", color=\"#33567A\", fillcolor=\"#F2F6F9\", fontcolor=\"#12283A\", penwidth=1.1, margin=\"0.16,0.1\"];\n  edge [fontname=\"Helvetica\", fontsize=10, color=\"#7B909F\", fontcolor=\"#0F6E6E\", arrowsize=0.7];\n  \"c_arousal\" [label=\"Arousal\", fillcolor=\"#E4F1F1\", color=\"#1E7B7B\"];\n  \"c_threat\" [label=\"Perceived threat\", fillcolor=\"#E4F1F1\", color=\"#1E7B7B\"];\n  \"c_arousal\" -> \"c_threat\" [label=\"causes\"];\n}\n","config":{"engine":"dot","options":null}},"evals":[],"jsHooks":[]}
```
