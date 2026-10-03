"""Validation and cross-language parity behaviour.

These lock the contracts that the byte-identical golden artefacts do not exercise:
the opt-in full validation, the structural error message text, the refusal of
non-boolean test outcomes, the non-mapping read guards, the OSF base_url override
and the report title fallback. The R suite asserts the same behaviour so the two
stay aligned.
"""
import pytest

import theoryforge as tf
from theoryforge.core import Theory


def _consistent() -> Theory:
    return Theory({
        "schema_version": "1.0", "id": "t", "title": "T", "maturity": "building",
        "constructs": [{"id": "c1", "label": "C1", "definition": "d"},
                       {"id": "c2", "label": "C2", "definition": "d"}],
        "propositions": [{"id": "p1", "from": "c1", "to": "c2", "relation": "increases"}],
        "predictions": [{"id": "h1", "statement": "s", "type": "directional",
                         "derives_from": ["p1"], "diagnostic_vs": ["a1"]}],
        "alternatives": [{"id": "a1", "label": "A1"}],
        "auxiliary_assumptions": [{"id": "x1", "statement": "s", "protects": ["h1"]}],
        "test_outcomes": [{"prediction_id": "h1", "passed": True}],
        "evidence": [{"supports": "h1", "direction": "corroborates"}],
    })


def _item(report: dict, iid: str) -> dict:
    return next(it for it in report["items"] if it["id"] == iid)


def _full_error(t: Theory) -> str:
    """The message validate(full=True) raises for ``t``."""
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    return str(exc.value)


def test_full_validation_passes_on_consistent_theory():
    assert _consistent().validate(full=True) is True


def test_full_validation_passes_on_every_shipped_theory(fixtures_dir):
    # The R suite asserts the same over the same files. Reading the directory
    # rather than a list means a new example cannot be added without being held
    # to referential integrity.
    paths = sorted(fixtures_dir.glob("*.theory.yaml"))
    assert len(paths) == 4
    for path in paths:
        assert tf.read(path).validate(full=True) is True, path.name


def test_full_validation_flags_dangling_and_duplicate_references():
    t = Theory({
        "schema_version": "1.0", "id": "b", "title": "B", "maturity": "building",
        "constructs": [{"id": "c1", "label": "C1", "definition": "d"},
                       {"id": "c1", "label": "C1b", "definition": "d"}],
        "propositions": [{"id": "p1", "from": "c1", "to": "cX", "relation": "increases"}],
        "predictions": [{"id": "h1", "statement": "s", "type": "directional",
                         "derives_from": ["pZ"], "diagnostic_vs": ["altZ"]}],
        "auxiliary_assumptions": [{"id": "x1", "statement": "s", "protects": ["hZ"]}],
        "test_outcomes": [{"prediction_id": "hZ", "passed": True}],
        "evidence": [{"supports": "hZ"}],
    })
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    msg = str(exc.value)
    for expected in (
        "duplicate construct id: c1",
        "proposition[0] to 'cX' is not a known construct",
        "prediction[0] derives_from 'pZ' is not a known proposition",
        "prediction[0] diagnostic_vs 'altZ' is not a known alternative",
        "assumption[0] protects 'hZ' is not a known prediction",
        "test_outcome[0] prediction_id 'hZ' is not a known prediction",
        "evidence[0] supports 'hZ' is not a known prediction",
    ):
        assert expected in msg


def test_default_validation_skips_referential_checks():
    # A dangling proposition endpoint is structurally valid; only full= flags it.
    Theory({
        "schema_version": "1.0", "id": "b", "title": "B", "maturity": "building",
        "propositions": [{"id": "p1", "from": "cX", "to": "cY", "relation": "increases"}],
    }).validate()


def test_enum_message_is_comma_joined_without_brackets():
    with pytest.raises(ValueError) as exc:
        Theory({"schema_version": "1.0", "id": "b", "title": "B", "maturity": "nope"}).validate()
    text = str(exc.value)
    assert "maturity must be one of building, developing, draft, testing" in text
    assert "[" not in text and "'" not in text


def test_unknown_top_level_field_is_refused():
    # A misspelt collection key drops the collection silently; the whole point
    # is that this is caught rather than scored.
    t = _consistent()
    t.data["predicitions"] = t.data.pop("predictions")
    with pytest.raises(ValueError) as exc:
        t.validate()
    assert "unknown top-level field: predicitions" in str(exc.value)


def test_known_top_level_fields_are_accepted():
    assert _consistent().validate() is True


def test_read_and_read_corpus_reject_non_mapping(tmp_path):
    p = tmp_path / "bad.yaml"
    p.write_text("- just\n- a\n- list\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Theory data must be a mapping"):
        tf.read(p)
    c = tmp_path / "badc.yaml"
    c.write_text("- 1\n- 2\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Corpus data must be a mapping"):
        tf.read_corpus(c)


def test_read_and_read_corpus_reject_sequence_of_mappings(tmp_path):
    # A sequence of mappings, unlike a sequence of scalars, parses to a plain
    # list in R too, so this is the form that slipped past the R guard.
    p = tmp_path / "seq.yaml"
    p.write_text("- {a: 1}\n- {b: 2}\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Theory data must be a mapping"):
        tf.read(p)
    c = tmp_path / "seqc.yaml"
    c.write_text("- {a: 1}\n- {b: 2}\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Corpus data must be a mapping"):
        tf.read_corpus(c)


def test_string_severity_is_refused_by_full_validation_and_by_scoring(tmp_path):
    # The schema types severity as a number in [0, 1]. A YAML string severity
    # previously passed validate(full=True) in both engines and then crashed
    # Python's check() while R silently coerced and scored; the R suite runs
    # the same file and asserts the same two messages.
    p = tmp_path / "string-severity.theory.yaml"
    p.write_text(
        'schema_version: "1.0"\n'
        "id: t\n"
        "title: T\n"
        "maturity: building\n"
        "predictions:\n"
        "  - id: h1\n"
        "    statement: s\n"
        "    type: directional\n"
        '    severity: "0.8"\n',
        encoding="utf-8",
    )
    t = tf.read(p)
    assert t.validate() is True  # the structural pass alone does not reach severity
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    assert "prediction[0] severity must be a number between 0 and 1" in str(exc.value)
    with pytest.raises(ValueError) as exc:
        t.check()
    assert str(exc.value) == (
        "check requires numeric prediction severities; non-numeric severity for prediction: h1"
    )


def test_out_of_range_severity_fails_full_validation():
    t = _consistent()
    t.data["predictions"][0]["severity"] = 1.5
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    assert "prediction[0] severity must be a number between 0 and 1" in str(exc.value)
    t.data["predictions"][0]["severity"] = 0.8
    assert t.validate(full=True) is True


def test_osf_push_base_url_override():
    res = tf.new_theory("t", "T").osf_push(node="abc12", base_url="https://example.org/v1/resources/")
    assert res["request"]["url"].startswith("https://example.org/v1/resources/abc12/")


def test_render_report_falls_back_to_id_on_empty_title(tmp_path):
    out = tf.new_theory("the-id", "").render_report(tmp_path / "r.qmd")
    assert "theoryforge report: the-id" in open(out, encoding="utf-8").read()


def test_mistyped_enum_values_are_refused_not_crashed_on():
    # A YAML sequence or mapping where the schema wants a scalar enum used to
    # reach `x in <set>` and raise an unhashable-type TypeError, abandoning the
    # errors already collected. R reported them, so the same file failed
    # differently in the two engines. Both now give the contract's messages,
    # which name the wrong type where 0.6.0 called the field missing.
    for value in (["draft", "building"], ["draft"], {"stage": "draft"}):
        t = Theory({"schema_version": "1.0", "id": "x", "title": "T", "maturity": value})
        with pytest.raises(ValueError) as exc:
            t.validate()
        assert str(exc.value) == (
            "invalid theory object: maturity must be a string; "
            "maturity must be one of building, developing, draft, testing"
        )
    t = Theory({"schema_version": "1.0", "id": "x", "title": "T", "maturity": 1})
    with pytest.raises(ValueError) as exc:
        t.validate()
    assert str(exc.value) == (
        "invalid theory object: maturity must be a string (quote the value in YAML); "
        "maturity must be one of building, developing, draft, testing"
    )

    # theory_form is the case where R was the lenient one: `%in%` unboxed the
    # one-element list and let it through.
    t = Theory({"schema_version": "1.0", "id": "x", "title": "T",
                "maturity": "draft", "theory_form": ["network"]})
    with pytest.raises(ValueError) as exc:
        t.validate()
    assert str(exc.value) == (
        "invalid theory object: theory_form must be one of "
        "network, process, typology, variance"
    )


def test_collection_entries_that_are_not_mappings_are_refused():
    # `constructs: [arousal, threat]` is a natural mistake: a sequence of
    # scalars where the schema wants a sequence of mappings. Each entry has no
    # fields, so every required one is reported missing, as in R.
    t = Theory({"schema_version": "1.0", "id": "x", "title": "T",
                "maturity": "draft", "constructs": ["arousal", "threat"]})
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    assert str(exc.value) == (
        "invalid theory object: construct[0] missing/empty id; "
        "construct[0] missing/empty label; construct[0] missing/empty definition; "
        "construct[1] missing/empty id; construct[1] missing/empty label; "
        "construct[1] missing/empty definition"
    )


# -- the whole schema (API_SPEC section 2) -------------------------------------
# The R suite (test-validation-parity.R) builds the same theories and asserts the
# same messages, and the edge phase of scripts/parity_check.py compares the two
# engines on the files in fixtures/edge/.


def test_a_present_required_value_that_is_not_a_string_is_named():
    # A field holding a number or a boolean is present, so calling it missing
    # sent readers looking for a typo. YAML reads an unquoted 1.0, 2026 or Yes
    # as a number or a boolean, so the message says how to keep it a string.
    t = Theory({
        "schema_version": 1.0, "id": 2026, "title": "  ", "maturity": "building",
        "constructs": [{"id": "c1", "label": True, "definition": None}],
        "propositions": [{"id": "p1", "from": "c1", "to": "c1", "relation": ["increases"]}],
        "predictions": [{"id": 7, "statement": "s", "type": {"form": "point"}}],
    })
    with pytest.raises(ValueError) as exc:
        t.validate()
    assert str(exc.value) == (
        "invalid theory object: "
        "schema_version must be a string (quote the value in YAML); "
        "id must be a string (quote the value in YAML); "
        "missing/empty required field: title; "
        "construct[0] label must be a string (quote the value in YAML); "
        "construct[0] missing/empty definition; "
        "proposition[0] relation must be a string; "
        "prediction[0] id must be a string (quote the value in YAML); "
        "prediction[0] type must be a string"
    )


def test_a_collection_that_is_not_a_list_is_named():
    # A scalar or a non-empty mapping where a collection belongs reads as an
    # empty collection (API_SPEC section 3), so validate says so. An empty
    # mapping loses nothing, and R builds it as list(), as it builds [].
    t = Theory({
        "schema_version": "1.0", "id": "x", "title": "T", "maturity": "building",
        "constructs": "arousal",
        "predictions": {"h1": {"id": "h1", "statement": "s", "type": "point"}},
        "evidence": 5, "provenance": True, "alternatives": {}, "test_outcomes": [],
        "propositions": None, "extra": 1,
    })
    with pytest.raises(ValueError) as exc:
        t.validate()
    assert str(exc.value) == (
        "invalid theory object: unknown top-level field: extra; "
        "constructs must be a list; predictions must be a list; "
        "evidence must be a list; provenance must be a list"
    )


def test_full_validation_checks_the_required_fields_of_every_collection():
    t = _consistent()
    t.data["auxiliary_assumptions"] = [{"id": "x1"}, {"id": 3, "statement": "s"}]
    t.data["alternatives"] = [{"id": "a1"}]
    t.data["evidence"] = [{"supports": "h1", "direction": "supports"}, {"supports": "h1"},
                          {"direction": "refutes"}]
    t.data["test_outcomes"] = [{"prediction_id": "h1", "passed": "true"},
                               {"prediction_id": "h1"}, {"passed": True}]
    assert t.validate() is True  # the structural pass does not read these collections
    assert _full_error(t) == (
        "invalid theory object: "
        "assumption[0] missing/empty statement; "
        "assumption[1] id must be a string (quote the value in YAML); "
        "alternative[0] missing/empty label; "
        "evidence[0] direction 'supports' not allowed; "
        "evidence[1] missing/empty direction; "
        "evidence[2] missing/empty supports; "
        "test_outcome[0] passed must be true or false; "
        "test_outcome[1] passed must be true or false; "
        "test_outcome[2] missing/empty prediction_id"
    )


def test_full_validation_checks_the_typed_optional_fields():
    t = _consistent()
    t.data["auxiliary_assumptions"] = [
        {"id": "x1", "statement": "s", "added_for": 5},
        {"id": "x2", "statement": "s", "added_for": None},
    ]
    t.data["test_outcomes"] = [
        {"prediction_id": "h1", "passed": True, "severity_at_test": 1.5, "registered": 2026,
         "date": ["2026-05-01"]},
        {"prediction_id": "h1", "passed": False, "severity_at_test": True},
        {"prediction_id": "h1", "passed": False, "severity_at_test": None, "registered": None,
         "date": "2026-05-01"},
    ]
    assert _full_error(t) == (
        "invalid theory object: "
        "assumption[0] added_for must be a string or null; "
        "test_outcome[0] severity_at_test must be a number between 0 and 1; "
        "test_outcome[0] registered must be a string or null; "
        "test_outcome[0] date must be a string or null; "
        "test_outcome[1] severity_at_test must be a number between 0 and 1"
    )


def test_full_validation_checks_every_entry_of_the_referencing_arrays():
    # An entry that is not a nonempty string reads as no entry at all (API_SPEC
    # section 4), so validate reports it in its place among the reference
    # messages. A single string is a one-element array, and any other value
    # that is not a list cannot be read as one.
    t = _consistent()
    t.data["predictions"] = [
        {"id": "h1", "statement": "s", "type": "point",
         "derives_from": ["pZ", None, "", 5, "p1"], "diagnostic_vs": ["a1", ["x"]]},
        {"id": "h2", "statement": "s", "type": "point", "derives_from": "p1", "diagnostic_vs": 5},
        {"id": "h3", "statement": "s", "type": "point", "derives_from": "  "},
    ]
    t.data["auxiliary_assumptions"] = [
        {"id": "x1", "statement": "s", "protects": [None, "h1", "hZ"]},
        {"id": "x2", "statement": "s", "protects": {"h1": True}},
    ]
    assert _full_error(t) == (
        "invalid theory object: "
        "prediction[0] derives_from 'pZ' is not a known proposition; "
        "prediction[0] derives_from entry 1 must be a nonempty string; "
        "prediction[0] derives_from entry 2 must be a nonempty string; "
        "prediction[0] derives_from entry 3 must be a nonempty string; "
        "prediction[0] diagnostic_vs entry 1 must be a nonempty string; "
        "prediction[1] diagnostic_vs must be a list; "
        "prediction[2] derives_from must be a list; "
        "assumption[0] protects entry 0 must be a nonempty string; "
        "assumption[0] protects 'hZ' is not a known prediction; "
        "assumption[1] protects must be a list"
    )


@pytest.mark.parametrize(("value", "expected"), [
    ({"type": "ode", "spec_ref": "models/panic.ode"}, None),
    ({"type": "none", "spec_ref": None}, None),
    ({"type": None}, None),
    ({}, None),
    ([], None),
    (None, None),
    ("ode", "formal_model must be a mapping"),
    (["ode"], "formal_model must be a mapping"),
    ({"type": "banana"}, "formal_model type 'banana' not allowed"),
    ({"type": "TBD"}, "formal_model type 'TBD' not allowed"),
    ({"type": ""}, "formal_model type '' not allowed"),
    ({"type": ["none"]}, "formal_model type must be a string"),
    ({"type": 3}, "formal_model type must be a string (quote the value in YAML)"),
    ({"type": "sem", "spec_ref": 5}, "formal_model spec_ref must be a string or null"),
])
def test_full_validation_checks_the_formal_model(value, expected):
    t = _consistent()
    t.data["formal_model"] = value
    assert t.validate() is True
    if expected is None:
        assert t.validate(full=True) is True
    else:
        assert _full_error(t) == "invalid theory object: " + expected


@pytest.mark.parametrize(("value", "expected"), [
    ({"id": "v1", "parent_id": None, "content_hash": None}, None),
    ({"id": "v2", "parent_id": "v1", "content_hash": "sha256:00"}, None),
    ({}, None),
    ([], None),
    (None, None),
    ("v1", "version must be a mapping"),
    ([{"id": "v1"}], "version must be a mapping"),
    ({"id": "v1", "author": "x", "date": "2026"},
     "version has unknown field: author; version has unknown field: date"),
    ({"id": 2, "parent_id": 1, "content_hash": ["x"]},
     "version id must be a string (quote the value in YAML); "
     "version parent_id must be a string or null; "
     "version content_hash must be a string or null"),
])
def test_full_validation_checks_the_version_block(value, expected):
    t = _consistent()
    t.data["version"] = value
    assert t.validate() is True
    if expected is None:
        assert t.validate(full=True) is True
    else:
        assert _full_error(t) == "invalid theory object: " + expected


@pytest.mark.parametrize(("value", "ok"), [
    ("1.0", True), ("10.25", True), ("one", False), ("1", False), ("1.0.0", False),
    ("v1.0", False), (" 1.0", False), ("1.0\n", False),
])
def test_full_validation_checks_the_schema_version_pattern(value, ok):
    t = _consistent()
    t.data["schema_version"] = value
    assert t.validate() is True  # the structural pass asks only for a nonempty string
    if ok:
        assert t.validate(full=True) is True
    else:
        assert _full_error(t) == (
            'invalid theory object: schema_version must match major.minor (for example "1.0")'
        )


def test_full_validation_checks_the_remaining_typed_fields():
    # The schema's other types, so that a theory the schema refuses is refused
    # here too (test_schema_agreement.py checks this with a JSON Schema validator).
    t = _consistent()
    t.data["constructs"] = [
        {"id": "c1", "label": "C1", "definition": "d", "measurement": ["m1", 5],
         "boundary_conditions": [["adults"]]},
        {"id": "c2", "label": "C2", "definition": "d", "measurement": {"m": "x"}},
    ]
    t.data["propositions"][0].update({"mechanism": 5, "functional_form": True})
    t.data["boundary_conditions"] = ["adults", None]
    t.data["predictions"][0]["risk_score"] = 2.0
    t.data["evidence"][0]["source_doi"] = 5
    t.data["test_outcomes"][0]["observed"] = 0.42
    t.data["alternatives"][0].update({"key_constructs": [3], "source_doi": ["10.1/x"]})
    t.data["provenance"] = [{"step": 1, "action": "tf_theory", "detail": "t"},
                            "tf_add_construct", [], [1], None]
    assert t.validate() is True
    assert _full_error(t) == (
        "invalid theory object: "
        "construct[0] measurement entry 1 must be a nonempty string; "
        "construct[0] boundary_conditions entry 0 must be a nonempty string; "
        "construct[1] measurement must be a list; "
        "proposition[0] mechanism must be a string (quote the value in YAML); "
        "proposition[0] functional_form must be a string (quote the value in YAML); "
        "boundary_conditions entry 1 must be a nonempty string; "
        "prediction[0] risk_score must be a number between 0 and 1; "
        "evidence[0] source_doi must be a string or null; "
        "test_outcome[0] observed must be a string (quote the value in YAML); "
        "alternative[0] key_constructs entry 0 must be a nonempty string; "
        "alternative[0] source_doi must be a string or null; "
        "provenance[0] step must be a string (quote the value in YAML); "
        "provenance[1] must be a mapping; "
        "provenance[3] must be a mapping; "
        "provenance[4] must be a mapping"
    )


# An unquoted integer of 400 digits. The reader keeps it as an int, too large
# for a float, while R's reader holds it as Inf.
HUGE = "1" + "0" * 400


def test_full_validation_reports_an_integer_too_large_for_a_float(tmp_path):
    # Testing such a number for NaN raised OverflowError, which lost every
    # message collected so far, while R reported each field.
    path = tmp_path / "huge.theory.yaml"
    path.write_text(f"""\
schema_version: "1.0"
id: t
title: T
maturity: testing
predictions:
  - id: h1
    statement: s
    type: point
    severity: {HUGE}
    risk_score: -{HUGE}
test_outcomes:
  - prediction_id: h1
    passed: true
    severity_at_test: {HUGE}
    observed: {HUGE}
""", encoding="utf-8")
    assert _full_error(tf.read(path)) == (
        "invalid theory object: "
        "prediction[0] severity must be a number between 0 and 1; "
        "test_outcome[0] severity_at_test must be a number between 0 and 1; "
        "prediction[0] risk_score must be a number between 0 and 1; "
        "test_outcome[0] observed must be a string (quote the value in YAML)"
    )


PASSED_STRING = """\
schema_version: "1.0"
id: t
title: T
maturity: testing
constructs:
  - id: c1
    label: Alpha
    definition: The first construct.
  - id: c2
    label: Beta
    definition: The second construct.
propositions:
  - id: p1
    from: c1
    to: c2
    relation: increases
    mechanism: Alpha drives Beta.
predictions:
  - id: h1
    statement: Beta rises with Alpha.
    type: directional
    derives_from: [p1]
auxiliary_assumptions:
  - id: x1
    statement: The effect needs a calm setting.
    added_for: h1
    protects: [h1]
test_outcomes:
  - prediction_id: h1
    passed: "true"
"""


def test_check_refuses_a_test_outcome_whose_passed_is_not_a_boolean(tmp_path):
    # A quoted "true" read as a failure, so the assumption added for h1 counted
    # as ad hoc and parsimony failed, in both engines alike.
    path = tmp_path / "passed-string.theory.yaml"
    path.write_text(PASSED_STRING, encoding="utf-8")
    t = tf.read(path)
    with pytest.raises(ValueError) as exc:
        t.check()
    assert str(exc.value) == (
        "check requires boolean test outcomes; "
        "non-boolean passed for test outcome of prediction: h1"
    )
    assert "test_outcome[0] passed must be true or false" in _full_error(t)
    # The refusal comes before any item is scored, the severity refusal included.
    t.data["predictions"][0]["severity"] = "0.8"
    with pytest.raises(ValueError, match="^check requires boolean test outcomes; "):
        t.check()
    del t.data["predictions"][0]["severity"]
    # Only a prediction other than h1, the anomaly x1 answers, can support x1,
    # so a second prediction carries the outcome from here on.
    t.data["predictions"].append({"id": "h2", "statement": "Beta lags Alpha by a day.",
                                  "type": "directional", "derives_from": ["p1"]})
    t.data["auxiliary_assumptions"][0]["protects"] = ["h1", "h2"]
    t.data["test_outcomes"] = [{"prediction_id": "h2", "passed": True}]
    assert _item(t.check(), "parsimony")["status"] == "pass"
    # A missing or null passed still reads as not passed.
    for outcome in ({"prediction_id": "h2"}, {"prediction_id": "h2", "passed": None}):
        t.data["test_outcomes"] = [outcome]
        assert _item(t.check(), "parsimony")["status"] == "fail"


def test_appraise_amendment_refuses_a_non_boolean_passed_in_either_theory():
    prior = _consistent()
    new = _consistent()
    new.data["predictions"].append(
        {"id": "h2", "statement": "s", "type": "point", "derives_from": ["p1"]})
    new.data["test_outcomes"] = [{"prediction_id": "h2", "passed": "yes"}]
    prior.data["test_outcomes"] = [{"prediction_id": "h1", "passed": 1}]
    with pytest.raises(ValueError) as exc:  # the amendment is checked first
        new.appraise_amendment(prior)
    assert str(exc.value) == (
        "appraise_amendment requires boolean test outcomes; "
        "non-boolean passed for test outcome of prediction: h2"
    )
    new.data["test_outcomes"] = [{"prediction_id": "h2", "passed": True}]
    with pytest.raises(ValueError) as exc:
        new.appraise_amendment(prior)
    assert str(exc.value) == (
        "appraise_amendment requires boolean test outcomes; "
        "non-boolean passed for test outcome of prediction: h1"
    )
    prior.data["test_outcomes"] = [{"prediction_id": "h1"}]
    # The boolean pass now counts. h2 derives from p1 alone, which the prior
    # already held, so it articulates old content and the amendment is neutral.
    result = new.appraise_amendment(prior)
    assert result["corroborated_new"] == ["h2"]
    assert (result["articulated"], result["verdict"]) == (["h2"], "neutral")
