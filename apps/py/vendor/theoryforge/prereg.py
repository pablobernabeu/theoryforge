"""Preregistration document export. Deterministic markdown output."""
from __future__ import annotations

import math

from ._access import MATURITY, PRED_TYPE, enum, field, items, ne_str, str_list, text
from ._io import write_lf as _write_lf
from ._num import number as _number
from .implications import implications as _implications
from .rigor import check as _check
from .scoring import severity as _severity

# What the derivation line reports for each status of the checklist's
# derivation_chain item (API_SPEC.md section 11). The item checks only that
# every prediction cites declared propositions, so the line says whether those
# references resolve.
_RESOLVE = {"pass": "yes", "fail": "no", "n/a": "not applicable (no predictions)"}

_IMPLIED_HEADING = "## Implied conditional independencies (derived from the causal graph, not predictions)"

_PLAN_HEADING = "## Sampling plan (author-recorded; not scored)"
_SIDED = ("two", "one")


def _fmt(x) -> str:
    """Format a number identically across languages: 3dp, trailing zeros stripped,
    at least one decimal kept (1.0 -> '1.0', 0.667 -> '0.667'). None, the score
    of a checklist item with nothing to assess, is 'n/a'."""
    if x is None:
        return "n/a"
    s = f"{float(x):.3f}".rstrip("0")
    return s + "0" if s.endswith(".") else s


def _outcome_result(t) -> str:
    """What a test outcome found: ``passed``, ``failed`` or ``no result recorded``.

    ``check()`` has refused a ``passed`` that is present and not a boolean, so
    what is left is a boolean or absent.
    """
    passed = field(t, "passed")
    if passed is True:
        return "passed"
    if passed is False:
        return "failed"
    return "no result recorded"


def _version_line(data: dict) -> list[str]:
    """The version line, when the version has an id, naming its parent when it has one."""
    ver = data.get("version")
    vid = text(field(ver, "id"))
    if not ne_str(vid):
        return []
    parent = text(field(ver, "parent_id"))
    return [f"- Version: {vid} (parent {parent})" if ne_str(parent) else f"- Version: {vid}"]


def _auxiliaries(pid: str, aux: list) -> list[str]:
    """The assumptions whose ``protects`` names ``pid``, in file order.

    An assumption with a nonempty ``added_for`` was added in answer to that
    prediction's anomaly, and any other is core, as the schema reads a null.
    """
    out = []
    for a in aux:
        if pid not in str_list(field(a, "protects")):
            continue
        added = text(field(a, "added_for"))
        out.append(f"{text(field(a, 'id'))} ({'added for ' + added if ne_str(added) else 'core'})")
    return out


def _test_record(pid: str, tos: list) -> str:
    """Every outcome of prediction ``pid``, in file order, or ``untested``.

    An outcome counts when its ``prediction_id`` is the string ``pid``, as in the
    amendment appraisal (API_SPEC.md section 10). The registration is labelled,
    since a bare value could be read as a second date.
    """
    done = []
    for t in tos:
        tid = field(t, "prediction_id")
        if not (isinstance(tid, str) and tid == pid):
            continue
        date, reg = text(field(t, "date")), text(field(t, "registered"))
        when = [date] if ne_str(date) else []
        if ne_str(reg):
            when.append(f"registered {reg}")
        done.append(_outcome_result(t) + (f" ({', '.join(when)})" if when else ""))
    return "already tested: " + "; ".join(done) if done else "untested"


def _plan_number(x: float) -> str:
    """A recorded value as the sampling plan writes it, with up to 15 significant digits.

    The plan repeats what the author recorded, so it does not round to the three
    decimals of ``_fmt``, which would write an alpha of 0.0001 as 0.0. R's
    ``sprintf("%.15g")`` gives the same text, an exponent such as ``5e-08``
    included.
    """
    return format(x, ".15g")


def _plan(p) -> str | None:
    """The sampling plan that prediction ``p`` states, or None when it states none.

    The ``test`` block is read leniently (API_SPEC.md section 30). A number that
    full validation would refuse reads as absent, text is read through
    ``text`` and ``sided`` through ``enum``. A qualifier is written only beside
    the value it qualifies: the unit with ``n_planned``, the scale with
    ``sesoi``, and the interval and method with the power or decision
    probability.
    """
    block = field(p, "test")
    if not isinstance(block, dict):
        return None

    def num(key: str, ok) -> float | None:
        x = _number(block.get(key))
        return x if x is not None and ok(x) else None

    def txt(key: str) -> str:
        s = text(block.get(key))
        return s if ne_str(s) else ""

    def unit_interval(x: float) -> bool:
        return 0 <= x <= 1

    clauses = []
    n = num("n_planned", lambda x: math.isfinite(x) and x == math.floor(x) and x >= 1)
    if n is not None:
        unit = txt("unit")
        clauses.append(f"n = {_plan_number(n)}" + (f" {unit}" if unit else ""))
    alpha = num("alpha", lambda x: 0 < x < 1)
    sided = enum(block.get("sided"), _SIDED)
    level = ([f"alpha {_plan_number(alpha)}"] if alpha is not None else []) + \
        ([f"{sided}-sided"] if sided else [])
    if level:
        clauses.append(", ".join(level))
    sesoi = num("sesoi", math.isfinite)
    if sesoi is not None:
        scale = txt("sesoi_scale")
        clauses.append(f"smallest effect of interest {_plan_number(sesoi)}"
                       + (f" {scale}" if scale else ""))
    power = num("power", unit_interval)
    decision = num("decision_probability", unit_interval)
    prob = ([f"power {_plan_number(power)}"] if power is not None else []) + \
        ([f"decision probability {_plan_number(decision)}"] if decision is not None else [])
    if prob:
        part = ", ".join(prob)
        lo, hi = num("power_lo", unit_interval), num("power_hi", unit_interval)
        if lo is not None and hi is not None and lo <= hi:
            part += f" [{_plan_number(lo)}, {_plan_number(hi)}]"
        method = txt("method")
        clauses.append(part + (f" ({method})" if method else ""))
    design = txt("design_ref")
    if design:
        clauses.append(f"design: {design}")
    justification = txt("justification")
    if not clauses:
        return justification or None
    line = "; ".join(clauses)
    return f"{line}. {justification}" if justification else line


def _sampling_plan(preds: list) -> list[str]:
    """The lines of the sampling-plan section, or none when no prediction states a plan.

    A theory without a plan therefore renders as it did before the section
    existed (API_SPEC.md section 30).
    """
    plans = [(text(field(p, "id")), _plan(p)) for p in preds]
    if all(plan is None for _, plan in plans):
        return []
    return ["", _PLAN_HEADING,
            *(f"- {pid}: {plan if plan is not None else 'no sampling plan stated'}"
              for pid, plan in plans)]


def _implied(data: dict) -> list[str]:
    """The lines of the implied-independencies section (API_SPEC.md section 11)."""
    try:
        imp = _implications(data)
    except ValueError as err:
        # A refusal: a feedback loop under the default, a repeated construct id
        # or a directed relation naming an undeclared construct. The reason is
        # what the section reports.
        return [f"_Not derived: {err}._"]
    if imp["implications"]:
        # A code span keeps dagitty's notation whole, since Markdown reads the
        # underscores of " _||_ " as emphasis around the two bars.
        return [f"- `{i['statement']}`" for i in imp["implications"]]
    if not imp["constructs"]:
        return ["_None: the theory states no directed relation between constructs._"]
    if imp["inseparable"]:
        return ["_None: no set of constructs separates any pair the theory leaves unjoined._"]
    return ["_None: every pair of constructs in the causal graph is adjacent._"]


def preregister(T, path=None) -> str:
    """Render the hypotheses section of a preregistration, writing it to ``path`` when one is given.

    The header gives the theory id, the version when it has an id (with its
    parent, when one is named), the schema version, the maturity and whether
    every prediction's derivation references resolve: ``yes``, ``no`` or ``not
    applicable (no predictions)``. The derivation line reports the checklist's
    reference check, which does not show that a prediction follows from the
    propositions it cites.

    Each hypothesis is listed in file order with its claim type, statement and
    derivation, followed by the auxiliary assumptions that protect it (``core``
    or ``added for <id>``), the registered rivals it discriminates and its test
    record. A hypothesis that a recorded outcome has already tested reads
    ``already tested: passed (<date>, registered <where>)``, one entry per
    outcome, and any other reads ``untested``.

    When at least one prediction states a sampling plan in its ``test`` block,
    a section headed ``Sampling plan (author-recorded; not scored)`` follows,
    with one line per prediction in file order. A line gives what is recorded
    of the planned sample, alpha and sidedness, smallest effect of interest,
    power or decision probability, design analysis and justification. A
    prediction without a plan reads ``no sampling plan stated``. Nothing
    scores the plan: power does not raise a claim's severity (Meehl, 1967),
    though it decides how informative a failed test is (Lakens, 2022). A theory
    without a plan has no such section.

    A section then lists the conditional independencies that
    ``implications()`` derives from the causal graph with its default
    settings, which are claims the theory makes without stating them, or says
    why there are none. The claim-form severity rubric closes the document.

    The document is the part of a preregistration that the theory file holds.
    It is to be completed with the study design, the analysis plan, the
    inference criteria and whatever the sampling plan leaves out, the sections
    that a template such as PRP-QUANT asks for (Bosnjak et al., 2022).

    References:
        Bosnjak, M., Fiebach, C. J., Mellor, D., Mueller, S., O'Connor, D. B.,
        Oswald, F. L., & Sokol, R. I. (2022). A template for preregistration of
        quantitative research in psychology: Report of the joint psychological
        societies preregistration task force. American Psychologist, 77(4),
        602-615. https://doi.org/10.1037/amp0000879

        Lakens, D. (2022). Sample size justification. Collabra: Psychology,
        8(1), Article 33267. https://doi.org/10.1525/collabra.33267

        Meehl, P. E. (1967). Theory-testing in psychology and physics: A
        methodological paradox. Philosophy of Science, 34(2), 103-115.
        https://doi.org/10.1086/288135
    """
    data = T.data if hasattr(T, "data") else T
    rep = _check(data)
    deriv = next((it for it in rep["items"] if it["id"] == "derivation_chain"), None)
    resolve = _RESOLVE[deriv["status"]] if deriv else "no"

    lines = [
        f"# Preregistration: {text(data.get('title'))}",
        "",
        f"- Theory ID: {text(data.get('id'))}",
        *_version_line(data),
        f"- Schema version: {text(data.get('schema_version'))}",
        f"- Maturity: {enum(data.get('maturity'), MATURITY) or ''}",
        f"- Derivation references resolve: {resolve}",
        "",
        "## Hypotheses",
    ]
    preds = items(data, "predictions")
    if not preds:
        lines.append("_No predictions specified._")
    else:
        aux = items(data, "auxiliary_assumptions")
        tos = items(data, "test_outcomes")
        alt_ids = {text(field(a, "id")) for a in items(data, "alternatives")}
        for i, p in enumerate(preds, start=1):
            df = str_list(field(p, "derives_from"))
            df_txt = ", ".join(df) if df else "—"
            ptype = enum(field(p, "type"), PRED_TYPE) or ""
            lines.append(f"{i}. [{ptype}] {text(field(p, 'statement'))} (derives from: {df_txt})")
            # Markdown nests a line under a numbered item only when it is
            # indented by the width of the number, its full stop and the space.
            pad = " " * (len(str(i)) + 2)
            pid = text(field(p, "id"))
            assumptions = _auxiliaries(pid, aux)
            if assumptions:
                lines.append(f"{pad}- Auxiliary assumptions: {', '.join(assumptions)}")
            named = str_list(field(p, "diagnostic_vs"))
            rivals = list(dict.fromkeys(d for d in named if d in alt_ids))
            if rivals:
                lines.append(f"{pad}- Rivals it discriminates: {', '.join(rivals)}")
            lines.append(f"{pad}- Test record: {_test_record(pid, tos)}")
        lines += _sampling_plan(preds)

    lines += ["", _IMPLIED_HEADING, *_implied(data)]

    # The values grade the form of each claim before any data (API_SPEC section
    # 9). They say nothing of how severely a claim is tested, and the heading
    # says so.
    lines += ["", "## Severity (pre-data rubric of claim form)"]
    sev = _severity(data)
    if not sev:
        lines.append("_No predictions specified._")
    else:
        for s in sev:
            pid, cs, rk = s["prediction_id"], _fmt(s["computed_severity"]), _fmt(s["risk_score"])
            lines.append(f"- {pid}: severity {cs}, risk {rk}")

    doc = "\n".join(lines) + "\n"
    if path is not None:
        _write_lf(path, doc)
    return doc
