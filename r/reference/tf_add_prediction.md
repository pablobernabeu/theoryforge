# Add a prediction to a theory (BUILDING mode)

Add a prediction to a theory (BUILDING mode)

## Usage

``` r
tf_add_prediction(
  theory,
  id,
  statement,
  type,
  derives_from = NULL,
  diagnostic_vs = NULL
)
```

## Arguments

- theory:

  A theory object (named list).

- id, statement, type:

  Prediction fields.

- derives_from, diagnostic_vs:

  Optional character vectors.

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
