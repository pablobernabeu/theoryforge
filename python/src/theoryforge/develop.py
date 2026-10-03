"""Development mode: the amendment appraisal (API_SPEC.md section 10).

Lakatos (1970, p. 118) calls a problemshift progressive when the new theory
predicts a fact its predecessor did not and some of that excess content is
corroborated, and degenerating when it is not. The appraisal therefore compares
what two versions of a theory claim, not the ids of their predictions. Meehl
(1990a) argues for appraising the amendments of a theory in these terms.
"""
from __future__ import annotations

from ._access import RELATION, enum, field, items, ne_str, str_list, text
from ._status import CORROBORATED, classify_auxiliary, content_key, prediction_status
from .rigor import _refuse_non_boolean_outcomes


def _proposition_content(p) -> tuple[str, str, str]:
    """What a proposition asserts: its endpoints and its relation, whatever its id."""
    return text(field(p, "from")), text(field(p, "to")), enum(field(p, "relation"), RELATION) or ""


def _registered_pass(t, pid: str) -> bool:
    """Whether outcome ``t`` is a pass of ``pid`` that names a preregistration."""
    tid = field(t, "prediction_id")
    return (isinstance(tid, str) and tid == pid and field(t, "passed") is True
            and ne_str(text(field(t, "registered"))))


def appraise_amendment(new, prior) -> dict:
    """Appraise an amendment as progressive, degenerating, or neutral relative to a prior version.

    The two versions are compared by content. A new prediction whose statement
    and type match a prediction the amendment dropped is that prediction
    renamed. A new prediction derived only from propositions the prior already
    held, and needing no new assumption, articulates old content. A prediction
    is corroborated when at least one test outcome passes it and none fails
    it. An assumption added for an anomaly (its ``added_for`` names the
    prediction it answers) is ad hoc unless a prediction it protects that is
    new in this version, other than the anomaly, is corroborated.

    The verdict is ``progressive`` when a corroborated new prediction is
    neither an articulation nor underived, no assumption is ad hoc and no
    corroborated prediction is dropped. It is ``degenerating`` when an
    assumption is ad hoc and no such prediction exists, and ``neutral``
    otherwise. Lakatos has only the first two. ``neutral`` is theoryforge's
    label for an amendment that meets neither rule, and the lists returned
    tell its cases apart.

    Returns:
        A dict whose keys follow API_SPEC.md section 10, with ``verdict``
        first and the four keys of 0.6.0 before the rest. ``new_predictions``,
        ``corroborated_new``, ``ad_hoc_assumptions``, ``articulated``,
        ``underived``, ``corroborated_new_registered``, ``dropped``,
        ``dropped_corroborated``, ``content_lost`` and ``new_anomalies`` are
        sorted id lists. ``renamed`` holds ``{prior, new}`` pairs sorted by
        ``new``, and ``assumptions`` one ``{id, added_for, class,
        independent}`` record per new assumption added for an anomaly, in
        file order. Only ``corroborated_new_registered`` reads ``registered``,
        and no date is read, so which version is the prior is the caller's
        responsibility.

    Raises:
        ValueError: ``new`` and ``prior`` are the same object. The builders
            work in place, so ``new = prior.add_prediction(...)`` makes the two
            one object, which can only be appraised as ``neutral``. Begin the
            amendment with ``prior.copy()``. Two distinct objects with equal
            content are appraised as usual.
        ValueError: a test outcome's ``passed`` is present and not a boolean,
            in ``new`` (checked first) or in ``prior``. A quoted ``"true"``
            read as a failure and could turn a progressive amendment into a
            degenerating one.

    References:
        Lakatos, I. (1970). Falsification and the methodology of scientific
        research programmes. In Criticism and the growth of knowledge
        (pp. 91-196). Cambridge University Press.
        https://doi.org/10.1017/cbo9781139171434.009
        Meehl, P. E. (1990a). Appraising and amending theories: The strategy of
        Lakatosian defense and two principles that warrant it. Psychological
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
    _refuse_non_boolean_outcomes(new, "appraise_amendment")
    _refuse_non_boolean_outcomes(prior, "appraise_amendment")

    # A missing id reads as "" (API_SPEC.md section 3, "Reading a theory"), as
    # in R. validate() reports the entry; the appraisal still runs.
    new_tos, prior_tos = items(new, "test_outcomes"), items(prior, "test_outcomes")
    new_preds, prior_preds = items(new, "predictions"), items(prior, "predictions")
    new_ids = [text(field(p, "id")) for p in new_preds]
    prior_ids = [text(field(p, "id")) for p in prior_preds]

    # A prediction under an id the prior lacks takes the first prior prediction
    # that makes the same claim, under an id the amendment dropped. A blank
    # statement claims nothing, so it is never matched.
    prior_keys = [content_key(p) for p in prior_preds]
    taken = [False] * len(prior_preds)
    renamed: list[dict[str, str]] = []
    for pid, p in zip(new_ids, new_preds, strict=True):
        key = content_key(p)
        if pid in prior_ids or not key[0]:
            continue
        for j, qid in enumerate(prior_ids):
            if not taken[j] and qid not in new_ids and prior_keys[j] == key:
                taken[j] = True
                renamed.append({"prior": qid, "new": pid})
                break
    renamed_new = {r["new"] for r in renamed}
    renamed_prior = {r["prior"] for r in renamed}

    new_predictions = [pid for pid in new_ids if pid not in prior_ids and pid not in renamed_new]
    corroborated_new = [pid for pid in new_predictions if prediction_status(pid, new_tos) == CORROBORATED]

    # Old content: a proposition whose endpoints and relation the prior holds,
    # under any id, so renaming a proposition adds nothing either.
    prior_aux_ids = {text(field(a, "id")) for a in items(prior, "auxiliary_assumptions")}
    new_aux = [a for a in items(new, "auxiliary_assumptions") if text(field(a, "id")) not in prior_aux_ids]
    protected = {q for a in new_aux for q in str_list(field(a, "protects"))}
    old_content = {_proposition_content(p) for p in items(prior, "propositions")}
    content_of: dict[str, tuple[str, str, str]] = {}
    for p in items(new, "propositions"):
        content_of.setdefault(text(field(p, "id")), _proposition_content(p))
    articulated: list[str] = []
    underived: list[str] = []
    for pid, p in zip(new_ids, new_preds, strict=True):
        if pid not in new_predictions:
            continue
        sources = str_list(field(p, "derives_from"))
        if not sources:
            underived.append(pid)
        elif pid not in protected and all(content_of.get(d) in old_content for d in sources):
            articulated.append(pid)

    dropped = [pid for pid in prior_ids if pid not in new_ids and pid not in renamed_prior]
    dropped_corroborated = [pid for pid in dropped if prediction_status(pid, prior_tos) == CORROBORATED]
    content_lost = [pid for pid in dropped if prediction_status(pid, prior_tos) == "untested"]

    retained = [(pid, pid) for pid in new_ids if pid in prior_ids]
    retained += [(r["prior"], r["new"]) for r in renamed]
    new_anomalies = [now for was, now in retained
                     if prediction_status(now, new_tos) in ("refuted", "mixed")
                     and prediction_status(was, prior_tos) in (CORROBORATED, "untested")]

    assumptions: list[dict] = []
    ad_hoc: list[str] = []
    for a in new_aux:
        added_for = text(field(a, "added_for"))
        if not ne_str(added_for):
            continue
        aid = text(field(a, "id"))
        cls, independent = classify_auxiliary(a, new_tos, new_predictions)
        assumptions.append({"id": aid, "added_for": added_for, "class": cls, "independent": independent})
        if cls != "independently_corroborated":
            ad_hoc.append(aid)

    registered = [pid for pid in corroborated_new if any(_registered_pass(t, pid) for t in new_tos)]

    adds_content = [pid for pid in corroborated_new if pid not in articulated and pid not in underived]
    if adds_content and not ad_hoc and not dropped_corroborated:
        verdict = "progressive"
    elif ad_hoc and not adds_content:
        verdict = "degenerating"
    else:
        verdict = "neutral"

    return {
        "verdict": verdict,
        "new_predictions": sorted(new_predictions),
        "corroborated_new": sorted(corroborated_new),
        "ad_hoc_assumptions": sorted(ad_hoc),
        "articulated": sorted(articulated),
        "underived": sorted(underived),
        "corroborated_new_registered": sorted(registered),
        "renamed": sorted(renamed, key=lambda r: r["new"]),
        "dropped": sorted(dropped),
        "dropped_corroborated": sorted(dropped_corroborated),
        "content_lost": sorted(content_lost),
        "new_anomalies": sorted(new_anomalies),
        "assumptions": assumptions,
    }
