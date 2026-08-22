# Names of the packaged example files

The bundled set is four example theories and one literature corpus,
`panic-corpus.yaml`, which
[`tf_read_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read_corpus.md)
reads.

## Usage

``` r
tf_example_names()
```

## Value

A sorted character vector of the `.yaml` file names. The Python twin's
`example_names()` applies the same extension filter, so the two list the
same set.

## Examples

``` r
tf_example_names()
#> [1] "modality-switching.theory.yaml"    "panic-corpus.yaml"                
#> [3] "panic-network-2026-v2.theory.yaml" "panic-network.theory.yaml"        
#> [5] "weak-theory.theory.yaml"          
```
