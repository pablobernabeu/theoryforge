"""Deterministic lexical redundancy screen, the default.

Embedding-based similarity, ``embedding_redundancy()``, is an opt-in screen whose
results depend on the embedder.
"""
from __future__ import annotations

import math
import unicodedata
from collections import Counter

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
    ``tf_jaccard()`` reads its vectors. A single string is a set of one word,
    and None the empty set. Returns the size of the intersection divided by
    the size of the union, rounded to 3 decimals, or 0.0 when both sets are
    empty.
    """
    a, b = (set() if v is None else {v} if isinstance(v, str) else set(v) for v in (a, b))
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


def _fields(T: dict) -> tuple[list[str], list[set[str]], list[str], list[set[str]]]:
    """What the screen compares of each construct: its id, its definition's
    tokens, its label and its measures, the last two as the screen names them."""
    cons = items(T, "constructs")
    ids = [text(field(c, "id")) for c in cons]
    toks = [tokens(text(field(c, "definition"))) for c in cons]
    labels = [_name(field(c, "label")) for c in cons]
    measures = [{_name(m) for m in str_list(field(c, "measurement"))} - {""} for c in cons]
    return ids, toks, labels, measures


_REASONS = ("near duplicate", "contained", "same label", "shared measurement")


def _pairs(T: dict, thr: dict) -> list[dict]:
    """The screen's record of every unordered construct pair, in construct order.

    A pair is flagged ``review`` for any of four reasons, given in this order
    in ``reason``: a ``near duplicate``, when its Jaccard similarity reaches
    ``redundancy_similarity_max``; ``contained``, when both definitions hold at
    least three tokens and their overlap coefficient reaches
    ``redundancy_overlap_max``; ``same label``, when the two constructs carry
    one name; and ``shared measurement``, when every measure one of them lists
    is listed for the other too, so that it has no indicator of its own and
    data from these measures cannot tell the two apart. Constructs that share
    a method or an inventory but keep measures of their own are not flagged.
    The checklist's non_redundancy item reads the same flags (``_flagged()``).
    Each similarity and overlap is the value ``jaccard()`` and ``_overlap()``
    give for the pair alone.
    """
    ids, toks, labels, measures = _fields(T)
    sim_max, overlap_max = thr["redundancy_similarity_max"], thr["redundancy_overlap_max"]
    sizes = [len(t) for t in toks]
    # What a pair's definitions give, which depends only on the number of
    # shared tokens and the two sizes: (similarity, overlap, reasons).
    known: dict[tuple[int, int, int], tuple[float, float, tuple[str, ...]]] = {}

    def screen(inter: int, la: int, lb: int) -> tuple[float, float, tuple[str, ...]]:
        sim = 0.0 if la + lb == 0 else rnd(inter / (la + lb - inter), 3)
        ov = 0.0 if not la or not lb else rnd(inter / min(la, lb), 3)
        why: tuple[str, ...] = ("near duplicate",) if sim >= sim_max else ()
        if la >= _MIN_OVERLAP_TOKENS and lb >= _MIN_OVERLAP_TOKENS and ov >= overlap_max:
            why += ("contained",)
        return sim, ov, why

    rows: list[dict] = []
    fields = (toks, sizes, measures, labels, ids)
    for i, (a, la, mi, label, id_a) in enumerate(zip(*fields, strict=True)):
        later = zip(*(f[i + 1:] for f in fields), strict=True)
        for b, lb, mj, label_b, id_b in later:
            key = (len(a & b), la, lb)
            got = known.get(key)
            if got is None:
                got = known[key] = screen(*key)
            sim, ov, why = got
            same = bool(label) and label == label_b
            shared = bool(mi) and bool(mj) and (mi <= mj or mj <= mi)
            if why or same or shared:
                reasons = list(why)
                if same:
                    reasons.append("same label")
                if shared:
                    reasons.append("shared measurement")
                flag, reason = "review", ", ".join(reasons)
            else:
                flag, reason = "ok", ""
            rows.append({"a": id_a, "b": id_b, "similarity": sim, "overlap": ov,
                         "flag": flag, "reason": reason})
    return rows


def _flagged(T: dict, thr: dict) -> bool:
    """Whether the screen flags any pair, as ``any(r["flag"] == "review" for r
    in _pairs(T, thr))`` would say, without comparing every pair.

    Two constructs share a label when a label is seen twice. A construct's
    measures lie within another's only if that construct lists the rarest of
    them, so only the constructs that list it are compared. A pair of
    definitions with ``m`` and ``n`` tokens, ``m <= n``, can be a near
    duplicate or contained only if it shares at least ``k(m)`` tokens: the
    rounded Jaccard similarity is at most the share of the ``n`` tokens that
    are shared, plus half a unit in the last place, and the overlap coefficient
    is that share of the ``m``. At least one of any ``m - k(m) + 1`` tokens of
    the shorter definition is then shared, so each construct is indexed by that
    many of its rarest tokens, and only definitions that hold one of another's
    indexed tokens are compared. Thresholds at or below 0, which would flag
    pairs that share no token, are left to the full comparison.
    """
    sim_max, overlap_max = thr["redundancy_similarity_max"], thr["redundancy_overlap_max"]
    if not (sim_max > 0 and overlap_max > 0):
        return any(r["flag"] == "review" for r in _pairs(T, thr))
    ids, toks, labels, measures = _fields(T)
    if len(ids) < 2:
        return False
    seen: set[str] = set()
    for label in labels:
        if label in seen:
            return True
        if label:
            seen.add(label)
    holders: dict[str, list[int]] = {}
    for j, ms in enumerate(measures):
        for m in ms:
            holders.setdefault(m, []).append(j)
    for i, ms in enumerate(measures):
        if ms:
            rarest = min(ms, key=lambda m: (len(holders[m]), m))
            if any(j != i and ms <= measures[j] for j in holders[rarest]):
                return True
    # The fewest shared tokens either flag needs, less a margin that covers
    # the rounding to 3 decimals.
    def needed(m: int) -> int:
        bound = (sim_max - 0.001) * m - 1e-6
        if m >= _MIN_OVERLAP_TOKENS:
            bound = min(bound, (overlap_max - 0.001) * m - 1e-6)
        return max(1, math.ceil(bound))

    freq = Counter(t for ts in toks for t in ts)
    index: dict[str, list[int]] = {}
    for j, ts in enumerate(toks):
        if ts:
            rare = sorted(ts, key=lambda t: (freq[t], t))
            for t in rare[:max(0, len(ts) - needed(len(ts)) + 1)]:
                index.setdefault(t, []).append(j)
    for i, a in enumerate(toks):
        near: set[int] = set()
        for t in a:
            near.update(index.get(t, ()))
        near.discard(i)
        la = len(a)
        for j in near:
            b = toks[j]
            lb = len(b)
            inter = len(a & b)
            if rnd(inter / (la + lb - inter), 3) >= sim_max:
                return True
            if (la >= _MIN_OVERLAP_TOKENS and lb >= _MIN_OVERLAP_TOKENS
                    and rnd(inter / min(la, lb), 3) >= overlap_max):
                return True
    return False


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
    at least three tokens), two constructs with the ``same label`` and two of
    which one has no measure that the other does not list (``shared
    measurement``). Labels and measures are compared after folding case,
    accents and whitespace. ``flag`` is ``ok``,
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
