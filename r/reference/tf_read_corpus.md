# Read a literature corpus from a YAML or JSON file

Reads a corpus object (`{schema_version, id, records}`) into a named
list. The format is chosen by the file extension (`.json` -\> JSON,
otherwise YAML).

## Usage

``` r
tf_read_corpus(path)
```

## Arguments

- path:

  Path to a `.yaml`/`.yml` or `.json` corpus file.

## Value

A named list holding the parsed corpus object.

## Examples

``` r
corpus <- list(
  schema_version = "1.0", id = "demo-corpus",
  records = list(
    list(id = "w1", keywords = list("arousal", "threat")),
    list(id = "w2", keywords = list("arousal", "threat"))
  )
)
path <- tempfile(fileext = ".json")
jsonlite::write_json(corpus, path, auto_unbox = TRUE)
tf_read_corpus(path)
#> $schema_version
#> [1] "1.0"
#> 
#> $id
#> [1] "demo-corpus"
#> 
#> $records
#> $records[[1]]
#> $records[[1]]$id
#> [1] "w1"
#> 
#> $records[[1]]$keywords
#> $records[[1]]$keywords[[1]]
#> [1] "arousal"
#> 
#> $records[[1]]$keywords[[2]]
#> [1] "threat"
#> 
#> 
#> 
#> $records[[2]]
#> $records[[2]]$id
#> [1] "w2"
#> 
#> $records[[2]]$keywords
#> $records[[2]]$keywords[[1]]
#> [1] "arousal"
#> 
#> $records[[2]]$keywords[[2]]
#> [1] "threat"
#> 
#> 
#> 
#> 
```
