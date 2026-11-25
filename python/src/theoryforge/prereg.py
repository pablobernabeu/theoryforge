"""Preregistration document export. Deterministic Markdown output."""
from __future__ import annotations

import math
import re

from ._access import (
    FORMAL_MODEL_TYPE,
    MATURITY,
    PRED_TYPE,
    RELATION,
    enum,
    field,
    items,
    ne_str,
    str_list,
    text,
)
from ._compat import theory_keyword
from ._io import write_lf as _write_lf
from ._num import number as _number
from .entailment import check_cycles, claim_line, prediction_verdicts, read_claim
from .entailment import entailments as _entailments
from .hashing import content_hash
from .implications import implications as _implications
from .rigor import check as _check
from .scoring import severity as _severity

# What the derivation line reports for each status of the checklist's
# derivation_chain item (API_SPEC.md section 11): whether every prediction
# cites declared propositions and, where it states a claim, whether the causal
# graph entails it.
_RESOLVE = {"pass": "yes", "fail": "no", "n/a": "not applicable (no predictions)"}

# How a rival's own propositions read a prediction's claim, beside the rival's id.
_RIVAL_READS = {"entailed": "its propositions entail the claim too",
                "contradicted": "its propositions contradict the claim",
                "undetermined": "its propositions leave the claim open"}

_IMPLIED_HEADING = "## Implied conditional independencies (derived from the causal graph, not predictions)"

_PLAN_HEADING = "## Sampling plan (author-recorded; not scored)"
_SIDED = ("two", "one")


# A line break inside a value would end the Markdown list item it is written
# into, so every run of them, with the spaces and tabs around it, becomes one
# space (API_SPEC.md section 11).
_BREAKS = re.compile(r"[ \t]*[\r\n]+[ \t]*")


def flat(s: str) -> str:
    """A text value written on one line."""
    return _BREAKS.sub(" ", s)


def _sentence(s: str) -> str:
    """``s`` ending in a full stop, a question mark or an exclamation mark."""
    s = s.rstrip(" ")
    return s if s.endswith((".", "?", "!")) else s + "."


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


def _region_text(p) -> str | None:
    """The region a prediction's ``bounds`` allow, as an interval, or None.

    An absent, infinite or null bound is open. A region that full validation
    would refuse, with no finite bound or a lower bound above the upper one, is
    not written.
    """
    b = field(p, "bounds")
    if not isinstance(b, dict):
        return None
    lo, hi = _number(b.get("lower")), _number(b.get("upper"))
    lo = lo if lo is not None and math.isfinite(lo) else None
    hi = hi if hi is not None and math.isfinite(hi) else None
    if (lo is None and hi is None) or (lo is not None and hi is not None and lo > hi):
        return None
    left = "(-inf" if lo is None else f"[{_plan_number(lo)}"
    right = "inf)" if hi is None else f"{_plan_number(hi)}]"
    return f"{left}, {right}"


def _theory_section(data: dict, cycles: str) -> list[str]:
    """The constructs, propositions, phenomena, assumptions, rivals and scope, in words."""
    out = ["", "## Theory", "", "### Constructs"]
    cons = items(data, "constructs")
    if not cons:
        out.append("_No constructs specified._")
    for c in cons:
        label, definition = flat(text(field(c, "label"))), flat(text(field(c, "definition")))
        line = f"- {text(field(c, 'id'))}" + (f" ({label})" if ne_str(label) else "") + ": "
        line += _sentence(definition) if ne_str(definition) else "No definition stated."
        measures = [flat(m) for m in str_list(field(c, "measurement"))]
        if measures:
            line += f" Measures: {'; '.join(measures)}."
        scope = [flat(b) for b in str_list(field(c, "boundary_conditions"))]
        if scope:
            line += f" Boundary conditions: {'; '.join(scope)}."
        out.append(line)
    out += ["", "### Propositions"]
    props = items(data, "propositions")
    if not props:
        out.append("_No propositions specified._")
    for p in props:
        rel = enum(field(p, "relation"), RELATION)
        frm, to = text(field(p, "from")), text(field(p, "to"))
        line = f"- {text(field(p, 'id'))}: " + (f"{frm} {rel} {to}." if rel
                                              else f"{frm} and {to}, with no relation stated.")
        mechanism = flat(text(field(p, "mechanism")))
        if ne_str(mechanism):
            line += f" Mechanism: {_sentence(mechanism)}"
        out.append(line)
    phenomena = items(data, "phenomena")
    if phenomena:
        out += ["", "### Phenomena to explain"]
        claims = _phenomenon_claims(data, cycles)
        for ph, claim in zip(phenomena, claims, strict=True):
            doi = text(field(ph, "source_doi"))
            out.append(f"- {text(field(ph, 'id'))}: {flat(text(field(ph, 'statement')))}"
                       + (f" (doi: {doi})" if ne_str(doi) else ""))
            if claim is not None:
                out.append(f"  - Claim: {claim}")
    aux = items(data, "auxiliary_assumptions")
    if aux:
        out += ["", "### Auxiliary assumptions"]
        for a in aux:
            added = text(field(a, "added_for"))
            kind = f"added for {added}" if ne_str(added) else "core"
            out.append(f"- {text(field(a, 'id'))} ({kind}): {flat(text(field(a, 'statement')))}")
    alts = items(data, "alternatives")
    if alts:
        out += ["", "### Rival accounts"]
        for a in alts:
            doi = text(field(a, "source_doi"))
            out.append(f"- {text(field(a, 'id'))}: {flat(text(field(a, 'label')))}"
                       + (f" (doi: {doi})" if ne_str(doi) else ""))
    scope = [flat(b) for b in str_list(data.get("boundary_conditions"))]
    if scope:
        out += ["", "### Scope", *(f"- {b}" for b in scope)]
    return out


def _phenomenon_claims(data: dict, cycles: str) -> list[str | None]:
    """The claim line of each phenomenon in file order, or None for one without a claim."""
    try:
        recs = iter([r for r in _entailments(data, cycles=cycles)["claims"]
                     if r["source"] == "phenomenon"])
        refused = False
    except ValueError:
        recs, refused = iter([]), True
    out: list[str | None] = []
    for ph in items(data, "phenomena"):
        c = read_claim(field(ph, "claim"))
        if c is None:
            out.append(None)
        elif refused:
            basis = "graph_refused" if c["ok"] else "malformed_claim"
            out.append(claim_line({**c, "verdict": "not_evaluated", "basis": basis, "via": []}))
        else:
            out.append(claim_line(next(recs)))
    return out


def _formal_model_line(data: dict) -> list[str]:
    """The formal-model line, when the theory declares a model of a schema type."""
    fm = data.get("formal_model")
    kind = enum(field(fm, "type"), FORMAL_MODEL_TYPE)
    if kind is None:
        return []
    ref = flat(text(field(fm, "spec_ref")))
    return [f"- Formal model: {kind}" + (f" ({ref})" if ne_str(ref) else "")]


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
        s = flat(text(block.get(key)))
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

    A theory without a plan therefore has no such section (API_SPEC.md section
    30).
    """
    plans = [(text(field(p, "id")), _plan(p)) for p in preds]
    if all(plan is None for _, plan in plans):
        return []
    return ["", _PLAN_HEADING,
            *(f"- {pid}: {plan if plan is not None else 'no sampling plan stated'}"
              for pid, plan in plans)]


_CYCLE = "implications requires an acyclic causal graph; cycle found: "


def _implied(data: dict, cycles: str) -> list[str]:
    """The lines of the implied-independencies section (API_SPEC.md section 11)."""
    try:
        imp = _implications(data, cycles=cycles)
    except ValueError as err:
        # A refusal: a feedback loop under the default, a repeated construct id
        # or a relation naming an undeclared construct. A loop is described for
        # a reader, and any other reason is reported as it is.
        msg = str(err)
        if msg.startswith(_CYCLE):
            loop = msg[len(_CYCLE):].split(";", 1)[0]
            return [f"_Not derived: the causal graph has a feedback loop, {loop}. With "
                    "cycles = 'sigma', the statements are read by sigma-separation and hold if "
                    "each loop settles to a unique equilibrium._"]
        return [f"_Not derived: {msg}._"]
    note = ([] if imp["acyclic"] else
            ["_Read by sigma-separation, since the causal graph has a feedback loop: each "
             "statement holds if every loop settles to a unique equilibrium._"])
    if imp["implications"]:
        # A code span keeps dagitty's notation whole, since Markdown reads the
        # underscores of " _||_ " as emphasis around the two bars.
        return note + [f"- `{i['statement']}`" for i in imp["implications"]]
    if not imp["constructs"]:
        return ["_None: the theory states no directed relation between constructs._"]
    if imp["inseparable"]:
        return note + ["_None: no set of constructs separates any pair the theory leaves unjoined._"]
    return note + ["_None: every pair of constructs in the causal graph is adjacent._"]


def _adjustment_line(rec: dict) -> str | None:
    """What an observational test of an effect claim must adjust for, or None."""
    if rec.get("identified") is None:
        return None
    if not rec["identified"]:
        return "none suffices"
    return ", ".join(rec["adjustment"]) or "none needed"


def _claim_lines(data: dict, cycles: str) -> tuple[list[tuple[str, str | None] | None],
                                                   list[dict | None]]:
    """For each prediction in file order, its claim and adjustment lines and its rivals' verdicts.

    A prediction that states no claim gets None (API_SPEC.md section 11).
    """
    verdicts = prediction_verdicts(data, cycles=cycles)
    try:
        recs = iter([r for r in _entailments(data, cycles=cycles)["claims"]
                     if r["source"] == "prediction"])
        refused = False
    except ValueError:
        recs, refused = iter([]), True
    lines: list[tuple[str, str | None] | None] = []
    for p in items(data, "predictions"):
        c = read_claim(field(p, "claim"))
        if c is None:
            lines.append(None)
        elif refused:
            basis = "graph_refused" if c["ok"] else "malformed_claim"
            lines.append((claim_line({**c, "verdict": "not_evaluated", "basis": basis, "via": []}), None))
        else:
            rec = next(recs)
            lines.append((claim_line(rec), _adjustment_line(rec)))
    return lines, verdicts


@theory_keyword
def preregister(theory, path=None, cycles: str = "refuse") -> str:
    """Render the theory and hypotheses sections of a preregistration, written to ``path`` if given.

    The header gives the theory id, the version when it has an id (with its
    parent, when one is named), the schema version, the maturity, the formal
    model when one is declared and the checklist's derivation check: ``yes``
    when every prediction cites declared propositions and the causal graph
    entails every claim it states, ``no`` otherwise and ``not applicable (no
    predictions)``.

    A theory section follows, so that the document can be read without the
    theory file: each construct with its label, definition, measures and
    boundary conditions, each proposition with its relation and mechanism, and,
    when the theory has them, the phenomena it sets out to explain with what
    the causal graph says of their claims, the auxiliary assumptions, the rival
    accounts and the scope.

    Each hypothesis is then listed in file order with its claim type,
    statement, prediction id and derivation, followed by the region its bounds
    allow, its claim and what the causal graph says of it, what an
    observational test of an effect claim must adjust for, the auxiliary
    assumptions that protect it (``core`` or ``added for <id>``), the
    registered rivals it is declared to discriminate, with how each rival's
    own propositions read the claim, and its test record. A hypothesis that a recorded outcome
    has already tested reads ``already tested: passed (<date>, registered
    <where>)``, one entry per outcome, and any other reads ``untested``.

    When at least one prediction states a sampling plan in its ``test`` block,
    a section headed ``Sampling plan (author-recorded; not scored)`` follows,
    with one line per prediction in file order. A line gives what is recorded
    of the planned sample, alpha and sidedness, smallest effect of interest,
    power or decision probability, design analysis and justification. A
    prediction without a plan reads ``no sampling plan stated``. Nothing
    scores the plan. The stated power raises no score, since more power
    weakens the corroboration a directional prediction earns (Meehl, 1967),
    though it decides how informative a failed test is (Lakens, 2022). A
    theory without a plan has no such section.

    A section then lists the conditional independencies that
    ``implications()`` derives from the causal graph, which are claims the
    theory makes without stating them, or says why there are none. ``cycles``
    is passed to it and to ``entailments()``: under the default, a graph with a
    feedback loop is not read, and with ``"sigma"`` it is read by
    sigma-separation. The claim-form severity rubric closes the document.
    Values are written on one line, so a line break inside a statement cannot
    end the list item it belongs to.

    The document is the part of a preregistration that the theory file holds.
    It is to be completed with the study design, the analysis plan, the
    inference criteria and whatever the sampling plan leaves out, the sections
    that a template such as PRP-QUANT asks for (Bosnjak et al., 2022).

    Raises:
        ValueError: when ``cycles`` is not ``"refuse"`` or ``"sigma"``, and
            when ``check()`` refuses the theory, because a test outcome's
            ``passed`` is present and not a boolean or a prediction's
            ``severity`` is not a finite number within [0, 1]. The message
            begins ``check requires``, and nothing is written.

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
    check_cycles(cycles, "preregister")
    data = theory.data if hasattr(theory, "data") else theory
    doc = "\n".join(document_lines(data, cycles)) + "\n"
    if path is not None:
        _write_lf(path, doc)
    return doc


def document_lines(data: dict, cycles: str, embedded: bool = False) -> list[str]:
    """The lines of the preregistration. ``embedded`` leaves out the severity
    section, which the dossier gives with the declared values beside it."""
    rep = _check(data)
    deriv = next((it for it in rep["items"] if it["id"] == "derivation_chain"), None)
    resolve = _RESOLVE[deriv["status"]] if deriv else "no"

    lines = [
        f"# Preregistration: {flat(text(data.get('title')))}",
        "",
        f"- Theory ID: {text(data.get('id'))}",
        *_version_line(data),
        f"- Schema version: {text(data.get('schema_version'))}",
        f"- Content hash: {content_hash(data)}",
        f"- Maturity: {enum(data.get('maturity'), MATURITY) or ''}",
        *_formal_model_line(data),
        f"- Derivations check: {resolve}",
        *_theory_section(data, cycles),
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
        claims, verdicts = _claim_lines(data, cycles)
        for i, p in enumerate(preds, start=1):
            df = str_list(field(p, "derives_from"))
            df_txt = ", ".join(df) if df else "—"
            ptype = enum(field(p, "type"), PRED_TYPE) or ""
            pid = text(field(p, "id"))
            ref = f"{pid}; " if ne_str(pid) else ""
            lines.append(f"{i}. [{ptype}] {flat(text(field(p, 'statement')))} "
                         f"({ref}derives from: {df_txt})")
            # Markdown nests a line under a numbered item only when it is
            # indented by the width of the number, its full stop and the space.
            pad = " " * (len(str(i)) + 2)
            region = _region_text(p)
            if region is not None:
                lines.append(f"{pad}- Region the claim allows: {region}")
            stated = claims[i - 1]
            if stated is not None:
                claim, adjust = stated
                lines.append(f"{pad}- Claim: {claim}")
                if adjust is not None:
                    lines.append(f"{pad}- Adjustment for an observational test: {adjust}")
            assumptions = _auxiliaries(pid, aux)
            if assumptions:
                lines.append(f"{pad}- Auxiliary assumptions: {', '.join(assumptions)}")
            named = str_list(field(p, "diagnostic_vs"))
            rivals = list(dict.fromkeys(d for d in named if d in alt_ids))
            if rivals:
                verdict = verdicts[i - 1]
                reads = verdict["rivals"] if verdict is not None else {}
                shown = [f"{d} ({_RIVAL_READS[reads[d]]})" if reads.get(d) in _RIVAL_READS else d
                         for d in rivals]
                lines.append(f"{pad}- Rivals it is declared to discriminate: {', '.join(shown)}")
            lines.append(f"{pad}- Test record: {_test_record(pid, tos)}")
        lines += _sampling_plan(preds)

    lines += ["", _IMPLIED_HEADING, *_implied(data, cycles)]
    if embedded:
        return lines

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

    return lines
