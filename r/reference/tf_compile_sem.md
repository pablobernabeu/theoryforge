# Compile a theory to lavaan model syntax

Compiles a theory's constructs and propositions into lavaan model syntax
written for [`lavaan::sem()`](https://rdrr.io/pkg/lavaan/man/sem.html).
Constructs with measurement indicators become a latent measurement model
(`=~`), propositions become structural paths (`~`) and covariances
(`~~`), and the covariances the theory rules out are fixed at zero.
Comments say what to check before a fit. The output is deterministic.

## Usage

``` r
tf_compile_sem(theory)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

## Value

The lavaan model syntax as a single string (LF line endings, single
trailing newline).

## The structural model

Each proposition becomes a line in file order: a regression
(`to ~ from`) for `causes`, `increases`, `decreases` and `mediates`, and
a covariance (`from ~~ to`) for `associates`. A `moderates` proposition
gives the moderator's main effect, `to ~ from`, unless a path relation
already writes that line. A comment follows on the product term, which
has to be added by hand: `to ~ x:from` for an observed predictor `x`,
and [`lavaan::sam()`](https://rdrr.io/pkg/lavaan/man/sam.html) or the
modsem package when the variables are latent.

The propositions form the graph that
[`tf_implications()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_implications.md)
reads. Two of its constructs that are both exogenous, with no
proposition pointing into either, or both terminal, with neither
pointing to another construct, are unrelated by the theory's account
unless an association joins them. By default,
[`lavaan::sem()`](https://rdrr.io/pkg/lavaan/man/sem.html) frees the
covariance of two exogenous latent variables and of two terminal
variables, and takes that of two exogenous observed variables from the
data. A fit with those defaults could not refute the claim. In the
modality-switching example, two of the six independencies
[`tf_implications()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_implications.md)
derives would go untested. The syntax therefore ends with a block that
fixes each such covariance at zero (`a ~~ 0*b`), and deleting the block
restores lavaan's defaults. A pair with a moderator keeps those
defaults, because the product term changes the moderator's role.

lavaan takes the covariances of observed exogenous variables from the
data only until a covariance line names one of them. It then treats that
variable as random and fixes at zero each of its covariances that the
syntax does not write. Where a zero line names such a variable, the
block therefore ends by freeing each covariance between two observed
exogenous variables that no association names, when either is a
moderator (`x ~~ m`). The moderator then keeps lavaan's defaults.

## Before fitting

The syntax is a starting point for a fit. Indicator names are the
sanitised measurement entries and must match columns of the data, so
entries written as column names, such as `heart_rate`, give syntax that
fits as it stands. A comment lists each construct with a single
indicator, whose residual variance
[`lavaan::sem()`](https://rdrr.io/pkg/lavaan/man/sem.html) fixes at
zero, so the construct is treated as measured without error. A comment
flags each feedback loop. A non-recursive model may not be identified
(Bollen, 1989), and the panic-network example is not, so check
identification before fitting. Some constructs have to be re-specified
by hand. A manipulation is better entered as a coded observed variable
and a categorical predictor with more than two levels as dummy
variables. A covariate that a measurement entry only describes needs a
variable of its own. Once the block names an observed predictor, a
product term added by hand needs a free covariance with each observed
exogenous variable that a covariance line names. lavaan fixes each one
left unwritten at zero, and each takes a line of its own (`x:m ~~ x`).

## Names

Every name is one lavaan reads as written. Construct ids that lavaan
would refuse or misread, such as `self-efficacy`, `1arousal`, `NA` or
its own keyword `efa`, are renamed. A comment after the header records
each renaming
(`# renamed for lavaan: 'self-efficacy' -> self_efficacy`). An indicator
is its measurement entry folded and lowercased, with each run of other
characters made one underscore. `i_` goes in front when the result would
still be refused, so `7-point Likert rating` gives
`i_7_point_likert_rating`. A comment writes each control character of an
id, and each character outside the Basic Multilingual Plane, as
`<U+XXXX>`, so that it stays one line that lavaan reads as a comment.
API_SPEC.md section 19 states the rules.

The function stops when two different ids would share a name, since
lavaan would merge them. Such a pair is two constructs, two indicators
of one construct or a construct and an indicator. A construct and an
indicator collide when the construct is measured by its own name or
named like an indicator of another construct. An indicator shared by two
constructs, a cross-loading, is allowed. The Python twin raises
`ValueError` with the same message text.

## References

Bollen, K. A. (1989). *Structural equations with latent variables*.
Wiley.
[doi:10.1002/9781118619179](https://doi.org/10.1002/9781118619179)

## See also

[`tf_implications()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_implications.md)
for the independencies the zero block encodes.

## Examples

``` r
# Measurement entries written as column names give syntax that fits as it
# stands. Threat and avoidance both follow from arousal alone, so the
# syntax fixes the covariance of their disturbances at zero.
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.",
                   measurement = c("heart_rate", "arousal_rating")) |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.",
                   measurement = "threat_rating") |>
  tf_add_construct("c_avoidance", "Avoidance", "Withdrawal from the trigger.",
                   measurement = c("avoidance_task", "avoidance_diary")) |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "increases") |>
  tf_add_proposition("p2", "c_arousal", "c_avoidance", "increases")
cat(tf_compile_sem(theory))
#> # lavaan model generated by theoryforge for demo-1
#> # Written for lavaan::sem(); indicator names are the sanitised measurement entries and must match columns of the data.
#> # Measurement model
#> c_arousal =~ heart_rate + arousal_rating
#> c_threat =~ threat_rating
#> c_avoidance =~ avoidance_task + avoidance_diary
#> # Single-indicator constructs (lavaan fixes the indicator's residual variance at zero, so each is treated as measured without error): c_threat
#> # Structural model
#> c_threat ~ c_arousal
#> c_avoidance ~ c_arousal
#> # Covariances the theory fixes at zero (lavaan::sem() frees them by default; delete this block to restore its defaults)
#> c_threat ~~ 0*c_avoidance
```
