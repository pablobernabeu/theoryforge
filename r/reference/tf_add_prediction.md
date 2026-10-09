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
  severity = NULL
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
```
