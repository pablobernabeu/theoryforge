"""Deterministic dynamical-system runner derived from a theory's network.

Each construct is a state variable, and each directed proposition contributes a signed linear
coupling term. The system dX/dt = (A - damping*I) X is integrated with fixed-step (Euler)
updates, so the trajectory is fully deterministic.
"""
from __future__ import annotations

import math
import numbers

from ._access import RELATION, enum, field, items, text
from ._num import rnd

_POS = {"increases", "causes", "mediates"}
_NEG = {"decreases"}


def _finite_number(x) -> bool:
    # A bool is an int in Python but a logical in R, which R refuses, so both
    # twins refuse it.
    return (isinstance(x, numbers.Real) and not isinstance(x, bool)
            and math.isfinite(x))


def _check_knobs(steps, dt, k, damping, init) -> int:
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
    return int(steps)


def simulate(T, steps: int = 10, dt: float = 0.1, k: float = 1.0,
             damping: float = 0.5, init: float = 1.0) -> dict:
    """Integrate the theory's construct network as a linear dynamical system.

    Returns {states, dt, steps, k, damping, init, trajectory}, where trajectory[t] is the
    state vector at step t (t = 0..steps), each value rounded to 6 decimals. All five
    knobs are echoed back as given, because the trajectory cannot be reproduced without
    them. Construct ids must be unique. A construct without an id is a state with no
    couplings, and two of them do not count as duplicates.

    ``steps`` must be a whole number of at least 0, ``dt`` a finite number above 0, and
    ``k``, ``damping`` and ``init`` finite numbers. Anything else raises ValueError.
    When a state grows so large that a million times it is not a finite double, the run
    stops with ValueError naming the step and the state.

    The explicit (Euler) step is stable only when |1 + dt*lambda| < 1 for every
    eigenvalue lambda of A - damping*I. A theory that decays at rate ``damping``
    therefore explodes with alternating sign once dt*damping exceeds 2. Raising
    ``damping`` can cause a divergence as well as fail to cure one. Reduce ``dt``, or
    ``k`` when the network's own feedback outgrows the damping.
    """
    n_steps = _check_knobs(steps, dt, k, damping, init)
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
    for p in items(T, "propositions"):
        f, t = text(field(p, "from")), text(field(p, "to"))
        rel = enum(field(p, "relation"), RELATION)
        if f in idx and t in idx:
            sign = 1.0 if rel in _POS else (-1.0 if rel in _NEG else 0.0)
            A[idx[t]][idx[f]] += sign * k

    X = [float(init)] * n
    traj = [[rnd(x, 6) for x in X]]
    for step in range(1, n_steps + 1):
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
                    "reduce dt or k")
        traj.append([rnd(x, 6) for x in X])

    return {"states": states, "dt": dt, "steps": steps, "k": k, "damping": damping,
            "init": init, "trajectory": traj}
