"""The claim-form riskiness rubric, a pre-data ranking of each prediction's claim.

The rubric reads a prediction's declared ``type`` and its ``diagnostic_vs`` ids.
It reads neither the statement nor any test, outcome or data.
"""
from __future__ import annotations

from ._access import PRED_TYPE, enum, field, items, str_list, text
from ._num import rnd

# The base riskiness of each claim form. The order follows Popper's (1959,
# sections 31-33) comparison of falsifiability by the subclass relation. Of two
# claims about one quantity, the one whose potential falsifiers include the
# other's is the more falsifiable, and an existence claim, a sign within it, a
# range within that sign and a value within that range form such a chain. The
# four values themselves are a package convention.
BASE = {"existence": 0.1, "directional": 0.4, "interval": 0.7, "point": 0.9}
# The discount on a directional prediction, also a package convention. Meehl
# (1967, 1990b) argues that predicting a sign alone risks little where almost
# everything correlates a little, but he gives no discount. His .25 and .30 are
# sizes of those ambient (crud) correlations, a different quantity from this
# discount.
CRUD = 0.25


def severity(T) -> list[dict]:
    """Per-prediction claim-form riskiness, in file order.

    A pre-data rubric of the form of each prediction's claim. ``risk_score`` is
    the base riskiness of the declared type: existence 0.1, directional 0.4,
    interval 0.7 and point 0.9. ``computed_severity`` discounts a directional
    prediction by 25 per cent, adds 0.1 when ``diagnostic_vs`` names a registered
    alternative and is capped at 1. The order of the types follows Popper (1959,
    sections 31-33) for nested claims about one quantity, and the directional
    penalty follows Meehl's (1967, 1990b) argument that a sign alone risks little.
    The base values, the discount and the bonus are the package's conventions,
    and neither source gives them.

    How severely a claim is tested depends on the design and the data, which the
    rubric does not read. A prediction scores the same however it is tested, and
    a failed test leaves the value where it was.

    References:
        Meehl, P. E. (1967). Theory-testing in psychology and physics: A
        methodological paradox. Philosophy of Science, 34(2), 103-115.
        https://doi.org/10.1086/288135
        Meehl, P. E. (1990b). Why summaries of research on psychological theories
        are often uninterpretable. Psychological Reports, 66(1), 195-244.
        https://doi.org/10.2466/pr0.1990.66.1.195
        Popper, K. R. (1959). The logic of scientific discovery. Hutchinson.
    """
    T = T.data if hasattr(T, "data") else T
    preds = items(T, "predictions")
    alt_ids = {text(field(a, "id")) for a in items(T, "alternatives")}
    out = []
    for p in preds:
        typ = enum(field(p, "type"), PRED_TYPE) or ""
        base = BASE.get(typ, 0.0)
        discounted = base * (1 - CRUD) if typ == "directional" else base
        dv = str_list(field(p, "diagnostic_vs"))
        # A package convention: naming a registered alternative the prediction
        # would discriminate from adds 0.1. The alternative is declared, not
        # checked against the statement.
        diag_bonus = 0.1 if any(d in alt_ids for d in dv) else 0.0
        out.append({
            "prediction_id": text(field(p, "id")),
            "type": typ,
            "risk_score": rnd(base, 3),
            "computed_severity": rnd(min(1.0, discounted + diag_bonus), 3),
        })
    return out
