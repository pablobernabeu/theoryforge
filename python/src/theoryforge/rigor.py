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
from .redundancy import jaccard, tokens

_CAUSAL = {"causes", "increases", "decreases"}
_FORBIDDING = {"point", "interval", "directional"}
_PRECISE = {"point", "interval"}


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


def _passed_for(outcome, prediction_ids) -> bool:
    """Whether a test outcome records a pass for one of ``prediction_ids``.

    The outcome's ``prediction_id`` must be a string. R's ``%in%`` would match
    the number 1 against the id "1", and Python's ``in`` would not.
    """
    pid = field(outcome, "prediction_id")
    return isinstance(pid, str) and pid in prediction_ids and field(outcome, "passed") is True


def _check_items(T: dict, thr: dict) -> dict:
    preds = items(T, "predictions")
    cons = items(T, "constructs")
    props = items(T, "propositions")
    aux = items(T, "auxiliary_assumptions")
    alts = items(T, "alternatives")
    tos = items(T, "test_outcomes")
    prop_ids = {text(field(p, "id")) for p in props}
    alt_ids = {text(field(a, "id")) for a in alts}
    out: dict[str, tuple[str, float]] = {}

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
    for p in preds:
        s = field(p, "severity")
        if s is None:
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
    ratio = len(aux) / max(1, len(props))
    ad_hoc = 0
    for x in aux:
        if field(x, "added_for") is not None:
            protects = str_list(field(x, "protects"))
            ok = any(_passed_for(t, protects) for t in tos)
            if not ok:
                ad_hoc += 1
    score = rnd(max(0.0, 1.0 - ratio / thr["parsimony_ratio_max"]), 3)
    if ad_hoc > 0:
        out["parsimony"] = ("fail", 0.0)
    else:
        out["parsimony"] = ("pass" if ratio <= thr["parsimony_ratio_max"] else "warn", score)

    # 5 non_redundancy
    if len(cons) < 2:
        max_sim = 0.0
    else:
        toks = [tokens(text(field(c, "definition"))) for c in cons]
        max_sim = 0.0
        for i in range(len(toks)):
            for j in range(i + 1, len(toks)):
                max_sim = max(max_sim, jaccard(toks[i], toks[j]))
    out["non_redundancy"] = (
        "pass" if max_sim < thr["redundancy_similarity_max"] else "warn",
        rnd(1.0 - max_sim, 3),
    )

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
    causal = [p for p in props if enum(field(p, "relation"), RELATION) in _CAUSAL]
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
    present = fm_type not in (None, "none")
    out["formalisation"] = ("pass", 1.0) if present else ("warn", 0.0)

    # 12 derivation_chain
    if not preds:
        out["derivation_chain"] = ("pass", 1.0)
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

    Raises ValueError for a prediction severity that is not a finite number or
    lies outside [0, 1] (API_SPEC.md section 4, item 3).
    """
    T = T.data if hasattr(T, "data") else T
    spec = _resources.checklist()
    thr = spec["thresholds"]
    results = _check_items(T, thr)

    items = []
    weighted = 0.0
    n_blockers_failed = 0
    for spec_item in spec["items"]:
        iid = spec_item["id"]
        status, score = results[iid]
        weighted += spec_item["weight"] * score
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
        "aggregate_score": rnd(weighted * 100, 1),
        "gate": gate,
        "n_blockers_failed": n_blockers_failed,
        "items": items,
    }


def report(T, format: str = "json") -> str:
    """Render the rigour report. format in {'json', 'html'}."""
    rep = check(T)  # check() unwraps Theory -> mapping
    if format == "json":
        return json.dumps(rep, indent=2, ensure_ascii=False)
    if format == "html":
        rows = "\n".join(
            f'    <tr><td>{it["id"]}</td><td>{it["status"]}</td>'
            f'<td>{it["score"]}</td><td>{it["citation"]}</td></tr>'
            for it in rep["items"]
        )
        return (
            f'<section class="theoryforge-report">\n'
            f'  <h2>Rigour report: {rep["theory_id"]}</h2>\n'
            f'  <p>Aggregate score: <strong>{rep["aggregate_score"]}</strong> &middot; '
            f'gate: <strong>{rep["gate"]}</strong></p>\n'
            f'  <table>\n    <tr><th>item</th><th>status</th><th>score</th><th>grounding</th></tr>\n'
            f'{rows}\n  </table>\n</section>\n'
        )
    raise ValueError(f"unknown report format: {format!r}")
