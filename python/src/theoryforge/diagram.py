"""Diagram intermediate representations. Byte-identical to the R output (API_SPEC.md section 5)."""
from __future__ import annotations

_CAUSAL = {"causes", "increases", "decreases"}
_TYPES = ("nomological_net", "provenance", "causal_dag", "development_roadmap",
          "pipeline", "context", "workflow", "venn", "rigor", "severity")


def _esc(s) -> str:
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


def _xml(s) -> str:
    return (str(s if s is not None else "")
            .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def _nomological_net(T: dict) -> str:
    lines = ["digraph nomological_net {", "  rankdir=LR;", "  node [shape=box, style=rounded];"]
    for c in _list(T, "constructs"):
        lines.append(f'  "{_esc(c.get("id"))}" [label="{_esc(c.get("label"))}"];')
    for p in _list(T, "propositions"):
        frm, to, rel = _esc(p.get("from")), _esc(p.get("to")), _esc(p.get("relation"))
        lines.append(f'  "{frm}" -> "{to}" [label="{rel}"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _provenance(T: dict) -> str:
    lines = ["digraph provenance {", "  rankdir=TB;", "  node [shape=box];"]
    steps = _list(T, "provenance")
    for i, s in enumerate(steps, start=1):
        action = str(s.get("action", "") or "")
        detail = str(s.get("detail", "") or "")
        label = f"{action}: {detail}" if detail.strip() else action
        lines.append(f'  "n{i}" [label="{_esc(label)}"];')
    for i in range(1, len(steps)):
        lines.append(f'  "n{i}" -> "n{i + 1}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _causal_dag(T: dict) -> str:
    lines = ["dag {"]
    for p in _list(T, "propositions"):
        if p.get("relation") in _CAUSAL:
            lines.append(f'  {p.get("from")} -> {p.get("to")}')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _development_roadmap(T: dict) -> str:
    from .rigor import check as _check
    rep = _check(T)
    todo = [it for it in rep["items"] if it["status"] != "pass"]
    lines = ["digraph development_roadmap {", "  rankdir=TB;", "  node [shape=box];"]
    if not todo:
        lines.append('  "all_checks_pass" [label="all checks pass"];')
    else:
        for it in todo:
            lines.append(f'  "{_esc(it["id"])}" [label="{_esc(it["id"])} ({it["status"]})"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _pipeline(T: dict) -> str:
    lines = ["digraph pipeline {", "  rankdir=LR;", "  node [shape=box];"]
    for p in _list(T, "predictions"):
        lines.append(f'  "{_esc(p.get("id"))}" [label="{_esc(p.get("type"))}"];')
    for t in _list(T, "test_outcomes"):
        rid = f'result_{t.get("prediction_id")}'
        passed = "true" if t.get("passed") is True else "false"
        lines.append(f'  "{_esc(rid)}" [label="passed={passed}"];')
        lines.append(f'  "{_esc(t.get("prediction_id"))}" -> "{_esc(rid)}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _context(T: dict) -> str:
    lines = ["digraph context {", "  rankdir=LR;", "  node [shape=box, style=rounded];"]
    lines.append(f'  "theory" [shape=ellipse, label="{_esc(T.get("title"))}"];')
    for c in _list(T, "constructs"):
        cid = _esc(c.get("id"))
        lines.append(f'  "{cid}" [label="{_esc(c.get("label"))}"];')
        lines.append(f'  "theory" -> "{cid}";')
    for i, bc in enumerate(_list(T, "boundary_conditions"), start=1):
        lines.append(f'  "scope{i}" [shape=note, label="{_esc(bc)}"];')
        lines.append(f'  "scope{i}" -> "theory" [style=dotted, label="holds within"];')
    for a in _list(T, "alternatives"):
        aid = _esc(a.get("id"))
        lines.append(f'  "{aid}" [shape=box, style=dashed, label="{_esc(a.get("label"))}"];')
        lines.append(f'  "theory" -> "{aid}" [style=dashed, label="contrasts with"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _workflow(T: dict) -> str:
    lines = ["digraph workflow {", "  rankdir=LR;", "  node [shape=box];"]
    lines.append("  subgraph cluster_build {")
    lines.append('    label="building";')
    for c in _list(T, "constructs"):
        lines.append(f'    "{_esc(c.get("id"))}" [label="{_esc(c.get("label"))}"];')
    lines.append("  }")
    lines.append("  subgraph cluster_relate {")
    lines.append('    label="propositions";')
    for p in _list(T, "propositions"):
        lines.append(f'    "prop_{_esc(p.get("id"))}" [label="{_esc(p.get("relation"))}"];')
    lines.append("  }")
    lines.append("  subgraph cluster_predict {")
    lines.append('    label="predictions";')
    for p in _list(T, "predictions"):
        lines.append(f'    "pred_{_esc(p.get("id"))}" [label="{_esc(p.get("type"))}"];')
    lines.append("  }")
    lines.append("  subgraph cluster_test {")
    lines.append('    label="testing";')
    for t in _list(T, "test_outcomes"):
        passed = "true" if t.get("passed") is True else "false"
        lines.append(f'    "outcome_{_esc(t.get("prediction_id"))}" [label="passed={passed}"];')
    lines.append("  }")
    for p in _list(T, "propositions"):
        lines.append(f'  "{_esc(p.get("from"))}" -> "prop_{_esc(p.get("id"))}";')
    for pred in _list(T, "predictions"):
        for src in (pred.get("derives_from") or []):
            lines.append(f'  "prop_{_esc(src)}" -> "pred_{_esc(pred.get("id"))}";')
    for t in _list(T, "test_outcomes"):
        pid = _esc(t.get("prediction_id"))
        lines.append(f'  "pred_{pid}" -> "outcome_{pid}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _circle(cx: int, cy: int, r: int) -> str:
    return (f'  <circle cx="{cx}" cy="{cy}" r="{r}" '
            'fill="#4e79a7" fill-opacity="0.35" stroke="#33567a"/>')


def _vlabel(x: int, y: int, s) -> str:
    return f'  <text x="{x}" y="{y}" text-anchor="middle">{_xml(s)}</text>'


def _vcount(x: int, y: int, k: int) -> str:
    return f'  <text x="{x}" y="{y}" text-anchor="middle" font-weight="bold">{k}</text>'


def _venn(T: dict) -> str:
    """Construct scope overlap: the first up to three constructs as sets of their
    boundary conditions, drawn as a fixed-layout (integer-coordinate) Venn diagram."""
    constructs = _list(T, "constructs")[:3]
    names, sets = [], []
    for c in constructs:
        bc = c.get("boundary_conditions")
        names.append(str(c.get("label") or c.get("id") or ""))
        sets.append(set(bc) if isinstance(bc, list) else set())
    n = len(constructs)
    out = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 300" '
           'font-family="sans-serif" font-size="13">',
           '  <text x="190" y="24" text-anchor="middle" font-size="15">Construct scope overlap</text>']
    if n == 0:
        out.append(_vlabel(190, 150, "(no constructs)"))
    elif n == 1:
        a = sets[0]
        out += [_circle(190, 150, 90), _vlabel(190, 55, names[0]), _vcount(190, 155, len(a))]
    elif n == 2:
        a, b = sets[0], sets[1]
        out += [_circle(150, 150, 90), _circle(230, 150, 90),
                _vlabel(110, 50, names[0]), _vlabel(270, 50, names[1]),
                _vcount(110, 155, len(a - b)), _vcount(190, 155, len(a & b)),
                _vcount(270, 155, len(b - a))]
    else:
        a, b, c = sets[0], sets[1], sets[2]
        out += [_circle(150, 135, 85), _circle(230, 135, 85), _circle(190, 195, 85),
                _vlabel(110, 45, names[0]), _vlabel(270, 45, names[1]), _vlabel(190, 290, names[2]),
                _vcount(120, 115, len(a - b - c)), _vcount(260, 115, len(b - a - c)),
                _vcount(190, 230, len(c - a - b)), _vcount(190, 105, len((a & b) - c)),
                _vcount(145, 180, len((a & c) - b)), _vcount(235, 180, len((b & c) - a)),
                _vcount(190, 160, len(a & b & c))]
    out.append("</svg>")
    return "\n".join(out) + "\n"


_STATUS_COLOR = {"pass": "#4caf50", "warn": "#ff9800", "fail": "#f44336"}


def _rigor(T: dict) -> str:
    """The rigour checklist as a colour-coded status grid (SVG)."""
    from .rigor import check as _check
    rep = _check(T)
    items = rep["items"]
    h = 60 + len(items) * 24 + 12
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 460 {h}" '
           'font-family="sans-serif" font-size="13">',
           '  <text x="20" y="28" font-size="15">Rigour checklist</text>',
           f'  <text x="20" y="46">aggregate score {rep["aggregate_score"]:.1f}, gate {rep["gate"]}</text>']
    for i, it in enumerate(items):
        y = 60 + i * 24
        color = _STATUS_COLOR.get(it["status"], "#9e9e9e")
        out.append(f'  <rect x="20" y="{y}" width="16" height="16" rx="3" fill="{color}"/>')
        out.append(f'  <text x="44" y="{y + 12}">{_xml(it["id"])}</text>')
        out.append(f'  <text x="320" y="{y + 12}">{_xml(it["status"])}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def _severity_chart(T: dict) -> str:
    """Per-prediction computed severity as horizontal bars (SVG)."""
    from .scoring import severity as _sev
    rows = _sev(T)
    h = 40 + max(len(rows), 1) * 28 + 8
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 380 {h}" '
           'font-family="sans-serif" font-size="13">',
           '  <text x="20" y="26" font-size="15">Prediction severity</text>']
    if not rows:
        out.append('  <text x="20" y="54">(no predictions)</text>')
    for i, r in enumerate(rows):
        y = 40 + i * 28
        sev = r["computed_severity"]
        w = int(sev * 200 + 0.5 + 1e-6)
        out.append(f'  <text x="20" y="{y + 12}">{_xml(r["prediction_id"])}</text>')
        out.append(f'  <rect x="130" y="{y}" width="{w}" height="16" rx="2" fill="#4e79a7"/>')
        out.append(f'  <text x="{135 + w}" y="{y + 12}">{sev:.3f}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def diagram(T: dict, type: str = "nomological_net", engine: str = "graphviz") -> str:
    """Return the diagram IR string for the requested type.

    ``engine`` is accepted for API parity; the IR is engine-independent (DOT for
    the digraphs, dagitty syntax for the causal DAG, and SVG for the Venn, the
    rigor grid, and the severity chart).
    """
    T = T.data if hasattr(T, "data") else T
    if type == "nomological_net":
        return _nomological_net(T)
    if type == "provenance":
        return _provenance(T)
    if type == "causal_dag":
        return _causal_dag(T)
    if type == "development_roadmap":
        return _development_roadmap(T)
    if type == "pipeline":
        return _pipeline(T)
    if type == "context":
        return _context(T)
    if type == "workflow":
        return _workflow(T)
    if type == "venn":
        return _venn(T)
    if type == "rigor":
        return _rigor(T)
    if type == "severity":
        return _severity_chart(T)
    raise ValueError(f"unknown diagram type {type!r}; expected one of {_TYPES}")
