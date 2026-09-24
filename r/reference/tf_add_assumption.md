# Add an auxiliary assumption (BUILDING mode)

Add an auxiliary assumption (BUILDING mode)

## Usage

``` r
tf_add_assumption(theory, id, statement, added_for = NULL, protects = NULL)
```

## Arguments

- theory:

  A theory object (named list).

- id, statement:

  Assumption fields.

- added_for:

  Optional reason the assumption was added.

- protects:

  Optional character vector of prediction ids it protects.

## Value

The (mutated) theory object.

## Examples

``` r
tf_theory("demo-1", "A demonstration theory") |>
  tf_add_assumption("a1", "Measurement error is negligible.")
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
#> [1] "tf_add_assumption"
#> 
#> $provenance[[2]]$detail
#> [1] "a1"
#> 
#> 
#> 
#> $auxiliary_assumptions
#> $auxiliary_assumptions[[1]]
#> $auxiliary_assumptions[[1]]$id
#> [1] "a1"
#> 
#> $auxiliary_assumptions[[1]]$statement
#> [1] "Measurement error is negligible."
#> 
#> $auxiliary_assumptions[[1]]$added_for
#> NULL
#> 
#> 
#> 
```
