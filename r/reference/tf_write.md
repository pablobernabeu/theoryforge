# Write a theory object to YAML or JSON

Serialises a theory object to disk. The format is chosen by the file
extension (`.json` -\> JSON, otherwise YAML). Files are written with LF
line endings.

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

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory")
tf_write(theory, tempfile(fileext = ".yaml"))
```
