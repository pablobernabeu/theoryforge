"""Prediction statuses, content keys and the ad hoc test (API_SPEC.md section 10).

The amendment appraisal reads its evidence through these helpers. R's
``develop.R`` holds the same three (``.tf_prediction_status``,
``.tf_content_key``, ``.tf_classify_auxiliary``).
"""
from __future__ import annotations

from ._access import PRED_TYPE, enum, field, str_list, text
from ._text import squish

CORROBORATED = "corroborated"


def prediction_status(pid: str, tos) -> str:
    """The status of prediction ``pid`` over every test outcome in ``tos``.

    ``corroborated`` when at least one outcome passed and none failed,
    ``refuted`` when some failed and none passed, ``mixed`` when both occur and
    ``untested`` otherwise. The order of the outcomes is not read, and neither
    are their dates, which the schema leaves free-form. An outcome counts only
    when its ``prediction_id`` is the string ``pid``, and a missing or null
    ``passed`` is neither a pass nor a failure.
    """
    passed = failed = False
    for t in tos:
        tid = field(t, "prediction_id")
        if not (isinstance(tid, str) and tid == pid):
            continue
        outcome = field(t, "passed")
        if outcome is True:
            passed = True
        elif outcome is False:
            failed = True
    if passed:
        return "mixed" if failed else CORROBORATED
    return "refuted" if failed else "untested"


def content_key(p) -> tuple[str, str]:
    """What a prediction claims: its statement with whitespace runs squished, and its type.

    Two predictions with the same key make the same claim whatever their ids,
    so a prediction that changed only its id, or the line breaks of its
    statement, is the same content. A type outside its enum reads as ``""``.
    """
    return squish(text(field(p, "statement"))), enum(field(p, "type"), PRED_TYPE) or ""


def classify_auxiliary(a, tos, eligible) -> tuple[str, list[dict]]:
    """The ad hoc class of an assumption added for an anomaly, with the evidence for it.

    The independent predictions are the distinct entries of the assumption's
    ``protects``, in their order, that are in ``eligible`` and are not its
    ``added_for``: what could support the assumption other than the anomaly it
    answers. Each is returned with its status in ``tos``. The class is
    ``ad_hoc1`` when there are none, so the assumption adds nothing that could
    be tested apart from the anomaly, ``ad_hoc2`` when none is corroborated and
    ``independently_corroborated`` otherwise. The amendment appraisal passes the
    predictions that are new in the amended version as ``eligible``, so content
    the prior already held cannot clear an assumption.
    """
    added_for = text(field(a, "added_for"))
    independent: list[str] = []
    for q in str_list(field(a, "protects")):
        if q != added_for and q in eligible and q not in independent:
            independent.append(q)
    records = [{"id": q, "status": prediction_status(q, tos)} for q in independent]
    if not records:
        return "ad_hoc1", records
    if all(r["status"] != CORROBORATED for r in records):
        return "ad_hoc2", records
    return "independently_corroborated", records
