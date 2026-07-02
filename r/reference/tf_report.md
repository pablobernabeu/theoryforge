# Render the rigour report as a string

Renders the result of
[`tf_check()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_check.md)
as a string. `format = "json"` returns valid, pretty-printed JSON;
`format = "html"` returns an HTML fragment.

## Usage

``` r
tf_report(theory, format = "json")
```

## Arguments

- theory:

  A theory object (named list).

- format:

  One of `"json"` (default) or `"html"`.

## Value

A single string.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_prediction("h1", "Arousal precedes threat appraisal.", "point")
cat(tf_report(theory, format = "json"))
#> {
#>   "theory_id": "demo-1",
#>   "schema_version": "1.0",
#>   "maturity": "building",
#>   "aggregate_score": 43,
#>   "gate": "blocked",
#>   "n_blockers_failed": 1,
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
#>       "score": 1,
#>       "weight": 0.1,
#>       "severity_if_fail": "warning",
#>       "citation": "Kelley (1927); Le et al. (2010); Lawson & Robins (2021)"
#>     },
#>     {
#>       "id": "construct_clarity",
#>       "status": "warn",
#>       "score": 0,
#>       "weight": 0.08,
#>       "severity_if_fail": "warning",
#>       "citation": "Suddaby (2010); Cronbach & Meehl (1955); Flake & Fried (2020)"
#>     },
#>     {
#>       "id": "scope",
#>       "status": "warn",
#>       "score": 0,
#>       "weight": 0.06,
#>       "severity_if_fail": "warning",
#>       "citation": "Whetten (1989); Bacharach (1989)"
#>     },
#>     {
#>       "id": "logical_why",
#>       "status": "warn",
#>       "score": 0,
#>       "weight": 0.08,
#>       "severity_if_fail": "warning",
#>       "citation": "Sutton & Staw (1995); Whetten (1989)"
#>     },
#>     {
#>       "id": "causal_testability",
#>       "status": "warn",
#>       "score": 0,
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
#>       "status": "fail",
#>       "score": 0,
#>       "weight": 0.08,
#>       "severity_if_fail": "blocker",
#>       "citation": "Scheel et al. (2021); Szollosi et al. (2020)"
#>     }
#>   ]
#> }
```
