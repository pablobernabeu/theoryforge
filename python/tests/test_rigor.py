import copy
import math

import pytest

import theoryforge as tf


def _items(report):
    return {it["id"]: it for it in report["items"]}


def test_panic_passes(panic_path):
    r = tf.read(panic_path).check()
    assert len(r["items"]) == 12
    assert r["gate"] == "pass"
    assert r["n_blockers_failed"] == 0
    it = _items(r)
    assert it["falsifiability"]["status"] == "pass"
    assert it["derivation_chain"]["status"] == "pass"
    assert it["causal_testability"]["status"] == "pass"
    assert it["diagnosticity"]["status"] == "pass"
    # aggregate is a sane bounded number
    assert 0.0 <= r["aggregate_score"] <= 100.0


def test_report_records_the_checklist_version(panic_path):
    # Every number in the report comes from the checklist's weights and
    # thresholds, so a report naming only the theory's schema version cannot be
    # compared against one scored by a different checklist.
    from theoryforge import _resources

    r = tf.read(panic_path).check()
    assert r["checklist_version"] == _resources.checklist()["schema_version"]
    assert list(r)[:4] == ["theory_id", "schema_version", "checklist_version", "maturity"]


def test_dossier_header_names_the_checklist_version(panic_path):
    t = tf.read(panic_path)
    assert f"- Checklist version: {t.check()['checklist_version']}" in t.dossier()


def test_weak_is_blocked(weak_path):
    r = tf.read(weak_path).check()
    assert r["gate"] == "blocked"
    it = _items(r)
    assert it["falsifiability"]["status"] == "fail"
    assert it["derivation_chain"]["status"] == "fail"
    assert r["n_blockers_failed"] == 2


def test_draft_is_advisory(weak_path):
    t = tf.read(weak_path)
    d = copy.deepcopy(t.data)
    d["maturity"] = "draft"
    r = tf.Theory(d).check()
    assert r["gate"] == "advisory"  # blockers do not block in draft mode


def test_check_reads_null_id_and_maturity_as_empty_strings():
    # R's .tf_str renders a null as "", and the report is compared
    # semantically across the twins, so Python must not emit null there.
    r = tf.Theory({"schema_version": None, "id": None, "title": "T",
                   "maturity": None}).check()
    assert r["theory_id"] == ""
    assert r["schema_version"] == ""
    assert r["maturity"] == ""


def _with_severities(*sevs):
    return tf.Theory({
        "schema_version": "1.0", "id": "t", "title": "T", "maturity": "building",
        "predictions": [
            {"id": f"h{i + 1}", "statement": "s", "type": "directional", "severity": s}
            for i, s in enumerate(sevs)
        ],
    })


def test_severity_mean_is_a_left_fold():
    # CPython 3.12+ sum() compensates and R's sum() uses an extended accumulator
    # on x86_64, so either gives 0.5 here where a plain left-to-right sum, as on
    # Apple Silicon R or Python 3.11, gives 0.49999999999999994. The twins agree
    # only if both fold left in file order (API_SPEC section 4).
    from theoryforge.rigor import _mean

    assert _mean([0.6, 0.7, 0.2]) == 0.49999999999999994


def test_risk_severity_status_comes_from_the_rounded_mean():
    # The exact mean equals min_severity (0.5). Comparing the unrounded mean made
    # the status depend on the platform's accumulator.
    it = _items(_with_severities(0.6, 0.7, 0.2).check())["risk_severity"]
    assert (it["status"], it["score"]) == ("pass", 0.5)


def test_check_refuses_a_severity_outside_the_unit_interval():
    # A severity of 7 was scored and could lift the aggregate above 100.
    for bad in (7, -3, 1.5):
        with pytest.raises(ValueError) as exc:
            _with_severities(0.5, bad).check()
        assert str(exc.value) == (
            "check requires prediction severities within [0, 1]; "
            "out-of-range severity for prediction: h2"
        )


def test_check_refuses_an_infinite_severity_as_non_numeric():
    # Python raised OverflowError from rnd() and R printed an aggregate of Inf.
    for bad in (math.inf, -math.inf, math.nan):
        with pytest.raises(ValueError) as exc:
            _with_severities(bad).check()
        assert str(exc.value) == (
            "check requires numeric prediction severities; "
            "non-numeric severity for prediction: h1"
        )


def test_check_accepts_the_ends_of_the_unit_interval():
    it = _items(_with_severities(0, 1).check())["risk_severity"]
    assert (it["status"], it["score"]) == ("pass", 0.5)


def test_rnd_never_returns_negative_zero():
    from theoryforge._num import rnd

    for x in (-0.0004, -0.0, -1e-9):
        assert math.copysign(1.0, rnd(x, 3)) == 1.0


def test_report_json_roundtrips(panic_path):
    import json
    r = tf.read(panic_path).report(format="json")
    parsed = json.loads(r)
    assert parsed["theory_id"] == "panic-network-2026"
    assert parsed["items"][0]["id"] == "falsifiability"


def test_report_html(panic_path):
    html = tf.read(panic_path).report(format="html")
    assert "<table>" in html and "Rigour report" in html
