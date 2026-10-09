# Simulate a theory's construct network as a linear dynamical system

Treats each construct (in file order) as a state variable and each
directed proposition as a signed linear coupling term, then propagates
`dX/dt = A X - damping * X` either with fixed-step (Euler) updates or
exactly, with the matrix exponential of `(A - damping * I) * dt`. The
result is fully deterministic. Construct ids must be unique; duplicates
are refused rather than resolved to an arbitrary state slot. A construct
without an id is a state with no couplings, and two of them do not count
as duplicates.

## Usage

``` r
tf_simulate(
  theory,
  steps = 10,
  dt = 0.1,
  k = 1,
  damping = 0.5,
  init = 1,
  method = "euler"
)
```

## Arguments

- theory:

  A theory object (named list), e.g. from
  [`tf_read()`](https://pablobernabeu.github.io/theoryforge/r/reference/tf_read.md).

- steps:

  Number of steps, a whole number of at least 0 (default `10`).

- dt:

  Time between rows, a finite number greater than 0 (default `0.1`).

- k:

  Coupling gain applied to each signed edge, a finite number (default
  `1.0`).

- damping:

  Per-state linear decay, a finite number (default `0.5`).

- init:

  Initial value for every state, a single finite number (default `1.0`).

- method:

  `"euler"` (the default for this release) or `"exact"`.

## Value

A named list
`list(states, dt, steps, k, damping, init, method, ignored, opposed, trajectory)`,
where `states` are the construct ids in file order and `trajectory` is a
list of `steps + 1` numeric vectors (row 0 = initial state), every value
rounded to 6 decimals. The knobs and the method are echoed back as
given, because the trajectory cannot be reproduced without them.
`ignored` lists the ids of the propositions that couple nothing
(moderates, associates, a relation outside the schema's set, or an
endpoint that is not a declared construct), and `opposed` the
`c(from, to)` pairs that carry couplings of both signs, which offset
each other. Invalid knobs are refused with the Python twin's messages.

## Details

With `method = "exact"` each step multiplies the state by the matrix
exponential, computed by scaling and squaring a degree-18 Taylor
polynomial (Moler and Van Loan, 2003, method 3), so the trajectory is
the solution of the linear system at times `0, dt, 2 * dt, ...` whatever
`dt` is.

With `method = "euler"`, the default for this release, the explicit step
is stable only when \\\|1 + dt \lambda\| \< 1\\ for every eigenvalue
\\\lambda\\ of `A - damping * I`. A theory that decays at rate `damping`
therefore explodes with alternating sign once `dt * damping` exceeds 2,
and the steps inflate a sustained oscillation into growth. Raising
`damping` can cause a divergence as well as fail to cure one. The
function warns when the Euler trajectory departs from the exact one by
more than 5 per cent of `max(1, |exact|)` at any step. The default will
change to `"exact"` in the next minor release.

When a state grows so large that a million times it is not a finite
number, the function stops with a message naming the step and the state.

The model is deliberately simple: one gain `k` for every coupling,
`causes` and `mediates` taken as positive, `moderates` and `associates`
coupling nothing, `functional_form` not read and a common initial value
for every state. A linear system has one equilibrium, or a continuum of
them when its matrix is singular, and never two separate ones, so it
cannot show bistability.

## References

Moler, C., & Van Loan, C. (2003). Nineteen dubious ways to compute the
exponential of a matrix, twenty-five years later. *SIAM Review, 45*(1),
3-49.
[doi:10.1137/S00361445024180](https://doi.org/10.1137/S00361445024180)

## Examples

``` r
theory <- tf_theory("demo-1", "A demonstration theory") |>
  tf_add_construct("c_arousal", "Arousal", "Bodily activation.") |>
  tf_add_construct("c_threat", "Perceived threat", "Appraised danger.") |>
  tf_add_proposition("p1", "c_arousal", "c_threat", "increases")
sim <- tf_simulate(theory, steps = 5, method = "exact")
sim$states
#> [[1]]
#> [1] "c_arousal"
#> 
#> [[2]]
#> [1] "c_threat"
#> 
sim$trajectory[[1]] # the common initial state
#> [1] 1 1
sim$trajectory[[length(sim$trajectory)]] # at time 5 * dt
#> [1] 0.778801 1.168201
```
