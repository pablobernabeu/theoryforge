"""Post-data severity from an outcome's estimate and standard error (API_SPEC.md section 29).

The R suite (test-post-data-severity.R) builds the same theories and asserts the
same values, rows and messages, and both twins compare their result for the
modality-switching example with the same golden file.
"""
import json
import math
from statistics import NormalDist

import pytest

import theoryforge as tf
from theoryforge._num import rnd
from theoryforge.core import Theory


def _theory(bounds, outcomes, statement="The effect lies within the bounds.") -> Theory:
    """A theory with one interval prediction h1, given ``bounds`` unless None."""
    pred = {"id": "h1", "statement": statement, "type": "interval"}
    if bounds is not None:
        pred["bounds"] = bounds
    return Theory({"schema_version": "1.0", "id": "t", "title": "T", "maturity": "testing",
                   "predictions": [pred], "test_outcomes": outcomes})


def _sev(bounds, estimate, se) -> float:
    outcome = {"prediction_id": "h1", "passed": True, "estimate": estimate, "se": se}
    rows = _theory(bounds, [outcome]).post_data_severity()
    assert len(rows) == 1
    return rows[0]["severity"]


def _refusal(t) -> str:
    with pytest.raises(ValueError) as exc:
        t.post_data_severity()
    return str(exc.value)


# -- the values ----------------------------------------------------------------

def test_mayo_and_spanos_worked_value():
    # Mayo and Spanos's (2011) worked value: the claim that a mean exceeds mu1
    # passes with SEV = Phi(1) = .841 when the estimate lies one standard error
    # above mu1. A one-sided claim is a lower bound with the upper bound open.
    assert _sev({"lower": 0.2, "upper": None}, 0.4, 0.2) == 0.841
    assert _sev({"lower": 0.2}, 0.4, 0.2) == 0.841


@pytest.mark.parametrize(("se", "expected"), [(0.01, 1.0), (0.10, 0.841), (0.20, 0.691)])
def test_one_claim_and_one_estimate_pass_less_severely_as_the_error_grows(se, expected):
    # |r| <= .10 with an estimate of 0. The claim-form rubric gives the claim one
    # value whatever the test, and post-data severity falls as the test weakens.
    assert _sev({"lower": -0.10, "upper": 0.10}, 0.0, se) == expected


def test_two_finite_bounds_give_one_minus_the_tost_p_value():
    # The two one-sided tests reject at p_lower and p_upper, and TOST reports
    # the larger. Its complement is the smaller of the two one-sided severities.
    phi = NormalDist().cdf
    for estimate, se in ((0.03, 0.05), (-0.08, 0.04), (0.12, 0.10), (0.0, 0.2)):
        p_lower = 1 - phi((estimate + 0.10) / se)
        p_upper = 1 - phi((0.10 - estimate) / se)
        assert _sev({"lower": -0.10, "upper": 0.10}, estimate, se) == \
            rnd(1 - max(p_lower, p_upper), 3)


def test_a_point_claim_caps_severity_at_one_half():
    # With lower equal to upper the two one-sided severities sum to 1, so their
    # minimum is at most .5. A point claim needs a tolerance around its value.
    assert _sev({"lower": 0.3, "upper": 0.3}, 0.3, 0.05) == 0.5
    assert _sev({"lower": 0.3, "upper": 0.3}, 0.32, 0.05) == 0.345
    assert _sev({"lower": 0.2, "upper": 0.4}, 0.32, 0.05) == 0.945


def test_an_estimate_outside_the_bounds_passes_with_low_severity():
    assert _sev({"lower": 20, "upper": 60}, 70, 6) == 0.048
    assert _sev({"lower": 20, "upper": None}, 15, 5) == 0.159


# -- the rows ------------------------------------------------------------------

ROWS_THEORY = {
    "schema_version": "1.0", "id": "t", "title": "T", "maturity": "testing",
    "predictions": [
        {"id": "h1", "statement": "s", "type": "interval", "bounds": {"lower": 20, "upper": 60}},
        {"id": "h2", "statement": "s", "type": "directional"},
        {"id": "h3", "statement": "s", "type": "directional",
         "bounds": {"lower": 0.1, "upper": None}},
        {"id": "h4", "statement": "s", "type": "directional", "bounds": {"lower": -math.inf,
                                                                      "upper": 0}},
    ],
    "test_outcomes": [
        {"prediction_id": "h1", "passed": True, "estimate": 41, "se": 6},
        # A prediction without bounds states no region for the estimate.
        {"prediction_id": "h2", "passed": True, "estimate": 1.0, "se": 0.5},
        # An outcome without an estimate and a standard error has no data to read.
        {"prediction_id": "h1", "passed": False, "estimate": None, "se": None},
        {"prediction_id": "h3", "passed": True, "estimate": 0.25, "se": 0.1},
        # An outcome naming no declared prediction, or naming one by a number.
        {"prediction_id": "hZ", "passed": True, "estimate": 1.0, "se": 0.5},
        {"prediction_id": ["h1"], "passed": True, "estimate": 1.0, "se": 0.5},
        "not an outcome",
        {"prediction_id": "h4", "passed": False, "estimate": 0.5, "se": 0.25},
    ],
}


def test_one_row_per_outcome_that_has_data_and_a_prediction_with_bounds():
    rows = Theory(json.loads(json.dumps(ROWS_THEORY, allow_nan=True))).post_data_severity()
    assert rows == [
        {"prediction_id": "h1", "outcome": 0, "lower": 20.0, "upper": 60.0,
         "estimate": 41.0, "se": 6.0, "severity": 0.999},
        {"prediction_id": "h3", "outcome": 3, "lower": 0.1, "upper": None,
         "estimate": 0.25, "se": 0.1, "severity": 0.933},
        # An infinite bound is open, and is reported as one.
        {"prediction_id": "h4", "outcome": 7, "lower": None, "upper": 0.0,
         "estimate": 0.5, "se": 0.25, "severity": 0.023},
    ]
    assert list(rows[0]) == ["prediction_id", "outcome", "lower", "upper", "estimate", "se",
                             "severity"]


def test_the_module_function_and_the_method_agree():
    t = Theory(dict(ROWS_THEORY))
    assert tf.post_data_severity(t) == t.post_data_severity() == tf.post_data_severity(t.data)


def test_a_theory_without_data_has_no_rows(panic_path, weak_path):
    assert tf.read(panic_path).post_data_severity() == []
    assert tf.read(weak_path).post_data_severity() == []
    assert tf.new_theory("t", "T").post_data_severity() == []


def test_the_modality_example_matches_its_golden(modality_path, fixtures_dir):
    rows = tf.read(modality_path).post_data_severity()
    assert rows == [{"prediction_id": "pred2", "outcome": 0, "lower": 20.0, "upper": 60.0,
                     "estimate": 41.0, "se": 6.0, "severity": 0.999}]
    golden = fixtures_dir / "expected" / "modality-switching-2026.post_data_severity.json"
    assert json.loads(golden.read_text(encoding="utf-8")) == rows


def test_the_name_is_not_collected_by_pytest():
    # pytest collects a module-level function whose name starts with test_, and
    # an exported test_severity() made every test module that imported it fail.
    assert not any(name.startswith("test") for name in tf.__all__)


# -- the refusals --------------------------------------------------------------

GOOD = {"prediction_id": "h1", "passed": True, "estimate": 41, "se": 6}


@pytest.mark.parametrize(("outcome", "message"), [
    ({"estimate": 41}, "requires both estimate and se; test_outcome[1]"),
    ({"se": 6, "estimate": None}, "requires both estimate and se; test_outcome[1]"),
    ({"estimate": 41, "se": 0}, "requires a finite se greater than 0; test_outcome[1]"),
    ({"estimate": 41, "se": -6}, "requires a finite se greater than 0; test_outcome[1]"),
    ({"estimate": 41, "se": "6"}, "requires a finite se greater than 0; test_outcome[1]"),
    ({"estimate": 41, "se": True}, "requires a finite se greater than 0; test_outcome[1]"),
    ({"estimate": 41, "se": math.inf}, "requires a finite se greater than 0; test_outcome[1]"),
    ({"estimate": 41, "se": math.nan}, "requires a finite se greater than 0; test_outcome[1]"),
    ({"estimate": math.nan, "se": 6}, "requires a finite estimate; test_outcome[1]"),
    ({"estimate": -math.inf, "se": 6}, "requires a finite estimate; test_outcome[1]"),
    ({"estimate": "41", "se": 6}, "requires a finite estimate; test_outcome[1]"),
    ({"estimate": [41], "se": 6}, "requires a finite estimate; test_outcome[1]"),
])
def test_an_outcome_without_usable_data_is_refused(outcome, message):
    # The outcome's data are refused whether or not its prediction declares
    # bounds, here none, since a half-recorded result is a mistake to report.
    bad = {"prediction_id": "h1", "passed": True, **outcome}
    for bounds in ({"lower": 20, "upper": 60}, None):
        t = _theory(bounds, [GOOD, bad])
        assert _refusal(t) == "post_data_severity " + message


@pytest.mark.parametrize(("bounds", "message"), [
    ({"lower": None, "upper": None}, "requires at least one finite bound; prediction 'h1'"),
    ({}, "requires at least one finite bound; prediction 'h1'"),
    ([], "requires at least one finite bound; prediction 'h1'"),
    ({"lower": -math.inf, "upper": math.inf},
     "requires at least one finite bound; prediction 'h1'"),
    ({"lower": 60, "upper": 20}, "requires lower <= upper; prediction 'h1'"),
    ({"lower": math.inf, "upper": 20}, "requires lower <= upper; prediction 'h1'"),
    ([20, 60], "requires bounds with numeric or null lower and upper; prediction 'h1'"),
    (40, "requires bounds with numeric or null lower and upper; prediction 'h1'"),
    ({"lower": "20", "upper": 60},
     "requires bounds with numeric or null lower and upper; prediction 'h1'"),
    ({"lower": 20, "upper": True},
     "requires bounds with numeric or null lower and upper; prediction 'h1'"),
    ({"lower": math.nan, "upper": 60},
     "requires bounds with numeric or null lower and upper; prediction 'h1'"),
])
def test_bounds_that_state_no_region_are_refused(bounds, message):
    assert _refusal(_theory(bounds, [GOOD])) == "post_data_severity " + message


def test_bounds_are_read_only_for_an_outcome_with_data():
    # Validation reports the bounds of every prediction. This function reads
    # a prediction's bounds only to compute a row from an outcome's data.
    assert _theory({"lower": 60, "upper": 20}, [{"prediction_id": "h1", "passed": True}]) \
        .post_data_severity() == []


def test_the_first_refusal_in_file_order_is_raised():
    t = _theory({"lower": 60, "upper": 20},
                [{"prediction_id": "h1", "passed": True, "estimate": 41, "se": 6},
                 {"prediction_id": "h1", "passed": True, "estimate": 41}])
    assert _refusal(t) == "post_data_severity requires lower <= upper; prediction 'h1'"
    t.data["test_outcomes"].reverse()
    assert _refusal(t) == "post_data_severity requires both estimate and se; test_outcome[0]"


HUGE = "1" + "0" * 400


def test_an_integer_too_large_for_a_float_reads_as_an_infinity(tmp_path):
    # The reader keeps it as an int and R's reader holds it as Inf, so both
    # twins take it for an infinity.
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
    bounds: {{lower: -{HUGE}, upper: 60}}
test_outcomes:
  - prediction_id: h1
    passed: true
    estimate: 41
    se: 6
""", encoding="utf-8")
    t = tf.read(path)
    assert t.post_data_severity() == [{"prediction_id": "h1", "outcome": 0, "lower": None,
                                       "upper": 60.0, "estimate": 41.0, "se": 6.0,
                                       "severity": 0.999}]
    t.data["test_outcomes"][0]["estimate"] = int(HUGE)
    assert _refusal(t) == "post_data_severity requires a finite estimate; test_outcome[0]"


# -- validation (API_SPEC.md section 2, item 14) -------------------------------

def test_full_validation_checks_bounds_estimate_and_se():
    t = Theory({
        "schema_version": "1.0", "id": "t", "title": "T", "maturity": "testing",
        "predictions": [
            {"id": "h1", "statement": "s", "type": "interval", "bounds": {"lower": 20, "upper": 60}},
            {"id": "h2", "statement": "s", "type": "interval", "bounds": [20, 60]},
            {"id": "h3", "statement": "s", "type": "interval",
             "bounds": {"lower": "20", "upper": 60, "unit": "ms"}},
            {"id": "h4", "statement": "s", "type": "interval",
             "bounds": {"lower": None, "upper": None}},
            {"id": "h5", "statement": "s", "type": "interval", "bounds": {"lower": 60, "upper": 20}},
            {"id": "h6", "statement": "s", "type": "interval",
             "bounds": {"lower": math.inf, "upper": -math.inf}},
            {"id": "h7", "statement": "s", "type": "interval", "bounds": {"lower": math.nan}},
            {"id": "h8", "statement": "s", "type": "directional", "bounds": {"lower": 0.1}},
            {"id": "h9", "statement": "s", "type": "directional", "bounds": None},
            {"id": "h10", "statement": "s", "type": "directional", "bounds": {}},
        ],
        "test_outcomes": [
            {"prediction_id": "h1", "passed": True, "estimate": 41, "se": 6},
            {"prediction_id": "h1", "passed": True, "estimate": "41", "se": 6},
            {"prediction_id": "h1", "passed": True, "estimate": math.nan, "se": 0},
            {"prediction_id": "h1", "passed": True, "estimate": 41},
            {"prediction_id": "h1", "passed": True, "se": math.inf},
            {"prediction_id": "h1", "passed": True, "estimate": True, "se": -1},
            {"prediction_id": "h1", "passed": True, "estimate": None, "se": None},
        ],
    })
    assert t.validate() is True
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    assert str(exc.value) == (
        "invalid theory object: "
        "prediction[1] bounds must be a mapping with numeric or null lower and upper; "
        "prediction[2] bounds has unknown field: unit; "
        "prediction[2] bounds must be a mapping with numeric or null lower and upper; "
        "prediction[3] bounds needs at least one finite bound; "
        "prediction[4] bounds lower exceeds upper; "
        "prediction[5] bounds needs at least one finite bound; "
        "prediction[5] bounds lower exceeds upper; "
        "prediction[6] bounds must be a mapping with numeric or null lower and upper; "
        "prediction[9] bounds needs at least one finite bound; "
        "test_outcome[1] estimate must be a finite number; "
        "test_outcome[2] estimate must be a finite number; "
        "test_outcome[2] se must be a finite number greater than 0; "
        "test_outcome[3] estimate and se must be given together; "
        "test_outcome[4] se must be a finite number greater than 0; "
        "test_outcome[4] estimate and se must be given together; "
        "test_outcome[5] estimate must be a finite number; "
        "test_outcome[5] se must be a finite number greater than 0"
    )


def test_full_validation_reads_an_integer_too_large_for_a_float_as_an_infinity(tmp_path):
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
    bounds: {{lower: {HUGE}}}
test_outcomes:
  - prediction_id: h1
    passed: true
    estimate: {HUGE}
    se: {HUGE}
""", encoding="utf-8")
    with pytest.raises(ValueError) as exc:
        tf.read(path).validate(full=True)
    assert str(exc.value) == (
        "invalid theory object: "
        "prediction[0] bounds needs at least one finite bound; "
        "test_outcome[0] estimate must be a finite number; "
        "test_outcome[0] se must be a finite number greater than 0"
    )


def test_a_theory_that_passes_full_validation_is_never_refused():
    # Every refusal above has a validation message, so a theory that validates
    # gets its rows.
    t = Theory(json.loads(json.dumps(ROWS_THEORY)))
    t.data["test_outcomes"] = [o for o in t.data["test_outcomes"] if isinstance(o, dict)
                               and isinstance(o["prediction_id"], str) and o["prediction_id"] != "hZ"]
    assert t.validate(full=True) is True
    assert len(t.post_data_severity()) == 3


# -- the dossier (API_SPEC.md section 20) --------------------------------------

def test_the_dossier_gives_each_computable_severity_in_the_test_record(modality_path):
    d = tf.read(modality_path).dossier()
    assert ("\n## Test record\n\n"
            "- pred2: passed; observed: Illustrative values, not a reported result: switch cost "
            "41 ms (SE 6 ms).; post-data severity 0.999 for [20.0, 60.0]\n"
            "\n## Evidence\n") in d


def test_the_dossier_writes_an_open_bound_as_an_infinity_and_skips_what_it_cannot_compute():
    t = Theory(json.loads(json.dumps(ROWS_THEORY)))
    t.data["test_outcomes"] = [
        {"prediction_id": "h3", "passed": True, "estimate": 0.25, "se": 0.1, "date": "2026-05-01"},
        {"prediction_id": "h4", "passed": False, "estimate": 0.5, "se": 0.25},
        {"prediction_id": "h2", "passed": True, "estimate": 1.0, "se": 0.5},
        # The dossier lists an outcome it cannot compute without the note, and goes on.
        {"prediction_id": "h1", "passed": True, "estimate": 41, "se": 0},
    ]
    d = t.dossier()
    assert ("\n## Test record\n\n"
            "- h3: passed; date: 2026-05-01; post-data severity 0.933 for [0.1, inf]\n"
            "- h4: failed; post-data severity 0.023 for [-inf, 0.0]\n"
            "- h2: passed\n"
            "- h1: passed\n"
            "\n## Evidence\n") in d
