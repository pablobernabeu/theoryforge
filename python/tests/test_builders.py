"""The BUILDING-mode builders, Theory.copy() and the amendment guard (API_SPEC.md section 8).

The R suite (test-builder.R) checks the same scalar arguments and null-key
template against the R builders, which handled both before the Python ones did.
"""
from collections import OrderedDict

import pytest

import theoryforge as tf

ALIASING_MESSAGE = (
    "appraise_amendment needs two distinct theory objects, but the amendment and the "
    "prior are the same object. The Python builders change a theory in place, so start "
    "the amendment from prior.copy()."
)


def _get_started_theory():
    """The theory the R Get started vignette builds, with the single strings it passes."""
    return (
        tf.new_theory("panic-network", "A network theory of panic")
        .add_construct("c_arousal", "Physiological arousal",
                       "Bodily activation in response to a stressor.",
                       measurement="heart rate variability",
                       boundary_conditions="awake adults")
        .add_construct("c_threat", "Perceived threat",
                       "Appraised danger of bodily sensations.",
                       measurement="self-report appraisal scale",
                       boundary_conditions="awake adults")
        .add_proposition("p1", "c_arousal", "c_threat", "causes",
                         mechanism="Activation raises the salience of threat cues.")
        .add_prediction("h1", "Arousal raises threat appraisal by a fixed amount.",
                        "point", derives_from="p1")
    )


def test_a_single_string_is_stored_as_a_one_element_list():
    t = _get_started_theory()
    arousal = t.data["constructs"][0]
    assert arousal["measurement"] == ["heart rate variability"]
    assert arousal["boundary_conditions"] == ["awake adults"]
    assert t.data["predictions"][0]["derives_from"] == ["p1"]

    t.add_alternative("alt1", "Cognitive account", key_constructs="c_threat")
    t.add_prediction("h2", "Threat appraisal follows arousal.", "directional",
                     derives_from="p1", diagnostic_vs="alt1")
    t.add_assumption("a1", "Arousal is measured at rest.", added_for="h1", protects="h1")
    assert t.data["alternatives"][0]["key_constructs"] == ["c_threat"]
    assert t.data["predictions"][1]["diagnostic_vs"] == ["alt1"]
    assert t.data["auxiliary_assumptions"][0]["protects"] == ["h1"]


def test_the_get_started_build_passes_the_gate_and_compiles_one_indicator():
    t = _get_started_theory()
    assert t.validate(full=True) is True
    rep = t.check()
    assert rep["gate"] == "pass"
    assert {i["id"]: i["status"] for i in rep["items"]}["derivation_chain"] == "pass"
    sem = t.compile_sem().splitlines()
    assert "c_arousal =~ heart_rate_variability" in sem
    assert "c_threat =~ self_report_appraisal_scale" in sem


def test_other_iterables_become_lists_and_other_scalars_one_element_lists():
    t = (
        tf.new_theory("demo", "Demo")
        .add_construct("c1", "C one", "the first", measurement=("m1", "m2"))
        .add_prediction("h1", "A claim.", "point", derives_from=(p for p in ["p1", "p2"]))
        .add_alternative("alt1", "A rival", key_constructs=7)
    )
    assert t.data["constructs"][0]["measurement"] == ["m1", "m2"]
    assert t.data["predictions"][0]["derives_from"] == ["p1", "p2"]
    assert t.data["alternatives"][0]["key_constructs"] == [7]


def test_a_typeerror_raised_inside_an_iterable_argument_propagates():
    # Only a value that cannot be iterated at all is wrapped. A generator that
    # fails part-way through is the caller's error and is never stored.
    def derivations():
        yield "p1"
        raise TypeError("failed while listing derivations")

    t = tf.new_theory("demo", "Demo")
    with pytest.raises(TypeError, match="failed while listing derivations"):
        t.add_prediction("h1", "A claim.", "point", derives_from=derivations())
    assert "predictions" not in t.data


def test_an_omitted_array_argument_stays_absent():
    t = tf.new_theory("demo", "Demo").add_construct("c1", "C", "d")
    assert "measurement" not in t.data["constructs"][0]
    assert "boundary_conditions" not in t.data["constructs"][0]


def test_a_template_with_null_collection_keys_accepts_the_builders(tmp_path):
    path = tmp_path / "template.theory.yaml"
    path.write_text(
        'schema_version: "1.0"\nid: stub\ntitle: Stub\nmaturity: draft\n'
        "constructs:\npropositions:\nprovenance:\n",
        encoding="utf-8",
    )
    t = tf.read(path)
    assert t.data["constructs"] is None
    assert t.data["provenance"] is None
    (t.add_construct("c1", "C one", "the first")
     .add_construct("c2", "C two", "the second")
     .add_proposition("p1", "c1", "c2", "causes")
     .set_formal_model("ode"))
    assert [c["id"] for c in t.data["constructs"]] == ["c1", "c2"]
    assert [p["id"] for p in t.data["propositions"]] == ["p1"]
    assert t.data["formal_model"] == {"type": "ode", "spec_ref": None}
    assert [(s["step"], s["action"]) for s in t.data["provenance"]] == [
        ("1", "tf_add_construct"), ("2", "tf_add_construct"),
        ("3", "tf_add_proposition"), ("4", "tf_set_formal_model"),
    ]
    assert t.validate(full=True) is True


def test_a_collection_that_is_not_a_list_is_refused_and_left_alone():
    base = {"schema_version": "1.0", "id": "x", "title": "X", "maturity": "building"}
    t = tf.Theory(dict(base, constructs="arousal"))
    with pytest.raises(TypeError) as err:
        t.add_construct("c1", "C", "d")
    assert str(err.value) == "cannot add to 'constructs': the theory holds a str there, not a list"
    assert t.data["constructs"] == "arousal"
    assert "provenance" not in t.data

    t = tf.Theory(dict(base, propositions={"p1": "c1 -> c2"}))
    with pytest.raises(TypeError, match="the theory holds a dict there, not a list"):
        t.add_proposition("p2", "c1", "c2", "causes")

    t = tf.Theory(dict(base, predictions=3))
    with pytest.raises(TypeError, match="the theory holds an int there, not a list"):
        t.add_prediction("h1", "A claim.", "point")

    t = tf.Theory(dict(base, alternatives=OrderedDict()))
    with pytest.raises(TypeError, match="the theory holds an OrderedDict there, not a list"):
        t.add_alternative("alt1", "A rival")

    # A malformed provenance log refuses the call before the item is stored.
    t = tf.Theory(dict(base, provenance="built by hand"))
    with pytest.raises(TypeError, match="cannot add to 'provenance'"):
        t.add_construct("c1", "C", "d")
    assert "constructs" not in t.data
    with pytest.raises(TypeError, match="cannot add to 'provenance'"):
        t.set_formal_model("ode")
    assert "formal_model" not in t.data


def test_copy_is_independent_of_the_original():
    v1 = tf.new_theory("demo", "Demo").add_construct("c1", "C one", "the first", measurement="m1")
    v2 = v1.copy()
    assert isinstance(v2, tf.Theory)
    assert v2 is not v1
    assert v2.data == v1.data
    v2.add_prediction("h1", "A claim.", "point")
    v2.data["constructs"][0]["measurement"].append("m2")
    assert "predictions" not in v1.data
    assert v1.data["constructs"][0]["measurement"] == ["m1"]
    assert [s["action"] for s in v1.data["provenance"]] == ["tf_theory", "tf_add_construct"]


def test_appraising_a_theory_against_itself_is_refused():
    # The R idiom `new <- prior |> tf_add_prediction(...)` written in Python:
    # the builder returns prior itself, changed in place.
    prior = tf.new_theory("demo-1", "A demonstration theory").add_prediction(
        "h1", "Effect is positive.", "directional")
    new = prior.add_prediction("h2", "Effect is exactly 0.30.", "point")
    new.data["test_outcomes"] = [{"prediction_id": "h2", "passed": True}]
    assert new is prior
    with pytest.raises(ValueError) as err:
        new.appraise_amendment(prior)
    assert str(err.value) == ALIASING_MESSAGE
    for amended, original in [(new, prior), (new.data, prior), (tf.Theory(prior.data), prior)]:
        with pytest.raises(ValueError, match="needs two distinct theory objects"):
            tf.appraise_amendment(amended, original)


def test_equal_content_in_distinct_objects_is_never_refused():
    prior = tf.new_theory("demo-1", "A demonstration theory").add_prediction(
        "h1", "Effect is positive.", "directional")
    assert prior.copy().appraise_amendment(prior) == {
        "verdict": "neutral", "new_predictions": [], "corroborated_new": [],
        "ad_hoc_assumptions": [],
    }


def test_the_develop_help_example_started_from_a_copy_is_progressive():
    # tf_appraise_amendment()'s help example, with the amendment begun from a copy.
    prior = tf.new_theory("demo-1", "A demonstration theory").add_prediction(
        "h1", "Effect is positive.", "directional")
    new = prior.copy().add_prediction("h2", "Effect is exactly 0.30.", "point")
    new.data["test_outcomes"] = [{"prediction_id": "h2", "passed": True}]
    assert [p["id"] for p in prior.data["predictions"]] == ["h1"]
    assert new.appraise_amendment(prior) == {
        "verdict": "progressive", "new_predictions": ["h2"], "corroborated_new": ["h2"],
        "ad_hoc_assumptions": [],
    }
