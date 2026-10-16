# Add a prediction to a theory (BUILDING mode)

Appends a prediction and a provenance entry, returning the mutated
theory.

## Usage

``` r
tf_add_prediction(
  theory,
  id,
  statement,
  type,
  derives_from = NULL,
  diagnostic_vs = NULL,
  severity = NULL,
  test = NULL
)
```

## Arguments

- theory:

  A theory object (named list).

- id:

  The prediction's identifier.

- statement:

  The claim in words.

- type:

  The form of the claim, one of four. `"existence"` asserts that an
  effect or relation exists, without a direction. `"directional"`
  asserts a sign or an order, including comparisons, interactions, the
  invariance of a direction across groups and claims that an effect
  occurs only when a condition holds. `"interval"` asserts that a
  quantity lies in a stated range, the range the theory permits.
  `"point"` asserts one value, with the tolerance that measurement
  requires. That width is measurement tolerance, not latitude the theory
  allows. The label is self-declared, and no function checks it against
  the statement.

- derives_from, diagnostic_vs:

  Optional character vectors.

- severity:

  Optional declared pre-data severity from 0 to 1, stored only when
  given. The checklist's risk_severity item reads it, and reads the
  claim-form rubric's value
  ([`tf_severity()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_severity.md))
  for a prediction that declares none.
  [`tf_dossier()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_dossier.md)
  sets the two side by side.

- test:

  Optional sampling plan for testing the prediction, a named list of any
  of `n_planned`, `unit`, `alpha`, `sided` (`"two"` or `"one"`), `sesoi`
  and `sesoi_scale` (the smallest effect of interest and its scale),
  `power` or `decision_probability` with an optional `power_lo` and
  `power_hi`, `method`, `design_ref` and `justification` (API_SPEC.md
  section 30). It is stored only when given.
  [`tf_preregister()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_preregister.md)
  lists it after the hypotheses, and nothing scores it.

## Value

The (mutated) theory object.

## Examples

``` r
tf_theory("demo-1", "A demonstration theory") |>
  tf_add_prediction("h1", "Arousal precedes threat appraisal.", "directional")
#> $schema_version
#> [1] "1.0"
#> 
#> $id
#> [1] "demo-1"
#> 
#> $title
#> [1] "A demonstration theory"
#> 
#> $maturity
#> [1] "building"
#> 
#> $theory_form
#> [1] "network"
#> 
#> $provenance
#> $provenance[[1]]
#> $provenance[[1]]$step
#> [1] "1"
#> 
#> $provenance[[1]]$action
#> [1] "tf_theory"
#> 
#> $provenance[[1]]$detail
#> [1] "demo-1"
#> 
#> 
#> $provenance[[2]]
#> $provenance[[2]]$step
#> [1] "2"
#> 
#> $provenance[[2]]$action
#> [1] "tf_add_prediction"
#> 
#> $provenance[[2]]$detail
#> [1] "h1"
#> 
#> 
#> 
#> $predictions
#> $predictions[[1]]
#> $predictions[[1]]$id
#> [1] "h1"
#> 
#> $predictions[[1]]$statement
#> [1] "Arousal precedes threat appraisal."
#> 
#> $predictions[[1]]$type
#> [1] "directional"
#> 
#> 
#> 

# A prediction with the sampling plan of its test.
tf_theory("demo-1", "A demonstration theory") |>
  tf_add_prediction("h1", "The switch cost lies between 20 and 60 ms.", "interval",
                    test = list(n_planned = 48, unit = "participants", alpha = 0.05,
                                sided = "two", power = 0.9))
#> $schema_version
#> [1] "1.0"
#> 
#> $id
#> [1] "demo-1"
#> 
#> $title
#> [1] "A demonstration theory"
#> 
#> $maturity
#> [1] "building"
#> 
#> $theory_form
#> [1] "network"
#> 
#> $provenance
#> $provenance[[1]]
#> $provenance[[1]]$step
#> [1] "1"
#> 
#> $provenance[[1]]$action
#> [1] "tf_theory"
#> 
#> $provenance[[1]]$detail
#> [1] "demo-1"
#> 
#> 
#> $provenance[[2]]
#> $provenance[[2]]$step
#> [1] "2"
#> 
#> $provenance[[2]]$action
#> [1] "tf_add_prediction"
#> 
#> $provenance[[2]]$detail
#> [1] "h1"
#> 
#> 
#> 
#> $predictions
#> $predictions[[1]]
#> $predictions[[1]]$id
#> [1] "h1"
#> 
#> $predictions[[1]]$statement
#> [1] "The switch cost lies between 20 and 60 ms."
#> 
#> $predictions[[1]]$type
#> [1] "interval"
#> 
#> $predictions[[1]]$test
#> $predictions[[1]]$test$n_planned
#> [1] 48
#> 
#> $predictions[[1]]$test$unit
#> [1] "participants"
#> 
#> $predictions[[1]]$test$alpha
#> [1] 0.05
#> 
#> $predictions[[1]]$test$sided
#> [1] "two"
#> 
#> $predictions[[1]]$test$power
#> [1] 0.9
#> 
#> 
#> 
#> 
```
