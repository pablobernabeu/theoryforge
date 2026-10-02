"""Deterministic, cross-platform rounding (API_SPEC.md section 3).

Python's built-in ``round`` uses round-half-to-even on the exact double, whose result can
differ across platforms for values that sit on an exact decimal half-boundary (e.g. 0.6125).
``rnd`` rounds half away from zero using pure floor arithmetic with a tiny bias (1e-6) that is
far larger than any cross-platform unit-in-the-last-place jitter (~1e-13 at these magnitudes)
yet far smaller than the rounding grid, so the result is identical on every platform and matches
the R implementation byte-for-byte.
"""
from __future__ import annotations

import math


def rnd(x: float, n: int) -> float:
    s = 10 ** n
    if x >= 0:
        r = math.floor(x * s + 0.5 + 1e-6) / s
    else:
        r = -math.floor(-x * s + 0.5 + 1e-6) / s
    # Adding +0.0 turns a negative zero into +0, as R's `+ 0` does, so a
    # negative value that rounds to zero never prints as -0.0 (API_SPEC.md
    # section 3).
    return r + 0.0
