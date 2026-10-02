"""The four prediction types, defined and honoured by the shipped examples.

The precision item, the falsifiability blocker and the claim-form rubric all read
a prediction's declared ``type``, so the schema defines each type and the bundled
theories use the labels as defined. The R suite asserts the same in
test-prediction-types.R.
"""
from __future__ import annotations

from pathlib import Path

import pytest

import theoryforge as tf
from theoryforge._resources import theory_schema

ROOT = Path(__file__).resolve().parents[2]
APP_EXAMPLES = ROOT / "apps" / "examples"


def test_schema_defines_each_prediction_type():
    props = theory_schema()["properties"]
    pred = props["predictions"]["items"]["properties"]
    desc = pred["type"]["description"]
    assert "existence: that an effect or relation exists, without a direction" in desc
    assert "directional: a sign or an order" in desc
    assert "the range the theory permits" in desc
    assert "measurement tolerance, not latitude the theory allows" in desc
    assert "self-declared" in desc


def test_schema_marks_the_unread_fields_as_informational():
    props = theory_schema()["properties"]
    pred = props["predictions"]["items"]["properties"]
    outcome = props["test_outcomes"]["items"]["properties"]
    assert pred["risk_score"]["description"].startswith("Informational, read by no function.")
    assert outcome["severity_at_test"]["description"] == "Informational, read by no function."


PANIC_POINT_STATEMENTS = {
    ("panic-network.theory.yaml", "pred1"):
        "An interoceptive challenge raises heart rate 20 beats per minute above baseline, "
        "within a measurement tolerance of 5, within 90 seconds.",
    ("panic-network-2026-v2.theory.yaml", "pred1"):
        "An interoceptive challenge raises heart rate 20 beats per minute above baseline, "
        "within a measurement tolerance of 5, within 90 seconds.",
    ("panic-network-2026-v2.theory.yaml", "pred4"):
        "Blocking interoceptive feedback lowers avoidance-task scores by 30 per cent, "
        "within a tolerance of 5 percentage points, within two weeks.",
}


@pytest.mark.parametrize(("fixture", "pid"), sorted(PANIC_POINT_STATEMENTS))
def test_panic_point_predictions_state_value_and_tolerance(fixtures_dir, fixture, pid):
    # These read "to a specified level" before, a point claim that named no value.
    preds = {p["id"]: p for p in tf.read(fixtures_dir / fixture).data["predictions"]}
    assert preds[pid]["type"] == "point"
    assert preds[pid]["statement"] == PANIC_POINT_STATEMENTS[(fixture, pid)]


def _app_example(name: str) -> tf.Theory:
    path = APP_EXAMPLES / name
    if not path.exists():
        pytest.skip("apps/examples is not reachable from this test run")
    return tf.read(path)


# Ordinal, comparative, anti-phase and invariance claims, typed as the sign or
# order they assert. Their declared severities are left as the authors set them.
RETYPED = [
    ("effort-recovery.theory.yaml", "pred3", 0.7),
    ("happy-vowel-manchester.theory.yaml", "pred_independence", 0.8),
    ("cognitive-dissonance.theory.yaml", "pred_rating_point", 0.7),
    ("cognitive-dissonance.theory.yaml", "pred_dissonance_mediates", 0.6),
    ("stereotype-threat.theory.yaml", "pred_salience_activation", 0.6),
]


@pytest.mark.parametrize(("name", "pid", "declared"), RETYPED)
def test_app_examples_type_comparative_claims_as_directional(name, pid, declared):
    preds = {p["id"]: p for p in _app_example(name).data["predictions"]}
    assert preds[pid]["type"] == "directional"
    assert preds[pid]["severity"] == declared


def test_effort_recovery_precision_reflects_its_one_interval_prediction():
    report = _app_example("effort-recovery.theory.yaml").check()
    precision = next(it for it in report["items"] if it["id"] == "precision")
    assert (precision["status"], precision["score"]) == ("warn", 0.333)
