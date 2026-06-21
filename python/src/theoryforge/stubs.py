"""Placeholders for features scheduled after P0 (see docs/project-plan.md)."""
from __future__ import annotations


class NotImplementedInP0(NotImplementedError):
    """Raised by features scaffolded but not yet implemented in the P0 release."""


def not_implemented(name: str):
    raise NotImplementedInP0(
        f"'{name}' is scaffolded but not implemented in the P0 release; "
        "see docs/project-plan.md for the phased roadmap."
    )
