"""Access to the vendored rigour checklist and theory schema."""
from __future__ import annotations

import json
from functools import lru_cache
from importlib.resources import files

import yaml


@lru_cache(maxsize=1)
def checklist() -> dict:
    """The rigour checklist specification (items, weights, thresholds, citations)."""
    text = (files("theoryforge") / "schema" / "rigor_checklist.yaml").read_text(encoding="utf-8")
    return yaml.safe_load(text)


@lru_cache(maxsize=1)
def theory_schema() -> dict:
    """The theory JSON Schema, read for its enumeration of recognised fields.

    No JSON-Schema engine is involved (API_SPEC.md section 2); ``validate`` only
    needs the ``properties`` key set, so the schema stays the single source of
    truth for which top-level fields exist.
    """
    text = (files("theoryforge") / "schema" / "theory.schema.json").read_text(encoding="utf-8")
    return json.loads(text)
