"""Render a theory's audit dossier as a standalone Quarto report.

Writes a `.qmd` (a YAML header plus the deterministic dossier body) and can optionally invoke
Quarto to render it. The report content is the deterministic `dossier` output, and only the
rendering step is environment-dependent.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from .dossier import dossier as _dossier


def render_report(T, path, title: str | None = None, render: bool = False, to: str = "html") -> str:
    """Write a Quarto report for the theory; render it with Quarto when ``render=True``.

    Returns the path of the written `.qmd`.
    """
    data = T.data if hasattr(T, "data") else T
    # Fall back to the id when the title is empty as well as absent (matches R's nzchar fallback).
    title = title or f"theoryforge report: {data.get('title') or data.get('id') or ''}"
    title = title.replace('"', "'")
    path = Path(path)
    if path.suffix.lower() != ".qmd":
        path = path.with_suffix(".qmd")
    header = f'---\ntitle: "{title}"\nformat: {to}\n---\n\n'
    path.write_text(header + _dossier(data), encoding="utf-8")
    if render:
        subprocess.run(["quarto", "render", str(path), "--to", to], check=True)  # pragma: no cover
    return str(path)
