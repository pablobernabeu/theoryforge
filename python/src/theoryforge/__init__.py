"""theoryforge: systematic theory development.

A rigorous, reproducible workflow for building, developing and testing scientific
theories. This is the feature-parity twin of the R package of the same name
(https://pablobernabeu.github.io/theoryforge/r/). Every public function has an
identically behaving counterpart there, pinned by the shared public specification
(https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md), so the two
implementations produce identical verdicts and byte-identical diagram intermediate
representations. The only exceptions are the assistive helpers that depend on a
network service or a user-supplied embedder (``fetch_corpus``, ``osf_push`` and
``embedding_redundancy``), which are documented as such.
"""
from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

from .core import Theory, new_theory, read, write
from .develop import appraise_amendment
from .diagram import diagram
from .dossier import dossier
from .embedding import embedding_redundancy
from .lit import fetch_corpus, landscape, lit_diagram, litmap, new_evidence_dois, read_corpus
from .osf import osf_push
from .prereg import preregister
from .redundancy import jaccard, redundancy_check, tokens
from .report_render import render_report
from .rigor import check, report
from .scoring import severity
from .sem import compile_sem
from .simulate import simulate

# The installed distribution's version (declared once, in pyproject.toml).
# The fallback covers running from an uninstalled source tree.
try:
    __version__ = version("theoryforge")
except PackageNotFoundError:  # pragma: no cover - uninstalled source tree
    __version__ = "0+unknown"

__all__ = [
    "Theory",
    "read",
    "write",
    "new_theory",
    "check",
    "report",
    "diagram",
    "redundancy_check",
    "tokens",
    "jaccard",
    "severity",
    "appraise_amendment",
    "preregister",
    "read_corpus",
    "litmap",
    "landscape",
    "lit_diagram",
    "fetch_corpus",
    "new_evidence_dois",
    "compile_sem",
    "dossier",
    "simulate",
    "embedding_redundancy",
    "render_report",
    "osf_push",
    "__version__",
]
