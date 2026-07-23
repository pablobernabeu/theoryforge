# Building, checking and diagramming a theory

`theoryforge` treats a scientific theory as a versioned,
machine-checkable object. This vignette walks through the core loop of
building a theory, checking its rigour and diagramming it (see the
[package overview](https://pablobernabeu.github.io/theoryforge/r/) for
the R/Python parity guarantee).

``` r

library(theoryforge)
```

## Building a theory

A theory is built incrementally with the BUILDING-mode verbs. Each verb
appends to the theory and records a provenance entry, so the steps
compose cleanly with the native pipe.

``` r

theory <- tf_theory("panic-network", "A network theory of panic") |>
  tf_add_construct("c_arousal", "Physiological arousal",
                   "Bodily activation in response to a stressor.",
                   measurement = "heart rate variability",
                   boundary_conditions = "awake adults") |>
  tf_add_construct("c_threat", "Perceived threat",
                   "Appraised danger of bodily sensations.",
                   measurement = "self-report appraisal scale",
                   boundary_conditions = "awake adults") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "causes",
                     mechanism = "Activation raises the salience of threat cues.") |>
  tf_add_prediction("h1", "Arousal raises threat appraisal by a fixed amount.",
                    "point", derives_from = "p1")

isTRUE(tf_validate(theory)) # structural checks: required fields and enums
#> [1] TRUE
isTRUE(tf_validate(theory, full = TRUE)) # also checks referential integrity of ids and cross-references
#> [1] TRUE
```

[`tf_validate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_validate.md)
returns `TRUE` invisibly on success and stops with a message listing
every problem otherwise, which is why the calls above are wrapped in
[`isTRUE()`](https://rdrr.io/r/base/Logic.html) to show the result. With
`full = TRUE` it additionally checks referential integrity, that ids are
unique and every cross-reference points to a declared id. It does not
require any optional dependency.

The failure path is the more informative one. Pointing a prediction at a
proposition that was never declared leaves the structural pass
untouched, since every required field is still present and well formed,
so the problem surfaces only under `full = TRUE`.

``` r

broken <- theory
broken$predictions[[1]]$derives_from <- "p_missing"
tf_validate(broken, full = TRUE)
#> Error:
#> ! invalid theory object: prediction[0] derives_from 'p_missing' is not a known proposition
```

The building vocabulary has two further verbs.
[`tf_add_assumption()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_add_assumption.md)
records an auxiliary assumption, and
[`tf_set_formal_model()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_set_formal_model.md)
attaches a formal-model reference. Applied to a copy of the theory, they
leave the original untouched.

``` r

extended <- theory |>
  tf_add_assumption("a1", "Arousal is measured at rest.", added_for = "h1") |>
  tf_set_formal_model("sem", spec_ref = "panic-sem.lavaan")
```

Every verb appends a provenance entry, recording the step, the action
and its detail, so the record of how a theory was built travels with the
object.

``` r

do.call(rbind, lapply(extended$provenance, as.data.frame))
#>   step              action        detail
#> 1    1           tf_theory panic-network
#> 2    2    tf_add_construct     c_arousal
#> 3    3    tf_add_construct      c_threat
#> 4    4  tf_add_proposition            p1
#> 5    5   tf_add_prediction            h1
#> 6    6   tf_add_assumption            a1
#> 7    7 tf_set_formal_model           sem
```

A theory can be written to and read back from disk. The format follows
the file extension (`.json` for JSON, otherwise YAML).

``` r

path <- tempfile(fileext = ".yaml")
tf_write(theory, path)
roundtrip <- tf_read(path)
identical(roundtrip$id, theory$id)
#> [1] TRUE
```

## Checking rigour

[`tf_check()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_check.md)
runs the 12-item rigour checklist defined in the vendored
`rigor_checklist.yaml`.

``` r

report <- tf_check(theory)

report$aggregate_score   # weighted score, 0-100, rounded to 1 dp
#> [1] 77.6
report$gate              # "pass", "blocked", or "advisory" (draft maturity)
#> [1] "pass"
report$n_blockers_failed # count of failed blocker items
#> [1] 0

# Per-item detail (checklist order preserved):
report$items[[1]]$id      # "falsifiability"
#> [1] "falsifiability"
report$items[[1]]$status  # "pass" / "warn" / "fail"
#> [1] "pass"
report$items[[1]]$score   # numeric in [0, 1]
#> [1] 1
```

Render it as JSON (valid, pretty-printed) or as an HTML fragment. The
JSON string is an artefact in its own right, shown here verbatim:

``` r

cat(tf_report(theory, format = "json"))
```

    {
      "theory_id": "panic-network",
      "schema_version": "1.0",
      "maturity": "building",
      "aggregate_score": 77.6,
      "gate": "pass",
      "n_blockers_failed": 0,
      "items": [
        {
          "id": "falsifiability",
          "status": "pass",
          "score": 1,
          "weight": 0.15,
          "severity_if_fail": "blocker",
          "citation": "Popper (1959); Bacharach (1989)"
        },
        {
          "id": "precision",
          "status": "pass",
          "score": 1,
          "weight": 0.1,
          "severity_if_fail": "warning",
          "citation": "Meehl (1967, 1990)"
        },
        {
          "id": "risk_severity",
          "status": "warn",
          "score": 0,
          "weight": 0.1,
          "severity_if_fail": "warning",
          "citation": "Mayo (2018); Meehl (1990)"
        },
        {
          "id": "parsimony",
          "status": "pass",
          "score": 1,
          "weight": 0.08,
          "severity_if_fail": "warning",
          "citation": "Forster & Sober (1994); Lakatos (1970)"
        },
        {
          "id": "non_redundancy",
          "status": "pass",
          "score": 0.857,
          "weight": 0.1,
          "severity_if_fail": "warning",
          "citation": "Kelley (1927); Le et al. (2010); Lawson & Robins (2021)"
        },
        {
          "id": "construct_clarity",
          "status": "pass",
          "score": 1,
          "weight": 0.08,
          "severity_if_fail": "warning",
          "citation": "Suddaby (2010); Cronbach & Meehl (1955); Flake & Fried (2020)"
        },
        {
          "id": "scope",
          "status": "pass",
          "score": 1,
          "weight": 0.06,
          "severity_if_fail": "warning",
          "citation": "Whetten (1989); Bacharach (1989)"
        },
        {
          "id": "logical_why",
          "status": "pass",
          "score": 1,
          "weight": 0.08,
          "severity_if_fail": "warning",
          "citation": "Sutton & Staw (1995); Whetten (1989)"
        },
        {
          "id": "causal_testability",
          "status": "pass",
          "score": 1,
          "weight": 0.06,
          "severity_if_fail": "warning",
          "citation": "Textor et al. (2016); Eronen & Bringmann (2021)"
        },
        {
          "id": "diagnosticity",
          "status": "warn",
          "score": 0,
          "weight": 0.06,
          "severity_if_fail": "warning",
          "citation": "Platt (1964); Fiedler (2017)"
        },
        {
          "id": "formalisation",
          "status": "warn",
          "score": 0,
          "weight": 0.05,
          "severity_if_fail": "warning",
          "citation": "Robinaugh et al. (2021); Guest & Martin (2021)"
        },
        {
          "id": "derivation_chain",
          "status": "pass",
          "score": 1,
          "weight": 0.08,
          "severity_if_fail": "blocker",
          "citation": "Scheel et al. (2021); Szollosi et al. (2020)"
        }
      ]
    }

The HTML fragment drops straight into a page and renders as a real
table:

``` r

cat(tf_report(theory, format = "html"))
```

## Rigour report: panic-network

Aggregate score: **77.6** · gate: **pass**

| item | status | score | grounding |
|----|----|----|----|
| falsifiability | pass | 1.0 | Popper (1959); Bacharach (1989) |
| precision | pass | 1.0 | Meehl (1967, 1990) |
| risk_severity | warn | 0.0 | Mayo (2018); Meehl (1990) |
| parsimony | pass | 1.0 | Forster & Sober (1994); Lakatos (1970) |
| non_redundancy | pass | 0.857 | Kelley (1927); Le et al. (2010); Lawson & Robins (2021) |
| construct_clarity | pass | 1.0 | Suddaby (2010); Cronbach & Meehl (1955); Flake & Fried (2020) |
| scope | pass | 1.0 | Whetten (1989); Bacharach (1989) |
| logical_why | pass | 1.0 | Sutton & Staw (1995); Whetten (1989) |
| causal_testability | pass | 1.0 | Textor et al. (2016); Eronen & Bringmann (2021) |
| diagnosticity | warn | 0.0 | Platt (1964); Fiedler (2017) |
| formalisation | warn | 0.0 | Robinaugh et al. (2021); Guest & Martin (2021) |
| derivation_chain | pass | 1.0 | Scheel et al. (2021); Szollosi et al. (2020) |

### Screening for redundant constructs

The lexical redundancy screen reports the Jaccard similarity of every
pair of construct definitions, sorted by descending similarity.

``` r

tf_redundancy_check(theory)
#>           a        b similarity flag
#> 1 c_arousal c_threat      0.143   ok
```

The lexical screen is deterministic but shallow. When a semantic
comparison is wanted,
[`tf_embedding_redundancy()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_embedding_redundancy.md)
takes any embedder that maps a definition to a numeric vector and
reports the cosine similarity of each construct pair. It needs no
optional dependency, since the embedder is supplied by the caller. A toy
bag-of-words embedder stands in for a real language model here.

``` r

vocab <- c("bodily", "activation", "appraised", "danger", "salience")
embedder <- function(def) {
  words <- strsplit(tolower(def), "[^a-z]+")[[1]]
  vapply(vocab, function(w) sum(words == w), numeric(1))
}
tf_embedding_redundancy(theory, embedder)
#>           a        b   cosine flag
#> 1 c_arousal c_threat 0.408248   ok
```

## Diagramming

[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
emits deterministic intermediate representations for several diagram
types. The digraphs are Graphviz DOT, and the causal DAG uses dagitty
syntax.

``` r

cat(tf_diagram(theory, type = "nomological_net"))
```

    digraph nomological_net {
      graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];
      node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, margin="0.16,0.1"];
      edge [fontname="Helvetica", fontsize=10, color="#7B909F", fontcolor="#0F6E6E", arrowsize=0.7];
      "c_arousal" [label="Physiological\narousal", fillcolor="#E4F1F1", color="#1E7B7B"];
      "c_threat" [label="Perceived threat", fillcolor="#E4F1F1", color="#1E7B7B"];
      "c_arousal" -> "c_threat" [label="causes"];
    }

``` r

cat(tf_diagram(theory, type = "causal_dag"))
```

    dag {
      c_arousal -> c_threat
    }

The DOT strings render with any Graphviz tool, and
[`tf_render_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_render_diagram.md)
does this without leaving R: it returns a DiagrammeR widget for the
viewer and for R Markdown, or a standalone SVG string with `as = "svg"`.
The packages it uses are optional, in Suggests, so the deterministic
core stays dependency-free. Rendered, the nomological net above reads as
a figure.

``` r

cat('<div class="tf-figure tf-diagram">', tf_render_diagram(theory, "nomological_net", as = "svg"), '</div>', sep = "")
```

![](data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjg1cHQiIGhlaWdodD0iNjlwdCIgdmlld2JveD0iMC4wMCAwLjAwIDI4NC43MyA2OS4yMCIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIiB4bWxuczp4bGluaz0iaHR0cDovL3d3dy53My5vcmcvMTk5OS94bGluayI+PGcgaWQ9ImdyYXBoMCIgY2xhc3M9ImdyYXBoIiB0cmFuc2Zvcm09InNjYWxlKDEgMSkgcm90YXRlKDApIHRyYW5zbGF0ZSgxNC40IDU0LjgpIj48dGl0bGU+Cm5vbW9sb2dpY2FsX25ldAo8L3RpdGxlPgo8IS0tIGNfYXJvdXNhbCAtLT48ZyBpZD0ibm9kZTEiIGNsYXNzPSJub2RlIj48dGl0bGU+CmNfYXJvdXNhbAo8L3RpdGxlPgo8cGF0aCBmaWxsPSIjZTRmMWYxIiBzdHJva2U9IiMxZTdiN2IiIHN0cm9rZS13aWR0aD0iMS4xIiBkPSJNNzYuMjYxMiwtNDAuNjAyQzc2LjI2MTIsLTQwLjYwMiAxMS45MTI4LC00MC42MDIgMTEuOTEyOCwtNDAuNjAyIDUuOTEyOCwtNDAuNjAyIC0uMDg3MiwtMzQuNjAyIC0uMDg3MiwtMjguNjAyIC0uMDg3MiwtMjguNjAyIC0uMDg3MiwtMTEuNzk4IC0uMDg3MiwtMTEuNzk4IC0uMDg3MiwtNS43OTggNS45MTI4LC4yMDIgMTEuOTEyOCwuMjAyIDExLjkxMjgsLjIwMiA3Ni4yNjEyLC4yMDIgNzYuMjYxMiwuMjAyIDgyLjI2MTIsLjIwMiA4OC4yNjEyLC01Ljc5OCA4OC4yNjEyLC0xMS43OTggODguMjYxMiwtMTEuNzk4IDg4LjI2MTIsLTI4LjYwMiA4OC4yNjEyLC0yOC42MDIgODguMjYxMiwtMzQuNjAyIDgyLjI2MTIsLTQwLjYwMiA3Ni4yNjEyLC00MC42MDIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iNDQuMDg3IiB5PSItMjMuNSIgZm9udC1mYW1pbHk9IkhlbHZldGljYSxzYW5zLVNlcmlmIiBmb250LXNpemU9IjExLjAwIiBmaWxsPSIjMTIyODNhIj5QaHlzaW9sb2dpY2FsPC90ZXh0Pjx0ZXh0IHRleHQtYW5jaG9yPSJtaWRkbGUiIHg9IjQ0LjA4NyIgeT0iLTEwLjMiIGZvbnQtZmFtaWx5PSJIZWx2ZXRpY2Esc2Fucy1TZXJpZiIgZm9udC1zaXplPSIxMS4wMCIgZmlsbD0iIzEyMjgzYSI+YXJvdXNhbDwvdGV4dD48L2c+PCEtLSBjX3RocmVhdCAtLT48ZyBpZD0ibm9kZTIiIGNsYXNzPSJub2RlIj48dGl0bGU+CmNfdGhyZWF0CjwvdGl0bGU+CjxwYXRoIGZpbGw9IiNlNGYxZjEiIHN0cm9rZT0iIzFlN2I3YiIgc3Ryb2tlLXdpZHRoPSIxLjEiIGQ9Ik0yNDMuOTY0NCwtMzguMkMyNDMuOTY0NCwtMzguMiAxNjMuODEzMiwtMzguMiAxNjMuODEzMiwtMzguMiAxNTcuODEzMiwtMzguMiAxNTEuODEzMiwtMzIuMiAxNTEuODEzMiwtMjYuMiAxNTEuODEzMiwtMjYuMiAxNTEuODEzMiwtMTQuMiAxNTEuODEzMiwtMTQuMiAxNTEuODEzMiwtOC4yIDE1Ny44MTMyLC0yLjIgMTYzLjgxMzIsLTIuMiAxNjMuODEzMiwtMi4yIDI0My45NjQ0LC0yLjIgMjQzLjk2NDQsLTIuMiAyNDkuOTY0NCwtMi4yIDI1NS45NjQ0LC04LjIgMjU1Ljk2NDQsLTE0LjIgMjU1Ljk2NDQsLTE0LjIgMjU1Ljk2NDQsLTI2LjIgMjU1Ljk2NDQsLTI2LjIgMjU1Ljk2NDQsLTMyLjIgMjQ5Ljk2NDQsLTM4LjIgMjQzLjk2NDQsLTM4LjIiIC8+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMjAzLjg4ODgiIHk9Ii0xNi45IiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTEuMDAiIGZpbGw9IiMxMjI4M2EiPlBlcmNlaXZlZAp0aHJlYXQ8L3RleHQ+PC9nPjwhLS0gY19hcm91c2FsJiM0NTsmZ3Q7Y190aHJlYXQgLS0+PGcgaWQ9ImVkZ2UxIiBjbGFzcz0iZWRnZSI+PHRpdGxlPgpjX2Fyb3VzYWwtJmd0O2NfdGhyZWF0CjwvdGl0bGU+CjxwYXRoIGZpbGw9Im5vbmUiIHN0cm9rZT0iIzdiOTA5ZiIgZD0iTTg4LjE3NjYsLTIwLjJDMTA1LjU0ODMsLTIwLjIgMTI1Ljc2NzYsLTIwLjIgMTQ0LjM5OTcsLTIwLjIiIC8+PHBvbHlnb24gZmlsbD0iIzdiOTA5ZiIgc3Ryb2tlPSIjN2I5MDlmIiBwb2ludHM9IjE0NC43MjUzLC0yMi42NTAxIDE1MS43MjUzLC0yMC4yIDE0NC43MjUyLC0xNy43NTAxIDE0NC43MjUzLC0yMi42NTAxIj48L3BvbHlnb24+PHRleHQgdGV4dC1hbmNob3I9Im1pZGRsZSIgeD0iMTIwLjAxMjUiIHk9Ii0yMy4yIiBmb250LWZhbWlseT0iSGVsdmV0aWNhLHNhbnMtU2VyaWYiIGZvbnQtc2l6ZT0iMTAuMDAiIGZpbGw9IiMwZjZlNmUiPmNhdXNlczwvdGV4dD48L2c+PC9nPjwvc3ZnPg==)

The causal DAG is the one view this does not cover, since it emits
dagitty syntax rather than DOT; paste it into a dagitty tool such as
[dagitty.net](https://dagitty.net) instead.

## Simulation

[`tf_simulate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_simulate.md)
treats each construct as a state variable and integrates the signed
proposition network as a linear dynamical system. The trajectory is
deterministic:

``` r

sim <- tf_simulate(theory, steps = 5)
unlist(sim$states)
#> [1] "c_arousal" "c_threat"
unlist(sim$trajectory[[1]]) # the common initial state
#> [1] 1 1
unlist(sim$trajectory[[6]]) # after five Euler steps
#> [1] 0.773781 1.181034
```

The two states separate immediately: arousal, which receives no incoming
coupling, decays under the damping term, while perceived threat is
pushed up by the positive coupling from arousal before the decay
eventually takes over.
