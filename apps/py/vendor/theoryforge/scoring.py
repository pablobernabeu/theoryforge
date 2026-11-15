"""How risky each prediction's claim is before the data, and how severely it passed after.

``severity()`` is the claim-form riskiness rubric, a pre-data ranking that reads
a prediction's declared ``type`` and its ``diagnostic_vs`` ids and neither the
statement nor any test, outcome or data. ``post_data_severity()`` reads the data:
each test outcome's estimate and standard error, set against the region its
prediction's ``bounds`` state.
"""
from __future__ import annotations

import math

from ._access import PRED_TYPE, enum, field, items, str_list, text
from ._num import number, rnd

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


_REFUSAL = "post_data_severity requires "


def _phi(z: float) -> float:
    """The standard normal distribution function. R's twin calls ``pnorm()``.

    The two agree to within 2.2e-16, far inside the rounding grid of ``rnd``.
    """
    return 0.5 * math.erfc(-z / math.sqrt(2.0))


def _finite(x: float | None) -> float | None:
    return x if x is not None and math.isfinite(x) else None


def _outcome_row(t, i: int, preds: list) -> tuple[dict | None, str | None]:
    """The post-data severity of test outcome ``i``, or the refusal it meets.

    Returns ``(row, None)`` when the severity is computed and ``(None, message)``
    when the outcome or its prediction's bounds are refused. It returns
    ``(None, None)`` when there is nothing to compute: the outcome records
    neither an estimate nor a standard error, or names no prediction with
    bounds. A prediction's bounds are read only here, for an outcome whose data
    passed, so a theory without data is never refused for its bounds.
    """
    est_raw, se_raw = field(t, "estimate"), field(t, "se")
    if est_raw is None and se_raw is None:
        return None, None
    where = f"; test_outcome[{i}]"
    if est_raw is None or se_raw is None:
        return None, _REFUSAL + "both estimate and se" + where
    se = number(se_raw)
    if se is None or not math.isfinite(se) or se <= 0:
        return None, _REFUSAL + "a finite se greater than 0" + where
    est = number(est_raw)
    if est is None or not math.isfinite(est):
        return None, _REFUSAL + "a finite estimate" + where

    # The matching rule of the amendment appraisal (API_SPEC.md section 10):
    # the outcome's prediction_id must be a string, and the first prediction
    # with that id in file order is the one tested.
    pid = field(t, "prediction_id")
    if not isinstance(pid, str):
        return None, None
    pred = next((p for p in preds if text(field(p, "id")) == pid), None)
    bounds = field(pred, "bounds")
    if bounds is None:
        return None, None
    where = f"; prediction '{pid}'"
    # R builds an empty mapping and an empty sequence alike as list().
    if isinstance(bounds, list) and not bounds:
        bounds = {}
    if not isinstance(bounds, dict):
        return None, _REFUSAL + "bounds with numeric or null lower and upper" + where
    lo_raw, up_raw = bounds.get("lower"), bounds.get("upper")
    lo, up = number(lo_raw), number(up_raw)
    # A bound that is present and not a number would otherwise read as open
    # and turn a two-sided claim into a one-sided one.
    if (lo_raw is not None and lo is None) or (up_raw is not None and up is None):
        return None, _REFUSAL + "bounds with numeric or null lower and upper" + where
    lower, upper = _finite(lo), _finite(up)
    if lower is None and upper is None:
        return None, _REFUSAL + "at least one finite bound" + where
    if lo is not None and up is not None and lo > up:
        return None, _REFUSAL + "lower <= upper" + where

    zs = []
    if lower is not None:
        zs.append((est - lower) / se)
    if upper is not None:
        zs.append((upper - est) / se)
    sev = rnd(min(_phi(z) for z in zs), 3)
    return {"prediction_id": pid, "outcome": i, "lower": lower, "upper": upper,
            "estimate": est, "se": se, "severity": sev}, None


def outcome_rows(T) -> list[tuple[dict | None, str | None]]:
    """``_outcome_row`` for every test outcome, in file order.

    ``post_data_severity()`` raises the first refusal, and the dossier gives the
    rows it can compute without raising.
    """
    data = T.data if hasattr(T, "data") else T
    preds = items(data, "predictions")
    return [_outcome_row(t, i, preds) for i, t in enumerate(items(data, "test_outcomes"))]


def post_data_severity(T) -> list[dict]:
    """How severely each bounded claim passed its test, from the outcome's estimate and SE.

    A prediction states the region its claim allows in ``bounds``, a mapping of
    ``lower`` and ``upper``, either of which may be null (or infinite) for an
    open side. A test outcome records the ``estimate`` it observed and its
    standard error ``se``. For an outcome with both, whose prediction declares
    bounds, the severity with which the claim passed is the smallest of
    ``Phi((estimate - lower) / se)`` and ``Phi((upper - estimate) / se)`` over
    the finite bounds, rounded to three decimals (Mayo & Spanos, 2006, 2011).
    It is the probability that the test would have given a result less in
    accord with the claim, had the claim been false at the bound. A one-sided
    claim, such as an effect above a smallest effect of interest, is a lower
    bound with the upper one open.

    The computation is a normal approximation to the sampling distribution of
    the estimate. With two finite bounds, the value equals 1 minus the p value of
    the two one-sided tests (TOST) of equivalence. A point claim with lower
    equal to upper can pass with a severity of at most 0.5, so it needs a
    tolerance around its value. Unlike ``severity()``, which grades the form of
    a claim before any data, this value depends on the design and the data. The
    rigour checklist does not read it.

    Returns:
        One record per test outcome, in file order, that carries both an
        estimate and a standard error and whose prediction declares bounds:
        ``{prediction_id, outcome, lower, upper, estimate, se, severity}``.
        ``outcome`` is the outcome's 0-based index among the test outcomes, and
        an open bound is None.

    Raises:
        ValueError: for the first outcome, in file order, that cannot be read,
            with the R twin's text: ``post_data_severity requires both estimate
            and se; test_outcome[<i>]``, ``... requires a finite se greater than
            0; ...``, ``... requires a finite estimate; ...``, and for its
            prediction's bounds ``... requires bounds with numeric or null lower
            and upper; prediction '<id>'``, ``... requires at least one finite
            bound; ...`` and ``... requires lower <= upper; ...``.
            ``validate(full=True)`` reports each of these.

    References:
        Mayo, D. G., & Spanos, A. (2006). Severe testing as a basic concept in a
        Neyman-Pearson philosophy of induction. The British Journal for the
        Philosophy of Science, 57(2), 323-357. https://doi.org/10.1093/bjps/axl003
        Mayo, D. G., & Spanos, A. (2011). Error statistics. In P. S.
        Bandyopadhyay & M. R. Forster (Eds.), Philosophy of statistics (pp.
        153-198). Elsevier. https://doi.org/10.1016/B978-0-444-51862-0.50005-8
    """
    rows = []
    for row, refusal in outcome_rows(T):
        if refusal is not None:
            raise ValueError(refusal)
        if row is not None:
            rows.append(row)
    return rows
