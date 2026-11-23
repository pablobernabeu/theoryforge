"""Deterministic lexical redundancy screen, the default.

Embedding-based similarity, ``embedding_redundancy()``, is an opt-in screen whose
results depend on the embedder.
"""
from __future__ import annotations

import unicodedata

from . import _resources
from ._access import field, items, str_list, text
from ._compat import theory_keyword
from ._num import rnd
from ._text import normalise_words, squish

STOPWORDS = {
    "the", "and", "for", "that", "with", "from", "are", "was", "its", "our", "their",
    "this", "these", "those", "towards", "toward", "into", "onto", "per", "via",
}
def tokens(s: str | None) -> set[str]:
    """Tokenise a string into a set of content tokens.

    The text is folded through ``schema/fold.json`` (accented Latin letters to
    ASCII, Greek and Cyrillic to small unaccented letters) and lower-cased in
    ASCII. A token is a maximal run of letters, marks and digits in any script
    (Unicode general categories L, M and N). Tokens shorter than three code
    points and English stopwords are dropped. None reads as the empty string.

    Raises:
        TypeError: when ``s`` is neither a string nor None, as R's
            ``tf_tokens()`` refuses it.
    """
    if s is not None and not isinstance(s, str):
        raise TypeError("tokens requires a string")
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


def jaccard(a, b) -> float:
    """Jaccard similarity of two token sets, such as two results of ``tokens()``.

    ``a`` and ``b`` may be any collections of strings, read as sets, as R's
    ``tf_jaccard()`` reads its vectors. Returns the size of the intersection
    divided by the size of the union, rounded to 3 decimals, or 0.0 when both
    sets are empty.
    """
    a, b = set(a), set(b)
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


def _name(s) -> str:
    """A label or measure as the screen compares it: folded, lower-cased and squished."""
    return squish(normalise_words(text(s)))


def _pairs(T: dict, thr: dict) -> list[dict]:
    """The screen's record of every unordered construct pair, in construct order.

    A pair is flagged ``review`` for any of four reasons, given in this order
    in ``reason``: a ``near duplicate``, when its Jaccard similarity reaches
    ``redundancy_similarity_max``; ``contained``, when both definitions hold at
    least three tokens and their overlap coefficient reaches
    ``redundancy_overlap_max``; ``same label``, when the two constructs carry
    one name; and ``shared measurement``, when they list a measure in common,
    so that data from it cannot tell them apart. The checklist's non_redundancy
    item reads the same flags.
    """
    cons = items(T, "constructs")
    ids = [text(field(c, "id")) for c in cons]
    toks = [tokens(text(field(c, "definition"))) for c in cons]
    labels = [_name(field(c, "label")) for c in cons]
    measures = [{_name(m) for m in str_list(field(c, "measurement"))} - {""} for c in cons]
    rows: list[dict] = []
    for i in range(len(cons)):
        for j in range(i + 1, len(cons)):
            a, b = toks[i], toks[j]
            sim = jaccard(a, b)
            ov = _overlap(a, b)
            reasons = []
            if sim >= thr["redundancy_similarity_max"]:
                reasons.append("near duplicate")
            if (len(a) >= _MIN_OVERLAP_TOKENS and len(b) >= _MIN_OVERLAP_TOKENS
                    and ov >= thr["redundancy_overlap_max"]):
                reasons.append("contained")
            if labels[i] and labels[i] == labels[j]:
                reasons.append("same label")
            if measures[i] & measures[j]:
                reasons.append("shared measurement")
            rows.append({
                "a": ids[i],
                "b": ids[j],
                "similarity": sim,
                "overlap": ov,
                "flag": "review" if reasons else "ok",
                "reason": ", ".join(reasons),
            })
    return rows


@theory_keyword
def redundancy_check(theory: dict) -> list[dict]:
    """Pairwise lexical similarity of construct definitions.

    Returns one record per unordered construct pair, ``{a, b, similarity,
    overlap, flag, reason}``, sorted by descending similarity then ``(a, b)``
    ascending. ``similarity`` is the Jaccard index of the two definitions'
    token sets and ``overlap`` their overlap coefficient, the shared tokens
    over the tokens of the shorter definition. ``flag`` is ``review`` and
    ``reason`` names why, in this order and separated by commas, for a
    ``near duplicate`` (a Jaccard similarity at or above the checklist's
    ``redundancy_similarity_max``), a definition ``contained`` in the other (an
    overlap at or above ``redundancy_overlap_max`` when both definitions hold
    at least three tokens), two constructs with the ``same label`` and two that
    list a measure in common (``shared measurement``). Labels and measures are
    compared after folding case, accents and whitespace. ``flag`` is ``ok``,
    and ``reason`` empty, otherwise.

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
    theory = theory.data if hasattr(theory, "data") else theory
    rows = _pairs(theory, _resources.checklist()["thresholds"])
    rows.sort(key=lambda r: (-r["similarity"], r["a"], r["b"]))
    return rows
