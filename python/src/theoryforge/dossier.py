"""Assemble a reviewer-facing audit bundle as a single Markdown document.

Composes the deterministic outputs (rigour report, severity table, provenance and the
preregistration document), so the bundle is itself deterministic.
"""
from __future__ import annotations

from ._access import field, items, text
from ._text import trim
from .prereg import _fmt
from .prereg import preregister as _preregister
from .rigor import check as _check
from .scoring import severity as _severity


def dossier(T) -> str:
    data = T.data if hasattr(T, "data") else T
    rep = _check(data)
    lines = [
        f"# theoryforge dossier: {text(data.get('title'))}",
        "",
        f"- Theory ID: {text(data.get('id'))}",
        f"- Maturity: {rep['maturity']}",
        # The score is only interpretable against the checklist that produced
        # it, so a reviewer reading the bundle can see which one that was.
        f"- Checklist version: {rep['checklist_version']}",
        f"- Aggregate rigour score: {_fmt(rep['aggregate_score'])}/100",
        f"- Gate: {rep['gate']}",
        f"- Blockers failed: {rep['n_blockers_failed']}",
        "",
        "## Rigour checklist",
        "",
        "| item | status | score | weight |",
        "| --- | --- | --- | --- |",
    ]
    for it in rep["items"]:
        lines.append(f"| {it['id']} | {it['status']} | {_fmt(it['score'])} | {_fmt(it['weight'])} |")

    lines += ["", "## Severity (pre-data rubric of claim form)", ""]
    sev = _severity(data)
    if not sev:
        lines.append("_No predictions specified._")
    else:
        for s in sev:
            pid, cs, rk = s["prediction_id"], _fmt(s["computed_severity"]), _fmt(s["risk_score"])
            lines.append(f"- {pid}: severity {cs}, risk {rk}")

    lines += ["", "## Provenance", ""]
    prov = items(data, "provenance")
    if not prov:
        lines.append("_No provenance recorded._")
    else:
        for i, s in enumerate(prov, start=1):
            action = text(field(s, "action"))
            detail = text(field(s, "detail"))
            lines.append(f"{i}. {action}: {detail}" if trim(detail) else f"{i}. {action}")

    lines += ["", "## Preregistration", ""]
    return "\n".join(lines) + "\n" + _preregister(data)
