"""Development mode. Progressive-versus-degenerating amendment appraisal.

This operationalises the Lakatosian distinction (Lakatos, 1970; Meehl, 1990). An amendment is
progressive if it yields newly corroborated predictions without ad-hoc immunising assumptions.
"""
from __future__ import annotations

from ._access import field, items, str_list, text
from .rigor import _passed_for


def appraise_amendment(new, prior) -> dict:
    """Appraise an amendment as progressive, degenerating, or neutral relative to a prior version.

    Raises:
        ValueError: ``new`` and ``prior`` are the same object. The builders
            work in place, so ``new = prior.add_prediction(...)`` makes the two
            one object, which can only be appraised as ``neutral``. Begin the
            amendment with ``prior.copy()``. Two distinct objects with equal
            content are appraised as usual.

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
    # Only identity is refused. Equal content in two objects is a legitimate
    # comparison, which R appraises as neutral, so it must pass here too.
    if new is prior:
        raise ValueError(
            "appraise_amendment needs two distinct theory objects, but the amendment and "
            "the prior are the same object. The Python builders change a theory in place, "
            "so start the amendment from prior.copy()."
        )

    # A missing id reads as "" (API_SPEC.md section 3, "Reading a theory"), as
    # in R. validate() reports the entry; the appraisal still runs.
    prior_pred_ids = {text(field(p, "id")) for p in items(prior, "predictions")}
    prior_aux_ids = {text(field(a, "id")) for a in items(prior, "auxiliary_assumptions")}
    tos = items(new, "test_outcomes")

    new_predictions = [pid for pid in (text(field(p, "id")) for p in items(new, "predictions"))
                       if pid not in prior_pred_ids]
    corroborated_new = [pid for pid in new_predictions if any(_passed_for(t, (pid,)) for t in tos)]

    ad_hoc = []
    for a in items(new, "auxiliary_assumptions"):
        aid = text(field(a, "id"))
        if aid in prior_aux_ids:
            continue
        if field(a, "added_for") is None:
            continue
        protects = str_list(field(a, "protects"))
        if not any(_passed_for(t, protects) for t in tos):
            ad_hoc.append(aid)

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
