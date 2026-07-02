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

tf_validate(theory) # structural checks: required fields and enums
```

[`tf_validate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_validate.md)
returns `TRUE` invisibly on success and stops with a message listing
every problem otherwise. It mirrors the Python `Theory.validate` and
does not require any optional dependency.

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
`rigor_checklist.yaml` and scored per
[`API_SPEC.md`](https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md)
section 4.

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

Render it as JSON (valid, pretty-printed) or as an HTML fragment:

``` r

cat(tf_report(theory, format = "json"))
#> {
#>   "theory_id": "panic-network",
#>   "schema_version": "1.0",
#>   "maturity": "building",
#>   "aggregate_score": 77.6,
#>   "gate": "pass",
#>   "n_blockers_failed": 0,
#>   "items": [
#>     {
#>       "id": "falsifiability",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.15,
#>       "severity_if_fail": "blocker",
#>       "citation": "Popper (1959); Bacharach (1989)"
#>     },
#>     {
#>       "id": "precision",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.1,
#>       "severity_if_fail": "warning",
#>       "citation": "Meehl (1967, 1990)"
#>     },
#>     {
#>       "id": "risk_severity",
#>       "status": "warn",
#>       "score": 0,
#>       "weight": 0.1,
#>       "severity_if_fail": "warning",
#>       "citation": "Mayo (2018); Meehl (1990)"
#>     },
#>     {
#>       "id": "parsimony",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.08,
#>       "severity_if_fail": "warning",
#>       "citation": "Forster & Sober (1994); Lakatos (1970)"
#>     },
#>     {
#>       "id": "non_redundancy",
#>       "status": "pass",
#>       "score": 0.857,
#>       "weight": 0.1,
#>       "severity_if_fail": "warning",
#>       "citation": "Kelley (1927); Le et al. (2010); Lawson & Robins (2021)"
#>     },
#>     {
#>       "id": "construct_clarity",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.08,
#>       "severity_if_fail": "warning",
#>       "citation": "Suddaby (2010); Cronbach & Meehl (1955); Flake & Fried (2020)"
#>     },
#>     {
#>       "id": "scope",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.06,
#>       "severity_if_fail": "warning",
#>       "citation": "Whetten (1989); Bacharach (1989)"
#>     },
#>     {
#>       "id": "logical_why",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.08,
#>       "severity_if_fail": "warning",
#>       "citation": "Sutton & Staw (1995); Whetten (1989)"
#>     },
#>     {
#>       "id": "causal_testability",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.06,
#>       "severity_if_fail": "warning",
#>       "citation": "Textor et al. (2016); Eronen & Bringmann (2021)"
#>     },
#>     {
#>       "id": "diagnosticity",
#>       "status": "warn",
#>       "score": 0,
#>       "weight": 0.06,
#>       "severity_if_fail": "warning",
#>       "citation": "Platt (1964); Fiedler (2017)"
#>     },
#>     {
#>       "id": "formalisation",
#>       "status": "warn",
#>       "score": 0,
#>       "weight": 0.05,
#>       "severity_if_fail": "warning",
#>       "citation": "Robinaugh et al. (2021); Guest & Martin (2021)"
#>     },
#>     {
#>       "id": "derivation_chain",
#>       "status": "pass",
#>       "score": 1,
#>       "weight": 0.08,
#>       "severity_if_fail": "blocker",
#>       "citation": "Scheel et al. (2021); Szollosi et al. (2020)"
#>     }
#>   ]
#> }
```

### Screening for redundant constructs

The lexical redundancy screen reports the Jaccard similarity of every
pair of construct definitions, sorted by descending similarity.

``` r

tf_redundancy_check(theory)
#>           a        b similarity flag
#> 1 c_arousal c_threat      0.143   ok
```

## Diagramming

[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
emits byte-identical intermediate representations for several diagram
types. The digraphs are Graphviz DOT, and the causal DAG uses dagitty
syntax.

``` r

cat(tf_diagram(theory, type = "nomological_net"))
#> digraph nomological_net {
#>   rankdir=LR;
#>   node [shape=box, style=rounded];
#>   "c_arousal" [label="Physiological arousal"];
#>   "c_threat" [label="Perceived threat"];
#>   "c_arousal" -> "c_threat" [label="causes"];
#> }
cat(tf_diagram(theory, type = "causal_dag"))
#> dag {
#>   c_arousal -> c_threat
#> }
```

These strings are compared byte-for-byte against the Python reference
outputs in the package’s tests, guaranteeing cross-language parity.

## Simulation

[`tf_simulate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_simulate.md)
treats each construct as a state variable and integrates the signed
proposition network as a linear dynamical system. The trajectory is
deterministic and parity-tested against the Python reference:

``` r

sim <- tf_simulate(theory, steps = 5)
sim$states
#> [[1]]
#> [1] "c_arousal"
#> 
#> [[2]]
#> [1] "c_threat"
sim$trajectory[[1]]
#> [1] 1 1
```
