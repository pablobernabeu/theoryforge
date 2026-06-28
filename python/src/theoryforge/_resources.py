"""Access to the vendored rigour checklist."""
from __future__ import annotations

from functools import lru_cache
from importlib.resources import files

import yaml


@lru_cache(maxsize=1)
def checklist() -> dict:
    """The rigour checklist specification (items, weights, thresholds, citations)."""
    text = (files("theoryforge") / "schema" / "rigor_checklist.yaml").read_text(encoding="utf-8")
    return yaml.safe_load(text)
