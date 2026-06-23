"""Bibliometric / literature layer (API_SPEC.md Part C).

The analysis (litmap, landscape, diagrams) is fully DETERMINISTIC given a corpus, so it is
parity-tested. The OpenAlex fetch adapter (fetch_corpus) is the parity-exempt assistive layer.
"""
from __future__ import annotations

import itertools
import json
from pathlib import Path

import yaml

from .redundancy import tokens

DEFAULT_MIN_LINK = 2


def _esc(s) -> str:
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


def read_corpus(path) -> dict:
    """Read a literature corpus from YAML or JSON."""
    path = Path(path)
    text = path.read_text(encoding="utf-8")
    return json.loads(text) if path.suffix.lower() == ".json" else yaml.safe_load(text)


def _records(corpus) -> list:
    corpus = corpus.data if hasattr(corpus, "data") else corpus
    recs = corpus.get("records")
    return recs if isinstance(recs, list) else []


def _pair_counts(records: list, field: str) -> dict:
    counts: dict[tuple, int] = {}
    for r in records:
        items = sorted({x for x in (r.get(field) or []) if x})
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
    all_keywords = sorted({k for r in records for k in (r.get("keywords") or []) if k})
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
            if tokens(a.get("label", "") + " " + " ".join(a.get("key_constructs") or [])) & th_tokens
        )
        focal_on = bool(focal_tokens & th_tokens)
        n = len(on) + (1 if focal_on else 0)
        status = "under_theorized" if n == 0 else ("crowded" if n >= 2 else "covered")
        themes_out.append({
            "id": th["id"], "keywords": th["keywords"],
            "alternatives": on, "focal": focal_on, "status": status,
        })
        if status == "under_theorized":
            under.append(th["id"])
        elif status == "crowded":
            crowded.append(th["id"])

    return {
        "theory_id": T.get("id", ""),
        "themes": themes_out,
        "under_theorized_fronts": under,
        "redundancy_risk": crowded,
    }


def _undirected(name: str, edges: list[dict]) -> str:
    nodes = sorted({n for e in edges for n in (e["a"], e["b"])})
    lines = [f"graph {name} {{", "  node [shape=ellipse];"]
    for n in nodes:
        lines.append(f'  "{_esc(n)}";')
    for e in edges:
        lines.append(f'  "{_esc(e["a"])}" -- "{_esc(e["b"])}" [label="{e["count"]}"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _theme_landscape(ls: dict) -> str:
    lines = ["digraph theme_landscape {", "  rankdir=LR;", "  node [shape=box];"]
    for th in ls["themes"]:
        label = f'{th["id"]}: {", ".join(th["keywords"])} ({th["status"]})'
        lines.append(f'  "{_esc(th["id"])}" [label="{_esc(label)}"];')
    # collect alternatives in first-seen order across themes
    alt_ids: list[str] = []
    for th in ls["themes"]:
        for a in th["alternatives"]:
            if a not in alt_ids:
                alt_ids.append(a)
    for a in alt_ids:
        lines.append(f'  "{_esc(a)}" [label="{_esc(a)}", shape=ellipse];')
    lines.append('  "focal" [label="focal", shape=ellipse, style=bold];')
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
    raise ValueError(f"unknown lit diagram type {type!r}")


def fetch_corpus(query: str, per_page: int = 25, mailto: str | None = None) -> dict:
    """Build a corpus from the OpenAlex API (network call).

    This adapter is assistive and parity-exempt. It is not part of the deterministic
    core and is not covered by parity tests.
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
