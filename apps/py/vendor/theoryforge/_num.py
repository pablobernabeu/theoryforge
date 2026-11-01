"""Deterministic, cross-platform rounding (API_SPEC.md section 3).

Python's built-in ``round`` uses round-half-to-even on the exact double, whose result can
differ across platforms for values that sit on an exact decimal half-boundary (e.g. 0.6125).
``rnd`` rounds half away from zero using pure floor arithmetic with a tiny bias (1e-6), far
smaller than the rounding grid, and matches the R implementation byte-for-byte. For the
checklist's scores, the bias is far larger than any cross-platform jitter in the last place.
It is absorbed once |x| * 10^n reaches 2^34 (|x| about 1.7e4 at n = 6), where adding 1e-6 no
longer changes the double. Larger values, such as the states of a growing simulation,
therefore round alike in the twins only because both compute the same double.
"""
from __future__ import annotations

import math


def rnd(x: float, n: int) -> float:
    s = 10 ** n
    # Defined for every double, as R's `sign(x) * floor(abs(x) * s + ...) / s`
    # computes it: NaN stays NaN, and a value whose scaled form is not finite
    # (an infinity, or a finite |x| above about 1.8e302 at n = 6) becomes an
    # infinity of its sign. math.floor() would raise ValueError and
    # OverflowError there.
    if math.isnan(x):
        return math.nan
    if not math.isfinite(abs(x) * s + 0.5 + 1e-6):
        return math.copysign(math.inf, x)
    if x >= 0:
        r = math.floor(x * s + 0.5 + 1e-6) / s
    else:
        r = -math.floor(-x * s + 0.5 + 1e-6) / s
    # Adding +0.0 turns a negative zero into +0, as R's `+ 0` does, so a
    # negative value that rounds to zero never prints as -0.0 (API_SPEC.md
    # section 3).
    return r + 0.0


def number(v) -> float | None:
    """``v`` as a float when it is a number other than NaN, and None otherwise.

    A boolean is not a number, as R's ``is.numeric()`` agrees. An integer too
    large for a float reads as the infinity of its sign, because R's reader
    holds an unquoted integer of 400 digits as ``Inf`` (API_SPEC.md section 3),
    and ``float()`` would raise OverflowError on it.
    """
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        return None
    try:
        x = float(v)
    except OverflowError:
        x = math.inf if v > 0 else -math.inf
    return None if math.isnan(x) else x
