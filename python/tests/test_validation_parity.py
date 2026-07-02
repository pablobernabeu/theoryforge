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


def test_read_and_read_corpus_reject_non_mapping(tmp_path):
    p = tmp_path / "bad.yaml"
    p.write_text("- just\n- a\n- list\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Theory data must be a mapping"):
        tf.read(p)
    c = tmp_path / "badc.yaml"
    c.write_text("- 1\n- 2\n", encoding="utf-8")
    with pytest.raises(ValueError, match="Corpus data must be a mapping"):
        tf.read_corpus(c)


def test_osf_push_base_url_override():
    res = tf.new_theory("t", "T").osf_push(node="abc12", base_url="https://example.org/v1/resources/")
    assert res["request"]["url"].startswith("https://example.org/v1/resources/abc12/")


def test_render_report_falls_back_to_id_on_empty_title(tmp_path):
    out = tf.new_theory("the-id", "").render_report(tmp_path / "r.qmd")
    assert "theoryforge report: the-id" in open(out, encoding="utf-8").read()
