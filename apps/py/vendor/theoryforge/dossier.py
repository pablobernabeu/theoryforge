"""Assemble a reviewer-facing audit bundle as a single Markdown document.

Composes the deterministic outputs (rigour report, severity table, test record,
evidence, provenance and the preregistration document), so the bundle is itself
deterministic.
"""
from __future__ import annotations

from ._access import EVIDENCE_DIRECTION, enum, field, items, ne_str, text
from ._num import rnd
from ._text import trim
from .prereg import _fmt, _outcome_result
from .prereg import preregister as _preregister
from .rigor import check as _check
from .scoring import outcome_rows as _outcome_rows
from .scoring import severity as _severity

# A declared severity further above the claim-form rubric than this is noted
# beside it (API_SPEC.md section 20). The note changes no status.
DECLARED_MARGIN = 0.2


def _post_data(row: dict) -> str:
    """The post-data severity note of a test-record line, an open bound written as an infinity."""
    lower = "-inf" if row["lower"] is None else _fmt(row["lower"])
    upper = "inf" if row["upper"] is None else _fmt(row["upper"])
    return f"; post-data severity {_fmt(row['severity'])} for [{lower}, {upper}]"


def dossier(T) -> str:
    """A reviewer-facing audit bundle in Markdown (API_SPEC.md section 20).

    The header gives the checklist version, the aggregate score, the checklist
    coverage, the gate and the blockers that failed. The rigour table prints
    ``n/a`` for an item with nothing to assess. The severity list gives each
    prediction's claim-form rubric values and, when the prediction declares a
    severity, that value too, with a note when it exceeds the rubric by more
    than 0.2. The test record lists every test outcome in file order, with what
    it found and the observation, date and registration it records, and with
    the post-data severity of ``post_data_severity()`` where it can be
    computed, an open bound written as ``-inf`` or ``inf``. The
    evidence lists the prediction each entry supports, its direction and its
    DOI. The provenance and the preregistration follow, and the implied
    independencies appear once, in the preregistration.

    Raises:
        ValueError: when ``check()`` refuses the theory, because a test
            outcome's ``passed`` is present and not a boolean or a prediction's
            ``severity`` is not a finite number within [0, 1]. The message
            begins ``check requires``.
    """
    data = T.data if hasattr(T, "data") else T
    rep = _check(data)
    failed = [it["id"] for it in rep["items"]
              if it["severity_if_fail"] == "blocker" and it["status"] == "fail"]
    blockers = f"{rep['n_blockers_failed']} ({', '.join(failed)})" if failed else "0"
    lines = [
        f"# theoryforge dossier: {text(data.get('title'))}",
        "",
        f"- Theory ID: {text(data.get('id'))}",
        f"- Maturity: {rep['maturity']}",
        # The score is only interpretable against the checklist that produced
        # it, so a reviewer reading the bundle can see which one that was.
        f"- Checklist version: {rep['checklist_version']}",
        f"- Aggregate rigour score: {_fmt(rep['aggregate_score'])}/100",
        # The share of the checklist's weight the aggregate is the mean over.
        f"- Checklist coverage: {_fmt(rep['coverage'])}",
        f"- Gate: {rep['gate']}",
        f"- Blockers failed: {blockers}",
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
        # check() above has refused any declared severity that is not a number
        # in [0, 1], so what is left is a number or absent.
        for p, s in zip(items(data, "predictions"), sev, strict=True):
            pid, cs, rk = s["prediction_id"], _fmt(s["computed_severity"]), _fmt(s["risk_score"])
            line = f"- {pid}: severity {cs}, risk {rk}"
            declared = field(p, "severity")
            if declared is not None:
                line += f", declared {_fmt(declared)}"
                if rnd(declared - s["computed_severity"], 3) > DECLARED_MARGIN:
                    line += f" (declared exceeds the rubric by more than {_fmt(DECLARED_MARGIN)})"
            lines.append(line)

    # Every outcome, in file order, with the fields it records (API_SPEC.md
    # section 20). check() above has refused a passed that is not a boolean.
    # An outcome whose post-data severity can be computed gives it last, and
    # one that post_data_severity() would refuse is listed without it.
    lines += ["", "## Test record", ""]
    tos = items(data, "test_outcomes")
    if not tos:
        lines.append("_No test outcomes recorded._")
    else:
        for t, (row, _) in zip(tos, _outcome_rows(data), strict=True):
            line = f"- {text(field(t, 'prediction_id'))}: {_outcome_result(t)}"
            for key in ("observed", "date", "registered"):
                value = text(field(t, key))
                if ne_str(value):
                    line += f"; {key}: {value}"
            if row is not None:
                line += _post_data(row)
            lines.append(line)

    lines += ["", "## Evidence", ""]
    evidence = items(data, "evidence")
    if not evidence:
        lines.append("_No evidence recorded._")
    else:
        for e in evidence:
            direction = enum(field(e, "direction"), EVIDENCE_DIRECTION) or ""
            line = f"- supports {text(field(e, 'supports'))}: {direction}"
            doi = text(field(e, "source_doi"))
            if ne_str(doi):
                line += f"; doi: {doi}"
            lines.append(line)

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
