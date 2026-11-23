# Write a theory object to YAML or JSON

Serialises a theory object to disk. The file extension sets the format:
JSON for `.json` and YAML otherwise. Files are UTF-8 with LF line
endings.

## Usage

``` r
tf_write(theory, path)
```

## Arguments

- theory:

  A theory object (named list).

- path:

  Destination path.

## Value

The `path` (invisibly).

## Details

Numbers keep 15 significant digits in both formats, logicals are written
as `true` and `false`, and a missing value (`NA`) is written as null,
which reads back as `NULL` in R and `None` in Python. Every field the
schema types as an array of strings (`derives_from`, `diagnostic_vs`,
`protects`, `measurement`, `boundary_conditions`, `key_constructs`) is
written as an array, even when the theory holds it as a single string. A
theory that validates against the package's own schema therefore still
validates once written, and it reads back the same in R and in Python.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory")
tf_write(theory, tempfile(fileext = ".yaml"))
```
