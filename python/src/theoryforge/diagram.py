"""Diagram intermediate representations. Byte-identical to the R output (API_SPEC.md section 5)."""
from __future__ import annotations

_CAUSAL = {"causes", "increases", "decreases"}
_TYPES = ("nomological_net", "provenance", "causal_dag", "development_roadmap", "pipeline")


def _esc(s) -> str:
    return str(s if s is not None else "").replace("\\", "\\\\").replace('"', '\\"')


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


def diagram(T: dict, type: str = "nomological_net", engine: str = "graphviz") -> str:
    """Return the diagram IR string for the requested type.

    ``engine`` is accepted for API parity; the IR is engine-independent
    (DOT for the two digraphs, dagitty syntax for the causal DAG).
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
    raise ValueError(f"unknown diagram type {type!r}; expected one of {_TYPES}")
