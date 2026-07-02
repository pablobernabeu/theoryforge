# Render a diagram intermediate representation

Produces a byte-identical diagram IR string for the requested type. The
`engine` argument is accepted for API parity; the IR is engine
independent (Graphviz DOT for the two digraphs, dagitty syntax for the
causal DAG). See API_SPEC.md section 5.

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

  Rendering engine label, accepted for parity (default `"graphviz"`).

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
#>   rankdir=LR;
#>   node [shape=box, style=rounded];
#>   "c_arousal" [label="Arousal"];
#>   "c_threat" [label="Perceived threat"];
#>   "c_arousal" -> "c_threat" [label="causes"];
#> }
cat(tf_diagram(theory, "causal_dag"))
#> dag {
#>   c_arousal -> c_threat
#> }
```
