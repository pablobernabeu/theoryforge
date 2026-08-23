"""Deterministic dynamical-system runner derived from a theory's network.

Each construct is a state variable, and each directed proposition contributes a signed linear
coupling term. The system dX/dt = (A - damping*I) X is integrated with fixed-step (Euler)
updates, so the trajectory is fully deterministic.
"""
from __future__ import annotations

from ._num import rnd

_POS = {"increases", "causes", "mediates"}
_NEG = {"decreases"}


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def simulate(T, steps: int = 10, dt: float = 0.1, k: float = 1.0,
             damping: float = 0.5, init: float = 1.0) -> dict:
    """Integrate the theory's construct network as a linear dynamical system.

    Returns {states, dt, steps, k, damping, init, trajectory}, where trajectory[t] is the
    state vector at step t (t = 0..steps), each value rounded to 6 decimals. All five
    knobs are echoed back, because the trajectory cannot be reproduced without them.
    """
    T = T.data if hasattr(T, "data") else T
    states = [c.get("id") for c in _list(T, "constructs")]
    n = len(states)
    # Duplicate construct ids have no defensible reading here, and the two
    # engines resolved them differently by accident (a dict comprehension keeps
    # the last index, R's `[[` on a named vector the first), so the same file
    # produced two plausible trajectories. Refuse instead of picking a winner.
    seen: set = set()
    for s in states:
        if s in seen:
            raise ValueError(f"simulate requires unique construct ids; duplicate construct id: {s}")
        seen.add(s)
    idx = {s: i for i, s in enumerate(states)}

    A = [[0.0] * n for _ in range(n)]
    for p in _list(T, "propositions"):
        f, t, rel = p.get("from"), p.get("to"), p.get("relation")
        if f in idx and t in idx:
            sign = 1.0 if rel in _POS else (-1.0 if rel in _NEG else 0.0)
            A[idx[t]][idx[f]] += sign * k

    X = [float(init)] * n
    traj = [[rnd(x, 6) for x in X]]
    for _ in range(steps):
        dX = [sum(A[i][j] * X[j] for j in range(n)) - damping * X[i] for i in range(n)]
        X = [X[i] + dt * dX[i] for i in range(n)]
        traj.append([rnd(x, 6) for x in X])

    return {"states": states, "dt": dt, "steps": steps, "k": k, "damping": damping,
            "init": init, "trajectory": traj}
