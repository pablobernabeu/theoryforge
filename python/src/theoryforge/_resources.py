"""Access to the vendored shared schema and rigour checklist."""
from __future__ import annotations

import json
from functools import lru_cache
from importlib.resources import files

import yaml


@lru_cache(maxsize=1)
def schema() -> dict:
    """The JSON Schema for a theory object (source of truth, vendored)."""
    text = (files("theoryforge") / "schema" / "theory.schema.json").read_text(encoding="utf-8")
    return json.loads(text)


@lru_cache(maxsize=1)
def checklist() -> dict:
    """The rigour checklist specification (items, weights, thresholds, citations)."""
    text = (files("theoryforge") / "schema" / "rigor_checklist.yaml").read_text(encoding="utf-8")
    return yaml.safe_load(text)
