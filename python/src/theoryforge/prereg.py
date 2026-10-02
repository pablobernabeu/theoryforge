"""Preregistration document export. Deterministic markdown output."""
from __future__ import annotations

from ._access import MATURITY, PRED_TYPE, enum, field, items, str_list, text
from ._io import write_lf as _write_lf
from .rigor import check as _check
from .scoring import severity as _severity


def _fmt(x) -> str:
    """Format a number identically across languages: 3dp, trailing zeros stripped,
    at least one decimal kept (1.0 -> '1.0', 0.667 -> '0.667')."""
    s = f"{float(x):.3f}".rstrip("0")
    return s + "0" if s.endswith(".") else s


def preregister(T, path=None) -> str:
    """Render a preregistration document, writing it to ``path`` when one is given."""
    data = T.data if hasattr(T, "data") else T
    rep = _check(data)
    deriv = next((it for it in rep["items"] if it["id"] == "derivation_chain"), None)
    verified = "yes" if deriv and deriv["status"] == "pass" else "no"

    lines = [
        f"# Preregistration: {text(data.get('title'))}",
        "",
        f"- Theory ID: {text(data.get('id'))}",
        f"- Schema version: {text(data.get('schema_version'))}",
        f"- Maturity: {enum(data.get('maturity'), MATURITY) or ''}",
        f"- Derivation chain verified: {verified}",
        "",
        "## Hypotheses",
    ]
    preds = items(data, "predictions")
    if not preds:
        lines.append("_No predictions specified._")
    else:
        for i, p in enumerate(preds, start=1):
            df = str_list(field(p, "derives_from"))
            df_txt = ", ".join(df) if df else "—"
            ptype = enum(field(p, "type"), PRED_TYPE) or ""
            lines.append(f"{i}. [{ptype}] {text(field(p, 'statement'))} (derives from: {df_txt})")

    # The values grade the form of each claim before any data (API_SPEC section
    # 9). They say nothing of how severely a claim is tested, and the heading
    # says so.
    lines += ["", "## Severity (pre-data rubric of claim form)"]
    sev = _severity(data)
    if not sev:
        lines.append("_No predictions specified._")
    else:
        for s in sev:
            pid, cs, rk = s["prediction_id"], _fmt(s["computed_severity"]), _fmt(s["risk_score"])
            lines.append(f"- {pid}: severity {cs}, risk {rk}")

    doc = "\n".join(lines) + "\n"
    if path is not None:
        _write_lf(path, doc)
    return doc
