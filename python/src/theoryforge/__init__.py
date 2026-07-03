"""theoryforge: systematic theory development.

A rigorous, reproducible workflow for building, developing and testing scientific
theories. This is the twin of the R package of the same name; its behaviour is
pinned by the shared specification (API_SPEC.md).
"""
from __future__ import annotations

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

__version__ = "0.1.0"

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
