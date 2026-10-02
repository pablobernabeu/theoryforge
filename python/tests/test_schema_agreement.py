"""Full validation refuses every theory a JSON Schema validator refuses.

``validate(full=True)`` checks ``theory.schema.json`` without a JSON Schema
engine, so that it runs unchanged in webR and Pyodide (API_SPEC.md section 2).
This module holds it to jsonschema's Draft 2020-12 validator, the draft the
schema declares. It checks the shipped theories, the gaps files in
``fixtures/edge/`` and one-fault variants of a theory that uses every field of
the schema. The few conveniences the contract documents, where the two are
meant to differ, are pinned as well.
"""
import copy
import json
from pathlib import Path

import pytest

import theoryforge as tf
from theoryforge.core import Theory

jsonschema = pytest.importorskip("jsonschema")
# Draft 2020-12 arrived in jsonschema 4.0, and the 3.x line lacks it. The class
# is tested in place of the version attribute, which jsonschema deprecates.
if not hasattr(jsonschema, "Draft202012Validator"):
    pytest.skip("Draft 2020-12 needs jsonschema 4.0 or later", allow_module_level=True)

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = jsonschema.Draft202012Validator(
    json.loads((ROOT / "schema" / "theory.schema.json").read_text(encoding="utf-8")))
SHIPPED = sorted([*(ROOT / "fixtures").glob("*.theory.yaml"),
                  *(ROOT / "apps" / "examples").glob("*.theory.yaml")])
GAPS = sorted((ROOT / "fixtures" / "edge").glob("gaps*.theory.yaml"))


def _schema_errors(data) -> list[str]:
    return sorted(err.message for err in VALIDATOR.iter_errors(data))


def test_the_file_corpus_is_found():
    # An empty glob would leave the two tests below with nothing to check.
    assert SHIPPED and GAPS


@pytest.mark.parametrize("path", SHIPPED, ids=lambda p: p.name)
def test_every_shipped_theory_passes_both(path):
    t = tf.read(path)
    assert _schema_errors(t.data) == []
    assert t.validate(full=True) is True


@pytest.mark.parametrize("path", GAPS, ids=lambda p: p.name)
def test_every_gaps_file_fails_both(path):
    t = tf.read(path)
    assert _schema_errors(t.data)
    with pytest.raises(ValueError, match="^invalid theory object: "):
        t.validate(full=True)


# A valid theory that holds every field the schema defines, so that each
# variant below breaks exactly one of the schema's rules.
BASE = {
    "schema_version": "1.0",
    "id": "t",
    "title": "T",
    "maturity": "building",
    "theory_form": "network",
    "version": {"id": "v2", "parent_id": "v1", "content_hash": None},
    "constructs": [
        {"id": "c1", "label": "C1", "definition": "The first construct.",
         "measurement": ["m1"], "boundary_conditions": ["adults"]},
        {"id": "c2", "label": "C2", "definition": "The second construct."},
    ],
    "propositions": [{"id": "p1", "from": "c1", "to": "c2", "relation": "increases",
                      "mechanism": "C1 drives C2.", "functional_form": "linear"}],
    "boundary_conditions": ["adults"],
    "predictions": [{"id": "h1", "statement": "C2 rises with C1.", "type": "point",
                     "derives_from": ["p1"], "diagnostic_vs": ["a1"], "risk_score": 0.9,
                     "severity": 0.9}],
    "auxiliary_assumptions": [{"id": "x1", "statement": "C1 is measured at rest.",
                               "added_for": None, "protects": ["h1"]}],
    "evidence": [{"supports": "h1", "direction": "corroborates", "source_doi": None}],
    "test_outcomes": [{"prediction_id": "h1", "observed": "0.31", "passed": True,
                       "severity_at_test": 0.8, "registered": None, "date": "2026-05-01"}],
    "alternatives": [{"id": "a1", "label": "A1", "key_constructs": ["c1"],
                      "source_doi": "10.1000/example"}],
    "formal_model": {"type": "ode", "spec_ref": None},
    "provenance": [{"step": "1", "action": "tf_theory", "detail": "t"}],
}

_DROP = object()


def _variant(path: tuple, value) -> dict:
    """A copy of BASE with the value at ``path`` replaced, or dropped for _DROP."""
    data = copy.deepcopy(BASE)
    target = data
    for key in path[:-1]:
        target = target[key]
    if value is _DROP:
        del target[path[-1]]
    else:
        target[path[-1]] = value
    return data


# (what breaks the schema, where, the value)
VIOLATIONS = [
    ("schema_version missing", ("schema_version",), _DROP),
    ("schema_version a number", ("schema_version",), 1.0),
    ("schema_version off its pattern", ("schema_version",), "one"),
    ("id empty", ("id",), ""),
    ("id a number", ("id",), 2026),
    ("title missing", ("title",), _DROP),
    ("title empty", ("title",), ""),
    ("maturity outside its enum", ("maturity",), "nope"),
    ("maturity a sequence", ("maturity",), ["draft"]),
    ("theory_form outside its enum", ("theory_form",), "web"),
    ("an unknown top-level field", ("predicitions",), []),
    ("version a string", ("version",), "v2"),
    ("version with an unknown field", ("version", "author"), "x"),
    ("version id a number", ("version", "id"), 2),
    ("version parent_id a number", ("version", "parent_id"), 1),
    ("version content_hash a sequence", ("version", "content_hash"), ["x"]),
    ("constructs a string", ("constructs",), "arousal"),
    ("constructs a mapping", ("constructs",), {"c1": {"id": "c1"}}),
    ("a construct that is a string", ("constructs", 1), "c2"),
    ("a construct that is null", ("constructs", 1), None),
    ("a construct without an id", ("constructs", 0, "id"), _DROP),
    ("a construct without a label", ("constructs", 0, "label"), _DROP),
    ("a construct without a definition", ("constructs", 0, "definition"), _DROP),
    ("a construct label that is a boolean", ("constructs", 0, "label"), True),
    ("a measurement entry that is a number", ("constructs", 0, "measurement"), ["m1", 5]),
    ("measurement a mapping", ("constructs", 0, "measurement"), {"m": "x"}),
    ("nested boundary conditions", ("constructs", 0, "boundary_conditions"), [["adults"]]),
    ("a proposition without from", ("propositions", 0, "from"), _DROP),
    ("a relation outside its enum", ("propositions", 0, "relation"), "boosts"),
    ("a relation as a sequence", ("propositions", 0, "relation"), ["increases"]),
    ("a mechanism that is a number", ("propositions", 0, "mechanism"), 5),
    ("a functional form that is a boolean", ("propositions", 0, "functional_form"), True),
    ("a null top-level boundary condition", ("boundary_conditions",), ["adults", None]),
    ("top-level boundary conditions a number", ("boundary_conditions",), 5),
    ("predictions a mapping", ("predictions",), {"h1": {"id": "h1"}}),
    ("a prediction without a statement", ("predictions", 0, "statement"), _DROP),
    ("a prediction type outside its enum", ("predictions", 0, "type"), "vague"),
    ("a null derives_from entry", ("predictions", 0, "derives_from"), [None]),
    ("diagnostic_vs a mapping", ("predictions", 0, "diagnostic_vs"), {"a1": True}),
    ("a risk score above one", ("predictions", 0, "risk_score"), 2),
    ("a risk score as a string", ("predictions", 0, "risk_score"), "0.9"),
    ("a severity below zero", ("predictions", 0, "severity"), -0.1),
    ("a severity as a string", ("predictions", 0, "severity"), "0.7"),
    ("an assumption without a statement", ("auxiliary_assumptions", 0, "statement"), _DROP),
    ("an assumption id that is a number", ("auxiliary_assumptions", 0, "id"), 3),
    ("added_for a number", ("auxiliary_assumptions", 0, "added_for"), 5),
    ("a null protects entry", ("auxiliary_assumptions", 0, "protects"), [None]),
    ("evidence without supports", ("evidence", 0, "supports"), _DROP),
    ("evidence without a direction", ("evidence", 0, "direction"), _DROP),
    ("a direction outside its enum", ("evidence", 0, "direction"), "supports"),
    ("an evidence source DOI that is a number", ("evidence", 0, "source_doi"), 5),
    ("an outcome without prediction_id", ("test_outcomes", 0, "prediction_id"), _DROP),
    ("an outcome without passed", ("test_outcomes", 0, "passed"), _DROP),
    ("passed as a string", ("test_outcomes", 0, "passed"), "true"),
    ("passed as a number", ("test_outcomes", 0, "passed"), 1),
    ("passed null", ("test_outcomes", 0, "passed"), None),
    ("observed a number", ("test_outcomes", 0, "observed"), 0.42),
    ("severity_at_test above one", ("test_outcomes", 0, "severity_at_test"), 1.5),
    ("registered a number", ("test_outcomes", 0, "registered"), 2026),
    ("date a number", ("test_outcomes", 0, "date"), 20260501),
    ("an alternative without a label", ("alternatives", 0, "label"), _DROP),
    ("a key construct that is a number", ("alternatives", 0, "key_constructs"), [3]),
    ("an alternative source DOI as a sequence", ("alternatives", 0, "source_doi"), ["10.1/x"]),
    ("formal_model a string", ("formal_model",), "ode"),
    ("a formal model type outside its enum", ("formal_model", "type"), "banana"),
    ("an empty formal model type", ("formal_model", "type"), ""),
    ("a formal model type as a sequence", ("formal_model", "type"), ["none"]),
    ("spec_ref a number", ("formal_model", "spec_ref"), 5),
    ("provenance a string", ("provenance",), "built by hand"),
    ("a provenance entry that is a string", ("provenance", 0), "tf_theory"),
    ("a provenance entry that is null", ("provenance", 0), None),
    ("a provenance step that is a number", ("provenance", 0, "step"), 1),
]

# Values the schema refuses and the contract reads by design (API_SPEC.md
# sections 2 and 4). They are a single string where an array of strings
# belongs, a null optional field and an empty sequence or mapping where the
# other belongs, since R builds both as list().
CONVENIENCES = [
    ("a string array written as one string", ("predictions", 0, "derives_from"), "p1"),
    ("a null string array", ("constructs", 0, "measurement"), None),
    ("a null optional text field", ("propositions", 0, "mechanism"), None),
    ("a null severity", ("predictions", 0, "severity"), None),
    ("a null collection", ("evidence",), None),
    ("an empty mapping for a collection", ("evidence",), {}),
    ("a null formal model", ("formal_model",), None),
    ("an empty sequence for the formal model", ("formal_model",), []),
    ("a null version", ("version",), None),
]


def test_the_base_theory_passes_both():
    assert _schema_errors(BASE) == []
    assert Theory(copy.deepcopy(BASE)).validate(full=True) is True


@pytest.mark.parametrize(("path", "value"), [v[1:] for v in VIOLATIONS],
                         ids=[v[0] for v in VIOLATIONS])
def test_each_schema_violation_fails_full_validation(path, value):
    data = _variant(path, value)
    assert _schema_errors(data), "the variant should break the schema"
    with pytest.raises(ValueError, match="^invalid theory object: "):
        Theory(data).validate(full=True)


@pytest.mark.parametrize(("path", "value"), [c[1:] for c in CONVENIENCES],
                         ids=[c[0] for c in CONVENIENCES])
def test_each_documented_convenience_passes_full_validation(path, value):
    data = _variant(path, value)
    assert _schema_errors(data), "the variant should break the schema"
    assert Theory(data).validate(full=True) is True
