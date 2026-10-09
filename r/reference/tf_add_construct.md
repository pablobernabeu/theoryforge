# Add a construct to a theory (BUILDING mode)

Appends a construct and a provenance entry, returning the mutated
theory.

## Usage

``` r
tf_add_construct(
  theory,
  id,
  label,
  definition,
  measurement = NULL,
  boundary_conditions = NULL
)
```

## Arguments

- theory:

  A theory object (named list).

- id, label, definition:

  Construct fields.

- measurement, boundary_conditions:

  Optional character vectors.

## Value

The (mutated) theory object.

## Examples

``` r
tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Physiological arousal",
                   "Bodily activation in response to a stressor.")
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
#> [1] "tf_add_construct"
#> 
#> $provenance[[2]]$detail
#> [1] "c_arousal"
#> 
#> 
#> 
#> $constructs
#> $constructs[[1]]
#> $constructs[[1]]$id
#> [1] "c_arousal"
#> 
#> $constructs[[1]]$label
#> [1] "Physiological arousal"
#> 
#> $constructs[[1]]$definition
#> [1] "Bodily activation in response to a stressor."
#> 
#> 
#> 
```
