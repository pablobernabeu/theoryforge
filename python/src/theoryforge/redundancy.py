"""Deterministic lexical redundancy screen, the default.

Embedding-based similarity (embedding_redundancy) is an opt-in, embedder-dependent
enhancement.
"""
from __future__ import annotations

import unicodedata

from . import _resources
from ._access import field, items, text
from ._num import rnd
from ._text import normalise_words

STOPWORDS = {
    "the", "and", "for", "that", "with", "from", "are", "was", "its", "our", "their",
    "this", "these", "those", "towards", "toward", "into", "onto", "per", "via",
}


def tokens(s: str) -> set[str]:
    """Tokenise a string into a set of content tokens (API_SPEC.md section 6).

    The text is folded through ``schema/fold.json`` (accented Latin letters to
    ASCII, Greek and Cyrillic to small unaccented letters) and lowercased in
    ASCII. A token is a maximal run of letters, marks and digits in any script
    (Unicode general categories L, M and N). Tokens shorter than three code
    points and English stopwords are dropped.
    """
    s = normalise_words(s or "")
    parts: list[str] = []
    run: list[str] = []
    for ch in s:
        if unicodedata.category(ch)[0] in "LMN":
            run.append(ch)
        elif run:
            parts.append("".join(run))
            run = []
    if run:
        parts.append("".join(run))
    return {t for t in parts if len(t) >= 3 and t not in STOPWORDS}


def jaccard(a: set[str], b: set[str]) -> float:
    if not a and not b:
        return 0.0
    inter = len(a & b)
    union = len(a | b)
    return rnd(inter / union, 3)


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
    cons = items(T, "constructs")
    thr = _resources.checklist()["thresholds"]["redundancy_similarity_max"]
    toks = [(text(field(c, "id")), tokens(text(field(c, "definition")))) for c in cons]
    rows: list[dict] = []
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
