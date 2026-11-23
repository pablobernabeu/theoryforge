"""Render a theory's audit dossier as a standalone Quarto report.

Writes a ``.qmd`` (a YAML header plus the deterministic dossier body) and can optionally
invoke Quarto to render it. The report content is the deterministic ``dossier`` output, and
only the rendering step depends on the environment.
"""
from __future__ import annotations

import os
import subprocess

from ._access import text
from ._compat import theory_keyword
from ._io import write_lf as _write_lf
from .dossier import dossier as _dossier

_YAML_DQ_ESCAPES = {"\\": "\\\\", '"': '\\"', "\n": "\\n", "\t": "\\t"}


def _yaml_dq(s: str) -> str:
    """Escape ``s`` for the inside of a YAML double-quoted scalar.

    The rule the R twin's .tf_yaml_dq() applies character for character
    (API_SPEC.md section 23): backslash and double quote are escaped, newline and
    tab become \\n and \\t, every other C0 control, DEL and the C1 controls
    become \\xNN, and the noncharacters U+FFFE and U+FFFF become \\uFFFE and
    \\uFFFF, since YAML forbids all of these raw in a stream. Unescaped, "A\\B"
    would be a parse error and "\\emph" an escape sequence.
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


def _qmd_path(path: str) -> str:
    """``path`` with its file name ending in ``.qmd``, by the rule ``render_report()`` states.

    Written out in full, rather than with ``Path.with_suffix``, so that R's twin
    can follow the same rule character for character.
    """
    cut = max(path.rfind("/"), path.rfind("\\")) + 1
    folder, name = path[:cut], path[cut:]
    if name.lower().endswith(".qmd"):
        return path
    dot = name.rfind(".")
    if dot > 0:
        name = name[:dot]
    return folder + name + ".qmd"


@theory_keyword
def render_report(theory, path, title: str | None = None, render: bool = False, to: str = "html") -> str:
    """Write a Quarto report for the theory, and render it with Quarto when ``render=True``.

    The report is a YAML header (``title`` and ``format``) followed by the ``dossier()`` body.
    A file name that does not end in ``.qmd`` (in any letter case) loses everything from its
    last dot, unless the name begins with that dot, and gains ``.qmd``. So ``report.md`` is
    written as ``report.qmd``, ``report`` and ``.hidden`` gain the suffix and ``a.tar.gz``
    becomes ``a.tar.qmd``.
    ``to`` is the Quarto output format, ``"html"`` by default, written into the header and
    passed to ``quarto render --to``.

    ``title`` defaults to ``"theoryforge report: <title-or-id>"``, also when empty. It is
    written as a YAML double-quoted scalar with backslashes, double quotes and control
    characters escaped, so a YAML parser reads back exactly the string passed. Quarto then
    reads the title as Markdown, so raw TeX such as ``\\emph{}`` is dropped from HTML output
    and ``$\\alpha$`` becomes mathematics.

    When ``check()`` refuses the theory, ``ValueError`` is raised before anything is written.
    With ``render=True``, the ``quarto`` command must be on the PATH. A failed render raises
    ``subprocess.CalledProcessError`` and a missing Quarto ``FileNotFoundError``, after the
    ``.qmd`` has been written.

    Returns the path of the written ``.qmd``.
    """
    data = theory.data if hasattr(theory, "data") else theory
    # Fall back to the id when the title is empty as well as absent (matches R's nzchar fallback).
    title = title or f"theoryforge report: {text(data.get('title')) or text(data.get('id'))}"
    path = _qmd_path(os.fspath(path))
    header = f'---\ntitle: "{_yaml_dq(title)}"\nformat: {to}\n---\n\n'
    _write_lf(path, header + _dossier(data))
    if render:
        subprocess.run(["quarto", "render", str(path), "--to", to], check=True)  # pragma: no cover
    return str(path)
