# Add a proposition to a theory (BUILDING mode)

Add a proposition to a theory (BUILDING mode)

## Usage

``` r
tf_add_proposition(theory, id, from, to, relation, mechanism = NULL)
```

## Arguments

- theory:

  A theory object (named list).

- id, from, to, relation:

  Proposition fields. `from` is the source construct id (named `from` to
  match the schema field).

- mechanism:

  Optional mechanism string.

## Value

The (mutated) theory object.

## Examples

``` r
tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "increases")
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
#> [1] "tf_add_construct"
#> 
#> $provenance[[2]]$detail
#> [1] "c_arousal"
#> 
#> 
#> $provenance[[3]]
#> $provenance[[3]]$step
#> [1] "3"
#> 
#> $provenance[[3]]$action
#> [1] "tf_add_construct"
#> 
#> $provenance[[3]]$detail
#> [1] "c_threat"
#> 
#> 
#> $provenance[[4]]
#> $provenance[[4]]$step
#> [1] "4"
#> 
#> $provenance[[4]]$action
#> [1] "tf_add_proposition"
#> 
#> $provenance[[4]]$detail
#> [1] "p1"
#> 
#> 
#> 
#> $constructs
#> $constructs[[1]]
#> $constructs[[1]]$id
#> [1] "c_arousal"
#> 
#> $constructs[[1]]$label
#> [1] "Arousal"
#> 
#> $constructs[[1]]$definition
#> [1] "Bodily activation."
#> 
#> 
#> $constructs[[2]]
#> $constructs[[2]]$id
#> [1] "c_threat"
#> 
#> $constructs[[2]]$label
#> [1] "Perceived threat"
#> 
#> $constructs[[2]]$definition
#> [1] "Appraised danger."
#> 
#> 
#> 
#> $propositions
#> $propositions[[1]]
#> $propositions[[1]]$id
#> [1] "p1"
#> 
#> $propositions[[1]]$from
#> [1] "c_arousal"
#> 
#> $propositions[[1]]$to
#> [1] "c_threat"
#> 
#> $propositions[[1]]$relation
#> [1] "increases"
#> 
#> 
#> 
```
