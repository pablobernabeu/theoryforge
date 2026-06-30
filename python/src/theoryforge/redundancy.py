"""Deterministic lexical redundancy screen, the parity-tested default.

Embedding-based similarity is an opt-in enhancement that is parity-exempt (see API_SPEC.md).
"""
from __future__ import annotations

import re

from . import _resources
from ._num import rnd

STOPWORDS = {
    "the", "and", "for", "that", "with", "from", "are", "was", "its", "our", "their",
    "this", "these", "those", "towards", "toward", "into", "onto", "per", "via",
}

_NON_ALNUM = re.compile(r"[^a-z0-9]+")


def tokens(s: str) -> set[str]:
    """Tokenise a string into a SET of content tokens (see API_SPEC.md section 6)."""
    s = (s or "").lower()
    parts = _NON_ALNUM.sub(" ", s).split()
    return {t for t in parts if len(t) >= 3 and t not in STOPWORDS}


def jaccard(a: set[str], b: set[str]) -> float:
    if not a and not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return rnd(inter / union, 3)


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def redundancy_check(T: dict) -> list[dict]:
    """Pairwise lexical similarity of construct definitions.

    Returns one record per unordered construct pair, sorted by descending
    similarity then ``(a, b)`` ascending.

    References:
        Le, H., Schmidt, F. L., Harter, J. K., & Lauver, K. J. (2010). The
        problem of empirical redundancy of constructs. Organizational Behavior
        and Human Decision Processes, 112(2), 112-125.
        https://doi.org/10.1016/j.obhdp.2010.02.003
        Lawson, K. M., & Robins, R. W. (2021). Sibling constructs. Personality
        and Social Psychology Review, 25(4), 344-366.
        https://doi.org/10.1177/10888683211047101
    """
    T = T.data if hasattr(T, "data") else T
    cons = _list(T, "constructs")
    thr = _resources.checklist()["thresholds"]["redundancy_similarity_max"]
    toks = [(c.get("id", ""), tokens(c.get("definition", ""))) for c in cons]
    rows = []
    for i in range(len(toks)):
        for j in range(i + 1, len(toks)):
            sim = jaccard(toks[i][1], toks[j][1])
            rows.append({
                "a": toks[i][0],
                "b": toks[j][0],
                "similarity": sim,
                "flag": "review" if sim >= thr else "ok",
            })
    rows.sort(key=lambda r: (-r["similarity"], r["a"], r["b"]))
    return rows
