# Names of the packaged example files

The bundled set is four example theories and two literature corpora,
which
[`tf_read_corpus()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read_corpus.md)
reads. `panic-corpus.yaml` is a small corpus designed to fall into four
themes, and `openalex-panic-2026.corpus.yaml` holds 150 works fetched
from OpenAlex and frozen.

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
#> [1] "modality-switching.theory.yaml"    "openalex-panic-2026.corpus.yaml"  
#> [3] "panic-corpus.yaml"                 "panic-network-2026-v2.theory.yaml"
#> [5] "panic-network.theory.yaml"         "weak-theory.theory.yaml"          
```
