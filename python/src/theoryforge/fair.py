"""Archive-ready export of a theory as a reusable digital object (API_SPEC.md Part F).

``fair_export`` renders a deterministic bundle — a README, citation metadata
(CITATION.cff), general-purpose deposition metadata (metadata.json, using the field
names common to Zenodo-style archives) and the audit dossier — from the
schema-validated theory object. The four rendered files are byte-identical across
languages and parity-tested; writing them to disk (plus a language-native copy of the
theory itself) is the only I/O and happens only when a path is given.
"""
from __future__ import annotations

from pathlib import Path

import yaml

from .dossier import dossier as _dossier
from .lit import _normalize_doi
from .prereg import _fmt
from .rigor import check as _check


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def _js(s) -> str:
    """Minimal JSON string escape (backslash then quote), mirrored in R."""
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


def _cited_dois(T: dict) -> list[str]:
    """Normalised DOIs cited by the theory's evidence and alternatives, deduplicated
    and sorted by normalised form (the API_SPEC.md section 18 normalisation)."""
    seen: set[str] = set()
    for coll in ("evidence", "alternatives"):
        for e in _list(T, coll):
            doi = e.get("source_doi")
            if isinstance(doi, str) and doi.strip():
                seen.add(_normalize_doi(doi))
    return sorted(seen)


def _readme(T: dict, rep: dict, version: str, license: str) -> str:
    lines = [
        f"# {T.get('title', '')}",
        "",
        f"- Theory ID: {T.get('id', '')}",
        f"- Version: {version}",
        f"- Maturity: {T.get('maturity', '')}",
        f"- Aggregate rigour score: {_fmt(rep['aggregate_score'])}/100 (gate: {rep['gate']})",
        f"- Licence: {license}",
        "",
        "## Constructs",
        "",
    ]
    cons = _list(T, "constructs")
    if cons:
        lines += [f"- {c.get('id', '')}: {c.get('label', '')}" for c in cons]
    else:
        lines.append("_No constructs declared._")
    lines += [
        "",
        "## Contents",
        "",
        "- `theory.yaml` — the machine-checkable theory object (theoryforge schema)",
        "- `dossier.md` — the audit dossier (rigour report, severity, provenance, preregistration)",
        "- `CITATION.cff` — citation metadata",
        "- `metadata.json` — deposition metadata for general-purpose archives",
        "",
        "## Reuse",
        "",
        "Validate, score, diagram, simulate or amend this theory with the theoryforge",
        "R or Python package: https://github.com/pablobernabeu/theoryforge",
    ]
    return "\n".join(lines) + "\n"


def _citation_cff(T: dict, version: str, license: str,
                  keywords: list[str], authors: list[str]) -> str:
    lines = [
        "cff-version: 1.2.0",
        "message: If you use this theory, please cite it.",
        "type: dataset",
        f"title: {T.get('title', '')}",
        f"version: {version}",
        f"license: {license}",
        "keywords:",
    ]
    lines += [f"  - {k}" for k in keywords]
    if authors:
        lines.append("authors:")
        lines += [f"  - name: {a}" for a in authors]
    else:
        lines.append("authors: []")
    return "\n".join(lines) + "\n"


def _metadata_json(T: dict, version: str, license: str,
                   keywords: list[str], authors: list[str]) -> str:
    title = _js(T.get("title", ""))
    desc = _js(f"{T.get('title', '')} — a machine-checkable scientific theory object "
               f"(id: {T.get('id', '')}, maturity: {T.get('maturity', '')}).")
    lines = [
        "{",
        f'  "title": "{title}",',
        '  "upload_type": "dataset",',
        f'  "description": "{desc}",',
        f'  "version": "{_js(version)}",',
        f'  "license": "{_js(license)}",',
        '  "keywords": [' + ", ".join(f'"{_js(k)}"' for k in keywords) + "],",
    ]
    if authors:
        lines.append('  "creators": [')
        for i, a in enumerate(authors):
            comma = "," if i < len(authors) - 1 else ""
            lines.append(f'    {{"name": "{_js(a)}"}}{comma}')
        lines.append("  ],")
    else:
        lines.append('  "creators": [],')
    dois = _cited_dois(T)
    if dois:
        lines.append('  "related_identifiers": [')
        for i, d in enumerate(dois):
            comma = "," if i < len(dois) - 1 else ""
            lines.append(f'    {{"relation": "cites", "identifier": "{_js(d)}"}}{comma}')
        lines.append("  ]")
    else:
        lines.append('  "related_identifiers": []')
    lines.append("}")
    return "\n".join(lines) + "\n"


def fair_export(T, path=None, authors=None, license: str = "CC-BY-4.0",
                keywords=None) -> dict:
    """Render the archive bundle for a theory, optionally writing it to ``path``.

    Returns ``{"README.md", "CITATION.cff", "metadata.json", "dossier.md"}`` mapping
    each filename to its rendered content. When ``path`` is given, the four files are
    written there together with ``theory.yaml`` (a language-native serialisation of
    the theory, excluded from cross-language parity). ``authors`` is a list of
    "Family, Given" (or entity) name strings used in the citation and deposition
    metadata; ``keywords`` defaults to ``["scientific-theory", "theoryforge", <id>]``.
    """
    data = T.data if hasattr(T, "data") else T
    authors = [str(a) for a in authors] if authors else []
    kws = [str(k) for k in keywords] if keywords else [
        "scientific-theory", "theoryforge", str(data.get("id", "") or "")]
    version = str(data.get("version", {}).get("id", "") or "") \
        if isinstance(data.get("version"), dict) else ""
    version = version if version.strip() else "unversioned"
    rep = _check(data)

    files = {
        "README.md": _readme(data, rep, version, license),
        "CITATION.cff": _citation_cff(data, version, license, kws, authors),
        "metadata.json": _metadata_json(data, version, license, kws, authors),
        "dossier.md": _dossier(data),
    }

    if path is not None:
        out = Path(path)
        out.mkdir(parents=True, exist_ok=True)
        for name, content in files.items():
            (out / name).write_bytes(content.encode("utf-8"))
        (out / "theory.yaml").write_text(
            yaml.safe_dump(data, sort_keys=False, allow_unicode=True), encoding="utf-8")
    return files
