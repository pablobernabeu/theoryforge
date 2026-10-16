"""The theory-rigour checklist engine. Scores a theory against the vendored 12-item checklist."""
from __future__ import annotations

import json
import math

from . import _resources
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
from ._num import rnd
from ._relations import DIRECTED
from ._status import classify_auxiliary
from .diagram import _xml
from .redundancy import _pairs
from .scoring import severity as _rubric

_FORBIDDING = {"point", "interval", "directional"}
_PRECISE = {"point", "interval"}
# The schema's formal-model types less "none", which declares that there is no model.
_FORMAL = FORMAL_MODEL_TYPE - {"none"}


def _ne_list(v) -> bool:
    """Whether a string array has an entry (API_SPEC.md section 4).

    A nonempty scalar string counts as a one-element array, as natural YAML such
    as ``derives_from: p1`` means, and an entry that is not a nonempty string
    does not count at all.
    """
    return len(str_list(v)) > 0


def _mean(xs):
    # A left fold in file order (API_SPEC.md section 4). CPython 3.12+ sum()
    # compensates and R's sum() keeps an extended accumulator on x86_64, so
    # either can differ from a plain double sum in the last bit, as for
    # (0.6, 0.7, 0.2).
    acc = 0.0
    for x in xs:
        acc += x
    return acc / len(xs)


def _ptype(p) -> str | None:
    return enum(field(p, "type"), PRED_TYPE)


def _refuse_non_boolean_outcomes(T, caller: str) -> None:
    """Refuse a test outcome whose ``passed`` is present and not a boolean.

    A quoted ``"true"`` read as a failure in both engines. The prediction then
    counted as uncorroborated and an assumption added for it as ad hoc, so an
    amendment that should be progressive came out degenerating. A missing or
    null ``passed`` still reads as not passed (API_SPEC.md section 4). The
    first offending outcome in file order is named.
    """
    for t in items(T, "test_outcomes"):
        passed = field(t, "passed")
        if passed is not None and not isinstance(passed, bool):
            raise ValueError(
                f"{caller} requires boolean test outcomes; "
                f"non-boolean passed for test outcome of prediction: {text(field(t, 'prediction_id'))}"
            )


def _check_items(T: dict, thr: dict) -> dict:
    """Each item's ``(status, score)``. An item with nothing to assess is ``("n/a", None)``."""
    preds = items(T, "predictions")
    cons = items(T, "constructs")
    props = items(T, "propositions")
    aux = items(T, "auxiliary_assumptions")
    alts = items(T, "alternatives")
    tos = items(T, "test_outcomes")
    prop_ids = {text(field(p, "id")) for p in props}
    alt_ids = {text(field(a, "id")) for a in alts}
    out: dict[str, tuple[str, float | None]] = {}

    # 1 falsifiability
    forbidding = [p for p in preds if _ptype(p) in _FORBIDDING]
    out["falsifiability"] = ("pass", 1.0) if len(forbidding) >= 1 else ("fail", 0.0)

    # 2 precision
    if not preds:
        out["precision"] = ("warn", 0.0)
    else:
        share = rnd(sum(1 for p in preds if _ptype(p) in _PRECISE) / len(preds), 3)
        out["precision"] = ("pass" if share >= thr["min_precision_share"] else "warn", share)

    # 3 risk_severity
    # Every prediction counts, with its declared severity when it has one and
    # the claim-form rubric's computed_severity otherwise. Skipping undeclared
    # predictions scored a theory built without severities 0.0 however risky
    # its claims, and let one declared value stand for a list of undeclared
    # claims.
    # A non-numeric severity has no defensible mean, and the two engines read
    # one differently by accident (R's as.numeric() coerced quoted numbers and
    # scored, Python crashed mid-sum), so the same file produced a verdict in
    # one language and a raw TypeError in the other. Refuse instead of
    # coercing; validate(full=True) reports the same file as invalid. An
    # infinity has no mean either, and a finite value outside [0, 1] would put
    # the score outside the checklist's scale (a severity of 7 could lift the
    # aggregate above 100). The status compares the rounded mean with the threshold, so the
    # last bit of the sum cannot decide it.
    sevs = []
    for p, r in zip(preds, _rubric(T), strict=True):
        s = field(p, "severity")
        if s is None:
            sevs.append(r["computed_severity"])
            continue
        if (isinstance(s, bool) or not isinstance(s, (int, float))
                or (isinstance(s, float) and not math.isfinite(s))):
            raise ValueError(
                "check requires numeric prediction severities; "
                f"non-numeric severity for prediction: {text(field(p, 'id'))}"
            )
        if s < 0 or s > 1:
            raise ValueError(
                "check requires prediction severities within [0, 1]; "
                f"out-of-range severity for prediction: {text(field(p, 'id'))}"
            )
        sevs.append(s)
    if not sevs:
        out["risk_severity"] = ("warn", 0.0)
    else:
        m = rnd(_mean(sevs), 3)
        out["risk_severity"] = ("pass" if m >= thr["min_severity"] else "warn", m)

    # 4 parsimony
    # Only an assumption added for an anomaly, one whose added_for names the
    # prediction it answers, is assessed. It is ad hoc, and fails the item, when
    # nothing it protects besides the anomaly is corroborated, by the rule of
    # the amendment appraisal (_status.classify_auxiliary). With no prior
    # version to compare, every prediction it protects counts, so
    # appraise_amendment(), which counts only the content an amendment adds, is
    # the authoritative check. Core assumptions are not counted: every
    # derivation uses auxiliaries (Meehl, 1990a), and a ratio of assumptions to
    # propositions penalised declaring them.
    defensive = [x for x in aux if ne_str(text(field(x, "added_for")))]
    if not defensive:
        out["parsimony"] = ("n/a", None)
    else:
        ad_hoc = [x for x in defensive
                  if classify_auxiliary(x, tos, str_list(field(x, "protects")))[0]
                  != "independently_corroborated"]
        out["parsimony"] = ("fail", 0.0) if ad_hoc else ("pass", 1.0)

    # 5 non_redundancy
    # The item follows the redundancy screen's flags (API_SPEC.md section 6).
    # Scoring 1 - max Jaccard docked points for vocabulary that sibling
    # constructs share, and the Jaccard ceiling alone missed a definition
    # contained in another.
    if len(cons) < 2:
        out["non_redundancy"] = ("n/a", None)
    else:
        flagged = any(r["flag"] == "review" for r in _pairs(T, thr))
        out["non_redundancy"] = ("warn", 0.0) if flagged else ("pass", 1.0)

    # 6 construct_clarity
    if not cons:
        out["construct_clarity"] = ("warn", 0.0)
    else:
        complete = sum(
            1 for c in cons
            if ne_str(field(c, "definition"))
            and _ne_list(field(c, "measurement"))
            and _ne_list(field(c, "boundary_conditions"))
        )
        frac = complete / len(cons)
        out["construct_clarity"] = ("pass" if frac == 1.0 else "warn", rnd(frac, 3))

    # 7 scope
    present = _ne_list(T.get("boundary_conditions")) or (
        bool(cons) and all(_ne_list(field(c, "boundary_conditions")) for c in cons)
    )
    out["scope"] = ("pass", 1.0) if present else ("warn", 0.0)

    # 8 logical_why
    if not props:
        out["logical_why"] = ("warn", 0.0)
    else:
        frac = sum(1 for p in props if ne_str(field(p, "mechanism"))) / len(props)
        out["logical_why"] = ("pass" if frac == 1.0 else "warn", rnd(frac, 3))

    # 9 causal_testability
    # Every relation that the relation table calls directed states an effect,
    # mediates and moderates included (API_SPEC.md section 28).
    causal = [p for p in props if enum(field(p, "relation"), RELATION) in DIRECTED]
    out["causal_testability"] = ("pass", 1.0) if len(causal) >= 1 else ("warn", 0.0)

    # 10 diagnosticity
    if not preds:
        out["diagnosticity"] = ("warn", 0.0)
    else:
        diag = [
            p for p in preds
            if any(d in alt_ids for d in str_list(field(p, "diagnostic_vs")))
        ]
        out["diagnosticity"] = ("pass" if len(diag) >= 1 else "warn", rnd(len(diag) / len(preds), 3))

    # 11 formalisation
    fm_type = enum(field(T.get("formal_model"), "type"), FORMAL_MODEL_TYPE)
    out["formalisation"] = ("pass", 1.0) if fm_type in _FORMAL else ("warn", 0.0)

    # 12 derivation_chain
    # With no prediction there is no derivation to check, which used to pass at
    # 1.0 and lift the empty theory's score.
    if not preds:
        out["derivation_chain"] = ("n/a", None)
    else:
        valid = [
            p for p in preds
            if _ne_list(field(p, "derives_from"))
            and all(d in prop_ids for d in str_list(field(p, "derives_from")))
        ]
        frac = len(valid) / len(preds)
        out["derivation_chain"] = ("pass" if frac == 1.0 else "fail", rnd(frac, 3))

    return out


def check(T) -> dict:
    """Compute the full rigour report (dict) for a Theory or theory mapping.

    Each item has a status (``pass``, ``warn`` or ``fail``) and a score in
    [0, 1]. An item with nothing to assess, such as the redundancy screen of a
    theory with one construct, has the status ``n/a`` and the score None, and
    is left out of the aggregate. The aggregate is the weighted mean of the
    applicable items' scores, times 100, and ``coverage`` is the share of the
    checklist's weight that was applicable (API_SPEC.md section 4).

    Raises:
        ValueError: a test outcome's ``passed`` is present and not a boolean,
            or a prediction's ``severity`` is not a finite number or lies
            outside [0, 1] (API_SPEC.md section 4, item 3).
            ``validate(full=True)`` reports both.
    """
    T = T.data if hasattr(T, "data") else T
    _refuse_non_boolean_outcomes(T, "check")
    spec = _resources.checklist()
    thr = spec["thresholds"]
    results = _check_items(T, thr)

    items = []
    weighted = 0.0
    applicable = 0.0
    n_blockers_failed = 0
    for spec_item in spec["items"]:
        iid = spec_item["id"]
        status, score = results[iid]
        # An item with nothing to assess is in neither sum. It used to score
        # 1.0, so the empty theory scored 26 and outscored a weak but real one.
        if score is not None:
            weighted += spec_item["weight"] * score
            applicable += spec_item["weight"]
        if spec_item["severity_if_fail"] == "blocker" and status == "fail":
            n_blockers_failed += 1
        items.append({
            "id": iid,
            "status": status,
            "score": score,
            "weight": spec_item["weight"],
            "severity_if_fail": spec_item["severity_if_fail"],
            "citation": spec_item["citation"],
        })

    # Nulls, numbers and sequences in these fields read as "" (API_SPEC.md
    # section 3, "Reading a theory"), and a maturity outside its enum is
    # absent. The report is compared across the twins, so the value printed
    # here must be one both engines can produce.
    maturity = enum(T.get("maturity"), MATURITY) or ""
    if maturity == "draft":
        gate = "advisory"
    else:
        gate = "blocked" if n_blockers_failed > 0 else "pass"

    return {
        "theory_id": text(T.get("id")),
        "schema_version": text(T.get("schema_version")),
        # Every number below comes from the checklist's weights and thresholds,
        # so two reports are only comparable if they were scored against the
        # same checklist. `schema_version` above is the theory's, not this.
        "checklist_version": spec.get("schema_version") or "",
        "maturity": maturity,
        # Nine of the twelve items always apply, so `applicable` is at least 0.74.
        "aggregate_score": rnd(weighted / applicable * 100, 1),
        "coverage": rnd(applicable, 3),
        "gate": gate,
        "n_blockers_failed": n_blockers_failed,
        "items": items,
    }


def report(T, format: str = "json") -> str:
    """Render the rigour report. format in {'json', 'html'}.

    The HTML fragment escapes every value it interpolates.
    """
    rep = check(T)  # check() unwraps Theory -> mapping
    if format == "json":
        return json.dumps(rep, indent=2, ensure_ascii=False)
    if format == "html":
        # Every interpolated value is escaped: the schema allows any non-empty id,
        # so '<' or '&' in it would otherwise reach the markup.
        rows = "\n".join(
            f'    <tr><td>{_xml(it["id"])}</td><td>{_xml(it["status"])}</td>'
            f'<td>{"n/a" if it["score"] is None else _xml(it["score"])}</td>'
            f'<td>{_xml(it["citation"])}</td></tr>'
            for it in rep["items"]
        )
        return (
            f'<section class="theoryforge-report">\n'
            f'  <h2>Rigour report: {_xml(rep["theory_id"])}</h2>\n'
            f'  <p>Aggregate score: <strong>{_xml(rep["aggregate_score"])}</strong> &middot; '
            f'gate: <strong>{_xml(rep["gate"])}</strong></p>\n'
            f'  <table>\n    <tr><th>item</th><th>status</th><th>score</th><th>grounding</th></tr>\n'
            f'{rows}\n  </table>\n</section>\n'
        )
    raise ValueError(f"unknown report format: {format!r}")
