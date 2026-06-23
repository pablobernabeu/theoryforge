"""Assemble a reviewer-facing audit bundle as a single Markdown document (API_SPEC.md Part D).

Composes the deterministic outputs (rigor report, severity table, provenance, and the
preregistration document) so the bundle is itself byte-identical across languages.
"""
from __future__ import annotations

from .prereg import _fmt
from .prereg import preregister as _preregister
from .rigor import check as _check
from .scoring import severity as _severity


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def dossier(T) -> str:
    data = T.data if hasattr(T, "data") else T
    rep = _check(data)
    lines = [
        f"# theoryforge dossier: {data.get('title', '')}",
        "",
        f"- Theory ID: {data.get('id', '')}",
        f"- Maturity: {data.get('maturity', '')}",
        f"- Aggregate rigor score: {_fmt(rep['aggregate_score'])}/100",
        f"- Gate: {rep['gate']}",
        f"- Blockers failed: {rep['n_blockers_failed']}",
        "",
        "## Rigor checklist",
        "",
        "| item | status | score | weight |",
        "| --- | --- | --- | --- |",
    ]
    for it in rep["items"]:
        lines.append(f"| {it['id']} | {it['status']} | {_fmt(it['score'])} | {_fmt(it['weight'])} |")

    lines += ["", "## Severity", ""]
    sev = _severity(data)
    if not sev:
        lines.append("_No predictions specified._")
    else:
        for s in sev:
            pid, cs, rk = s["prediction_id"], _fmt(s["computed_severity"]), _fmt(s["risk_score"])
            lines.append(f"- {pid}: severity {cs}, risk {rk}")

    lines += ["", "## Provenance", ""]
    prov = _list(data, "provenance")
    if not prov:
        lines.append("_No provenance recorded._")
    else:
        for i, s in enumerate(prov, start=1):
            action = str(s.get("action", "") or "")
            detail = str(s.get("detail", "") or "")
            lines.append(f"{i}. {action}: {detail}" if detail.strip() else f"{i}. {action}")

    lines += ["", "## Preregistration", ""]
    return "\n".join(lines) + "\n" + _preregister(data)
