"""Preregistration document export. Deterministic markdown output."""
from __future__ import annotations

from pathlib import Path

from .rigor import _as_list
from .rigor import check as _check
from .scoring import severity as _severity


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


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
        f"# Preregistration: {data.get('title', '')}",
        "",
        f"- Theory ID: {data.get('id', '')}",
        f"- Schema version: {data.get('schema_version', '')}",
        f"- Maturity: {data.get('maturity', '')}",
        f"- Derivation chain verified: {verified}",
        "",
        "## Hypotheses",
    ]
    preds = _list(data, "predictions")
    if not preds:
        lines.append("_No predictions specified._")
    else:
        for i, p in enumerate(preds, start=1):
            df = _as_list(p.get("derives_from"))
            df_txt = ", ".join(df) if df else "—"
            lines.append(f"{i}. [{p.get('type')}] {p.get('statement')} (derives from: {df_txt})")

    lines += ["", "## Severity"]
    sev = _severity(data)
    if not sev:
        lines.append("_No predictions specified._")
    else:
        for s in sev:
            pid, cs, rk = s["prediction_id"], _fmt(s["computed_severity"]), _fmt(s["risk_score"])
            lines.append(f"- {pid}: severity {cs}, risk {rk}")

    text = "\n".join(lines) + "\n"
    if path is not None:
        Path(path).write_bytes(text.encode("utf-8"))
    return text
