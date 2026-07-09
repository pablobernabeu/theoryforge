"""Development mode. Progressive-versus-degenerating amendment appraisal (API_SPEC.md section 10).

This operationalises the Lakatosian distinction (Lakatos, 1970; Meehl, 1990). An amendment is
progressive if it yields newly corroborated predictions without ad-hoc immunising assumptions.
"""
from __future__ import annotations

from .rigor import _as_list


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def appraise_amendment(new, prior) -> dict:
    """Appraise an amendment as progressive, degenerating, or neutral relative to a prior version.

    References:
        Lakatos, I. (1970). Falsification and the methodology of scientific
        research programmes. In Criticism and the growth of knowledge
        (pp. 91-196). Cambridge University Press.
        https://doi.org/10.1017/cbo9781139171434.009
        Meehl, P. E. (1990). Appraising and amending theories. Psychological
        Inquiry, 1(2), 108-141. https://doi.org/10.1207/s15327965pli0102_1
    """
    new = new.data if hasattr(new, "data") else new
    prior = prior.data if hasattr(prior, "data") else prior

    prior_pred_ids = {p.get("id") for p in _list(prior, "predictions")}
    prior_aux_ids = {a.get("id") for a in _list(prior, "auxiliary_assumptions")}
    tos = _list(new, "test_outcomes")

    def passed(pid: str) -> bool:
        return any(t.get("prediction_id") == pid and t.get("passed") is True for t in tos)

    new_predictions = [p.get("id") for p in _list(new, "predictions") if p.get("id") not in prior_pred_ids]
    corroborated_new = [pid for pid in new_predictions if passed(pid)]

    ad_hoc = []
    for a in _list(new, "auxiliary_assumptions"):
        if a.get("id") in prior_aux_ids:
            continue
        if a.get("added_for") is None:
            continue
        protects = _as_list(a.get("protects"))
        if not any(t.get("prediction_id") in protects and t.get("passed") is True for t in tos):
            ad_hoc.append(a.get("id"))

    if len(corroborated_new) >= 1 and len(ad_hoc) == 0:
        verdict = "progressive"
    elif len(ad_hoc) >= 1 and len(corroborated_new) == 0:
        verdict = "degenerating"
    else:
        verdict = "neutral"

    return {
        "verdict": verdict,
        "new_predictions": sorted(new_predictions),
        "corroborated_new": sorted(corroborated_new),
        "ad_hoc_assumptions": sorted(ad_hoc),
    }
