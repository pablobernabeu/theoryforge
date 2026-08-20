"""Validation and cross-language parity behaviour.

These lock the contracts that the byte-identical golden artefacts do not exercise:
the opt-in referential-integrity validation, the structural error message text,
the non-mapping read guards, the OSF base_url override and the report title
fallback. The R suite asserts the same behaviour so the two stay aligned.
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
        "evidence": [{"supports": "h1"}],
    })


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
    # differently in the two engines. Both now give the contract's message.
    for value in (["draft", "building"], ["draft"], {"stage": "draft"}):
        t = Theory({"schema_version": "1.0", "id": "x", "title": "T", "maturity": value})
        with pytest.raises(ValueError) as exc:
            t.validate()
        assert str(exc.value) == (
            "invalid theory object: missing/empty required field: maturity; "
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
