"""The shipped schemas compile under a strict validator and describe what the packages do.

Ajv, the most widely used JavaScript validator, refuses by default to compile a schema
with a keyword JSON Schema does not define, and theory.schema.json carried one, a plain
``comment``. The first test walks every subschema of both schemas the package ships and
fails on any such keyword, which is the check of Ajv's strict mode that CI also runs.
The other tests hold three field descriptions to the behaviour they describe: the
version is checked but gates nothing, draft maturity changes the gate and nothing else,
and the form of a theory leaves the checklist as it is.
"""
import copy
import json
from importlib.resources import files

import pytest

import theoryforge as tf

# Every keyword of the JSON Schema 2020-12 vocabularies: core, applicator, unevaluated,
# validation, meta-data, format annotation and content.
KEYWORDS = frozenset({
    "$schema", "$id", "$ref", "$anchor", "$dynamicRef", "$dynamicAnchor", "$vocabulary",
    "$comment", "$defs",
    "prefixItems", "items", "contains", "additionalProperties", "properties",
    "patternProperties", "dependentSchemas", "propertyNames", "if", "then", "else",
    "allOf", "anyOf", "oneOf", "not",
    "unevaluatedItems", "unevaluatedProperties",
    "type", "const", "enum", "multipleOf", "maximum", "exclusiveMaximum", "minimum",
    "exclusiveMinimum", "maxLength", "minLength", "pattern", "maxItems", "minItems",
    "uniqueItems", "maxContains", "minContains", "maxProperties", "minProperties",
    "required", "dependentRequired",
    "title", "description", "default", "deprecated", "readOnly", "writeOnly", "examples",
    "format", "contentEncoding", "contentMediaType", "contentSchema",
})
# Keywords whose value is a schema, a list of schemas or a mapping of names to schemas.
ONE_SCHEMA = ("items", "contains", "additionalProperties", "propertyNames", "if", "then",
              "else", "not", "unevaluatedItems", "unevaluatedProperties", "contentSchema")
SCHEMA_LISTS = ("prefixItems", "allOf", "anyOf", "oneOf")
SCHEMA_MAPS = ("properties", "patternProperties", "$defs", "dependentSchemas")


def _schema(name: str) -> dict:
    return json.loads((files("theoryforge") / "schema" / name).read_text(encoding="utf-8"))


def _unknown_keywords(schema, where: str = "#") -> list[str]:
    """The JSON pointer of every key in a schema object that is not a keyword."""
    if not isinstance(schema, dict):  # true and false are schemas too
        return []
    found = [f"{where}/{key}" for key in schema if key not in KEYWORDS]
    for key in ONE_SCHEMA:
        if key in schema:
            found += _unknown_keywords(schema[key], f"{where}/{key}")
    for key in SCHEMA_LISTS:
        for i, sub in enumerate(schema.get(key, [])):
            found += _unknown_keywords(sub, f"{where}/{key}/{i}")
    for key in SCHEMA_MAPS:
        for name, sub in schema.get(key, {}).items():
            found += _unknown_keywords(sub, f"{where}/{key}/{name}")
    return found


def test_the_walk_finds_an_unknown_keyword_at_any_depth():
    schema = {"properties": {"a": {"items": {"type": "string", "nullable": True}}},
              "anyOf": [{"comment": "x"}], "additionalProperties": False}
    assert _unknown_keywords(schema) == ["#/anyOf/0/comment",
                                         "#/properties/a/items/nullable"]


@pytest.mark.parametrize("name", ["theory.schema.json", "corpus.schema.json"])
def test_every_key_of_a_shipped_schema_is_a_json_schema_keyword(name):
    assert _unknown_keywords(_schema(name)) == []


def _description(field: str) -> str:
    return _schema("theory.schema.json")["properties"][field]["description"]


def _variant(path, **fields) -> tf.Theory:
    data = copy.deepcopy(tf.read(path).data)
    data.update(fields)
    return tf.Theory(data)


def test_schema_version_is_checked_but_gates_nothing():
    # A version the packages have never heard of reads, validates and scores as
    # the current one does. Only full validation looks at the version, and only
    # at its major.minor form.
    path = tf.example_path("panic-network.theory.yaml")
    current = tf.read(path).check()
    future = _variant(path, schema_version="9.0")
    assert future.validate(full=True) is True
    report = future.check()
    assert (report["aggregate_score"], report["gate"]) == (
        current["aggregate_score"], current["gate"])
    off_pattern = _variant(path, schema_version="v1")
    assert off_pattern.validate() is True
    with pytest.raises(ValueError, match="schema_version must match major.minor"):
        off_pattern.validate(full=True)
    assert off_pattern.check()["aggregate_score"] == current["aggregate_score"]
    description = _description("schema_version")
    assert "validate(full) checks its pattern" in description
    assert "neither package gates loading" in description


def test_draft_maturity_changes_the_gate_and_nothing_else():
    path = tf.example_path("weak-theory.theory.yaml")
    building = _variant(path, maturity="building").check()
    draft = _variant(path, maturity="draft").check()
    assert building["gate"] == "blocked"
    assert draft["gate"] == "advisory"
    # The blockers still fail and still count in the score.
    assert draft["n_blockers_failed"] == building["n_blockers_failed"] > 0
    assert draft["items"] == building["items"]
    assert draft["aggregate_score"] == building["aggregate_score"]
    description = _description("maturity")
    assert "still reported as fail" in description
    assert "still count in the aggregate score" in description
    assert "never reads blocked" in description


def test_theory_form_leaves_the_checklist_unchanged():
    path = tf.example_path("panic-network.theory.yaml")
    reports = [_variant(path, theory_form=form).check()
               for form in ("variance", "network", "typology", "process")]
    assert all(len(r["items"]) == 12 for r in reports)
    assert all(r == reports[0] for r in reports)
    assert "the checklist applies the same twelve items to every form" in (
        _description("theory_form"))
