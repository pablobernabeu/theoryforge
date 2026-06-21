"""Opt-in embedding-based construct-redundancy screen (API_SPEC.md Part E).

PARITY-EXEMPT: results depend on a user-supplied embedding function whose outputs are not
deterministic across model versions or SDKs. This is the assistive counterpart to the
deterministic lexical screen in `redundancy.py`; it is excluded from the parity contract and CI.
"""
from __future__ import annotations

import math
from collections.abc import Callable, Sequence

from . import _resources
from ._num import rnd


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def _cosine(a: Sequence[float], b: Sequence[float]) -> float:
    num = sum(x * y for x, y in zip(a, b, strict=False))
    da = math.sqrt(sum(x * x for x in a))
    db = math.sqrt(sum(y * y for y in b))
    if da == 0 or db == 0:
        return 0.0
    return num / (da * db)


def embedding_redundancy(T, embedder: Callable[[str], Sequence[float]],
                         threshold: float | None = None) -> list[dict]:
    """Pairwise cosine similarity of embedded construct definitions.

    `embedder` maps a definition string to a numeric vector. Returns one record per unordered
    construct pair, sorted by descending similarity then (a, b), with a `review`/`ok` flag.
    """
    T = T.data if hasattr(T, "data") else T
    if threshold is None:
        threshold = _resources.checklist()["thresholds"]["redundancy_similarity_max"]
    cons = _list(T, "constructs")
    vecs = [(c.get("id", ""), embedder(c.get("definition", ""))) for c in cons]
    rows = []
    for i in range(len(vecs)):
        for j in range(i + 1, len(vecs)):
            sim = rnd(_cosine(vecs[i][1], vecs[j][1]), 6)
            rows.append({
                "a": vecs[i][0], "b": vecs[j][0],
                "cosine": sim, "flag": "review" if sim >= threshold else "ok",
            })
    rows.sort(key=lambda r: (-r["cosine"], r["a"], r["b"]))
    return rows
