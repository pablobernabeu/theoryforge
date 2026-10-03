"""The amendment appraisal compares content, not prediction ids (API_SPEC.md section 10).

Most cases amend the panic example. The R suite (test-develop.R) builds the same
amendments and asserts the same records.
"""
import copy

import theoryforge as tf
from theoryforge._status import prediction_status

S4 = ("Blocking interoceptive feedback lowers avoidance-task scores by 30 per cent, "
      "within a tolerance of 5 percentage points, within two weeks.")

# The record of an amendment that changes nothing, keys in the order of API_SPEC.md section 10.
EMPTY = {
    "verdict": "neutral",
    "new_predictions": [],
    "corroborated_new": [],
    "ad_hoc_assumptions": [],
    "articulated": [],
    "underived": [],
    "corroborated_new_registered": [],
    "renamed": [],
    "dropped": [],
    "dropped_corroborated": [],
    "content_lost": [],
    "new_anomalies": [],
    "assumptions": [],
}


def _record(**changes):
    return {**EMPTY, **changes}


def _v1(fixtures_dir):
    return tf.read(fixtures_dir / "panic-network.theory.yaml").data


def _with_failed_pred2(fixtures_dir):
    """The panic example with a failed test of pred2, the anomaly the rescue cases answer."""
    prior = _v1(fixtures_dir)
    prior["test_outcomes"].append({"prediction_id": "pred2", "passed": False})
    return prior


def _with_p4(theory):
    """``theory`` amended as the revised v2 amends v1: a new proposition and a prediction from it."""
    t = copy.deepcopy(theory)
    t["propositions"].append({
        "id": "p4", "from": "c_arousal", "to": "c_avoidance", "relation": "increases",
        "mechanism": "Bodily sensations are themselves feared, so activities that raise "
                     "arousal are avoided directly.",
    })
    t["predictions"].append({"id": "pred4", "derives_from": ["p4"], "statement": S4, "type": "point"})
    t["test_outcomes"].append({"prediction_id": "pred4", "passed": True, "registered": "osf.io/fghij"})
    return t


def test_the_record_keeps_its_four_fields_first(fixtures_dir):
    # D6: identical versions add nothing, lose nothing and are neutral.
    v1 = _v1(fixtures_dir)
    result = tf.appraise_amendment(copy.deepcopy(v1), v1)
    assert result == EMPTY
    assert list(result) == list(EMPTY)


def test_a_status_reads_every_outcome_of_the_prediction():
    tos = [
        {"prediction_id": "h1", "passed": True},
        {"prediction_id": "h2", "passed": False},
        {"prediction_id": "h3", "passed": True},
        {"prediction_id": "h3", "passed": False},
        {"prediction_id": "h4"},
        {"prediction_id": "h4", "passed": None},
        "h5",
        {"prediction_id": 5, "passed": True},
        {"prediction_id": ["h6"], "passed": True},
    ]
    statuses = [prediction_status(pid, tos) for pid in ("h1", "h2", "h3", "h4", "h5", "5", "h6")]
    assert statuses == ["corroborated", "refuted", "mixed", "untested", "untested", "untested",
                        "untested"]


def test_a_prediction_derived_from_unchanged_propositions_is_an_articulation(fixtures_dir):
    # D0: the v2 shipped with 0.6.0. pred4 derives from p1 and p2, which v1
    # already held, so it states a consequence of the prior's own content. The
    # dropped functional_form is not part of what the appraisal compares.
    v1 = _v1(fixtures_dir)
    new = copy.deepcopy(v1)
    del new["propositions"][0]["functional_form"]
    new["predictions"].append({"id": "pred4", "derives_from": ["p1", "p2"], "statement": S4, "type": "point"})
    new["test_outcomes"].append({"prediction_id": "pred4", "passed": True, "registered": "osf.io/fghij"})
    assert tf.appraise_amendment(new, v1) == _record(
        new_predictions=["pred4"], corroborated_new=["pred4"], articulated=["pred4"],
        corroborated_new_registered=["pred4"])


def test_failed_replications_leave_a_new_prediction_mixed(fixtures_dir):
    # D1: one pass and two failures make pred4 mixed, which is not corroborated.
    v1 = _v1(fixtures_dir)
    new = _with_p4(v1)
    new["test_outcomes"] += [{"prediction_id": "pred4", "passed": False} for _ in range(2)]
    assert prediction_status("pred4", new["test_outcomes"]) == "mixed"
    assert tf.appraise_amendment(new, v1) == _record(new_predictions=["pred4"])


def test_a_renamed_prediction_is_not_new(fixtures_dir):
    # D2: pred1 under a new id, its statement reflowed, is the same content.
    v1 = _v1(fixtures_dir)
    new = copy.deepcopy(v1)
    statement = new["predictions"][0]["statement"]
    new["predictions"][0]["id"] = "pred1_v2"
    new["predictions"][0]["statement"] = "  " + statement.replace(" ", "  \n ", 1) + "\t"
    new["test_outcomes"][0]["prediction_id"] = "pred1_v2"
    assert tf.appraise_amendment(new, v1) == _record(renamed=[{"prior": "pred1", "new": "pred1_v2"}])
    # A different claim form is a different prediction, so pred1 is then dropped.
    new["predictions"][0]["type"] = "interval"
    result = tf.appraise_amendment(new, v1)
    assert (result["renamed"], result["new_predictions"], result["dropped"]) == ([], ["pred1_v2"], ["pred1"])
    assert result["dropped_corroborated"] == ["pred1"]


def test_renames_are_matched_in_file_order_and_sorted_by_new_id():
    prior = {"predictions": [{"id": "x", "statement": "S1", "type": "point"},
                             {"id": "y", "statement": "S2", "type": "point"},
                             {"id": "a", "statement": "S", "type": "point"},
                             {"id": "b", "statement": "S", "type": "point"},
                             {"id": "e", "statement": "", "type": "point"}]}
    new = {"predictions": [{"id": "z1", "statement": "S2", "type": "point"},
                           {"id": "a1", "statement": "S1", "type": "point"},
                           {"id": "c", "statement": "S", "type": "point"},
                           {"id": "d", "statement": "S", "type": "point"},
                           {"id": "f", "statement": " ", "type": "point"}]}
    result = tf.appraise_amendment(new, prior)
    assert result["renamed"] == [{"prior": "x", "new": "a1"}, {"prior": "a", "new": "c"},
                                 {"prior": "b", "new": "d"}, {"prior": "y", "new": "z1"}]
    # A blank statement says nothing about content, so it is never a rename.
    assert (result["new_predictions"], result["dropped"], result["content_lost"]) == (["f"], ["e"], ["e"])


def test_every_list_of_ids_is_sorted_by_code_point():
    prior = {"predictions": [{"id": i, "statement": f"claim {i}", "type": "point"}
                             for i in ("b2", "a3", "B1")]}
    result = tf.appraise_amendment({"predictions": []}, prior)
    assert result["dropped"] == ["B1", "a3", "b2"]
    assert result["content_lost"] == ["B1", "a3", "b2"]


def test_a_rescue_cleared_by_a_reanalysis_of_its_anomaly_is_ad_hoc(fixtures_dir):
    # D3, and I16 case A: the amendment answers the failed pred2 with an
    # assumption and a passing re-analysis of pred2 itself. Accommodating the
    # anomaly adds no content.
    prior = _with_failed_pred2(fixtures_dir)
    new = copy.deepcopy(prior)
    new["auxiliary_assumptions"].append({
        "id": "aux_rescue", "statement": "The band holds only for high baseline avoidance.",
        "added_for": "pred2", "protects": ["pred2"]})
    new["test_outcomes"].append({"prediction_id": "pred2", "passed": True})
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="degenerating", ad_hoc_assumptions=["aux_rescue"],
        assumptions=[{"id": "aux_rescue", "added_for": "pred2", "class": "ad_hoc1", "independent": []}])


def test_an_old_corroborated_prediction_cannot_clear_a_rescue(fixtures_dir):
    # I16 case B: pred1 passed before the amendment, so listing it in protects
    # lends the assumption no support.
    prior = _with_failed_pred2(fixtures_dir)
    new = copy.deepcopy(prior)
    new["auxiliary_assumptions"].append({
        "id": "aux_rescue", "statement": "s", "added_for": "pred2", "protects": ["pred2", "pred1"]})
    result = tf.appraise_amendment(new, prior)
    assert result["assumptions"] == [
        {"id": "aux_rescue", "added_for": "pred2", "class": "ad_hoc1", "independent": []}]
    assert result["verdict"] == "degenerating"


def test_a_free_text_added_for_still_marks_a_rescue(fixtures_dir):
    # I16 case D: added_for gives a reason, not the anomaly's id, and the
    # failure record is dropped. pred2 is still old content.
    prior = _with_failed_pred2(fixtures_dir)
    new = copy.deepcopy(prior)
    new["test_outcomes"] = [t for t in new["test_outcomes"] if t["passed"]]
    new["auxiliary_assumptions"].append({
        "id": "aux_rescue", "statement": "s", "added_for": "a subgroup explanation",
        "protects": ["pred2"]})
    new["test_outcomes"].append({"prediction_id": "pred2", "passed": True})
    result = tf.appraise_amendment(new, prior)
    assert result["assumptions"] == [
        {"id": "aux_rescue", "added_for": "a subgroup explanation", "class": "ad_hoc1", "independent": []}]
    assert result["ad_hoc_assumptions"] == ["aux_rescue"]
    assert result["verdict"] == "degenerating"


def test_a_corroborated_new_prediction_clears_the_assumption_that_yields_it(fixtures_dir):
    # I16 case C. pred5 derives from the unchanged p2 but needs the new
    # assumption, so it is new content and not an articulation. While pred5 is
    # untested, the assumption is ad hoc (ad_hoc2), and its corroboration clears it.
    prior = _with_failed_pred2(fixtures_dir)
    new = copy.deepcopy(prior)
    new["predictions"].append({
        "id": "pred5", "statement": "Exposure lowers avoidance only where baseline avoidance is high.",
        "type": "directional", "derives_from": ["p2"]})
    new["auxiliary_assumptions"].append({
        "id": "aux_baseline", "statement": "Exposure works through habituation of high avoidance.",
        "added_for": "pred2", "protects": ["pred2", "pred5", "pred5"]})
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="degenerating", new_predictions=["pred5"], ad_hoc_assumptions=["aux_baseline"],
        assumptions=[{"id": "aux_baseline", "added_for": "pred2", "class": "ad_hoc2",
                      "independent": [{"id": "pred5", "status": "untested"}]}])
    new["test_outcomes"].append({"prediction_id": "pred5", "passed": True, "registered": "osf.io/x"})
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="progressive", new_predictions=["pred5"], corroborated_new=["pred5"],
        corroborated_new_registered=["pred5"],
        assumptions=[{"id": "aux_baseline", "added_for": "pred2", "class": "independently_corroborated",
                      "independent": [{"id": "pred5", "status": "corroborated"}]}])


def test_only_an_assumption_added_for_an_anomaly_is_appraised(fixtures_dir):
    # A null, blank or non-text added_for marks a core assumption, and
    # added_for is read as text, so a one-element list names its element.
    v1 = _v1(fixtures_dir)
    new = copy.deepcopy(v1)
    new["auxiliary_assumptions"] += [
        {"id": "core_null", "statement": "s", "added_for": None, "protects": ["pred2"]},
        {"id": "core_blank", "statement": "s", "added_for": " ", "protects": ["pred2"]},
        {"id": "core_number", "statement": "s", "added_for": 5, "protects": ["pred2"]},
        {"id": "listed", "statement": "s", "added_for": ["pred2"], "protects": ["pred2"]},
    ]
    result = tf.appraise_amendment(new, v1)
    assert result["assumptions"] == [
        {"id": "listed", "added_for": "pred2", "class": "ad_hoc1", "independent": []}]
    assert result["ad_hoc_assumptions"] == ["listed"]


def test_dropping_untested_predictions_is_reported_as_content_lost(fixtures_dir):
    # D4: refuted pred2 and untested pred3 are dropped. Losing untested content
    # is reported and does not block a progressive verdict.
    prior = _with_failed_pred2(fixtures_dir)
    new = _with_p4(prior)
    new["predictions"] = [p for p in new["predictions"] if p["id"] not in ("pred2", "pred3")]
    new["test_outcomes"] = [t for t in new["test_outcomes"] if t["prediction_id"] != "pred2"]
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="progressive", new_predictions=["pred4"], corroborated_new=["pred4"],
        corroborated_new_registered=["pred4"], dropped=["pred2", "pred3"], content_lost=["pred3"])


def test_dropping_a_corroborated_prediction_blocks_a_progressive_verdict(fixtures_dir):
    v1 = _v1(fixtures_dir)
    new = _with_p4(v1)
    new["predictions"] = [p for p in new["predictions"] if p["id"] != "pred1"]
    new["test_outcomes"] = [t for t in new["test_outcomes"] if t["prediction_id"] != "pred1"]
    assert tf.appraise_amendment(new, v1) == _record(
        new_predictions=["pred4"], corroborated_new=["pred4"], corroborated_new_registered=["pred4"],
        dropped=["pred1"], dropped_corroborated=["pred1"])


def test_a_failed_replication_of_retained_content_is_a_new_anomaly(fixtures_dir):
    # D5. An anomaly is reported and never decides the verdict.
    v1 = _v1(fixtures_dir)
    new = copy.deepcopy(v1)
    new["test_outcomes"].append({"prediction_id": "pred1", "passed": False, "registered": "osf.io/klmno"})
    assert tf.appraise_amendment(new, v1) == _record(new_anomalies=["pred1"])
    result = tf.appraise_amendment(_with_p4(new), v1)
    assert (result["verdict"], result["new_anomalies"]) == ("progressive", ["pred1"])
    # A renamed prediction is retained content too.
    new["predictions"][0]["id"] = "pred1_v2"
    for t in new["test_outcomes"]:
        t["prediction_id"] = "pred1_v2"
    result = tf.appraise_amendment(new, v1)
    assert result["renamed"] == [{"prior": "pred1", "new": "pred1_v2"}]
    assert result["new_anomalies"] == ["pred1_v2"]


def test_an_unregistered_pass_corroborates_but_is_not_reported_as_registered(fixtures_dir):
    # D7: registered is read for the report key alone.
    v1 = _v1(fixtures_dir)
    for registered in (None, " "):
        new = _with_p4(v1)
        new["test_outcomes"][-1]["registered"] = registered
        assert tf.appraise_amendment(new, v1) == _record(
            verdict="progressive", new_predictions=["pred4"], corroborated_new=["pred4"])


def test_a_prediction_derived_from_nothing_adds_no_content(fixtures_dir):
    v1 = _v1(fixtures_dir)
    new = copy.deepcopy(v1)
    new["predictions"].append({"id": "pred5", "statement": "A claim derived from nothing.", "type": "point"})
    new["test_outcomes"].append({"prediction_id": "pred5", "passed": True})
    assert tf.appraise_amendment(new, v1) == _record(
        new_predictions=["pred5"], corroborated_new=["pred5"], underived=["pred5"])


def test_propositions_are_compared_by_content_not_by_id(fixtures_dir):
    # p2 renamed q2 holds the same content, so a prediction derived from q2
    # still articulates what the prior held. Reversing p2's relation changes it.
    v1 = _v1(fixtures_dir)
    pred5 = {"id": "pred5", "statement": "Threat predicts avoidance a week later.", "type": "point"}
    renamed = copy.deepcopy(v1)
    renamed["propositions"][1]["id"] = "q2"
    for p in renamed["predictions"]:
        p["derives_from"] = ["q2" if d == "p2" else d for d in p["derives_from"]]
    renamed["predictions"].append({**pred5, "derives_from": ["q2"]})
    renamed["test_outcomes"].append({"prediction_id": "pred5", "passed": True})
    result = tf.appraise_amendment(renamed, v1)
    assert (result["verdict"], result["articulated"]) == ("neutral", ["pred5"])
    changed = copy.deepcopy(v1)
    changed["propositions"][1]["relation"] = "decreases"
    changed["predictions"].append({**pred5, "derives_from": ["p2"]})
    changed["test_outcomes"].append({"prediction_id": "pred5", "passed": True})
    result = tf.appraise_amendment(changed, v1)
    assert (result["verdict"], result["articulated"]) == ("progressive", [])
