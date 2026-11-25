"""Deterministic dynamical-system runner derived from a theory's network.

Each construct is a state variable, and each proposition whose relation is ``increases``,
``decreases``, ``causes`` or ``mediates`` contributes a linear coupling term with the sign
the relation table (API_SPEC.md section 28) gives it. ``causes`` and ``mediates`` state no
sign and are coupled positively, an assumption the result records. The system
dX/dt = (A - damping*I) X is propagated either with fixed-step (Euler) updates or exactly, with
the matrix exponential of (A - damping*I)*dt. Both are deterministic and computed with
explicit loops in a fixed order, so the R package gives the same values to the last bit.
"""
from __future__ import annotations

import math
import numbers
import warnings
from collections.abc import Mapping
from itertools import repeat
from operator import add, mul, truediv

from ._access import RELATION, enum, field, items, text
from ._compat import theory_keyword
from ._num import rnd
from ._relations import PATHS, RELATIONS

_METHODS = ("euler", "exact")
# Degree of the Taylor polynomial of the propagator, after scaling the matrix
# to an infinity norm of at most 0.5 (API_SPEC section 22).
_TAYLOR_DEGREE = 18
# The Euler run warns once a state departs from the exact one by more than
# this fraction of max(1, |exact|).
_DEPARTURE = 0.05
_EULER_WARNING = ("simulate: the Euler steps depart from the exact solution by more than "
                  "5 per cent; use method 'exact' or a smaller dt")
_INIT_FORM = ("simulate requires init to be a finite number or a mapping from construct ids "
              "to finite numbers")
_INIT_UNKNOWN = "simulate requires init to name declared constructs; unknown construct id: "


def _finite_number(x) -> bool:
    # A bool is an int in Python but a logical in R, which R refuses, so both
    # twins refuse it.
    return (isinstance(x, numbers.Real) and not isinstance(x, bool)
            and math.isfinite(x))


def _init_mapping(init) -> bool:
    """Whether ``init`` maps nonempty strings to finite numbers.

    R holds a mapping as a named vector or list, whose names are strings and
    cannot be empty, so an empty or non-string key is refused here as well.
    """
    return (isinstance(init, Mapping)
            and all(isinstance(key, str) and key != "" for key in init)
            and all(_finite_number(value) for value in init.values()))


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
    if not (_finite_number(init) or _init_mapping(init)):
        raise ValueError(_INIT_FORM)
    if not (isinstance(method, str) and method in _METHODS):
        raise ValueError("simulate requires method to be one of: euler, exact")
    return int(steps)


def _rows(B: list) -> list:
    """For each row of B: the columns of its nonzero entries, the span from the
    first of them to one past the last, and whether every entry is finite.
    NaN counts as nonzero. A row whose sum is not finite is taken to hold an
    entry that is not finite, which at worst means a term is added that could
    have been skipped."""
    out = []
    for row in B:
        nonzero = [j for j, b in enumerate(row) if b]
        out.append((nonzero, nonzero[0] if nonzero else 0, nonzero[-1] + 1 if nonzero else 0,
                    math.isfinite(sum(row))))
    return out


def _matmul(A: list, B: list, rows: list | None = None) -> list:
    """A times B, each element a left fold over the inner index m.

    Row i of the product is built by adding A[i][m] times row m of B for each
    m in turn, so that every element adds its terms in the order of m, as the
    triple loop over i, j and m does. A term with one factor 0 and the other
    finite is 0 or -0, and adding it leaves a sum unchanged, since a sum that
    starts at +0 never holds -0, so such terms are skipped. A term with an
    infinite or NaN factor is always added. ``rows`` is ``_rows(B)``, which a
    caller that multiplies by the same B again can pass.
    """
    n = len(A)
    if rows is None:
        rows = _rows(B)
    every_row_finite = all(r[3] for r in rows)
    out = []
    for row_a in A:
        acc = [0.0] * n
        terms = ([(m, a) for m, a in enumerate(row_a) if a] if every_row_finite
                 else enumerate(row_a))
        for m, a in terms:
            nonzero, lo, hi, finite = rows[m]
            if a == 0.0 and finite:
                continue
            row_b = B[m]
            if not math.isfinite(a):
                acc = list(map(add, acc, map(mul, repeat(a), row_b)))
            elif 3 * len(nonzero) < hi - lo:
                for j in nonzero:
                    acc[j] = acc[j] + a * row_b[j]
            elif lo < hi:
                acc[lo:hi] = map(add, acc[lo:hi], map(mul, repeat(a), row_b[lo:hi]))
        out.append(acc)
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
    rows = _rows(A)
    for kk in range(1, _TAYLOR_DEGREE + 1):
        term = _matmul(term, A, rows)
        term = [list(map(truediv, row, repeat(kk))) for row in term]
        E = [list(map(add, row_e, row_t)) for row_e, row_t in zip(E, term, strict=True)]
    for _ in range(s):
        E = _matmul(E, E)
    return E


def _check_finite(X: list, states: list, step: int, remedy: str) -> None:
    """Stop the run at the first state, in file order, that cannot be rounded.

    rnd() scales by 10^6, so the scaled value is tested. A state can stay finite
    for a few steps after that product overflows, and rnd() would then write an
    infinity into the trajectory, as R's rounding does.
    """
    for i, x in enumerate(X):
        if not math.isfinite(x * 1e6):
            raise ValueError(
                f"simulate diverged at step {step}: state '{states[i]}' is not finite; "
                + remedy)


def _nonzero(M: list) -> list:
    """The entries of each row of M that are not 0, as (column, value) pairs in
    column order. NaN is not 0 and is kept."""
    return [[(j, x) for j, x in enumerate(row) if x != 0.0] for row in M]


def _apply(rows: list, X: list) -> list:
    """M times X, each sum a left-to-right loop as R adds, from the nonzero
    entries of M's rows (``_nonzero()``).

    Every state in X is finite, since each update is tested before the next, so
    the terms a 0 of M gives are 0 or -0 and leave the sum as it is.
    """
    out = []
    for row in rows:
        acc = 0.0
        for j, x in row:
            acc = acc + x * X[j]
        out.append(acc)
    return out


@theory_keyword
def simulate(theory, steps: int = 10, dt: float = 0.1, k: float = 1.0,
             damping: float = 0.5, init: float | Mapping[str, float] = 1.0,
             method: str = "euler") -> dict:
    """Propagate the theory's construct network as a linear dynamical system.

    Returns {states, dt, steps, k, damping, init, initial_state, method, ignored,
    assumed_positive, opposed, trajectory}, where trajectory[t] is the state vector
    at time t*dt (t = 0..steps), each value rounded to 6 decimals. The settings and
    the method are returned as given, because the trajectory cannot be reproduced
    without them, and ``initial_state`` gives the value each state starts from, in
    the order of ``states``. Construct ids must be unique. A construct without an
    id is a state with no couplings, and two of them do not count as duplicates.

    Each proposition between two declared constructs whose relation is
    ``increases``, ``decreases``, ``causes`` or ``mediates`` adds k times the sign
    of its relation to the coupling from ``from`` to ``to``. The signs are those
    of the relation table (API_SPEC.md section 28): +1 for ``increases`` and -1
    for ``decreases``. ``causes`` and ``mediates`` state no sign, and they are
    coupled at +k by assumption. ``assumed_positive`` lists their ids, in file
    order, since that choice alone can decide whether a feedback loop grows or
    settles. ``ignored`` lists the ids of the propositions that couple nothing
    (``moderates``, ``associates``, a relation outside the schema's set or an
    endpoint that is not a declared construct), and ``opposed`` the ``[from,
    to]`` pairs that carry couplings of both signs, which offset each other.

    ``init`` is either one finite number, the value every state starts from, or
    a mapping from construct ids to finite numbers, in which case each state it
    does not name starts from 0. A mapping with one entry gives the response to
    an impulse in that construct. A key that is not a declared construct id
    raises ValueError.

    ``method = "exact"`` multiplies the state by the matrix exponential of
    (A - damping*I)*dt at every step, computed by scaling and squaring a degree-18
    Taylor polynomial (Moler & Van Loan, 2003, method 3), so the trajectory is the
    solution of the linear system at those times whatever ``dt`` is.
    ``method = "euler"`` (the default for this release) takes fixed explicit steps,
    which are stable only when |1 + dt*lambda| < 1 for every eigenvalue lambda of
    A - damping*I. A theory that decays at rate ``damping`` therefore grows without
    bound, alternating in sign, once dt*damping exceeds 2, and the steps turn a
    sustained oscillation into growth. The Euler run warns (UserWarning) when it
    departs from the exact solution, at any step, by more than 5 per cent of the
    larger of |exact| and the largest absolute starting value (1 when every
    starting value is 0), so that the warning does not depend on the unit of
    ``init``. The default will change to ``"exact"`` in the next minor release.

    ``steps`` must be a whole number of at least 0 and ``dt`` a finite number
    above 0. ``k`` and ``damping`` must be finite numbers, ``init`` as above and
    ``method`` one of "euler" and "exact". Anything else raises ValueError. When a
    state grows so large that a million times it is not a finite double, the run
    stops with ValueError naming the step and the state. The initial state is
    tested as step 0, so a starting value beyond about 1.8e302 in absolute value
    stops there.

    The model is deliberately simple: one gain ``k`` for every coupling,
    ``causes`` and ``mediates`` taken as positive, ``moderates`` and
    ``associates`` coupling nothing and ``functional_form`` not read. A linear
    system has one equilibrium, or a continuum of them when its matrix is
    singular, and never two separate ones, so it cannot show bistability.

    References:
        Moler, C., & Van Loan, C. (2003). Nineteen dubious ways to compute the
        exponential of a matrix, twenty-five years later. SIAM Review, 45(1),
        3-49. https://doi.org/10.1137/S00361445024180
    """
    n_steps = _check_knobs(steps, dt, k, damping, init, method)
    # The knobs are echoed as given, and computed with as doubles, as R holds
    # them: a NumPy float32 would otherwise make some products float32.
    dt_, k_, damping_ = float(dt), float(k), float(damping)
    theory = theory.data if hasattr(theory, "data") else theory
    states = [text(field(c, "id")) for c in items(theory, "constructs")]
    n = len(states)
    # Duplicate construct ids have no defensible reading here: a dict
    # comprehension keeps the last index and R's `[[` on a named vector the
    # first, so the two engines would give two plausible trajectories for the
    # same file. Refuse instead of picking a winner.
    # Constructs without ids share no id: no proposition can name them, so
    # each is a state with no couplings.
    seen: set = set()
    for s in states:
        if s in seen and s != "":
            raise ValueError(f"simulate requires unique construct ids; duplicate construct id: {s}")
        seen.add(s)
    idx = {s: i for i, s in enumerate(states) if s != ""}
    if isinstance(init, Mapping):
        for key in init:
            if key not in idx:
                raise ValueError(_INIT_UNKNOWN + key)
        X = [float(init[s]) if s in init else 0.0 for s in states]
    else:
        X = [float(init)] * n

    A = [[0.0] * n for _ in range(n)]
    ignored: list = []
    assumed: list = []
    # The signs each ordered pair carries, in the order the pairs first couple.
    pair_signs: dict = {}
    for p in items(theory, "propositions"):
        f, t = text(field(p, "from")), text(field(p, "to"))
        rel = enum(field(p, "relation"), RELATION)
        if rel in PATHS and f in idx and t in idx:
            stated = RELATIONS[rel][1]
            sign = 1.0 if stated is None else float(stated)
            A[idx[t]][idx[f]] += sign * k_
            pair_signs.setdefault((f, t), set()).add(sign)
            if stated is None:
                assumed.append(text(field(p, "id")))
        else:
            ignored.append(text(field(p, "id")))
    opposed = [[f, t] for (f, t), signs in pair_signs.items() if len(signs) == 2]

    # The exact propagator, which method "exact" steps with and the Euler run
    # is checked against. Neither needs it when nothing moves.
    E: list = []
    if n > 0 and n_steps > 0:
        J = [[A[i][j] - (damping_ if i == j else 0.0) for j in range(n)] for i in range(n)]
        E = _nonzero(_propagator(J, dt_))
    couplings = _nonzero(A)
    # A smaller dt cures an Euler divergence that the step causes, but it does
    # not change the exact solution, which grows only when the system does.
    # Raising damping shifts every eigenvalue of J to the left, so it tames
    # the exact solution, while it can make the Euler steps diverge.
    remedy = ("raise damping, reduce k or take fewer steps" if method == "exact"
              else "reduce dt or k")

    initial = list(X)
    # Row 0 is tested as every update is. A finite init can be too large to
    # round (about 1.8e302 or more), and only init shapes this row.
    _check_finite(X, states, 0, "reduce init")
    Y = list(X)  # the exact state the Euler run is compared with
    # The departure is measured against the larger of |exact| and the largest
    # absolute starting value, so that it does not depend on the unit of init.
    # A run that starts at 0 everywhere takes 1. R computes the same scale.
    scale = 0.0
    for x in X:
        if abs(x) > scale:
            scale = abs(x)
    if scale == 0.0:
        scale = 1.0
    departed = False
    traj = [[rnd(x, 6) for x in X]]
    for step in range(1, n_steps + 1):
        if method == "exact":
            X = _apply(E, X)
        else:
            # A left-to-right loop, as R adds. The builtin sum() compensates
            # rounding error from Python 3.12, and in fast-growing regimes that
            # moved the twins apart beyond the parity tolerance.
            dX = [acc - damping_ * x for acc, x in zip(_apply(couplings, X), X, strict=True)]
            X = [X[i] + dt_ * dX[i] for i in range(n)]
        _check_finite(X, states, step, remedy)
        if method == "euler" and not departed:
            Y = _apply(E, Y)
            for i in range(n):
                # An exact state beyond the double range is a departure too,
                # since the Euler state is still finite here.
                if (not math.isfinite(Y[i])
                        or abs(X[i] - Y[i]) > _DEPARTURE * max(scale, abs(Y[i]))):
                    departed = True
                    break
        traj.append([rnd(x, 6) for x in X])

    if departed:
        warnings.warn(_EULER_WARNING, UserWarning, stacklevel=2)
    return {"states": states, "dt": dt, "steps": steps, "k": k, "damping": damping,
            "init": dict(init) if isinstance(init, Mapping) else init,
            "initial_state": initial, "method": method, "ignored": ignored,
            "assumed_positive": assumed, "opposed": opposed, "trajectory": traj}
