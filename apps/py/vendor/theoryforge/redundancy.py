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


# The overlap coefficient flags a pair only when both definitions hold at least
# this many tokens. One or two content words contained in a longer definition
# are too few to call the two constructs the same.
_MIN_OVERLAP_TOKENS = 3


def _overlap(a: set[str], b: set[str]) -> float:
    """|A and B| / min(|A|, |B|), the overlap coefficient, to 3 decimals, or 0.0 if either is empty."""
    if not a or not b:
        return 0.0
    return rnd(len(a & b) / min(len(a), len(b)), 3)


def _pairs(T: dict, thr: dict) -> list[dict]:
    """The screen's record of every unordered construct pair, in construct order.

    A pair is flagged ``review`` when its Jaccard similarity reaches
    ``redundancy_similarity_max``, a near-duplicate, or when both definitions
    hold at least three tokens and their overlap coefficient reaches
    ``redundancy_overlap_max``, one definition contained in the other. The
    checklist's non_redundancy item reads the same flags.
    """
    toks = [(text(field(c, "id")), tokens(text(field(c, "definition"))))
            for c in items(T, "constructs")]
    rows: list[dict] = []
    for i in range(len(toks)):
        for j in range(i + 1, len(toks)):
            a, b = toks[i][1], toks[j][1]
            sim = jaccard(a, b)
            ov = _overlap(a, b)
            contained = (len(a) >= _MIN_OVERLAP_TOKENS and len(b) >= _MIN_OVERLAP_TOKENS
                         and ov >= thr["redundancy_overlap_max"])
            rows.append({
                "a": toks[i][0],
                "b": toks[j][0],
                "similarity": sim,
                "overlap": ov,
                "flag": "review" if sim >= thr["redundancy_similarity_max"] or contained else "ok",
            })
    return rows


def redundancy_check(T: dict) -> list[dict]:
    """Pairwise lexical similarity of construct definitions.

    Returns one record per unordered construct pair, ``{a, b, similarity,
    overlap, flag}``, sorted by descending similarity then ``(a, b)``
    ascending. ``similarity`` is the Jaccard index of the two definitions'
    token sets and ``overlap`` their overlap coefficient, the shared tokens
    over the tokens of the shorter definition. ``flag`` is ``review`` for a
    near-duplicate, a Jaccard similarity at or above the checklist's
    ``redundancy_similarity_max``, and for a definition contained in the other,
    an overlap at or above ``redundancy_overlap_max`` when both definitions
    hold at least three tokens. It is ``ok`` otherwise.

    The screen compares words, so it cannot detect empirical redundancy, two
    differently defined constructs that correlate almost perfectly once
    measurement error is corrected for (Le et al., 2010). Sibling constructs
    (Lawson & Robins, 2021) may share vocabulary without being redundant.

    References:
        Le, H., Schmidt, F. L., Harter, J. K., & Lauver, K. J. (2010). The
        problem of empirical redundancy of constructs in organizational
        research: An empirical investigation. Organizational Behavior and Human
        Decision Processes, 112(2), 112-125.
        https://doi.org/10.1016/j.obhdp.2010.02.003
        Lawson, K. M., & Robins, R. W. (2021). Sibling constructs: What are
        they, why do they matter, and how should you handle them? Personality
        and Social Psychology Review, 25(4), 344-366.
        https://doi.org/10.1177/10888683211047101
    """
    T = T.data if hasattr(T, "data") else T
    rows = _pairs(T, _resources.checklist()["thresholds"])
    rows.sort(key=lambda r: (-r["similarity"], r["a"], r["b"]))
    return rows
