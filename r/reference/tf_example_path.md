# Path to a packaged example file

Path to a packaged example file

## Usage

``` r
tf_example_path(name)
```

## Arguments

- name:

  File name, e.g. `"panic-network.theory.yaml"`. See
  [`tf_example_names()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_example_names.md).

## Value

The path to the installed file.

## Examples

``` r
tf_read(tf_example_path("panic-network.theory.yaml"))$id
#> [1] "panic-network-2026"
```
