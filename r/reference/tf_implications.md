# Derive a theory's implied conditional independencies

Reads every proposition through the relation table (API_SPEC.md section
28). A directed relation (`"increases"`, `"decreases"`, `"causes"`,
`"mediates"` or `"moderates"`) is an edge from `from` to `to`, and
`"associates"` is a bidirected edge, covariance the theory leaves
unexplained, as a latent common cause of the two constructs would. The
constructs that a directed relation names are the vertices, and an
association is an edge only between two of them. The function then takes
every pair of vertices that no edge joins. The pair is stated
independent given the parents of both when those m-separate it
(Richardson, 2003), and otherwise given all the other ancestors of the
two when those do. A pair that neither set separates is separated by no
set of constructs (Richardson & Spirtes, 2002, Theorem 4.2), so the
theory implies no independence for it, and it is listed under
`inseparable`. These are the conditional independencies the causal graph
implies, each one a claim that data could refute. When every relation is
directed and the graph is acyclic, they are the basis set of Pearl
(1988) and Shipley (2000), from which every other independence the graph
implies follows.

## Usage

``` r
tf_implications(theory, cycles = "refuse")
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- cycles:

  What to do with a graph whose directed edges form a cycle: `"refuse"`
  (the default) stops with an error, and `"sigma"` derives the
  statements by sigma-separation (see the section on feedback loops).

## Value

A named list
`list(theory_id, criterion, acyclic, constructs, n_edges, n_bidirected, feedback, implications, n_implications, inseparable)`.
`criterion` names the separation criterion, `"m"` under
`cycles = "refuse"` and `"sigma"` under `cycles = "sigma"`. `constructs`
holds the vertices in file order. `n_edges` counts the directed edges
the theory states and `n_bidirected` the bidirected ones, a pair stated
twice counting once, before any acyclification. `feedback` lists the
feedback loops, each a list of the ids of its members in file order and
the loops in the order of their first members. A loop has two or more
members, or one construct with an edge to itself. `acyclic` is `TRUE`
when `feedback` is empty, which is always the case under
`cycles = "refuse"`, and both are carried so that a serialised record
states the verdict. Each entry of `implications` is a list
`list(a, b, given, statement)`, where `statement` renders the claim as
`a _||_ b | z1, z2`, and each entry of `inseparable` is `list(a, b)`.
Pairs come in construct file order, as do the members of `given`.

## Details

Constructs that no directed relation names are left out, because silence
about a construct is not a claim that it is independent of anything, and
so are constructs without an id, which no proposition can name. A
construct named only by associations would be a collider on every path
through it, so leaving it out loses no statement about the others. A
theory with no directed relations therefore comes back with no vertices
and no error.

## Measurement

The statements concern constructs, and a study measures them with error.
Error in a conditioning construct leaves part of the dependence that
holding it fixed should remove. A conditional statement tested on
observed scores is therefore rejected too often, and more often the
larger the sample (Westfall & Yarkoni, 2016). Take a chain whose two
paths have standardised coefficients of .5, with the middle construct
measured at a reliability of .8. A partial-correlation test at the 5 per
cent level then rejects the true statement in about 14, 29 and 51 per
cent of studies of 200, 500 and 1,000 observations. Conditional
statements are better tested with latent-variable models, such as one
built on the measurement model that
[`tf_compile_sem()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_compile_sem.md)
writes (Thoemmes et al., 2018).

## Feedback loops

With `cycles = "sigma"`, a graph whose directed edges form a cycle is
read by sigma-separation (Bongers et al., 2021), the criterion that
holds when each feedback loop, a strongly connected component of the
directed edges, has a unique equilibrium. The graph is replaced by its
acyclification (Definition A.13): every member of a loop takes the
parents of the whole loop from outside it, and the members of a loop are
joined to each other by bidirected edges. Each pair the theory leaves
unjoined is then tested in that graph as above, where m-separation
equals sigma-separation in the theory's own graph (Proposition A.19).
There, two members of one loop are always joined. So is a construct
outside a loop to every member, when it enters one of them or when it or
a member of its own loop is associated with one of them. No set
separates such a pair, and when the theory itself leaves the pair
unjoined, it is listed under `inseparable`. A theory that posits
alternative stable states, such as a bistable network, has more than one
equilibrium and violates the assumption, and its sigma statements are
not guaranteed. On an acyclic graph, the two options give the same
statements. Applying d-separation to a cyclic graph, as dagitty does
with the causal_dag export, is valid only in special cases such as a
linear model.

## Refusals

The function stops in four cases. A value of `cycles` other than
`"refuse"` or `"sigma"` is refused before the theory is read. Two
constructs sharing an id would give one node two sets of parents, and a
directed relation naming an undeclared construct would shrink the graph
and so imply independencies the theory never claimed. With
`cycles = "refuse"`, the default, a cycle among the directed edges is
refused too, and the message names a cycle that was found and the
`"sigma"` option. The Python twin raises `ValueError` in the same cases,
with the same message text.

## References

Bongers, S., Forré, P., Peters, J., & Mooij, J. M. (2021). Foundations
of structural causal models with cycles and latent variables. *The
Annals of Statistics*, 49(5), 2885-2915.
[doi:10.1214/21-AOS2064](https://doi.org/10.1214/21-AOS2064)

Pearl, J. (1988). *Probabilistic reasoning in intelligent systems:
Networks of plausible inference*. Morgan Kaufmann.

Richardson, T. (2003). Markov properties for acyclic directed mixed
graphs. *Scandinavian Journal of Statistics*, 30(1), 145-157.
[doi:10.1111/1467-9469.00323](https://doi.org/10.1111/1467-9469.00323)

Richardson, T., & Spirtes, P. (2002). Ancestral graph Markov models.
*The Annals of Statistics*, 30(4), 962-1030.
[doi:10.1214/aos/1031689015](https://doi.org/10.1214/aos/1031689015)

Shipley, B. (2000). A new inferential test for path models based on
directed acyclic graphs. *Structural Equation Modeling*, 7(2), 206-218.
[doi:10.1207/S15328007SEM0702_4](https://doi.org/10.1207/S15328007SEM0702_4)

Thoemmes, F., Rosseel, Y., & Textor, J. (2018). Local fit evaluation of
structural equation models using graphical criteria. *Psychological
Methods*, 23(1), 27-41.
[doi:10.1037/met0000147](https://doi.org/10.1037/met0000147)

Westfall, J., & Yarkoni, T. (2016). Statistically controlling for
confounding constructs is harder than you think. *PLOS ONE*, 11(3),
e0152719.
[doi:10.1371/journal.pone.0152719](https://doi.org/10.1371/journal.pone.0152719)

## See also

[`tf_diagram()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_diagram.md)
with `type = "causal_dag"`, which exports the same graph as dagitty
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

# Stating that arousal and avoidance also covary for reasons the theory
# leaves open withdraws that claim: the pair is joined by an edge.
covary <- tf_add_proposition(theory, "p3", "c_arousal", "c_avoidance", "associates")
tf_implications(covary)$n_implications
#> [1] 0

# Closing a feedback loop from threat back to arousal makes the graph cyclic.
# The default refuses it, and sigma-separation keeps the claim, since holding
# threat fixed still cuts the one way out of the loop towards avoidance.
loop <- tf_add_proposition(theory, "p3", "c_threat", "c_arousal", "causes")
try(tf_implications(loop))
#> Error : implications requires an acyclic causal graph; cycle found: c_arousal -> c_threat -> c_arousal; set cycles to 'sigma' to derive sigma-separation statements
implied <- tf_implications(loop, cycles = "sigma")
lapply(implied$feedback, unlist)
#> [[1]]
#> [1] "c_arousal" "c_threat" 
#> 
implied$implications[[1]]$statement
#> [1] "c_arousal _||_ c_avoidance | c_threat"
```
