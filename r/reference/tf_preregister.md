# Render the hypotheses section of a preregistration

Produces a deterministic preregistration markdown string for a theory
and, if `path` is given, writes it (LF, single trailing newline).

## Usage

``` r
tf_preregister(theory, path = NULL)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- path:

  Optional destination path; when given, the markdown is written with LF
  line endings.

## Value

The preregistration markdown as a single string.

## Details

The header gives the theory id, the version when it has an id (with its
parent, when one is named), the schema version, the maturity and whether
every prediction's derivation references resolve: `yes`, `no` or
`not applicable (no predictions)`. The derivation line reports the
checklist's reference check, which does not show that a prediction
follows from the propositions it cites.

Each hypothesis is listed in file order with its claim type, statement
and derivation, followed by the auxiliary assumptions that protect it
(`core` or `added for <id>`), the registered rivals it discriminates and
its test record. A hypothesis that a recorded outcome has already tested
reads `already tested: passed (<date>, registered <where>)`, one entry
per outcome, and any other reads `untested`.

When at least one prediction states a sampling plan in its `test` block,
a section headed `Sampling plan (author-recorded; not scored)` follows,
with one line per prediction in file order. A line gives what is
recorded of the planned sample, alpha and sidedness, smallest effect of
interest, power or decision probability, design analysis and
justification. A prediction without a plan reads
`no sampling plan stated`. Nothing scores the plan: power does not raise
a claim's severity (Meehl, 1967), though it decides how informative a
failed test is (Lakens, 2022). A theory without a plan has no such
section.

A section then lists the conditional independencies that
[`tf_implications()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_implications.md)
derives from the causal graph with its default settings, which are
claims the theory makes without stating them, or says why there are
none. The claim-form severity rubric closes the document.

The document is the part of a preregistration that the theory file
holds. It is to be completed with the study design, the analysis plan,
the inference criteria and whatever the sampling plan leaves out, the
sections that a template such as PRP-QUANT asks for (Bosnjak et al.,
2022).

## References

Bosnjak, M., Fiebach, C. J., Mellor, D., Mueller, S., O'Connor, D. B.,
Oswald, F. L., & Sokol, R. I. (2022). A template for preregistration of
quantitative research in psychology: Report of the joint psychological
societies preregistration task force. *American Psychologist*, 77(4),
602-615. [doi:10.1037/amp0000879](https://doi.org/10.1037/amp0000879)

Lakens, D. (2022). Sample size justification. *Collabra: Psychology*,
8(1), Article 33267.
[doi:10.1525/collabra.33267](https://doi.org/10.1525/collabra.33267)

Meehl, P. E. (1967). Theory-testing in psychology and physics: A
methodological paradox. *Philosophy of Science*, 34(2), 103-115.
[doi:10.1086/288135](https://doi.org/10.1086/288135)

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_prediction("h1", "Effect is exactly 0.30.", "point")
cat(tf_preregister(theory))
#> # Preregistration: A demonstration theory
#> 
#> - Theory ID: demo-1
#> - Schema version: 1.0
#> - Maturity: building
#> - Derivation references resolve: no
#> 
#> ## Hypotheses
#> 1. [point] Effect is exactly 0.30. (derives from: —)
#>    - Test record: untested
#> 
#> ## Implied conditional independencies (derived from the causal graph, not predictions)
#> _None: the theory states no directed relation between constructs._
#> 
#> ## Severity (pre-data rubric of claim form)
#> - h1: severity 0.9, risk 0.9
```
