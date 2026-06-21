"""The theory-rigor checklist engine. See API_SPEC.md section 4 for the contract."""
from __future__ import annotations

import json

from . import _resources
from ._num import rnd
from .redundancy import jaccard, tokens

_CAUSAL = {"causes", "increases", "decreases"}
_FORBIDDING = {"point", "interval", "directional"}
_PRECISE = {"point", "interval"}


def _ne_str(v) -> bool:
    return isinstance(v, str) and v.strip() != ""


def _ne_list(v) -> bool:
    return isinstance(v, list) and len(v) > 0


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def _mean(xs):
    return sum(xs) / len(xs)


def _check_items(T: dict, thr: dict) -> dict:
    preds = _list(T, "predictions")
    cons = _list(T, "constructs")
    props = _list(T, "propositions")
    aux = _list(T, "auxiliary_assumptions")
    alts = _list(T, "alternatives")
    tos = _list(T, "test_outcomes")
    prop_ids = {p.get("id") for p in props}
    alt_ids = {a.get("id") for a in alts}
    out: dict[str, tuple[str, float]] = {}

    # 1 falsifiability
    forbidding = [p for p in preds if p.get("type") in _FORBIDDING]
    out["falsifiability"] = ("pass", 1.0) if len(forbidding) >= 1 else ("fail", 0.0)

    # 2 precision
    if not preds:
        out["precision"] = ("warn", 0.0)
    else:
        share = sum(1 for p in preds if p.get("type") in _PRECISE) / len(preds)
        out["precision"] = ("pass" if share >= thr["min_precision_share"] else "warn", rnd(share, 3))

    # 3 risk_severity
    sevs = [p["severity"] for p in preds if p.get("severity") is not None]
    if not sevs:
        out["risk_severity"] = ("warn", 0.0)
    else:
        m = _mean(sevs)
        out["risk_severity"] = ("pass" if m >= thr["min_severity"] else "warn", rnd(m, 3))

    # 4 parsimony
    ratio = len(aux) / max(1, len(props))
    ad_hoc = 0
    for x in aux:
        if x.get("added_for") is not None:
            protects = x.get("protects") or []
            ok = any(t.get("prediction_id") in protects and t.get("passed") is True for t in tos)
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
        toks = [tokens(c.get("definition", "")) for c in cons]
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
            if _ne_str(c.get("definition"))
            and _ne_list(c.get("measurement"))
            and _ne_list(c.get("boundary_conditions"))
        )
        frac = complete / len(cons)
        out["construct_clarity"] = ("pass" if frac == 1.0 else "warn", rnd(frac, 3))

    # 7 scope
    present = _ne_list(T.get("boundary_conditions")) or (
        bool(cons) and all(_ne_list(c.get("boundary_conditions")) for c in cons)
    )
    out["scope"] = ("pass", 1.0) if present else ("warn", 0.0)

    # 8 logical_why
    if not props:
        out["logical_why"] = ("warn", 0.0)
    else:
        frac = sum(1 for p in props if _ne_str(p.get("mechanism"))) / len(props)
        out["logical_why"] = ("pass" if frac == 1.0 else "warn", rnd(frac, 3))

    # 9 causal_testability
    causal = [p for p in props if p.get("relation") in _CAUSAL]
    out["causal_testability"] = ("pass", 1.0) if len(causal) >= 1 else ("warn", 0.0)

    # 10 diagnosticity
    if not preds:
        out["diagnosticity"] = ("warn", 0.0)
    else:
        diag = [
            p for p in preds
            if _ne_list(p.get("diagnostic_vs")) and any(d in alt_ids for d in p.get("diagnostic_vs"))
        ]
        out["diagnosticity"] = ("pass" if len(diag) >= 1 else "warn", rnd(len(diag) / len(preds), 3))

    # 11 formalization
    fm = T.get("formal_model")
    present = isinstance(fm, dict) and fm.get("type") not in (None, "none")
    out["formalization"] = ("pass", 1.0) if present else ("warn", 0.0)

    # 12 derivation_chain
    if not preds:
        out["derivation_chain"] = ("pass", 1.0)
    else:
        valid = [
            p for p in preds
            if _ne_list(p.get("derives_from")) and all(d in prop_ids for d in p.get("derives_from"))
        ]
        frac = len(valid) / len(preds)
        out["derivation_chain"] = ("pass" if frac == 1.0 else "fail", rnd(frac, 3))

    return out


def check(T) -> dict:
    """Compute the full rigor report (dict) for a Theory or theory mapping."""
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

    maturity = T.get("maturity", "")
    if maturity == "draft":
        gate = "advisory"
    else:
        gate = "blocked" if n_blockers_failed > 0 else "pass"

    return {
        "theory_id": T.get("id", ""),
        "schema_version": T.get("schema_version", ""),
        "maturity": maturity,
        "aggregate_score": rnd(weighted * 100, 1),
        "gate": gate,
        "n_blockers_failed": n_blockers_failed,
        "items": items,
    }


def report(T, format: str = "json") -> str:
    """Render the rigor report. format in {'json', 'html'}."""
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
            f'  <h2>Rigor report: {rep["theory_id"]}</h2>\n'
            f'  <p>Aggregate score: <strong>{rep["aggregate_score"]}</strong> &middot; '
            f'gate: <strong>{rep["gate"]}</strong></p>\n'
            f'  <table>\n    <tr><th>item</th><th>status</th><th>score</th><th>grounding</th></tr>\n'
            f'{rows}\n  </table>\n</section>\n'
        )
    raise ValueError(f"unknown report format: {format!r}")
