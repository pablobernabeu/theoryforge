# Derive a theory's implied conditional independencies

Reads the propositions whose relation is causal (`"causes"`,
`"increases"`, `"decreases"`) as directed edges over the constructs they
connect, checks that the resulting graph is acyclic, and returns its
basis set: for every pair of non-adjacent constructs, the claim that the
two are independent given the parents of both. A basis set implies every
other conditional independence the graph entails, so it is the shortest
complete statement of what the theory forbids in data, and each entry is
something a study could find and refute.

## Usage

``` r
tf_implications(theory)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

## Value

A named list
`list(theory_id, acyclic, constructs, n_edges, implications, n_implications)`.
`constructs` holds, in file order, the constructs a causal proposition
connects. `acyclic` is always `TRUE` in a returned record, since a
cyclic graph is refused; it is carried so that a serialised record
states the verdict rather than leaving a reader to infer that the check
ran. Each entry of `implications` is a list
`list(a, b, given, statement)`, where `statement` renders the claim as
`a _||_ b | z1, z2`. Pairs come in construct file order, as do the
members of `given`.

## Details

Constructs that no causal proposition connects are left out, because
silence about a construct is not a claim that it is independent of
anything. A theory with no causal propositions therefore comes back with
an empty basis set and no error.

## Refusals

The function stops in three cases. Two constructs sharing an id would
give one node two sets of parents, and a causal proposition naming an
undeclared construct would shrink the graph and so imply independencies
the theory never claimed. A cyclic causal graph has no basis set at all,
and the message names a cycle that was found. The Python twin raises
`ValueError` on the same three, with the same message text.

## References

Pearl, J. (1988). *Probabilistic reasoning in intelligent systems:
Networks of plausible inference*. Morgan Kaufmann.

Shipley, B. (2000). A new inferential test for path models based on
directed acyclic graphs. *Structural Equation Modeling*, 7(2), 206-218.
[doi:10.1207/S15328007SEM0702_4](https://doi.org/10.1207/S15328007SEM0702_4)

## See also

[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
with `type = "causal_dag"`, which exports the same subgraph as dagitty
syntax without reading it, and the methodological foundations article
for the literature behind the causal-testability criterion.

## Examples

``` r
# A mediated chain commits the theory to one thing it does not state
# directly: arousal and avoidance are independent once threat is held fixed.
theory <- tf_theory("mediation", "A mediated chain") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_construct("c_avoidance", "Avoidance", "Withdrawal from the trigger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "increases") |>
  tf_add_proposition("p2", "c_threat", "c_avoidance", "increases")

implied <- tf_implications(theory)
implied$n_implications
#> [1] 1
implied$implications[[1]]$statement
#> [1] "c_arousal _||_ c_avoidance | c_threat"
```
