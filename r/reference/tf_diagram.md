# Render a diagram intermediate representation

Produces a deterministic diagram IR string for the requested type. The
`engine` argument is accepted but has no effect, because the IR is
engine independent (Graphviz DOT for the two digraphs, dagitty syntax
for the causal DAG).

## Usage

``` r
tf_diagram(theory, type = "nomological_net", engine = "graphviz")
```

## Arguments

- theory:

  A theory object (named list).

- type:

  One of `"nomological_net"` (default), `"provenance"`, `"causal_dag"`,
  `"development_roadmap"`, `"pipeline"`, `"context"` (the theory, its
  scope, and its rivals), `"workflow"` (the building-to-testing
  pipeline), `"venn"` (construct scope overlap, as an SVG), `"rigour"`
  (the checklist as a status grid, as an SVG), or `"severity"`
  (per-prediction severity bars, as an SVG).

- engine:

  Rendering engine label, accepted but unused (default `"graphviz"`).

## Value

A single string ending in a newline. Graphviz DOT for the digraphs,
dagitty syntax for the causal DAG, and SVG for the Venn.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "causes")
cat(tf_diagram(theory, "nomological_net"))
#> digraph nomological_net {
#>   graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
#>   node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
#>   edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
#>   "c_arousal" [label="Arousal", fillcolor="#E4F1F1", color="#1E7B7B"];
#>   "c_threat" [label="Perceived threat", fillcolor="#E4F1F1", color="#1E7B7B"];
#>   "c_arousal" -> "c_threat" [label="causes"];
#> }
cat(tf_diagram(theory, "causal_dag"))
#> dag {
#>   c_arousal -> c_threat
#> }
```
