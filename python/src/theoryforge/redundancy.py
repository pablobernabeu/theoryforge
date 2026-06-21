"""Deterministic lexical redundancy screen (the parity-tested default).

Embedding-based similarity is an opt-in enhancement (parity-exempt; see API_SPEC.md).
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
    """Tokenize a string into a SET of content tokens (see API_SPEC.md section 6)."""
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
