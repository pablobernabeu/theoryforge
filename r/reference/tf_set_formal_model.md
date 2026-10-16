# Set the formal model (BUILDING mode)

Set the formal model (BUILDING mode)

## Usage

``` r
tf_set_formal_model(theory, type, spec_ref = NULL)
```

## Arguments

- theory:

  A theory object (named list).

- type:

  Formal-model type (e.g. `"ode"`).

- spec_ref:

  Optional reference to the model specification.

## Value

The (mutated) theory object.

## Examples

``` r
tf_theory("demo-1", "A demonstration theory") |>
  tf_set_formal_model("ode", spec_ref = "models/panic.ode")
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
#> [1] "tf_set_formal_model"
#> 
#> $provenance[[2]]$detail
#> [1] "ode"
#> 
#> 
#> 
#> $formal_model
#> $formal_model$type
#> [1] "ode"
#> 
#> $formal_model$spec_ref
#> [1] "models/panic.ode"
#> 
#> 
```
