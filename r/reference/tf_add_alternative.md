# Add an alternative theory (BUILDING mode)

Add an alternative theory (BUILDING mode)

## Usage

``` r
tf_add_alternative(theory, id, label, key_constructs = NULL)
```

## Arguments

- theory:

  A theory object (named list).

- id, label:

  Alternative fields.

- key_constructs:

  Optional character vector.

## Value

The (mutated) theory object.

## Examples

``` r
tf_theory("demo-1", "A demonstration theory") |>
  tf_add_alternative("alt1", "Cognitive appraisal account",
                     key_constructs = c("c_threat"))
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
#> [1] "tf_add_alternative"
#> 
#> $provenance[[2]]$detail
#> [1] "alt1"
#> 
#> 
#> 
#> $alternatives
#> $alternatives[[1]]
#> $alternatives[[1]]$id
#> [1] "alt1"
#> 
#> $alternatives[[1]]$label
#> [1] "Cognitive appraisal account"
#> 
#> $alternatives[[1]]$key_constructs
#> $alternatives[[1]]$key_constructs[[1]]
#> [1] "c_threat"
#> 
#> 
#> 
#> 
```
