"""Deterministic dynamical-system runner derived from a theory's network.

Each construct is a state variable, and each directed proposition contributes a signed linear
coupling term. The system dX/dt = (A - damping*I) X is propagated either with fixed-step
(Euler) updates or exactly, with the matrix exponential of (A - damping*I)*dt. Both are fully
deterministic and computed with explicit loops in a fixed order, so the R twin gives the same
bits.
"""
from __future__ import annotations

import math
import numbers
import warnings

from ._access import RELATION, enum, field, items, text
from ._num import rnd

_POS = {"increases", "causes", "mediates"}
_NEG = {"decreases"}
_METHODS = ("euler", "exact")
# Degree of the Taylor polynomial of the propagator, after scaling the matrix
# to an infinity norm of at most 0.5 (API_SPEC section 22).
_TAYLOR_DEGREE = 18
# The Euler run warns once a state departs from the exact one by more than
# this fraction of max(1, |exact|).
_DEPARTURE = 0.05
_EULER_WARNING = ("simulate: the Euler steps depart from the exact solution by more than "
                  "5 per cent; use method 'exact' or a smaller dt")


def _finite_number(x) -> bool:
    # A bool is an int in Python but a logical in R, which R refuses, so both
    # twins refuse it.
    return (isinstance(x, numbers.Real) and not isinstance(x, bool)
            and math.isfinite(x))


def _check_knobs(steps, dt, k, damping, init, method) -> int:
    """Refuse invalid knobs with the messages the R twin gives (API_SPEC section 22).

    Returns the number of steps as an int. ``numbers.Integral`` covers numpy
    integers, which are not ``int``, and a float is accepted when it is whole, as R
    accepts 3 as well as 3L.
    """
    if isinstance(steps, numbers.Integral) and not isinstance(steps, bool):
        whole = int(steps) >= 0
    else:
        whole = (isinstance(steps, float) and math.isfinite(steps)
                 and steps.is_integer() and steps >= 0)
    if not whole:
        raise ValueError("simulate requires steps to be a whole number of at least 0")
    if not (_finite_number(dt) and dt > 0):
        raise ValueError("simulate requires dt to be a finite number greater than 0")
    if not _finite_number(k):
        raise ValueError("simulate requires k to be a finite number")
    if not _finite_number(damping):
        raise ValueError("simulate requires damping to be a finite number")
    if not _finite_number(init):
        raise ValueError("simulate requires init to be a single finite number")
    if not (isinstance(method, str) and method in _METHODS):
        raise ValueError("simulate requires method to be one of: euler, exact")
    return int(steps)


def _matmul(A: list, B: list) -> list:
    """A times B by explicit loops, the inner index last, each sum a left fold."""
    n = len(A)
    out = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            acc = 0.0
            for m in range(n):
                acc = acc + A[i][m] * B[m][j]
            out[i][j] = acc
    return out


def _propagator(J: list, dt: float) -> list:
    """expm(dt*J) by scaling and squaring a degree-18 Taylor polynomial.

    Method 3 of Moler and Van Loan (2003). The matrix is halved s times until
    its infinity norm (the largest absolute row sum) is at most 0.5, the Taylor
    series is summed as term = term*A/k for k = 1..18, and the sum is squared s
    times. Every loop runs in a fixed order so that the R twin's
    ``.tf_sim_propagator()`` gives the same bits. A matrix whose norm is not
    finite has no computable propagator, and the result is NaN throughout, so
    the first step diverges.
    """
    n = len(J)
    M = [[dt * J[i][j] for j in range(n)] for i in range(n)]
    norm = 0.0
    for i in range(n):
        r = 0.0
        for j in range(n):
            r = r + abs(M[i][j])
        if not math.isfinite(r):
            return [[math.nan] * n for _ in range(n)]
        if r > norm:
            norm = r
    s = 0
    while norm > 0.5:
        norm = norm / 2.0
        s += 1
    scale = 1.0
    for _ in range(s):
        scale = scale / 2.0
    A = [[M[i][j] * scale for j in range(n)] for i in range(n)]
    E = [[1.0 if i == j else 0.0 for j in range(n)] for i in range(n)]
    term = [row[:] for row in E]
    for kk in range(1, _TAYLOR_DEGREE + 1):
        term = _matmul(term, A)
        term = [[term[i][j] / kk for j in range(n)] for i in range(n)]
        E = [[E[i][j] + term[i][j] for j in range(n)] for i in range(n)]
    for _ in range(s):
        E = _matmul(E, E)
    return E


def _apply(E: list, X: list) -> list:
    """E times X, each sum a left-to-right loop as R adds."""
    n = len(X)
    out = []
    for i in range(n):
        acc = 0.0
        for j in range(n):
            acc = acc + E[i][j] * X[j]
        out.append(acc)
    return out


def simulate(T, steps: int = 10, dt: float = 0.1, k: float = 1.0,
             damping: float = 0.5, init: float = 1.0, method: str = "euler") -> dict:
    """Propagate the theory's construct network as a linear dynamical system.

    Returns {states, dt, steps, k, damping, init, method, ignored, opposed,
    trajectory}, where trajectory[t] is the state vector at time t*dt (t = 0..steps),
    each value rounded to 6 decimals. The knobs and the method are echoed back as
    given, because the trajectory cannot be reproduced without them. ``ignored``
    lists the ids of the propositions that couple nothing (moderates, associates, a
    relation outside the schema's set, or an endpoint that is not a declared
    construct), and ``opposed`` the ``[from, to]`` pairs that carry couplings of
    both signs, which offset each other. Construct ids must be unique. A construct
    without an id is a state with no couplings, and two of them do not count as
    duplicates.

    ``method = "exact"`` multiplies the state by the matrix exponential of
    (A - damping*I)*dt at every step, so the trajectory is the solution of the
    linear system at those times whatever ``dt`` is. ``method = "euler"`` (the
    default for this release) takes fixed explicit steps, which are stable only
    when |1 + dt*lambda| < 1 for every eigenvalue lambda of A - damping*I. A theory
    that decays at rate ``damping`` therefore explodes with alternating sign once
    dt*damping exceeds 2, and the steps inflate a sustained oscillation into
    growth. The Euler run warns (UserWarning) when it departs from the exact
    solution by more than 5 per cent of max(1, |exact|) at any step. The default
    will change to ``"exact"`` in the next minor release.

    ``steps`` must be a whole number of at least 0, ``dt`` a finite number above 0,
    ``k``, ``damping`` and ``init`` finite numbers, and ``method`` one of "euler"
    and "exact". Anything else raises ValueError. When a state grows so large that
    a million times it is not a finite double, the run stops with ValueError naming
    the step and the state.

    The model is deliberately simple: one gain ``k`` for every coupling, ``causes``
    and ``mediates`` taken as positive, ``moderates`` and ``associates`` coupling
    nothing, ``functional_form`` not read and a common initial value for every
    state. A linear system has one equilibrium, or a continuum of them when its
    matrix is singular, and never two separate ones, so it cannot show bistability.
    """
    n_steps = _check_knobs(steps, dt, k, damping, init, method)
    T = T.data if hasattr(T, "data") else T
    states = [text(field(c, "id")) for c in items(T, "constructs")]
    n = len(states)
    # Duplicate construct ids have no defensible reading here, and the two
    # engines resolved them differently by accident (a dict comprehension keeps
    # the last index, R's `[[` on a named vector the first), so the same file
    # produced two plausible trajectories. Refuse instead of picking a winner.
    # Constructs without ids share no id: no proposition can name them, so
    # each is a state with no couplings.
    seen: set = set()
    for s in states:
        if s in seen and s != "":
            raise ValueError(f"simulate requires unique construct ids; duplicate construct id: {s}")
        seen.add(s)
    idx = {s: i for i, s in enumerate(states) if s != ""}

    A = [[0.0] * n for _ in range(n)]
    ignored: list = []
    # The signs each ordered pair carries, in the order the pairs first couple.
    pair_signs: dict = {}
    for p in items(T, "propositions"):
        f, t = text(field(p, "from")), text(field(p, "to"))
        rel = enum(field(p, "relation"), RELATION)
        sign = 1.0 if rel in _POS else (-1.0 if rel in _NEG else 0.0)
        if f in idx and t in idx:
            A[idx[t]][idx[f]] += sign * k
        if f in idx and t in idx and sign != 0.0:
            pair_signs.setdefault((f, t), set()).add(sign)
        else:
            ignored.append(text(field(p, "id")))
    opposed = [[f, t] for (f, t), signs in pair_signs.items() if len(signs) == 2]

    # The exact propagator, which method "exact" steps with and the Euler run
    # is checked against. Neither needs it when nothing moves.
    E: list = []
    if n > 0 and n_steps > 0:
        J = [[A[i][j] - (damping if i == j else 0.0) for j in range(n)] for i in range(n)]
        E = _propagator(J, dt)
    # A smaller dt cures an Euler divergence that the step causes, but it does
    # not change the exact solution, which grows only when the system does.
    # Raising damping shifts every eigenvalue of J to the left, so it tames
    # the exact solution, while it can make the Euler steps diverge.
    remedy = ("raise damping, reduce k or take fewer steps" if method == "exact"
              else "reduce dt or k")

    X = [float(init)] * n
    Y = list(X)  # the exact state the Euler run is compared with
    departed = False
    traj = [[rnd(x, 6) for x in X]]
    for step in range(1, n_steps + 1):
        if method == "exact":
            X = _apply(E, X)
        else:
            dX = []
            for i in range(n):
                # A left-to-right loop, as R adds. The builtin sum() compensates
                # rounding error from Python 3.12, and in fast-growing regimes that
                # moved the twins apart beyond the parity tolerance.
                acc = 0.0
                for j in range(n):
                    acc = acc + A[i][j] * X[j]
                dX.append(acc - damping * X[i])
            X = [X[i] + dt * dX[i] for i in range(n)]
        # rnd() scales by 10^6, so test the scaled value: a state can stay
        # finite for a few more steps after that product overflows, and rnd()
        # would raise OverflowError where R carries Inf and NaN.
        for i, x in enumerate(X):
            if not math.isfinite(x * 1e6):
                raise ValueError(
                    f"simulate diverged at step {step}: state '{states[i]}' is not finite; "
                    + remedy)
        if method == "euler" and not departed:
            Y = _apply(E, Y)
            for i in range(n):
                # An exact state beyond the double range is a departure too,
                # since the Euler state is still finite here.
                if (not math.isfinite(Y[i])
                        or abs(X[i] - Y[i]) > _DEPARTURE * max(1.0, abs(Y[i]))):
                    departed = True
                    break
        traj.append([rnd(x, 6) for x in X])

    if departed:
        warnings.warn(_EULER_WARNING, UserWarning, stacklevel=2)
    return {"states": states, "dt": dt, "steps": steps, "k": k, "damping": damping,
            "init": init, "method": method, "ignored": ignored, "opposed": opposed,
            "trajectory": traj}
