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

## Details

The file is read exactly as the Python twin's `theoryforge.read()` reads
it (API_SPEC.md section 3). The text is UTF-8, and a byte-order mark is
ignored. A YAML or JSON sequence is always a list, even with one
element, so `maturity: [draft]` is refused by
[`tf_validate()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_validate.md)
as it is in Python. Unquoted `y`, `Y`, `n` and `N` stay strings, as do
dates, while `yes`, `no`, `true`, `false`, `on` and `off` are logicals.
Integers are decimal, octal or hexadecimal only, so `1:30` and `1_000`
are strings, and so is a number written with a comma (`1,000`). An
integer too large for an R integer is read as a double. A merge key
(`<<`) lets the mapping's own keys win. A key repeated in any mapping,
in YAML or JSON, stops with `(<path>) Duplicate map key: '<key>'`.

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
