"""Render a theory's audit dossier as a standalone Quarto report.

Writes a `.qmd` (a YAML header plus the deterministic dossier body) and can optionally invoke
Quarto to render it. The report content is the deterministic `dossier` output, and only the
rendering step is environment-dependent.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from ._access import text
from ._io import write_lf as _write_lf
from .dossier import dossier as _dossier

_YAML_DQ_ESCAPES = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t"}


def _yaml_dq(s: str) -> str:
    """Escape ``s`` for the inside of a YAML double-quoted scalar.

    The rule the R twin's .tf_yaml_dq() applies character for character
    (API_SPEC.md section 23): backslash and double quote are escaped, newline and
    tab become \\n and \\t, every other C0 control, DEL and the C1 controls
    become \\xNN, and the noncharacters U+FFFE and U+FFFF become \\uFFFE and
    \\uFFFF, since YAML forbids all of these raw in a stream. The 0.6.0 header
    left backslashes alone, so "A\\B" was a parse error and "\\emph" read as an
    escape.
    """
    out = []
    for ch in s:
        code = ord(ch)
        if ch in _YAML_DQ_ESCAPES:
            out.append(_YAML_DQ_ESCAPES[ch])
        elif code < 0x20 or 0x7F <= code <= 0x9F:
            out.append(f"\\x{code:02X}")
        elif code in (0xFFFE, 0xFFFF):
            out.append(f"\\u{code:04X}")
        else:
            out.append(ch)
    return "".join(out)


def render_report(T, path, title: str | None = None, render: bool = False, to: str = "html") -> str:
    """Write a Quarto report for the theory; render it with Quarto when ``render=True``.

    ``title`` defaults to ``"theoryforge report: <title-or-id>"``, also when empty. It is
    written as a YAML double-quoted scalar with backslashes, double quotes and control
    characters escaped, so a YAML parser reads back exactly the string passed. Quarto then
    reads the title as Markdown, so raw TeX such as ``\\emph{}`` is dropped from HTML output
    and ``$\\alpha$`` becomes mathematics.

    Returns the path of the written `.qmd`.
    """
    data = T.data if hasattr(T, "data") else T
    # Fall back to the id when the title is empty as well as absent (matches R's nzchar fallback).
    title = title or f"theoryforge report: {text(data.get('title')) or text(data.get('id'))}"
    path = Path(path)
    if path.suffix.lower() != ".qmd":
        path = path.with_suffix(".qmd")
    header = f'---\ntitle: "{_yaml_dq(title)}"\nformat: {to}\n---\n\n'
    _write_lf(path, header + _dossier(data))
    if render:
        subprocess.run(["quarto", "render", str(path), "--to", to], check=True)  # pragma: no cover
    return str(path)
