# Simulate a theory's construct network as a linear dynamical system

Treats each construct (in file order) as a state variable and each
directed proposition as a signed linear coupling term, then integrates
`dX/dt = A X - damping * X` with fixed-step (Euler) updates. The result
is fully deterministic.

## Usage

``` r
tf_simulate(theory, steps = 10, dt = 0.1, k = 1, damping = 0.5, init = 1)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- steps:

  Number of Euler steps (default `10`).

- dt:

  Integration step size (default `0.1`).

- k:

  Coupling gain applied to each signed edge (default `1.0`).

- damping:

  Per-state linear decay (default `0.5`).

- init:

  Initial value for every state (default `1.0`).

## Value

A named list `list(states, dt, steps, trajectory)`, where `states` are
the construct ids in file order and `trajectory` is a list of
`steps + 1` numeric vectors (row 0 = initial state), every value rounded
to 6 decimals.

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "increases")
sim <- tf_simulate(theory, steps = 5)
sim$states
#> [[1]]
#> [1] "c_arousal"
#> 
#> [[2]]
#> [1] "c_threat"
#> 
sim$trajectory[[1]] # the common initial state
#> [1] 1 1
sim$trajectory[[length(sim$trajectory)]] # after five Euler steps
#> [1] 0.773781 1.181034
```
