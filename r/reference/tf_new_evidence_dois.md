# DOIs not already cited by a theory (deterministic)

Compares each DOI in `candidate_dois` against the theory's
`evidence[].source_doi` and `alternatives[].source_doi` fields, by
normalised form (lowercased, with any doi.org/dx.doi.org URL prefix
stripped), so a fresh literature search, for example via OpenAlex,
Scopus, or any other source, can be checked against what the theory
already engages with. Returns the qualifying DOIs in their original
form, deduplicated and sorted by normalised form. Deterministic and
takes no network dependency: the search itself is left to whichever
literature tool the caller prefers.

## Usage

``` r
tf_new_evidence_dois(theory, candidate_dois)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- candidate_dois:

  Character vector of DOIs to check.

## Value

A character vector of the candidate DOIs not already cited, deduplicated
and sorted.

## Examples

``` r
# The bundled panic theory cites one DOI as evidence and one for each of its
# two registered alternatives. All three count as already cited.
theory <- tf_read(system.file("fixtures", "panic-network.theory.yaml",
                              package = "theoryforge"))
tf_new_evidence_dois(theory, c(
  "10.1016/j.brat.2015.10.002",                   # cited as evidence
  "https://doi.org/10.1016/0005-7967(86)90011-2", # an alternative, in URL form
  "https://doi.org/10.1037/0033-2909.99.1.20"     # not yet cited
))
#> [1] "https://doi.org/10.1037/0033-2909.99.1.20"
```
