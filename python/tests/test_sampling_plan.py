"""The sampling plan a prediction records (API_SPEC.md section 30).

A prediction may carry a ``test`` block: the planned sample size, alpha,
sidedness, smallest effect of interest, power and the design analysis behind
them. Full validation checks it, the preregistration lists it after the
hypotheses, and nothing scores it. The R suite (test-sampling-plan.R) builds the
same theories and asserts the same messages and lines.
"""
import copy
import math

import pytest

import theoryforge as tf
from theoryforge import _resources
from theoryforge.core import Theory

SECTION = "## Sampling plan (author-recorded; not scored)"

FULL = {"n_planned": 120, "unit": "participants", "alpha": 0.005, "sided": "one",
        "sesoi": 0.2, "sesoi_scale": "Cohen's d", "power": 0.9, "power_lo": 0.88,
        "power_hi": 0.92, "method": "simulation in pilotr", "design_ref": "https://osf.io/abcde",
        "justification": "The smallest effect that would change practice."}


def _theory(*tests) -> Theory:
    """A theory with one interval prediction h<i> per entry, given ``test`` unless _ABSENT."""
    preds = []
    for i, block in enumerate(tests, start=1):
        p = {"id": f"h{i}", "statement": f"Claim {i}.", "type": "interval"}
        if block is not _ABSENT:
            p["test"] = block
        preds.append(p)
    return Theory({"schema_version": "1.0", "id": "t", "title": "T", "maturity": "testing",
                   "predictions": preds})


_ABSENT = object()


def _full_errors(t: Theory) -> str:
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    return str(exc.value)


def _section(text: str) -> str:
    """The sampling-plan section of a preregistration, from its heading to the blank line."""
    start = text.index(SECTION)
    return text[start:text.index("\n\n", start)]


# -- the schema ------------------------------------------------------------------

def test_the_schema_closes_the_test_block():
    test = _resources.theory_schema()["properties"]["predictions"]["items"]["properties"]["test"]
    assert test["additionalProperties"] is False
    assert list(test["properties"]) == [
        "n_planned", "unit", "alpha", "sided", "sesoi", "sesoi_scale", "power",
        "decision_probability", "power_lo", "power_hi", "method", "design_ref",
        "justification"]
    assert test["properties"]["n_planned"] == {"type": "integer", "minimum": 1}
    assert test["properties"]["alpha"] == {"type": "number", "exclusiveMinimum": 0,
                                           "exclusiveMaximum": 1}
    assert test["properties"]["sided"] == {"type": "string", "enum": ["two", "one"]}
    assert test["dependentRequired"] == {"power_lo": ["power_hi"], "power_hi": ["power_lo"]}


# -- the builder (API_SPEC.md section 8) -------------------------------------------

def test_add_prediction_stores_a_test_block_when_given():
    block = {"n_planned": 48, "alpha": 0.05}
    t = (tf.new_theory("t", "T")
         .add_prediction("h1", "Claim.", "interval", severity=0.6, test=block)
         .add_prediction("h2", "Claim.", "interval"))
    h1, h2 = t.data["predictions"]
    assert list(h1) == ["id", "statement", "type", "severity", "test"]
    assert h1["test"] == {"n_planned": 48, "alpha": 0.05}
    assert "test" not in h2
    # The block is stored as a copy, as R's value semantics store it, so a later
    # change to the caller's mapping leaves the theory as it was.
    block["alpha"] = 0.01
    assert h1["test"]["alpha"] == 0.05
    assert t.data["provenance"][-2] == {"step": "2", "action": "tf_add_prediction",
                                        "detail": "h1"}


# -- validation (API_SPEC.md section 2, item 14) ------------------------------------

def test_a_complete_block_and_the_empty_forms_pass_full_validation():
    t = _theory(FULL, None, {}, [], _ABSENT, {"n_planned": 2.0, "power": 1, "power_lo": 0,
                                             "power_hi": 1})
    assert t.validate(full=True) is True


def test_full_validation_reports_each_fault_of_a_test_block():
    t = _theory(
        FULL,
        "n = 48",
        [48, 0.05],
        {"sides": "two", "n_planned": 0, "unit": 5, "alpha": 0.05},
        {"n_planned": 48.5, "alpha": 1, "sided": "both"},
        {"n_planned": "48", "alpha": 0, "sided": ["two"], "sesoi": "20"},
        {"n_planned": True, "alpha": True, "sesoi": math.inf, "sesoi_scale": ["ms"],
         "power": 1.2, "decision_probability": -0.1, "power_lo": 0.95, "power_hi": 0.85},
        {"power_lo": 0.8, "method": 1, "design_ref": True, "justification": ["x"]},
        {"power_lo": "0.8", "power_hi": math.nan, "sesoi": math.nan},
        {"power_hi": 0.9},
    )
    # The structural pass leaves the block alone.
    assert t.validate() is True
    assert _full_errors(t) == "invalid theory object: " + "; ".join([
        "prediction[1] test must be a mapping",
        "prediction[2] test must be a mapping",
        "prediction[3] test has unknown field: sides",
        "prediction[3] test n_planned must be a whole number of at least 1",
        "prediction[3] test unit must be a string (quote the value in YAML)",
        "prediction[4] test n_planned must be a whole number of at least 1",
        "prediction[4] test alpha must be a number between 0 and 1",
        "prediction[4] test sided must be one of: two, one",
        "prediction[5] test n_planned must be a whole number of at least 1",
        "prediction[5] test alpha must be a number between 0 and 1",
        "prediction[5] test sided must be one of: two, one",
        "prediction[5] test sesoi must be a finite number",
        "prediction[6] test n_planned must be a whole number of at least 1",
        "prediction[6] test alpha must be a number between 0 and 1",
        "prediction[6] test sesoi must be a finite number",
        "prediction[6] test sesoi_scale must be a string",
        "prediction[6] test power must be a number between 0 and 1",
        "prediction[6] test decision_probability must be a number between 0 and 1",
        "prediction[6] test power_lo exceeds power_hi",
        "prediction[7] test power_lo and power_hi must be given together",
        "prediction[7] test method must be a string (quote the value in YAML)",
        "prediction[7] test design_ref must be a string (quote the value in YAML)",
        "prediction[7] test justification must be a string",
        "prediction[8] test sesoi must be a finite number",
        "prediction[8] test power_lo must be a number between 0 and 1",
        "prediction[8] test power_hi must be a number between 0 and 1",
        "prediction[9] test power_lo and power_hi must be given together",
    ])


def test_a_test_block_is_reported_after_the_risk_score_and_the_bounds():
    t = _theory({"alpha": 2})
    t.data["predictions"][0].update({"risk_score": 2, "bounds": [20, 60]})
    assert _full_errors(t) == (
        "invalid theory object: "
        "prediction[0] risk_score must be a number between 0 and 1; "
        "prediction[0] bounds must be a mapping with numeric or null lower and upper; "
        "prediction[0] test alpha must be a number between 0 and 1")


def test_an_integer_too_large_for_a_float_is_no_planned_sample(tmp_path):
    # R's reader holds an unquoted integer of 400 digits as Inf, so both twins
    # refuse it as a sample size.
    path = tmp_path / "huge.theory.yaml"
    path.write_text(f"""\
schema_version: "1.0"
id: t
title: T
maturity: testing
predictions:
  - id: h1
    statement: s
    type: interval
    test: {{n_planned: 1{"0" * 400}}}
""", encoding="utf-8")
    assert _full_errors(tf.read(path)) == (
        "invalid theory object: prediction[0] test n_planned must be a whole number of at least 1")


# -- the preregistration (API_SPEC.md sections 11 and 30) ----------------------------

def test_the_preregistration_lists_the_sampling_plan_after_the_hypotheses():
    t = _theory(
        FULL,
        _ABSENT,
        {"decision_probability": 0.8, "method": "simulation"},
        {"alpha": 0.0001, "sided": "two"},
        {"justification": "Fixed by the size of the archive."},
        # A qualifier is written only with the value it qualifies.
        {"unit": "participants", "sesoi_scale": "ms", "power_lo": 0.8, "power_hi": 0.9,
         "method": "analytic"},
        {"sided": "two", "n_planned": 48},
        "48 participants",
        # A value that full validation refuses reads as absent.
        {"n_planned": 48.5, "alpha": 1, "power": 1.5, "sided": "both", "unit": 5},
        {"power": 0.85, "decision_probability": 0.7, "power_lo": 0.9, "power_hi": 0.8},
        {"n_planned": 1e6, "alpha": 5e-8, "sesoi": -0.2, "power": 1},
    )
    text = t.preregister()
    assert _section(text) == "\n".join([
        SECTION,
        "- h1: n = 120 participants; alpha 0.005, one-sided; smallest effect of interest 0.2 "
        "Cohen's d; power 0.9 [0.88, 0.92] (simulation in pilotr); design: "
        "https://osf.io/abcde. The smallest effect that would change practice.",
        "- h2: no sampling plan stated",
        "- h3: decision probability 0.8 (simulation)",
        "- h4: alpha 0.0001, two-sided",
        "- h5: Fixed by the size of the archive.",
        "- h6: no sampling plan stated",
        "- h7: n = 48; two-sided",
        "- h8: no sampling plan stated",
        "- h9: no sampling plan stated",
        "- h10: power 0.85, decision probability 0.7",
        "- h11: n = 1000000; alpha 5e-08; smallest effect of interest -0.2; power 1",
    ])
    # The section sits between the hypotheses and the implied independencies.
    assert "   - Test record: untested\n\n" + SECTION + "\n" in text
    assert _section(text) + "\n\n## Implied conditional independencies" in text


def test_a_theory_without_a_stated_plan_has_no_section():
    bare = _theory(_ABSENT, _ABSENT).preregister()
    assert SECTION not in bare
    for blocks in ((None, {}), ([], "n = 48"), ({"unit": "participants"}, {"alpha": 2})):
        assert _theory(*blocks).preregister() == bare


def test_the_modality_example_states_its_plan_and_matches_its_golden(modality_path, fixtures_dir):
    t = tf.read(modality_path)
    text = t.preregister()
    golden = (fixtures_dir / "expected" / "modality-switching-2026.prereg.md").read_bytes()
    assert text.encode("utf-8") == golden
    assert _section(text) == "\n".join([
        SECTION,
        "- pred1: no sampling plan stated",
        "- pred2: n = 48 participants; alpha 0.05, two-sided; smallest effect of interest "
        "20 ms; power 0.9 (simulation). Illustrative values.",
        "- pred3: no sampling plan stated",
        "- pred4: no sampling plan stated",
    ])
    # Without the block the document is the earlier format, the section left out.
    del t.data["predictions"][1]["test"]
    assert t.preregister() == text.replace(_section(text) + "\n\n", "")


@pytest.mark.parametrize(("fixture", "golden"), [
    ("panic-network.theory.yaml", "panic-network-2026.prereg.md"),
    ("panic-network-2026-v2.theory.yaml", "panic-network-2026-v2.prereg.md"),
    ("weak-theory.theory.yaml", "weak-demo.prereg.md"),
])
def test_every_other_fixture_keeps_its_preregistration(fixtures_dir, fixture, golden):
    text = tf.read(fixtures_dir / fixture).preregister()
    assert SECTION not in text
    assert text.encode("utf-8") == (fixtures_dir / "expected" / golden).read_bytes()


def test_the_dossier_carries_the_plan_in_its_preregistration(modality_path):
    d = tf.read(modality_path).dossier()
    assert "\n## Preregistration\n\n# Preregistration: " in d
    assert d.count(SECTION) == 1
    assert d.endswith(tf.read(modality_path).preregister())


def test_a_written_theory_reads_back_with_its_plan(tmp_path, modality_path):
    t = tf.read(modality_path)
    for name in ("m.theory.yaml", "m.theory.json"):
        t.write(tmp_path / name)
        back = tf.read(tmp_path / name)
        assert back.data["predictions"][1]["test"] == t.data["predictions"][1]["test"]
        assert back.preregister() == t.preregister()


# -- recorded, not scored -------------------------------------------------------------

def test_the_block_moves_no_score(modality_path):
    # Power must not raise a prediction's severity (Meehl, 1967), so nothing
    # reads the block but validation and the preregistration.
    with_plan = tf.read(modality_path)
    without = copy.deepcopy(with_plan)
    del without.data["predictions"][1]["test"]
    for p in with_plan.data["predictions"]:
        p["test"] = {"n_planned": 10_000, "alpha": 0.001, "power": 0.99}
    assert with_plan.check() == without.check()
    assert with_plan.severity() == without.severity()
    assert with_plan.post_data_severity() == without.post_data_severity()
    assert with_plan.report() == without.report()
