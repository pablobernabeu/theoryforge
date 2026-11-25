"""Bibliometric literature layer.

The analysis (the literature map, the landscape and their diagrams) is deterministic for
a given corpus. Only the OpenAlex fetch, ``fetch_corpus()``, depends on a live network
service.
"""
from __future__ import annotations

import http.client
import io
import itertools
import json
import math
import os
import urllib.error
import warnings
from datetime import datetime, timezone
from urllib.parse import urlencode

from ._access import field, items, ne_str, str_list, text
from ._load import load_document
from ._num import rnd
from ._text import find_doi, normalise_doi, quoted
from .redundancy import tokens

DEFAULT_MIN_LINK = 2
DEFAULT_MAX_TOKEN_SHARE = 0.5

# Words that name a kind of account and say nothing about what it is about, so
# that "model" in a rival's label cannot match a theme on model fit
# (API_SPEC.md section 15).
THEORY_WORDS = frozenset({
    "theory", "theories", "model", "models", "account", "accounts",
    "hypothesis", "hypotheses", "framework", "frameworks", "approach", "approaches",
})


def _esc(s) -> str:
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


def read_corpus(path) -> dict:
    """Read a literature corpus from YAML or JSON (JSON when the suffix is ``.json``).

    The file is read by the rules that ``read`` follows, so an unquoted keyword such
    as ``y`` or ``n`` stays a string, a repeated key is refused and so is a YAML document that its
    aliases expand past 1000000 values. A document that is not a mapping raises
    ``ValueError("Corpus data must be a mapping")``. The records themselves are checked
    by ``litmap()`` and ``landscape()``.
    """
    data = load_document(path)
    if not isinstance(data, dict):
        raise ValueError("Corpus data must be a mapping")
    return data


def _positive_int(value, name: str) -> int:
    """``value`` as an int when it is one integral number of at least 1.

    An int or an integral float passes, never a bool, so that the R twin, which
    holds 2 and 2.0 alike, takes the same arguments (API_SPEC.md section 14).
    """
    ok = (
        not isinstance(value, bool)
        and isinstance(value, (int, float))
        and math.isfinite(value)
        and value == int(value)
        and value >= 1
    )
    if not ok:
        raise ValueError(f"{name} must be a positive integer")
    return int(value)


def _share(value, name: str) -> float:
    """``value`` as a float when it is one number from 0 to 1, never a bool.

    NaN fails both comparisons and an infinity the upper one, so neither passes
    (API_SPEC.md section 15).
    """
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not 0 <= value <= 1:
        raise ValueError(f"{name} must be a number between 0 and 1")
    return float(value)


# R holds a number read from a file as a double, which is exact for integers
# below 2^53 in absolute value. Not every larger one can be written back as the
# same decimal string in both twins, so all are refused (API_SPEC.md section 14).
_EXACT_LIMIT = 2 ** 53

_NOT_STRINGS = ("invalid corpus: record[{i}] {field} must be strings "
                "(an unquoted no, yes, on or off is read as a boolean; quote it)")


def _entry(value, i: int, field: str, k: int) -> str | None:
    """One keyword or reference as a string, or None when it is dropped.

    A string is kept as it is and an empty one dropped, as null is. An
    integer-valued number becomes its decimal string. Anything else (a boolean,
    a fractional or non-finite number, a list or a mapping) is refused.
    """
    if value is None:
        return None
    if isinstance(value, str):
        return value or None
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if isinstance(value, float) and not (math.isfinite(value) and value.is_integer()):
            raise ValueError(_NOT_STRINGS.format(i=i, field=field))
        if abs(value) >= _EXACT_LIMIT:
            raise ValueError(f"invalid corpus: record[{i}] {field} entry {k} is a number "
                             "too large to be an exact identifier; quote it")
        return str(int(value))
    raise ValueError(_NOT_STRINGS.format(i=i, field=field))


def _values(record: dict, i: int, field: str) -> list[str]:
    """The keywords or references of record ``i`` as strings, in file order.

    A sequence gives its entries, null or an absent field gives none, and any
    other value is a one-entry list (``keywords: arousal``). A mapping is refused.
    """
    v = record.get(field)
    if v is None:
        return []
    if isinstance(v, dict):
        raise ValueError(_NOT_STRINGS.format(i=i, field=field))
    entries = v if isinstance(v, list) else [v]
    out = []
    for k, x in enumerate(entries):
        s = _entry(x, i, field, k)
        if s is not None:
            out.append(s)
    return out


def _records(corpus) -> list[tuple[list[str], list[str]]]:
    """Each record's (keywords, references), every entry checked (API_SPEC.md section 14).

    The corpus must hold a ``records`` sequence, empty or not, of mappings.
    """
    corpus = corpus.data if hasattr(corpus, "data") else corpus
    recs = corpus.get("records") if isinstance(corpus, dict) else None
    if not isinstance(recs, list):
        raise ValueError("invalid corpus: missing records list")
    out = []
    for i, r in enumerate(recs):
        if not isinstance(r, dict):
            raise ValueError(f"invalid corpus: record[{i}] is not a mapping")
        out.append((_values(r, i, "keywords"), _values(r, i, "references")))
    return out


def _reference_key(ref: str) -> str:
    """The node a reference counts as in the co-citation map (API_SPEC.md section 14).

    A reference that holds a DOI is keyed by the DOI as ``normalise_doi`` gives
    it, so that ``10.1016/J.BRAT...``, ``doi:10.1016/j.brat...`` and
    ``https://doi.org/10.1016/j.brat...`` are one work: DOI names are
    case-insensitive under ASCII case folding (DOI Handbook, 'Case Insensitivity
    of the DOI Name', https://www.doi.org/doi-handbook/DOIHandbook_2025.pdf).
    Any other reference, a Scopus or OpenAlex identifier or a fixture key, is
    kept exactly as written.
    """
    found = find_doi(ref)
    return ref if found is None else found


def _pair_counts(values: list[list[str]]) -> dict:
    """Count every unordered pair (a < b) of each record's sorted unique values."""
    counts: dict[tuple, int] = {}
    for vals in values:
        for a, b in itertools.combinations(sorted(set(vals)), 2):
            counts[(a, b)] = counts.get((a, b), 0) + 1
    return counts


def _edges(counts: dict, min_link: int) -> list[dict]:
    return [
        {"a": a, "b": b, "count": c}
        for (a, b), c in sorted(counts.items())
        if c >= min_link
    ]


def _components(edges: list[dict]) -> list[dict]:
    """Connected components (deterministic) over the keyword co-occurrence edges."""
    parent: dict[str, str] = {}

    def find(x: str) -> str:
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x: str, y: str) -> None:
        parent[find(x)] = find(y)

    for e in edges:
        union(e["a"], e["b"])

    groups: dict[str, list[str]] = {}
    for node in parent:
        groups.setdefault(find(node), []).append(node)

    comps = [sorted(members) for members in groups.values()]
    comps.sort(key=lambda kws: kws[0])  # order by smallest keyword
    return [
        {"id": f"theme_{i}", "keywords": kws, "size": len(kws)}
        for i, kws in enumerate(comps, start=1)
    ]


METHODS = ("components", "simple_centres")


def _method(value) -> str:
    if not isinstance(value, str) or value not in METHODS:
        raise ValueError("litmap requires method to be 'components' or 'simple_centres'")
    return value


def _settings(min_link, method, min_cocitation, min_theme_size, max_theme_size, max_df,
              min_df) -> dict:
    """litmap's arguments checked in signature order (API_SPEC.md section 14).

    The theme sizes, ``max_df`` and ``min_df`` are checked whichever method is
    asked for, although only simple centres reads them.
    """
    min_link = _positive_int(min_link, "min_link")
    method = _method(method)
    min_cocitation = (min_link if min_cocitation is None
                      else _positive_int(min_cocitation, "min_cocitation"))
    min_theme_size = _positive_int(min_theme_size, "min_theme_size")
    ok = (not isinstance(max_theme_size, bool) and isinstance(max_theme_size, (int, float))
          and math.isfinite(max_theme_size) and max_theme_size == int(max_theme_size)
          and max_theme_size >= 2)
    if not ok:
        raise ValueError("max_theme_size must be an integer of at least 2")
    max_theme_size = int(max_theme_size)
    if min_theme_size > max_theme_size:
        raise ValueError("min_theme_size must not exceed max_theme_size")
    max_df = _share(max_df, "max_df")
    min_df = _positive_int(min_df, "min_df")
    return {"method": method, "min_link": min_link, "min_cocitation": min_cocitation,
            "min_theme_size": min_theme_size, "max_theme_size": max_theme_size, "max_df": max_df,
            "min_df": min_df}


# The settings a simple-centres record gives in ``parameters``, in this order.
_PARAMETERS = ("min_link", "min_cocitation", "min_theme_size", "max_theme_size", "max_df", "min_df")


def _quadrants(themes: list[dict]) -> None:
    """Place each theme in the strategic diagram of Cobo et al. (2011).

    Both axes are split at their median, the mean of the middle two values for
    an even count, and a value is high when it lies above the median, or at it
    when the median is the highest value of the axis. A theme with centrality
    0 is therefore low. When every theme has the same value on an axis, a lone
    theme included, the axis cannot be split and every quadrant is None.
    """
    def median(values: list[float]) -> float:
        v = sorted(values)
        mid = len(v) // 2
        return v[mid] if len(v) % 2 else (v[mid - 1] + v[mid]) / 2

    if not themes:
        return
    cs = [t["centrality"] for t in themes]
    ds = [t["density"] for t in themes]
    if min(cs) == max(cs) or min(ds) == max(ds):
        for t in themes:
            t["quadrant"] = None
        return
    def high(v: float, values: list[float]) -> bool:
        m = median(values)
        return v > m or (v == m and m == max(values))

    for t in themes:
        high_c, high_d = high(t["centrality"], cs), high(t["density"], ds)
        t["quadrant"] = ("motor" if high_d else "basic") if high_c else (
            "niche" if high_d else "emerging_or_declining")


def _simple_centres(keyword_lists: list[list[str]], s: dict) -> tuple[list[str], list[dict], list[dict]]:
    """Co-word themes by simple centres (Coulter et al., 1998; Cobo et al., 2011).

    Returns the field terms, the keyword edges over the other keywords and the
    themes, each with its centrality, density and quadrant. Every rule,
    tie-break and summation order is pinned in API_SPEC.md section 14, so that
    the R twin computes the same floats.
    """
    sets = [sorted(set(kws)) for kws in keyword_lists]
    n = len(sets)
    df: dict[str, int] = {}
    for kws in sets:
        for k in kws:
            df[k] = df.get(k, 0) + 1
    field_terms = sorted(k for k, v in df.items() if v / n > s["max_df"])
    # The field terms and the keywords of fewer than min_df records are left out.
    left_out = set(field_terms) | {k for k, v in df.items() if v < s["min_df"]}
    counts = _pair_counts([[k for k in kws if k not in left_out] for kws in sets])
    kw_edges = _edges(counts, s["min_link"])

    # The equivalence index from the integer counts, in one division.
    links = [(e["a"], e["b"], (e["count"] * e["count"]) / (df[e["a"]] * df[e["b"]]))
             for e in kw_edges]
    adj: dict[str, dict[str, float]] = {}
    for a, b, e in links:
        adj.setdefault(a, {})[b] = e
        adj.setdefault(b, {})[a] = e

    # Pass 1: the strongest link whose ends are both free seeds a theme, which
    # takes the free neighbour of a member with the strongest link, the smaller
    # keyword on a tie, until it reaches max_theme_size or has no free
    # neighbour.
    assigned: set[str] = set()
    groups = []
    for a, b, _ in sorted(links, key=lambda x: (-x[2], x[0], x[1])):
        if a in assigned or b in assigned:
            continue
        members = {a, b}
        while len(members) < s["max_theme_size"]:
            best = None
            for m in members:
                for h, e in adj[m].items():
                    if h not in members and h not in assigned and (best is None or (-e, h) < best):
                        best = (-e, h)
            if best is None:
                break
            members.add(best[1])
        assigned |= members
        if len(members) >= s["min_theme_size"]:
            groups.append(sorted(members))
    groups.sort(key=lambda kws: kws[0])

    # Pass 2: centrality sums the links from the theme to the keywords of other
    # themes, density the links inside it, each added one at a time over the
    # sorted keywords. A link to a keyword in no theme counts for neither,
    # since Cobo et al. (2011) define centrality over the links to other themes.
    theme_of = {k: i for i, kws in enumerate(groups, start=1) for k in kws}
    themes = []
    for i, kws in enumerate(groups, start=1):
        external = internal = 0.0
        for j, m in enumerate(kws):
            for h in sorted(adj[m]):
                if theme_of.get(h, i) != i:
                    external += adj[m][h]
            for h in kws[j + 1:]:
                if h in adj[m]:
                    internal += adj[m][h]
        themes.append({"id": f"theme_{i}", "keywords": kws, "size": len(kws),
                       "centrality": rnd(10 * external, 6),
                       "density": rnd(100 * internal / len(kws), 6)})
    _quadrants(themes)
    return field_terms, kw_edges, themes


def _litmap(corpus, s: dict, co_citation: bool = True, records: list | None = None) -> dict:
    """litmap with its settings checked, the co-citation count skipped when ``co_citation`` is False.

    ``landscape`` reads only the themes, and on a corpus with references the
    co-citation count is most of the work. It also passes the ``records`` it
    has already checked, since it reads their keywords as well.
    """
    if records is None:
        records = _records(corpus)
    keywords = [kw for kw, _ in records]
    if s["method"] == "simple_centres":
        field_terms, kw_edges, themes = _simple_centres(keywords, s)
    else:
        kw_edges = _edges(_pair_counts(keywords), s["min_link"])
        themes = _components(kw_edges)
    out = {
        "n_records": len(records),
        "keywords": sorted({k for kws in keywords for k in kws}),
        "keyword_cooccurrence": kw_edges,
        "themes": themes,
    }
    if co_citation:
        keyed = [[_reference_key(r) for r in refs] for _, refs in records]
        out["co_citation"] = _edges(_pair_counts(keyed), s["min_cocitation"])
    if s["method"] == "simple_centres":
        out["method"] = s["method"]
        out["parameters"] = {k: s[k] for k in _PARAMETERS}
        out["field_terms"] = field_terms
    return out


# litmap warns of a giant theme only in a map of at least this many linked
# keywords, since a smaller map, such as a single pair, can be one theme
# legitimately.
_GIANT_MIN_KEYWORDS = 10


def _warn_if_one_theme_dominates(themes: list[dict]) -> None:
    """Warn when the largest theme holds more than half of ten or more linked keywords.

    Connected components merge every theme that shares a keyword, so the hub
    keywords of a real corpus join it into one theme (API_SPEC.md section 14).
    """
    if not themes:
        return
    n = sum(t["size"] for t in themes)
    largest = max(t["size"] for t in themes)
    if n < _GIANT_MIN_KEYWORDS or 2 * largest <= n:
        return
    p = rnd(100 * (largest / n), 1)
    # stacklevel 3 names the caller of litmap or landscape.
    warnings.warn(
        f"litmap: one theme holds {p:.1f} per cent of the {n} linked keywords; connected "
        "components cannot separate themes in a corpus this connected, so the themes and "
        "any landscape built on them are not informative (method 'simple_centres' gives "
        "bounded themes)",
        UserWarning, stacklevel=3)


def litmap(corpus, min_link: int = DEFAULT_MIN_LINK, method: str = "components",
           min_cocitation: int | None = None, min_theme_size: int = 2,
           max_theme_size: int = 10, max_df: float = 1.0, min_df: int = 1) -> dict:
    """Keyword co-occurrence, themes and co-citation, all deterministic.

    ``min_link``, 2 by default, is the smallest count a keyword pair needs to be
    an edge, and ``min_cocitation`` the same for a reference pair (``min_link``
    when None). Co-citation maps of real corpora are large: 200 OpenAlex records
    give about 11,000 reference pairs at a threshold of 2, so a higher
    ``min_cocitation`` is often wanted. Both must be positive integers. The
    corpus is checked before anything is counted: integer entries become
    decimal strings, and booleans, fractions and nested values are refused.

    A reference that holds a DOI is keyed by the DOI, lower-cased and without
    its resolver prefix, as ``new_evidence_dois`` compares DOIs. One work cited
    as ``10.1016/J.BRAT.2015.10.002`` in one record and as
    ``https://doi.org/10.1016/j.brat.2015.10.002`` in another is therefore one
    node, labelled ``10.1016/j.brat.2015.10.002``. Any other reference, such as
    a Scopus or OpenAlex identifier, is compared exactly as written, and so is
    every keyword.

    ``method`` chooses how keywords are grouped into themes. With
    ``"components"``, the default, a theme is a connected component of the
    keyword map, and on a real corpus one or a few keywords shared by most
    records join nearly every keyword into one. When the map links at least ten
    keywords and the largest theme holds more than half of them, a UserWarning
    says so: such themes, and any landscape built on them, do not describe the
    field. The result is returned unchanged.

    ``"simple_centres"`` is the co-word clustering of Coulter et al. (1998) and
    Cobo et al. (2011). Each link is weighted by the equivalence index
    ``c * c / (df_a * df_b)``, where ``c`` counts the records holding both
    keywords and ``df`` the records holding each. The strongest link between
    two unassigned keywords seeds a theme, which takes its strongest unassigned
    neighbour until it holds ``max_theme_size`` keywords, ties going to the
    keyword first in code-point order. A keyword whose links all reach
    keywords already in themes joins none. Themes smaller than
    ``min_theme_size`` are dropped. Keywords in more than ``max_df`` of the
    records are field terms, left out of the map and reported as
    ``field_terms``. Keywords in fewer than ``min_df`` records are left out of
    the map too, so that a rare keyword cannot seed a theme. The default of 1
    leaves out none. Each theme gains its centrality (ten times the summed
    index of its links to the keywords of other themes) and its density (100
    times the summed index of its internal links, over its size), the measures
    of Callon et al. (1991) as Cobo et al. (2011) scale them. It also gains its
    quadrant in the strategic diagram, split here at the median of each
    measure, a value counting as high when it lies above the median, or at it
    when the median is the measure's highest value:
    ``motor`` (both high), ``basic`` (central but not dense), ``niche`` (dense
    but not central) or ``emerging_or_declining`` (both low). A theme with
    centrality 0 is therefore never central. When all themes share one value
    of either measure, as a lone theme does, that measure cannot be split and
    the quadrant is None. The record gains ``method``, ``parameters`` (the six
    settings used) and ``field_terms``. Components remain the default for this
    release.

    ``min_theme_size`` must be a positive integer, ``max_theme_size`` an
    integer of at least 2 no smaller than it, ``max_df`` a number from 0 to 1
    and ``min_df`` a positive integer. They are checked with either method,
    although only simple centres reads them.

    Returns:
        A dict with ``n_records``, ``keywords`` (every keyword, sorted),
            ``keyword_cooccurrence`` (edges ``{a, b, count}`` sorted by ``(a, b)``),
            ``themes`` (each ``{id, keywords, size}``, ordered by its smallest
            keyword) and ``co_citation`` (edges as for keywords), followed by the
            keys that ``"simple_centres"`` adds, as described above.

    References: Callon, Courtial and Laville (1991), Scientometrics 22,
    155-205, https://doi.org/10.1007/BF02019280. Coulter, Monarch and Konda
    (1998), Journal of the American Society for Information Science 49,
    1206-1223,
    https://doi.org/10.1002/(SICI)1097-4571(1998)49:13%3C1206::AID-ASI7%3E3.0.CO;2-F.
    Cobo, López-Herrera, Herrera-Viedma and Herrera (2011), Journal of
    Informetrics 5, 146-166, https://doi.org/10.1016/j.joi.2010.10.002.
    """
    s = _settings(min_link, method, min_cocitation, min_theme_size, max_theme_size, max_df,
                  min_df)
    out = _litmap(corpus, s)
    if s["method"] == "components":
        _warn_if_one_theme_dominates(out["themes"])
    return out


def _field_tokens(keyword_lists: list[list[str]], max_token_share: float) -> set[str]:
    """Tokens of more than ``max_token_share`` of the records' keywords.

    A record counts once for each token of its keywords, and the share is taken
    over every record, those without keywords included.
    """
    n = len(keyword_lists)
    counts: dict[str, int] = {}
    for kws in keyword_lists:
        for t in tokens(" ".join(kws)):
            counts[t] = counts.get(t, 0) + 1
    return {t for t, c in counts.items() if c / n > max_token_share}


def landscape(theory, corpus, min_link: int = DEFAULT_MIN_LINK,
              max_token_share: float = DEFAULT_MAX_TOKEN_SHARE,
              method: str = "components") -> dict:
    """Match the words of a theory and its registered alternatives against a corpus's themes.

    A theme is matched by the words its keywords share with the focal theory's
    construct labels, or with an alternative's label and key constructs, and
    every match reports those words (``focal_terms`` and ``alternative_terms``).
    Three kinds of word never match. Field tokens, the words most of the corpus
    shares, are those in the keywords of more than ``max_token_share`` of the
    records. Phenomenon tokens are the words of the theory's title, which names
    the phenomenon that the focal theory and its rivals all explain. A
    construct word that also appears in the title does not match either. The
    third kind is the words that name a kind of account, held in
    ``theoryforge.lit.THEORY_WORDS``: theory, model, account, hypothesis,
    framework and approach, with their plurals. One shared word is enough for
    a match.

    The match is lexical. It shows that an account and a theme have a word in
    common, and does not show that the account explains what the theme's
    records report, nor that a theme without a match is unexplained.

    A theme is ``under_theorised`` when none of the registered accounts (the
    focal theory and its registered alternatives) matches it, ``covered`` when
    one does and ``crowded`` when two or more do. An alternative id that is
    repeated counts once. The statuses count matching accounts only. An account
    the theory does not register, or one that names the same idea in other
    words, may address an under-theorised theme. A crowded theme may call for
    predictions that discriminate between its accounts, and is not a finding
    that they compete or are redundant. ``under_theorised_fronts`` lists the
    ids of the under-theorised themes, and ``redundancy_risk``, despite its
    name, the ids of the crowded ones.

    ``min_link`` (2 by default) must be a positive integer, ``max_token_share``
    (0.5 by default) a number from 0 to 1 and ``method`` one of litmap's,
    checked in that order and before the corpus. The
    themes are litmap's, built by ``method`` with litmap's other defaults. With
    ``"components"``, the same warning is given when one theme holds most of the
    linked keywords. With ``"simple_centres"``, the record gains ``method``
    after ``theory_id`` and each theme its ``centrality``, ``density`` and
    ``quadrant``.

    Returns:
        A dict with ``theory_id``, ``max_token_share`` (the value used),
            ``field_tokens``, ``phenomenon_tokens``, ``themes``,
            ``under_theorised_fronts`` and ``redundancy_risk``. Each theme holds
            ``id``, ``keywords``, ``alternatives`` (the ids of the alternatives that
            match it), ``focal``, ``status``, ``focal_terms`` and
            ``alternative_terms``, the last a list of ``{id, terms}`` in the order
            of ``alternatives``.
    """
    T = theory.data if hasattr(theory, "data") else theory
    min_link = _positive_int(min_link, "min_link")
    max_token_share = _share(max_token_share, "max_token_share")
    s = _settings(min_link, method, None, 2, 10, 1.0, 1)
    records = _records(corpus)
    lm = _litmap(corpus, s, co_citation=False, records=records)
    if s["method"] == "components":
        _warn_if_one_theme_dominates(lm["themes"])

    field_tokens = _field_tokens([kw for kw, _ in records], max_token_share)
    phenomenon_tokens = tokens(text(T.get("title")))
    excluded = phenomenon_tokens | THEORY_WORDS
    focal_tokens = tokens(" ".join(text(field(c, "label")) for c in items(T, "constructs"))) - excluded
    # Sorted by id once, stably, so a repeated id keeps its file order.
    alts = sorted(
        ((text(field(a, "id")),
          tokens(" ".join([text(field(a, "label"))] + str_list(field(a, "key_constructs")))) - excluded)
         for a in items(T, "alternatives")),
        key=lambda alt: alt[0],
    )

    themes_out = []
    under, crowded = [], []
    for th in lm["themes"]:
        th_tokens = tokens(" ".join(th["keywords"])) - field_tokens - THEORY_WORDS
        focal_terms = sorted(focal_tokens & th_tokens)
        alt_terms = [{"id": aid, "terms": sorted(a_tokens & th_tokens)}
                     for aid, a_tokens in alts if a_tokens & th_tokens]
        on = [a["id"] for a in alt_terms]
        focal_on = bool(focal_terms)
        # A repeated alternative id is one account, so it counts once.
        n = len(set(on)) + (1 if focal_on else 0)
        status = "under_theorised" if n == 0 else ("crowded" if n >= 2 else "covered")
        theme = {
            "id": th["id"], "keywords": th["keywords"],
            "alternatives": on, "focal": focal_on, "status": status,
            "focal_terms": focal_terms, "alternative_terms": alt_terms,
        }
        if s["method"] == "simple_centres":
            theme.update({k: th[k] for k in ("centrality", "density", "quadrant")})
        themes_out.append(theme)
        if status == "under_theorised":
            under.append(th["id"])
        elif status == "crowded":
            crowded.append(th["id"])

    head = {"theory_id": text(T.get("id"))}
    if s["method"] == "simple_centres":
        head["method"] = s["method"]
    return {
        **head,
        "max_token_share": max_token_share,
        "field_tokens": sorted(field_tokens),
        "phenomenon_tokens": sorted(phenomenon_tokens),
        "themes": themes_out,
        "under_theorised_fronts": under,
        "redundancy_risk": crowded,
    }


def _undirected(name: str, edges: list[dict]) -> str:
    from .diagram import _fill, _prelude
    nodes = sorted({n for e in edges for n in (e["a"], e["b"])})
    role = "construct" if name == "keyword_cooccurrence" else "prediction"
    lines = _prelude(name, "LR", directed=False)
    lines.append(f'  node [shape=ellipse, style="filled", {_fill(role)}];')
    for n in nodes:
        lines.append(f'  "{_esc(n)}";')
    for e in edges:
        lines.append(f'  "{_esc(e["a"])}" -- "{_esc(e["b"])}" [label="{e["count"]}"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


# Theme colours track the landscape statuses: a theme that no registered
# account matches is teal, one that two or more match is amber and a covered
# one grey.
_THEME_ROLE = {"under_theorised": "construct", "crowded": "proposition", "covered": "covered"}


def _theme_landscape(ls: dict) -> str:
    from .diagram import _INK, _fill, _prelude, _wrap
    lines = _prelude("theme_landscape", "LR")
    for th in ls["themes"]:
        label = f'{_esc(th["id"])}\\n{_wrap(", ".join(th["keywords"]), 24)}\\n({th["status"]})'
        lines.append(f'  "{_esc(th["id"])}" [label="{label}", {_fill(_THEME_ROLE[th["status"]])}];')
    # collect alternatives in first-seen order across themes
    alt_ids: list[str] = []
    for th in ls["themes"]:
        for a in th["alternatives"]:
            if a not in alt_ids:
                alt_ids.append(a)
    for a in alt_ids:
        lines.append(f'  "{_esc(a)}" [label="{_wrap(a)}", shape=ellipse, {_fill("rival")}];')
    lines.append(f'  "focal" [label="focal", shape=ellipse, fillcolor="{_INK}", '
                 f'color="{_INK}", fontcolor="#FFFFFF"];')
    for a in alt_ids:
        for th in ls["themes"]:
            if a in th["alternatives"]:
                lines.append(f'  "{_esc(a)}" -> "{_esc(th["id"])}";')
    for th in ls["themes"]:
        if th["focal"]:
            lines.append(f'  "focal" -> "{_esc(th["id"])}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _strongest(edges: list[dict], max_edges: int) -> list[dict]:
    """The ``max_edges`` edges with the highest counts, ties to the earlier (a, b), in (a, b) order."""
    kept = sorted(edges, key=lambda e: (-e["count"], e["a"], e["b"]))[:max_edges]
    return sorted(kept, key=lambda e: (e["a"], e["b"]))


def lit_diagram(obj: dict, type: str = "keyword_cooccurrence", max_edges: int | None = None) -> str:
    """DOT for the literature layer.

    ``obj`` is a ``litmap()`` result for ``"keyword_cooccurrence"`` (the
    default) or ``"co_citation"``, and a ``landscape()`` result for
    ``"theme_landscape"``. A record without the edge list asked for gives a
    graph with no nodes. ``max_edges`` caps a keyword_cooccurrence or
    co_citation diagram at that many edges, the highest counts first and ties
    broken by (a, b). Only their endpoints are drawn. None draws every edge,
    and theme_landscape ignores it.

    Returns:
        A single DOT string ending in a newline: an undirected graph for the
            two network views and a digraph for the theme landscape.

    Raises:
        ValueError: for an unknown ``type``, and when ``max_edges`` is not a
            positive integer.
    """
    if max_edges is not None:
        max_edges = _positive_int(max_edges, "max_edges")
    if type in ("keyword_cooccurrence", "co_citation"):
        edges = obj.get(type, [])
        if max_edges is not None and len(edges) > max_edges:
            edges = _strongest(edges, max_edges)
        return _undirected(type, edges)
    if type == "theme_landscape":
        return _theme_landscape(obj)
    raise ValueError(
        f"unknown lit diagram type {quoted(type)}; expected one of "
        "keyword_cooccurrence, co_citation, theme_landscape"
    )


def new_evidence_dois(theory, candidate_dois: list) -> list:
    """DOIs in ``candidate_dois`` not already cited by the theory's evidence or alternatives.

    Compares by normalised form, so a fresh literature search, for example via OpenAlex,
    Scopus or any other source, can be checked against what the theory already engages
    with. The normalised form is the DOI itself, trimmed, lower-cased (ASCII letters
    only) and percent-decoded, wherever it sits in the text, so ``doi: 10...``,
    ``DOI 10...``, ``doi.org/10...``, ``https://www.doi.org/10...`` and a URL with
    ``%2F`` all match the bare DOI, and trailing full stops, commas and semicolons are
    dropped. A double slash after the prefix, as in ``10.1037//0033-2909.99.1.20``, is
    made single, since doi.org redirects such a DOI to the one with a single slash. A
    candidate that is not a string, or holds only whitespace, is skipped: None, the
    float NaN that pandas gives a missing value, an empty string and a number among
    them. A single string is one candidate. Returns the qualifying DOIs in their
    original form, deduplicated and sorted by normalised form. The function is
    deterministic and makes no network call. The search itself is left to whichever
    literature tool the caller prefers.
    """
    T = theory.data if hasattr(theory, "data") else theory
    known = set()
    for key in ("evidence", "alternatives"):
        for entry in items(T, key):
            doi = text(field(entry, "source_doi"))
            if doi:
                known.add(normalise_doi(doi))

    # A single string is one candidate, as in R, where iterating over it would
    # give its characters. None is tested for directly, so that a pandas Series,
    # which has no truth value, is read too.
    if isinstance(candidate_dois, str):
        candidate_dois = [candidate_dois]
    seen, out = set(), []
    for doi in [] if candidate_dois is None else candidate_dois:
        if not ne_str(doi):
            continue
        norm = normalise_doi(doi)
        if norm in known or norm in seen:
            continue
        seen.add(norm)
        out.append(doi)
    return sorted(out, key=normalise_doi)


_OPENALEX_WORKS = "https://api.openalex.org/works"

# Seconds an outbound request may go without progress before it is abandoned:
# urlopen applies it to the connection and to each read, as the R twin's curl
# callback does to the transfer. Without one, a stalled service hangs an
# interactive session indefinitely.
_NET_TIMEOUT = 30

_KEY_MESSAGE = "api_key must be a string of visible ASCII characters"


class OpenAlexHTTPError(urllib.error.HTTPError):
    """OpenAlex refused a request.

    A subclass of ``urllib.error.HTTPError``, so a handler written for the error
    that ``urlopen`` raises still catches it, with the same ``code``, headers and
    readable body. Its ``str()`` is ``OpenAlex request failed with HTTP <code>``,
    followed by ``: <message>`` when the body is a JSON object that carries one.
    """

    def __init__(self, url: str, code: int, message: str, hdrs, body: bytes):
        super().__init__(url, code, message, hdrs, io.BytesIO(body))

    def __str__(self) -> str:
        return self.msg

    def __repr__(self) -> str:
        return f"<{type(self).__name__} {self.code}: {self.msg!r}>"


def _urlopen(request, timeout):
    """Send ``request`` with ``urllib.request.urlopen``.

    fetch_corpus sends every request through this function, which the tests
    replace with a stand-in (R: ``.tf_http``).
    """
    from urllib.request import urlopen

    return urlopen(request, timeout=timeout)  # noqa: S310 (documented external call)


def _api_key(value) -> str:
    """The key to send, or "" for none (R: ``.tf_api_key``).

    The key travels in a header, so spaces, tabs and line breaks around it (a
    key pasted into an environment file, say) are trimmed. Any other character
    outside visible ASCII is refused before a request is made, because it would
    break the header and urllib's error about the header prints the key.
    """
    if not isinstance(value, str):
        raise ValueError(_KEY_MESSAGE)
    key = value.strip(" \t\r\n")
    if any(not "!" <= ch <= "~" for ch in key):
        raise ValueError(_KEY_MESSAGE)
    return key


def _json_message(body: bytes) -> str:
    """The ``message`` field of a JSON object, else its ``error`` field, else ""."""
    try:
        data = json.loads(body)
    except ValueError:
        return ""
    if isinstance(data, dict):
        for name in ("message", "error"):
            if ne_str(data.get(name)):
                return data[name]
    return ""


def _openalex_page(params: dict, headers: dict, key: str) -> dict:
    """One page of OpenAlex works, the parsed response (R: ``.tf_openalex_page``).

    The HTTP status is checked and the results list required. ``params`` are
    the query parameters in the order they are sent.
    """
    from urllib.request import Request

    url = _OPENALEX_WORKS + "?" + urlencode(params)
    request = Request(url)
    # urllib copies a request's ordinary headers into the request a redirect
    # makes, whatever server it points to, so the key could follow a redirect to
    # another host. An unredirected header is sent with this request only. The R
    # twin's libcurl keeps it for the same scheme, host and port alone
    # (API_SPEC.md section 17).
    for name, value in headers.items():
        request.add_unredirected_header(name, value)
    try:
        with _urlopen(request, timeout=_NET_TIMEOUT) as resp:
            body = resp.read()
    except urllib.error.HTTPError as err:
        try:
            body = err.read() if err.fp is not None else b""
        except TimeoutError:
            raise
        except (OSError, http.client.HTTPException) as read_err:
            # The error reply was cut short or its connection reset.
            raise urllib.error.URLError(read_err) from read_err
        # A server that repeats the key in an error must not carry it into the message.
        if key:
            body = body.replace(key.encode("ascii"), b"<api_key>")
        message = f"OpenAlex request failed with HTTP {err.code}"
        detail = _json_message(body)
        if detail:
            message += f": {detail}"
        raise OpenAlexHTTPError(url, err.code, message, err.hdrs, body) from err
    except (urllib.error.URLError, TimeoutError):
        raise
    except (OSError, http.client.HTTPException) as err:
        # A connection reset, or a reply cut short, while the response is read.
        # urllib raises these as they are, and a failure of the connection is
        # reported as a URLError.
        raise urllib.error.URLError(err) from err
    try:
        data = json.loads(body)
    except ValueError:
        data = None
    if not isinstance(data, dict) or not isinstance(data.get("results"), list):
        raise ValueError("OpenAlex response has no results list")
    if not all(isinstance(w, dict) for w in data["results"]):
        raise ValueError("OpenAlex response has a work that is not an object")
    return data


def _meta(page: dict) -> dict:
    meta = page.get("meta")
    return meta if isinstance(meta, dict) else {}


def _whole_number(x) -> int | None:
    """``x`` when it is one whole number, otherwise None (R: ``.tf_whole_number``)."""
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        return None
    if isinstance(x, float) and not (math.isfinite(x) and x.is_integer()):
        return None
    return int(x)


def _later_page(params: dict, headers: dict, key: str, n: int) -> dict:
    """A page after the first, whose failure says how many records came before it.

    The message gains `` (after <n> records were fetched)``. The error keeps its
    class, and an OpenAlexHTTPError keeps its status and body (R:
    ``.tf_later_page``).
    """
    note = f" (after {n} record was fetched)" if n == 1 else f" (after {n} records were fetched)"
    try:
        return _openalex_page(params, headers, key)
    except OpenAlexHTTPError as err:
        raise OpenAlexHTTPError(err.url, err.code, err.msg + note, err.hdrs, err.read()) from err
    except urllib.error.URLError as err:
        raise urllib.error.URLError(f"{err.reason}{note}") from err
    except ValueError as err:
        raise ValueError(f"{err}{note}") from err
    except TimeoutError as err:
        raise TimeoutError(f"{err}{note}") from err


# The fields of a work that _openalex_record maps, the only ones requested.
_SELECT = "id,doi,title,publication_year,keywords,concepts,referenced_works"

# OpenAlex serves the first 10,000 results of a search by page number, without
# a key, and later ones only through a cursor.
_PAGE_NUMBER_LIMIT = 10_000


def _entries(w: dict, key: str) -> list:
    """The entries of a field OpenAlex gives as an array, or none when it is anything else."""
    v = w.get(key)
    return v if isinstance(v, list) else []


def _names(entries: list) -> list:
    """The ``display_name`` of each entry that gives one as nonempty text."""
    names = [e.get("display_name") for e in entries if isinstance(e, dict)]
    return [n for n in names if isinstance(n, str) and n]


def _openalex_record(w: dict) -> dict:
    """One OpenAlex work as a corpus record."""
    # Entries without a name must be dropped before the emptiness test: a
    # keywords list made only of nulls is non-empty as returned, which would
    # suppress the concepts fallback and leave the record with no keywords at
    # all. The R twin filters first for the same reason.
    kws = _names(_entries(w, "keywords"))
    if not kws:
        kws = _names(_entries(w, "concepts")[:5])
    record: dict = {"id": w.get("id"), "doi": w.get("doi")}
    # The corpus schema types a title as a string, so a null one is left out.
    if isinstance(w.get("title"), str):
        record["title"] = w["title"]
    record.update({
        "year": w.get("publication_year"),
        "keywords": kws,
        "references": [r for r in _entries(w, "referenced_works") if isinstance(r, str)],
    })
    return record


def fetch_corpus(query: str, per_page: int = 25, mailto: str | None = None,
                 api_key: str | None = None, max_records: int | None = None) -> dict:
    """Build a corpus from the OpenAlex API (network call).

    It depends on a live external service whose results change over time, so it
    is not part of the package's deterministic core. The result is a corpus,
    ``{schema_version: "1.0", id: "openalex:<query>", source, records}``. Each
    work is mapped to ``{id, doi, title, year, keywords, references}``, with the
    DOI as OpenAlex gives it and the top five concepts standing in for keywords
    when a work has none. A work whose title is null has no ``title``, since the
    corpus schema types a title as a string. Only the fields the record uses are
    requested.

    OpenAlex returns the works that match a search in pages of ``per_page``,
    ranked by relevance, and a search usually matches far more works than one
    page holds. ``per_page`` may be 1 to 200, but OpenAlex supports pages of up
    to 100 and has deprecated larger ones. A ``max_records`` above ``per_page``
    pages on until that many works are collected or the results run out. By
    default, ``max_records`` equals ``per_page``, so one request is made. When
    the pages needed lie within the first 10,000 results, they are requested by
    number, which OpenAlex serves without a key. A larger ``max_records`` pages
    through OpenAlex's cursor instead, and OpenAlex serves a cursor past the
    first page only with an API key: without one, it refuses the second page
    with HTTP 401. Each page is one request and costs USD 0.001. OpenAlex allows
    USD 0.10 a day without a key, about 100 pages, and USD 1 with a free key.

    ``api_key`` defaults to the ``OPENALEX_API_KEY`` environment variable, and
    ``""`` sends no key. The key is sent only in an ``Authorization: Bearer``
    header, never in the URL, the corpus or an error message. ``mailto``, when
    it is a non-empty string, is still sent, but OpenAlex now ignores it, since
    API keys replaced the polite pool it once selected.

    The arguments are checked before any request. ValueError is raised when
    ``query`` is not a string with at least one character left after trimming
    (``query must be a non-empty string``), when ``per_page`` is not a whole
    number from 1 to 200 (``per_page must be between 1 and 200``) and when
    ``max_records`` is not a positive whole number (``max_records must be a
    positive integer``). The key is trimmed of the spaces, tabs and line breaks
    around it, and ValueError is also raised when ``api_key``, or the
    ``OPENALEX_API_KEY`` value, is not a string or, once trimmed, holds a
    character outside visible ASCII.

    When OpenAlex refuses a request, as it does with HTTP 429 once the budget is
    spent and with HTTP 401 when a later cursor page is asked for without a key,
    ``theoryforge.lit.OpenAlexHTTPError`` (a ``urllib.error.HTTPError``) is
    raised with the status and OpenAlex's own message, and the request is not
    retried. A response without a ``results`` list, or with a work that is not
    an object, raises ValueError. Keyword and concept entries without a name
    given as text, and references that are not text, are left out. A request is
    abandoned after 30 seconds without progress. A failure to connect, including
    a connection that times out, raises ``urllib.error.URLError``, as does a
    connection reset or closed, or a reply cut short, while a reply or an error
    reply is read, and a reply that stalls raises ``TimeoutError``. Neither is
    an ``OpenAlexHTTPError``. When a page after the first fails, the works
    fetched before it are not returned, and the message ends with the number of
    them, as in ``(after 200 records were fetched)``.

    The corpus records where, when and how it was fetched in ``source``. It
    gives the service, endpoint and query and the UTC time of retrieval
    (``retrieved``), then the number of works that matched (``total_count``),
    the number kept (``n_records``), the page size and the order (``sort``).
    The date matters because the keywords change. Since late September 2026,
    OpenAlex has written each work's keywords with a language model that reads
    its title, abstract and venue. It merges and splits that vocabulary over
    time. Works without keywords fall back to their concepts, a deprecated
    vocabulary of its own. ``litmap`` compares keywords as exact strings, so a
    concept matches a keyword only where the two vocabularies write a term
    alike, which the concept 'Panic disorder' and the keyword 'panic disorder'
    do not. Save a fetched corpus and work from the saved file.
    """
    if not ne_str(query):
        raise ValueError("query must be a non-empty string")
    # Reject out-of-range page sizes here rather than passing them through for
    # OpenAlex to reject, and with the same message the R twin uses. An
    # integral float passes, as max_records does.
    ok = (not isinstance(per_page, bool) and isinstance(per_page, (int, float))
          and math.isfinite(per_page) and per_page == int(per_page) and 1 <= per_page <= 200)
    if not ok:
        raise ValueError("per_page must be between 1 and 200")
    per_page = int(per_page)
    max_records = per_page if max_records is None else _positive_int(max_records, "max_records")
    key = _api_key(os.environ.get("OPENALEX_API_KEY", "") if api_key is None else api_key)
    headers = {"Authorization": f"Bearer {key}"} if key else {}
    params = {"search": query, "per-page": str(per_page), "select": _SELECT}
    if isinstance(mailto, str) and mailto:
        params["mailto"] = mailto

    # Page numbers when the pages needed lie within the first 10,000 results,
    # since OpenAlex serves those without a key. Otherwise a cursor, which
    # OpenAlex serves past the first page only to a request with an API key
    # (HTTP 401 without one): "*" asks for the first page, and each page names
    # the cursor of the next. The run ends with enough works or an empty page,
    # and a cursor run also when no cursor follows (API_SPEC.md section 17).
    by_number = -(-max_records // per_page) * per_page <= _PAGE_NUMBER_LIMIT
    retrieved = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    page = _openalex_page({**params, **({"page": "1"} if by_number else {"cursor": "*"})},
                          headers, key)
    total_count = _whole_number(_meta(page).get("count"))
    records = [_openalex_record(w) for w in page["results"]]
    number = 1
    while len(records) < max_records and page["results"]:
        if by_number:
            number += 1
            where: dict = {"page": str(number)}
        else:
            cursor = _meta(page).get("next_cursor")
            if not ne_str(cursor):
                break
            where = {"cursor": cursor}
        page = _later_page({**params, **where}, headers, key, len(records))
        records += [_openalex_record(w) for w in page["results"]]
    records = records[:max_records]

    return {
        "schema_version": "1.0",
        "id": f"openalex:{query}",
        "source": {
            "service": "OpenAlex",
            "endpoint": _OPENALEX_WORKS,
            "query": query,
            "retrieved": retrieved,
            "total_count": total_count,
            "n_records": len(records),
            "per_page": per_page,
            # The order OpenAlex gives a search unless told otherwise. The
            # adapter sends no sort, so this records that default.
            "sort": "relevance_score:desc",
        },
        "records": records,
    }
