"""Opt-in embedding-based construct-redundancy screen.

Results depend on a user-supplied embedding function whose outputs are not deterministic
across model versions or SDKs. This screen is the assistive counterpart to the
deterministic lexical screen of ``redundancy_check()``.
"""
from __future__ import annotations

import math
from collections.abc import Callable, Sequence

from . import _resources
from ._access import field, items, text
from ._compat import theory_keyword
from ._num import number, rnd


def _cosine(a: Sequence[float], b: Sequence[float]) -> float:
    # The caller enforces equal lengths and nonzero norms; strict guards the
    # first rather than letting a mismatch silently truncate the sum.
    num = sum(x * y for x, y in zip(a, b, strict=True))
    da = math.sqrt(sum(x * x for x in a))
    db = math.sqrt(sum(y * y for y in b))
    return num / (da * db)


def _usable(v) -> bool:
    """Whether an embedding vector holds only finite numbers and has a nonzero norm.

    An empty vector passes here and is refused with its pair's lengths.
    """
    xs = [number(x) for x in v]
    if any(x is None or not math.isfinite(x) for x in xs):
        return False
    return not xs or any(x != 0 for x in xs)


@theory_keyword
def embedding_redundancy(theory, embedder: Callable[[str], Sequence[float]],
                         threshold: float | None = None) -> list[dict]:
    """Pairwise cosine similarity of embedded construct definitions.

    ``embedder`` is called once per construct, in the order of the theory's constructs, with
    its definition string, and must return a numeric vector. The vectors of every compared
    pair must be of equal, nonzero length, or a ValueError names the pair. Returns one record
    per unordered construct pair, ``{a, b, cosine, flag}``, sorted by descending ``cosine``
    then (a, b). ``cosine`` is rounded to 6 decimals, and ``flag`` is ``review`` when it
    reaches ``threshold`` and ``ok`` otherwise.

    ``threshold`` defaults to the checklist's ``embedding_similarity_max`` (0.85). How high
    a cosine two unrelated definitions reach depends on the embedding model, so a
    threshold suited to one model may flag everything or nothing under another, and
    the value is best set for the model in use.

    Raises:
        ValueError: when ``threshold`` is not one number from -1 to 1, when a
            vector holds a value that is not a finite number or is all zeros,
            which has no direction to compare, naming the first such construct,
            and when the vectors of a pair differ in length or are empty.
    """
    theory = theory.data if hasattr(theory, "data") else theory
    if threshold is None:
        threshold = _resources.checklist()["thresholds"]["embedding_similarity_max"]
    x = number(threshold)
    if x is None or not -1 <= x <= 1:
        raise ValueError("embedding_redundancy requires a threshold from -1 to 1")
    cons = items(theory, "constructs")
    vecs = [(text(field(c, "id")), list(embedder(text(field(c, "definition"))))) for c in cons]
    for cid, v in vecs:
        if not _usable(v):
            raise ValueError("embedding_redundancy requires finite, nonzero embedding vectors; "
                             f"the vector of construct {cid} is not")
    rows: list[dict] = []
    for i in range(len(vecs)):
        for j in range(i + 1, len(vecs)):
            # Unequal or empty vectors have no defensible cosine: R's
            # sum(a * b) would recycle the shorter vector and a plain zip()
            # truncate the longer, so the same embedder could give two
            # confident, different similarities. Refuse instead of picking a
            # reading.
            la, lb = len(vecs[i][1]), len(vecs[j][1])
            if la == 0 or lb == 0 or la != lb:
                raise ValueError(
                    "embedding_redundancy requires equal-length nonempty embedding vectors; "
                    f"constructs {vecs[i][0] or ''} and {vecs[j][0] or ''} "
                    f"have lengths {la} and {lb}"
                )
            sim = rnd(_cosine(vecs[i][1], vecs[j][1]), 6)
            rows.append({
                "a": vecs[i][0], "b": vecs[j][0],
                "cosine": sim, "flag": "review" if sim >= threshold else "ok",
            })
    rows.sort(key=lambda r: (-r["cosine"], r["a"], r["b"]))
    return rows
