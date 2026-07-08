"""The severity rubric, a documented and deterministic operationalisation (API_SPEC.md section 9)."""
from __future__ import annotations

from ._num import rnd

BASE = {"existence": 0.1, "directional": 0.4, "interval": 0.7, "point": 0.9}
CRUD = 0.25  # Meehl (1990) ambient-correlation discount for directional predictions


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def severity(T) -> list[dict]:
    """Per-prediction risk and computed severity, in file order.

    References:
        Mayo, D. G. (2018). Statistical inference as severe testing. Cambridge
        University Press. https://doi.org/10.1017/9781107286184
        Meehl, P. E. (1990). Why summaries of research on psychological theories
        are often uninterpretable. Psychological Reports, 66, 195-244.
        https://doi.org/10.2466/pr0.1990.66.1.195
    """
    T = T.data if hasattr(T, "data") else T
    preds = _list(T, "predictions")
    alt_ids = {a.get("id") for a in _list(T, "alternatives")}
    out = []
    for p in preds:
        typ = p.get("type")
        base = BASE.get(typ, 0.0)
        discounted = base * (1 - CRUD) if typ == "directional" else base
        dv = p.get("diagnostic_vs") or []
        diag_bonus = 0.1 if dv and any(d in alt_ids for d in dv) else 0.0
        out.append({
            "prediction_id": p.get("id"),
            "type": typ,
            "risk_score": rnd(base, 3),
            "computed_severity": rnd(min(1.0, discounted + diag_bonus), 3),
        })
    return out
