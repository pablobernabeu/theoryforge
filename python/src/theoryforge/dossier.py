"""Assemble a reviewer-facing audit bundle as a single Markdown document.

Composes the deterministic outputs (rigour report, severity table, test record,
evidence, provenance and the hypotheses section of a preregistration), so the
bundle is itself deterministic.
"""
from __future__ import annotations

from . import _resources
from ._access import EVIDENCE_DIRECTION, enum, field, items, ne_str, text
from ._compat import theory_keyword
from ._num import rnd
from ._text import trim
from .entailment import check_cycles, claim_line, discriminate, entailments, equivalent_models
from .hashing import content_hash
from .prereg import _fmt, _outcome_result, _plan_number, document_lines, flat
from .rigor import check as _check
from .scoring import outcome_rows as _outcome_rows
from .scoring import severity as _severity

# A declared severity further above the claim-form rubric than this is noted
# beside it (API_SPEC.md section 20). The note changes no status.
DECLARED_MARGIN = 0.2


def _post_data(row: dict, passed) -> str:
    """The post-data severity note of a test-record line, an open bound written as an infinity.

    The bounds are written as recorded, with up to 15 significant digits, so a
    small bound is not rounded to zero. A severity that rounds to 1 or 0 is
    written as ``> 0.999`` or ``< 0.001``. A pass whose estimate lies outside
    the region is said to be one.
    """
    lower = "-inf" if row["lower"] is None else _plan_number(row["lower"])
    upper = "inf" if row["upper"] is None else _plan_number(row["upper"])
    # Rounded to three decimals, a severity of 0.9996 would read as 1, which
    # no finite test can give.
    sev = row["severity"]
    value = "> 0.999" if sev == 1 else "< 0.001" if sev == 0 else _fmt(sev)
    note = f"; post-data severity {value} for [{lower}, {upper}]"
    # A pass with the estimate outside the region is not refused, since a test
    # that fails to reject a predicted value passes it (Meehl, 1967), but the
    # reader is told.
    est = row["estimate"]
    outside = ((row["lower"] is not None and est < row["lower"])
               or (row["upper"] is not None and est > row["upper"]))
    if passed is True and outside:
        note += "; recorded as passed, with the estimate outside that region"
    return note


def _claims_section(data: dict, cycles: str) -> list[str]:
    """What the causal graph says of each claim (API_SPEC.md section 20)."""
    try:
        recs = entailments(data, cycles=cycles)["claims"]
    except ValueError as err:
        return [f"_Not read: {err}._"]
    if not recs:
        return ["_No prediction or phenomenon states a claim._"]
    return [f"- {r['id']} ({r['source']}): {claim_line(r)}" for r in recs]


def _equivalence_section(data: dict) -> list[str]:
    """Which causal directions an equivalent model reverses (API_SPEC.md section 20)."""
    try:
        eq = equivalent_models(data)
    except ValueError as err:
        return [f"_Not read: {err}._"]
    if eq["reason"] == "feedback_loop":
        return ["_Not determined: the causal graph has a feedback loop._"]
    if eq["reason"] == "associations":
        return ["_Not determined: the theory states associations, and the rule covers "
                "graphs of directed relations alone._"]
    if not eq["edges"]:
        return ["_None: the theory states no directed relation between constructs._"]
    word = {"compelled": "fixed in every equivalent model",
            "reversible": "reversed in some equivalent model"}
    return [f"- {', '.join(e['propositions'])}: {e['from']} -> {e['to']} ({word[e['status']]})"
            for e in eq["edges"]]


def _rivals_section(data: dict, cycles: str) -> list[str]:
    """How the theory compares with each rival that states propositions (API_SPEC.md section 20)."""
    out = []
    for a in items(data, "alternatives"):
        aid = text(field(a, "id"))
        if not (ne_str(aid) and items(a, "propositions")):
            continue
        try:
            d = discriminate(data, aid, cycles=cycles)
        except ValueError as err:
            out.append(f"- {aid}: not compared: {err}")
            continue
        if not d["evaluated"]:
            out.append(f"- {aid}: not compared, since a causal graph has a feedback loop")
            continue
        found = [c["id"] for c in d["claims"] if c["discriminates"]]
        n = d["counts"]
        line = (f"- {aid}: claims it discriminates: {', '.join(found) if found else 'none'}; "
                f"independencies one implies and the other does not: {n['independencies']}; "
                f"decisive differences in sign: {n['decisive_effects']} effects, "
                f"{n['decisive_associations']} associations")
        if d["markov_equivalent"]:
            line += "; Markov equivalent to the theory"
        out.append(line)
    return out or ["_No alternative states propositions._"]


@theory_keyword
def dossier(theory, cycles: str = "refuse") -> str:
    """A reviewer-facing audit bundle in Markdown.

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
    check_cycles(cycles, "dossier")
    data = theory.data if hasattr(theory, "data") else theory
    rep = _check(data)
    digest = content_hash(data)
    criteria = {it["id"]: it["criterion"] for it in _resources.checklist()["items"]}
    failed = [it["id"] for it in rep["items"]
              if it["severity_if_fail"] == "blocker" and it["status"] == "fail"]
    blockers = f"{rep['n_blockers_failed']} ({', '.join(failed)})" if failed else "0"
    lines = [
        f"# theoryforge dossier: {flat(text(data.get('title')))}",
        "",
        f"- Theory ID: {text(data.get('id'))}",
        f"- Content hash: {digest}",
        f"- Maturity: {rep['maturity']}",
        # The score is only interpretable against the checklist that produced
        # it, so a reviewer reading the bundle can see which one that was.
        f"- Checklist version: {rep['checklist_version']}",
        f"- Aggregate rigour score: {_fmt(rep['aggregate_score'])}/100 "
        f"({_fmt(rep['aggregate_range'][0])} to {_fmt(rep['aggregate_range'][1])} "
        "under other weightings)",
        # The share of the checklist's weight the aggregate is the mean over.
        f"- Checklist coverage: {_fmt(rep['coverage'])}",
        f"- Gate: {rep['gate']}",
        f"- Blockers failed: {blockers}",
        "",
        "## Rigour checklist",
        "",
        "| item | criterion | status | score | weight |",
        "| --- | --- | --- | --- | --- |",
    ]
    for it in rep["items"]:
        lines.append(f"| {it['id']} | {criteria.get(it['id'], '')} | {it['status']} | "
                     f"{_fmt(it['score'])} | {_fmt(it['weight'])} |")

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
                value = flat(text(field(t, key)))
                if ne_str(value):
                    line += f"; {key}: {value}"
            if row is not None:
                line += _post_data(row, field(t, "passed"))
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

    lines += ["", "## Claims and the causal graph", "", *_claims_section(data, cycles)]
    lines += ["", "## Equivalent models", "", *_equivalence_section(data)]
    lines += ["", "## Rivals", "", *_rivals_section(data, cycles)]

    lines += ["", "## Provenance", ""]
    prov = items(data, "provenance")
    if not prov:
        lines.append("_No provenance recorded._")
    else:
        for i, s in enumerate(prov, start=1):
            action = flat(text(field(s, "action")))
            detail = flat(text(field(s, "detail")))
            lines.append(f"{i}. {action}: {detail}" if trim(detail) else f"{i}. {action}")

    # The preregistration is a document of its own, so its headings move one
    # level down to sit under this section. Its severity list is left out, since
    # the dossier gives it above with the declared values.
    prereg = ["#" + line if line.startswith("#") else line
              for line in document_lines(data, cycles, embedded=True, report=rep, digest=digest)]
    lines += ["", "## Preregistration", "", *prereg]
    return "\n".join(lines) + "\n"
