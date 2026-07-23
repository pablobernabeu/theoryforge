"""Diagram intermediate representations. Deterministic string renderers for every diagram type."""
from __future__ import annotations

from .rigor import _as_list

_CAUSAL = {"causes", "increases", "decreases"}
_TYPES = ("nomological_net", "provenance", "causal_dag", "development_roadmap",
          "pipeline", "context", "workflow", "venn", "rigour", "severity")


def _esc(s) -> str:
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


def _xml(s) -> str:
    return (str(s if s is not None else "")
            .replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def _trunc(s, n: int) -> str:
    """Truncate an over-long label with an ellipsis. Identical to the R reference
    so SVG output stays byte-identical; a no-op for the short identifiers used."""
    s = str(s)
    return s if len(s) <= n else s[:n - 1] + "…"


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


# The Meridian palette the DOT views share: fill/border pairs keyed by role.
# These are part of the IR (both implementations emit them byte-identically),
# so a renderer needs no styling of its own.
_INK = "#12283A"
_FILL = {
    "construct":   ("#E4F1F1", "#1E7B7B"),
    "proposition": ("#FBF1DC", "#9C6B14"),
    "prediction":  ("#E7EDF5", "#33567A"),
    "passed":      ("#E5F2E7", "#3E7A46"),
    "failed":      ("#F9E5E4", "#B2453C"),
    "scope":       ("#FBF7EA", "#B49B55"),
    "rival":       ("#F1F1F1", "#8A8A8A"),
    "warn":        ("#FBF1DC", "#9C6B14"),
    "fail":        ("#F9E5E4", "#B2453C"),
    "covered":     ("#F1F1F1", "#8A8A8A"),
}


# How many advisory steps the development roadmap places side by side.
_ROADMAP_COLS = 3


def _fill(role: str) -> str:
    f, c = _FILL[role]
    return f'fillcolor="{f}", color="{c}"'


def _prelude(name: str, rankdir: str, directed: bool = True) -> list[str]:
    """The shared style header every DOT view opens with."""
    kw = "digraph" if directed else "graph"
    return [
        f"{kw} {name} {{",
        f'  graph [rankdir={rankdir}, bgcolor="transparent", fontname="Helvetica", '
        'fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];',
        '  node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", '
        f'color="#33567A", fillcolor="#F2F6F9", fontcolor="{_INK}", penwidth=1.1, '
        'margin="0.16,0.1"];',
        '  edge [fontname="Helvetica", fontsize=10, color="#7B909F", '
        'fontcolor="#0F6E6E", arrowsize=0.7];',
    ]


def _wrap(s, width: int = 18) -> str:
    """Escape a label and wrap it onto lines of at most `width` characters,
    breaking at spaces (a longer single word stays whole). Wrapping happens
    after escaping, and lines join with a literal backslash-n, DOT's in-label
    newline, so nodes stay narrow enough for a documentation column."""
    text = _esc(s)
    if not text:
        return ""
    lines, cur = [], ""
    for word in text.split(" "):
        if not cur:
            cur = word
        elif len(cur) + 1 + len(word) <= width:
            cur += " " + word
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return "\\n".join(lines)


def _nomological_net(T: dict) -> str:
    lines = _prelude("nomological_net", "LR")
    for c in _list(T, "constructs"):
        lines.append(f'  "{_esc(c.get("id"))}" [label="{_wrap(c.get("label"))}", {_fill("construct")}];')
    for p in _list(T, "propositions"):
        frm, to, rel = _esc(p.get("from")), _esc(p.get("to")), _esc(p.get("relation"))
        lines.append(f'  "{frm}" -> "{to}" [label="{rel}"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _provenance(T: dict) -> str:
    lines = _prelude("provenance", "TB")
    steps = _list(T, "provenance")
    for i, s in enumerate(steps, start=1):
        action = str(s.get("action", "") or "")
        detail = str(s.get("detail", "") or "")
        label = _esc(action) + ("\\n" + _wrap(detail, 26) if detail.strip() else "")
        lines.append(f'  "n{i}" [label="{label}"];')
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
    from . import _resources
    from .prereg import _fmt
    from .rigor import check as _check
    rep = _check(T)
    criterion = {it["id"]: it.get("criterion", "") for it in _resources.checklist()["items"]}
    todo = [it for it in rep["items"] if it["status"] != "pass"]
    # Blockers before advisories, and heavier checks before lighter ones. The
    # order is the recommendation: a reader who works down the column addresses
    # what gates the theory first, rather than whatever the checklist happens to
    # list first.
    rank = sorted(range(len(todo)), key=lambda i: (
        0 if todo[i]["severity_if_fail"] == "blocker" else 1, -todo[i]["weight"], i))
    todo = [todo[i] for i in rank]
    lines = _prelude("development_roadmap", "TB")
    # The hub names the theory and its standing, so the column beneath it reads
    # as this theory's outstanding work rather than an anonymous list.
    lines.append(f'  "roadmap" [shape=ellipse, label="{_wrap(T.get("title"), 20)}\\n'
                 f'score {_fmt(rep["aggregate_score"])}, gate {_esc(rep["gate"])}", '
                 f'fillcolor="{_INK}", color="{_INK}", fontcolor="#FFFFFF"];')
    if not todo:
        lines.append(f'  "all_checks_pass" [label="all checks pass", {_fill("passed")}];')
        lines.append('  "roadmap" -> "all_checks_pass";')
    else:
        for n, it in enumerate(todo, start=1):
            iid = _esc(it["id"])
            consequence = "blocks the gate" if it["severity_if_fail"] == "blocker" else "advisory"
            lines.append(f'  "{iid}" [label="{n}. {iid}\\n{_wrap(criterion.get(it["id"], ""), 22)}'
                         f'\\n{consequence}", {_fill(it["status"])}];')
        # What gates the theory runs down the spine one step at a time; the
        # advisories that follow are laid out several abreast, which keeps a
        # long list from growing into a strip too tall to take in at once.
        blockers = [it for it in todo if it["severity_if_fail"] == "blocker"]
        advisories = [it for it in todo if it["severity_if_fail"] != "blocker"]
        prev = "roadmap"
        for it in blockers:
            lines.append(f'  "{prev}" -> "{_esc(it["id"])}";')
            prev = _esc(it["id"])
        rows = [advisories[i:i + _ROADMAP_COLS] for i in range(0, len(advisories), _ROADMAP_COLS)]
        for r, row in enumerate(rows):
            head = _esc(row[0]["id"])
            if r == 0:
                lines.append(f'  "{prev}" -> "{head}";')
            else:
                lines.append(f'  "{_esc(rows[r - 1][0]["id"])}" -> "{head}" [style=invis];')
            if len(row) > 1:
                chain = " -> ".join(f'"{_esc(x["id"])}"' for x in row)
                lines.append(f"  {{ rank=same; {chain} [style=invis]; }}")
            else:
                lines.append(f'  {{ rank=same; "{head}"; }}')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _pipeline(T: dict) -> str:
    lines = _prelude("pipeline", "LR")
    for p in _list(T, "predictions"):
        pid = _esc(p.get("id"))
        lines.append(f'  "{pid}" [label="{pid}\\n{_esc(p.get("type"))}", {_fill("prediction")}];')
    for t in _list(T, "test_outcomes"):
        rid = f'result_{t.get("prediction_id")}'
        role = "passed" if t.get("passed") is True else "failed"
        lines.append(f'  "{_esc(rid)}" [label="{role}", {_fill(role)}];')
        lines.append(f'  "{_esc(t.get("prediction_id"))}" -> "{_esc(rid)}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _context(T: dict) -> str:
    lines = _prelude("context", "LR")
    lines.append(f'  "theory" [shape=ellipse, label="{_wrap(T.get("title"), 20)}", '
                 f'fillcolor="{_INK}", color="{_INK}", fontcolor="#FFFFFF"];')
    for c in _list(T, "constructs"):
        cid = _esc(c.get("id"))
        lines.append(f'  "{cid}" [label="{_wrap(c.get("label"))}", {_fill("construct")}];')
        lines.append(f'  "theory" -> "{cid}";')
    for i, bc in enumerate(_as_list(T.get("boundary_conditions")), start=1):
        lines.append(f'  "scope{i}" [shape=note, style="filled", label="{_wrap(bc)}", {_fill("scope")}];')
        lines.append(f'  "scope{i}" -> "theory" [style=dotted, label="holds within"];')
    for a in _list(T, "alternatives"):
        aid = _esc(a.get("id"))
        lines.append(f'  "{aid}" [style="rounded,filled,dashed", '
                     f'label="{_wrap(a.get("label"))}", {_fill("rival")}];')
        lines.append(f'  "theory" -> "{aid}" [style=dashed, label="contrasts with"];')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _cluster(lines: list[str], key: str, title: str) -> None:
    lines.append(f"  subgraph cluster_{key} {{")
    lines.append(f'    label="{title}";')
    lines.append('    style="rounded";')
    lines.append('    color="#C4D1D9";')
    lines.append('    fontcolor="#5B7285";')


def _workflow(T: dict) -> str:
    lines = _prelude("workflow", "LR")
    _cluster(lines, "build", "building")
    for c in _list(T, "constructs"):
        lines.append(f'    "{_esc(c.get("id"))}" '
                     f'[label="{_wrap(c.get("label"), 16)}", {_fill("construct")}];')
    lines.append("  }")
    _cluster(lines, "relate", "propositions")
    for p in _list(T, "propositions"):
        pid = _esc(p.get("id"))
        lines.append(f'    "prop_{pid}" [label="{pid}\\n{_esc(p.get("relation"))}", {_fill("proposition")}];')
    lines.append("  }")
    _cluster(lines, "predict", "predictions")
    for p in _list(T, "predictions"):
        pid = _esc(p.get("id"))
        lines.append(f'    "pred_{pid}" [label="{pid}\\n{_esc(p.get("type"))}", {_fill("prediction")}];')
    lines.append("  }")
    _cluster(lines, "test", "testing")
    for t in _list(T, "test_outcomes"):
        pid = _esc(t.get("prediction_id"))
        role = "passed" if t.get("passed") is True else "failed"
        lines.append(f'    "outcome_{pid}" [label="{pid}\\n{role}", {_fill(role)}];')
    lines.append("  }")
    for p in _list(T, "propositions"):
        lines.append(f'  "{_esc(p.get("from"))}" -> "prop_{_esc(p.get("id"))}";')
    for pred in _list(T, "predictions"):
        for src in _as_list(pred.get("derives_from")):
            lines.append(f'  "prop_{_esc(src)}" -> "pred_{_esc(pred.get("id"))}";')
    for t in _list(T, "test_outcomes"):
        pid = _esc(t.get("prediction_id"))
        lines.append(f'  "pred_{pid}" -> "outcome_{pid}";')
    lines.append("}")
    return "\n".join(lines) + "\n"


def _circle(cx: int, cy: int, r: int) -> str:
    # The outline carries the set structure, so it is drawn in the teal already
    # used for construct borders elsewhere in the palette. That colour clears the
    # 3:1 contrast floor for graphical objects (WCAG 1.4.11) against both the
    # light paper and the dark page, whereas the former navy outline fell below
    # it on a dark background and took the whole figure with it. The translucent
    # fill is decorative reinforcement only: no opacity composites to a readable
    # ratio on a dark page, which is why the boundary has to do the work.
    return (f'  <circle cx="{cx}" cy="{cy}" r="{r}" '
            'fill="#4e79a7" fill-opacity="0.35" stroke="#1e7b7b"/>')


def _svg_open(width: int, height: int) -> str:
    """Open an SVG element carrying explicit dimensions as well as a viewBox.

    A viewBox on its own leaves the image with no intrinsic size, so a browser
    resolves ``width: auto`` to the full width of the container and scales the
    declared 13px type by whatever factor that implies. The three chart views
    declare different viewBox widths, so the same label then rendered at a
    different size in each figure. Stating width and height gives each view its
    natural size wherever it is embedded, which is what the rendered Graphviz
    views already do, and leaves the stylesheet free to shrink a wide chart on a
    narrow viewport without inflating the type on a wide one.
    """
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
            f'viewBox="0 0 {width} {height}" font-family="sans-serif" font-size="13">')


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
        sets.append(set(_as_list(bc)))
    n = len(constructs)
    out = [_svg_open(380, 300),
           '  <text x="190" y="24" text-anchor="middle" font-size="15">Construct scope overlap</text>']
    if n == 0:
        out.append(_vlabel(190, 150, "(no constructs)"))
    elif n == 1:
        a = sets[0]
        out += [_circle(190, 150, 82), _vlabel(190, 55, names[0]), _vcount(190, 155, len(a))]
    elif n == 2:
        a, b = sets[0], sets[1]
        out += [_circle(150, 150, 82), _circle(230, 150, 82),
                _vlabel(110, 50, names[0]), _vlabel(270, 50, names[1]),
                _vcount(110, 155, len(a - b)), _vcount(190, 155, len(a & b)),
                _vcount(270, 155, len(b - a))]
    else:
        a, b, c = sets[0], sets[1], sets[2]
        out += [_circle(150, 135, 78), _circle(230, 135, 78), _circle(190, 195, 78),
                _vlabel(110, 45, names[0]), _vlabel(270, 45, names[1]), _vlabel(190, 290, names[2]),
                _vcount(120, 115, len(a - b - c)), _vcount(260, 115, len(b - a - c)),
                _vcount(190, 230, len(c - a - b)), _vcount(190, 105, len((a & b) - c)),
                _vcount(145, 180, len((a & c) - b)), _vcount(235, 180, len((b & c) - a)),
                _vcount(190, 160, len(a & b & c))]
    out.append("</svg>")
    return "\n".join(out) + "\n"


_STATUS_COLOUR = {"pass": "#4caf50", "warn": "#ff9800", "fail": "#f44336"}


def _rigor(T: dict) -> str:
    """The rigour checklist as a colour-coded status grid (SVG)."""
    from .rigor import check as _check
    rep = _check(T)
    items = rep["items"]
    h = 60 + len(items) * 24 + 12
    out = [_svg_open(460, h),
           '  <text x="20" y="28" font-size="15">Rigour checklist</text>',
           f'  <text x="20" y="46">aggregate score {rep["aggregate_score"]:.1f}, gate {rep["gate"]}</text>']
    for i, it in enumerate(items):
        y = 60 + i * 24
        colour = _STATUS_COLOUR.get(it["status"], "#9e9e9e")
        out.append(f'  <rect x="20" y="{y}" width="16" height="16" rx="3" fill="{colour}"/>')
        out.append(f'  <text x="44" y="{y + 12}">{_xml(it["id"])}</text>')
        out.append(f'  <text x="320" y="{y + 12}">{_xml(it["status"])}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def _severity_chart(T: dict) -> str:
    """Per-prediction computed severity as horizontal bars (SVG)."""
    from .scoring import severity as _sev
    rows = _sev(T)
    h = 40 + max(len(rows), 1) * 28 + 8
    labels = [_trunc(r["prediction_id"], 15) for r in rows]
    # Bars start just past the longest row label (estimated at 8 px per character
    # at this font size), so short labels leave no dead gap before the bars, and
    # each value label trails its own bar.
    bar_x = 20 + max((len(lab) for lab in labels), default=0) * 8 + 10
    width = bar_x + 250  # 200 for a full bar, then the gap and the value label
    out = [_svg_open(width, h),
           '  <text x="20" y="26" font-size="15">Prediction severity</text>']
    if not rows:
        out.append('  <text x="20" y="54">(no predictions)</text>')
    for i, r in enumerate(rows):
        y = 40 + i * 28
        sev = r["computed_severity"]
        w = int(sev * 200 + 0.5 + 1e-6)
        out.append(f'  <text x="20" y="{y + 12}">{_xml(labels[i])}</text>')
        out.append(f'  <rect x="{bar_x}" y="{y}" width="{w}" height="16" rx="2" fill="#4e79a7"/>')
        out.append(f'  <text x="{bar_x + w + 5}" y="{y + 12}">{sev:.3f}</text>')
    out.append("</svg>")
    return "\n".join(out) + "\n"


def diagram(T: dict, type: str = "nomological_net", engine: str = "graphviz") -> str:
    """Return the diagram IR string for the requested type.

    ``engine`` is accepted but has no effect, because the IR is engine-independent
    (DOT for the digraphs, dagitty syntax for the causal DAG, and SVG for the Venn,
    the rigour grid and the severity chart).
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
    if type == "rigour":
        return _rigor(T)
    if type == "severity":
        return _severity_chart(T)
    raise ValueError(f"unknown diagram type {type!r}; expected one of {_TYPES}")
