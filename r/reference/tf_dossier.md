# Render a theory audit dossier (Markdown)

Assembles a reviewer-facing audit bundle: the header, the
rigour-checklist table, the severity list, the provenance list, and the
appended preregistration document. The output is deterministic, so the
same theory always yields the same dossier.

## Usage

``` r
tf_dossier(theory)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

## Value

The dossier Markdown as a single string (LF line endings, single
trailing newline).

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "causes",
                     mechanism = "Activation raises salience of threat cues.") |>
  tf_add_prediction("h1", "Effect is exactly 0.30.", "point")
cat(tf_dossier(theory))
#> # theoryforge dossier: A demonstration theory
#> 
#> - Theory ID: demo-1
#> - Maturity: building
#> - Aggregate rigour score: 57.0/100
#> - Gate: blocked
#> - Blockers failed: 1
#> 
#> ## Rigour checklist
#> 
#> | item | status | score | weight |
#> | --- | --- | --- | --- |
#> | falsifiability | pass | 1.0 | 0.15 |
#> | precision | pass | 1.0 | 0.1 |
#> | risk_severity | warn | 0.0 | 0.1 |
#> | parsimony | pass | 1.0 | 0.08 |
#> | non_redundancy | pass | 1.0 | 0.1 |
#> | construct_clarity | warn | 0.0 | 0.08 |
#> | scope | warn | 0.0 | 0.06 |
#> | logical_why | pass | 1.0 | 0.08 |
#> | causal_testability | pass | 1.0 | 0.06 |
#> | diagnosticity | warn | 0.0 | 0.06 |
#> | formalisation | warn | 0.0 | 0.05 |
#> | derivation_chain | fail | 0.0 | 0.08 |
#> 
#> ## Severity
#> 
#> - h1: severity 0.9, risk 0.9
#> 
#> ## Provenance
#> 
#> 1. tf_theory: demo-1
#> 2. tf_add_construct: c_arousal
#> 3. tf_add_construct: c_threat
#> 4. tf_add_proposition: p1
#> 5. tf_add_prediction: h1
#> 
#> ## Preregistration
#> 
#> # Preregistration: A demonstration theory
#> 
#> - Theory ID: demo-1
#> - Schema version: 1.0
#> - Maturity: building
#> - Derivation chain verified: no
#> 
#> ## Hypotheses
#> 1. [point] Effect is exactly 0.30. (derives from: —)
#> 
#> ## Severity
#> - h1: severity 0.9, risk 0.9
```
