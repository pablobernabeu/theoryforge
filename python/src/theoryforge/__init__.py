"""theoryforge: systematic theory development.

A reproducible workflow for building, developing and testing scientific theories.
An R package of the same name (https://pablobernabeu.github.io/theoryforge/r/)
offers a counterpart of every public function. Both follow one public specification
(https://github.com/pablobernabeu/theoryforge/blob/main/API_SPEC.md), so they produce
the same verdicts and the same diagram intermediate representations. The helpers
that depend on a network service or a user-supplied embedder (``fetch_corpus``,
``osf_push`` and ``embedding_redundancy``) and the diagram renderer
(``render_diagram``) have counterparts there too, but their results can differ
between the two packages. Their documentation describes what each depends on.
"""
from __future__ import annotations

from importlib.metadata import PackageNotFoundError, version

from .core import Theory, new_theory, read, write
from .develop import appraise_amendment
from .diagram import diagram
from .dossier import dossier
from .embedding import embedding_redundancy
from .entailment import discriminate, entailments, equivalent_models
from .examples import example_names, example_path
from .hashing import content_hash
from .implications import implications
from .lit import fetch_corpus, landscape, lit_diagram, litmap, new_evidence_dois, read_corpus
from .osf import OSFUploadError, osf_push
from .prereg import preregister
from .redundancy import jaccard, redundancy_check, tokens
from .render import render_diagram
from .report_render import render_report
from .rigor import check, report
from .scoring import post_data_severity, severity
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
    "content_hash",
    "check",
    "report",
    "diagram",
    "redundancy_check",
    "tokens",
    "jaccard",
    "severity",
    "post_data_severity",
    "appraise_amendment",
    "implications",
    "entailments",
    "equivalent_models",
    "discriminate",
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
    "render_diagram",
    "osf_push",
    "OSFUploadError",
    "example_path",
    "example_names",
    "__version__",
]
