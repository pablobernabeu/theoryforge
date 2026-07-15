"""Bibliometric / literature layer.

The analysis (litmap, landscape, diagrams) is fully deterministic given a corpus. The
OpenAlex fetch adapter (fetch_corpus) is the assistive layer, whose results depend on a
live network service.
"""
from __future__ import annotations

import itertools
import json
from pathlib import Path

import yaml

from .redundancy import tokens
from .rigor import _as_list

DEFAULT_MIN_LINK = 2


def _esc(s) -> str:
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


def read_corpus(path) -> dict:
    """Read a literature corpus from YAML or JSON."""
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    data = json.loads(text) if path.suffix.lower() == ".json" else yaml.safe_load(text)
    if not isinstance(data, dict):
        raise ValueError("Corpus data must be a mapping")
    return data


def _records(corpus) -> list:
    corpus = corpus.data if hasattr(corpus, "data") else corpus
    recs = corpus.get("records")
    return recs if isinstance(recs, list) else []


def _pair_counts(records: list, field: str) -> dict:
    counts: dict[tuple, int] = {}
    for r in records:
        items = sorted({x for x in _as_list(r.get(field)) if x})
        for a, b in itertools.combinations(items, 2):
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


def litmap(corpus, min_link: int = DEFAULT_MIN_LINK) -> dict:
    """Keyword co-occurrence, thematic components, and co-citation, all deterministic."""
    records = _records(corpus)
    all_keywords = sorted({k for r in records for k in _as_list(r.get("keywords")) if k})
    kw_edges = _edges(_pair_counts(records, "keywords"), min_link)
    cocit = _edges(_pair_counts(records, "references"), min_link)
    return {
        "n_records": len(records),
        "keywords": all_keywords,
        "keyword_cooccurrence": kw_edges,
        "themes": _components(kw_edges),
        "co_citation": cocit,
    }


def landscape(theory, corpus, min_link: int = DEFAULT_MIN_LINK) -> dict:
    """Map a theory and its registered alternatives onto the literature's themes."""
    T = theory.data if hasattr(theory, "data") else theory
    lm = litmap(corpus, min_link)

    focal_src = " ".join(
        [T.get("title", "")] + [c.get("label", "") for c in (T.get("constructs") or [])]
    )
    focal_tokens = tokens(focal_src)
    alts = T.get("alternatives") or []

    themes_out = []
    under, crowded = [], []
    for th in lm["themes"]:
        th_tokens = tokens(" ".join(th["keywords"]))
        on = sorted(
            a.get("id") for a in alts
            if tokens(a.get("label", "") + " " + " ".join(_as_list(a.get("key_constructs")))) & th_tokens
        )
        focal_on = bool(focal_tokens & th_tokens)
        n = len(on) + (1 if focal_on else 0)
        status = "under_theorised" if n == 0 else ("crowded" if n >= 2 else "covered")
        themes_out.append({
            "id": th["id"], "keywords": th["keywords"],
            "alternatives": on, "focal": focal_on, "status": status,
        })
        if status == "under_theorised":
            under.append(th["id"])
        elif status == "crowded":
            crowded.append(th["id"])

    return {
        "theory_id": T.get("id", ""),
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


# Theme colours track the landscape statuses: an untouched front is teal (an
# opportunity), a crowded one amber (a redundancy risk), a covered one grey.
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


def lit_diagram(obj: dict, type: str = "keyword_cooccurrence") -> str:
    """DOT for the literature layer. type in {keyword_cooccurrence, co_citation, theme_landscape}."""
    if type in ("keyword_cooccurrence", "co_citation"):
        return _undirected(type, obj.get(type, []))
    if type == "theme_landscape":
        return _theme_landscape(obj)
    raise ValueError(
        f"unknown lit diagram type {type!r}; expected one of "
        "('keyword_cooccurrence', 'co_citation', 'theme_landscape')"
    )


_DOI_PREFIXES = ("https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:")


def _normalize_doi(doi) -> str:
    d = str(doi or "").strip().lower()
    for prefix in _DOI_PREFIXES:
        if d.startswith(prefix):
            return d[len(prefix):]
    return d


def new_evidence_dois(theory, candidate_dois: list) -> list:
    """DOIs in `candidate_dois` not already cited by the theory's evidence or alternatives.

    Compares by normalised form (lowercased, with any doi.org/dx.doi.org URL prefix
    stripped), so a fresh literature search, for example via OpenAlex, Scopus, or any
    other source, can be checked against what the theory already engages with. Returns
    the qualifying DOIs in their original form, deduplicated and sorted by normalised
    form. Deterministic and takes no network dependency: the search itself is left to
    whichever literature tool the caller prefers.
    """
    T = theory.data if hasattr(theory, "data") else theory
    known = set()
    for e in T.get("evidence") or []:
        doi = e.get("source_doi")
        if doi:
            known.add(_normalize_doi(doi))
    for a in T.get("alternatives") or []:
        doi = a.get("source_doi")
        if doi:
            known.add(_normalize_doi(doi))

    seen, out = set(), []
    for doi in candidate_dois or []:
        if not doi:
            continue
        norm = _normalize_doi(doi)
        if norm in known or norm in seen:
            continue
        seen.add(norm)
        out.append(doi)
    return sorted(out, key=_normalize_doi)


def fetch_corpus(query: str, per_page: int = 25, mailto: str | None = None) -> dict:
    """Build a corpus from the OpenAlex API (network call).

    This adapter is assistive. It depends on a live external service whose results
    change over time, so it sits outside the package's deterministic core.
    """
    import urllib.parse
    import urllib.request

    params = {"search": query, "per-page": str(per_page)}
    if mailto:
        params["mailto"] = mailto
    url = "https://api.openalex.org/works?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=30) as resp:  # noqa: S310 (documented external call)
        data = json.load(resp)

    records = []
    for w in data.get("results", []):
        kws = [k.get("display_name") for k in (w.get("keywords") or [])]
        if not kws:
            kws = [c.get("display_name") for c in (w.get("concepts") or [])[:5]]
        records.append({
            "id": w.get("id"),
            "title": w.get("title"),
            "year": w.get("publication_year"),
            "keywords": [k for k in kws if k],
            "references": w.get("referenced_works") or [],
        })
    return {"schema_version": "1.0", "id": f"openalex:{query}", "records": records}
