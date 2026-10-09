"""Access to the vendored rigour checklist, theory schema and fold table."""
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


@lru_cache(maxsize=1)
def fold_table() -> dict[int, str | None]:
    """The fold table of ``schema/fold.json`` as a ``str.translate`` table.

    Each folded character maps to its replacement, and each code point of the
    table's ``delete_ranges`` (the combining marks U+0300-036F) maps to None, so
    one ``translate`` call folds a text (API_SPEC.md section 3, "Normalising text").
    """
    text = (files("theoryforge") / "schema" / "fold.json").read_text(encoding="utf-8")
    spec = json.loads(text)
    table: dict[int, str | None] = {ord(k): v for k, v in spec["map"].items()}
    for lo, hi in spec["delete_ranges"]:
        for cp in range(int(lo, 16), int(hi, 16) + 1):
            table[cp] = None
    return table
