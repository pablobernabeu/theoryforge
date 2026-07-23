# Start a new, empty theory object (BUILDING mode entry point)

Seeds `schema_version = "1.0"` and a first provenance entry
`{step:"1", action:"tf_theory", detail:<id>}`.

## Usage

``` r
tf_theory(id, title, maturity = "building", theory_form = "network")
```

## Arguments

- id:

  Theory id.

- title:

  Human-readable title.

- maturity:

  Maturity stage (default `"building"`).

- theory_form:

  Theory form (default `"network"`).

## Value

A theory object (named list).

## Examples

``` r
tf_theory("demo-1", "A demonstration theory")
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
#> 
```
