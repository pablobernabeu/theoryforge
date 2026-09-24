# Read a theory object from a YAML or JSON file

Reads a theory object authored as YAML (or JSON, chosen by file
extension) into a named list.

## Usage

``` r
tf_read(path)
```

## Arguments

- path:

  Path to a `.yaml`/`.yml` or `.json` file.

## Value

A named list holding the parsed theory object.

## Examples

``` r
# Round-trip a theory through a temporary file.
theory <- tf_theory("demo-1", "A demonstration theory")
path <- tempfile(fileext = ".yaml")
tf_write(theory, path)
tf_read(path)
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
