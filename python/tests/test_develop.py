"""The amendment appraisal compares content, not prediction ids (API_SPEC.md section 10).

Most cases amend the panic example, and the rest amend the edge cases
fixtures/edge/amend-*.theory.yaml. The R suite (test-develop.R) builds the same
amendments and asserts the same records.
"""
import copy

import pytest

import theoryforge as tf
from theoryforge._status import prediction_status

S4 = ("Blocking interoceptive feedback lowers avoidance-task scores by 30 per cent, "
      "within a tolerance of 5 percentage points, within two weeks.")

# The one independence the panic example's v1 implies. A direct path from
# arousal to avoidance withdraws it, and the failed test of pred_indep refutes it.
LOST = "c_arousal _||_ c_avoidance | c_perceived_threat"

# The sign v1 entails and the shipped v2 gives up: with p3 unsigned, the new
# route from threat through arousal to avoidance leaves the effect open.
SIGN = "effect of c_perceived_threat on c_avoidance: positive"

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
    "theoretically_progressive": False,
    "empirically_progressive": False,
    "revised": [],
    "weakened_refuted": [],
    "unresolved": [],
    "implications_compared": True,
    "implications_lost": [],
    "implications_lost_unrefuted": [],
    "implications_gained": [],
    "entailments_lost": [],
    "signs_lost": [],
    "protected_only": [],
    "refuted_new": [],
    "corroborated_new_severity": [],
}


def _record(**changes):
    """EMPTY with ``changes``. Unless the changes say otherwise, each corroborated
    new prediction has no post-data severity, since no outcome records an estimate."""
    out = {**EMPTY, **changes}
    if "corroborated_new_severity" not in changes:
        out["corroborated_new_severity"] = [{"id": i, "severity": None}
                                            for i in sorted(out["corroborated_new"])]
    return out


def _v1(fixtures_dir):
    return tf.read(fixtures_dir / "panic-network.theory.yaml").data


def _signed_p3(theory):
    """``theory`` with p3, from threat to arousal, stated as ``increases``.

    Adding p4 to the panic example then keeps every sign v1 entails, so the
    cases built on it test one rule at a time.
    """
    t = copy.deepcopy(theory)
    for p in t["propositions"]:
        if p["id"] == "p3":
            p["relation"] = "increases"
    return t


def _edge(fixtures_dir, name):
    return tf.read(fixtures_dir / "edge" / f"{name}.theory.yaml").data


def _with_failed_pred2(fixtures_dir):
    """The panic example with a failed test of pred2, the anomaly the rescue cases answer."""
    prior = _signed_p3(_v1(fixtures_dir))
    prior["test_outcomes"].append({"prediction_id": "pred2", "passed": False})
    return prior


def _with_p4(theory):
    """``theory`` amended as v2 amends v1: a new proposition and a prediction from it."""
    t = copy.deepcopy(theory)
    t["propositions"].append({
        "id": "p4", "from": "c_arousal", "to": "c_avoidance", "relation": "increases",
        "mechanism": "Bodily sensations are themselves feared, so activities that raise "
                     "arousal are avoided directly.",
    })
    t["predictions"].append({"id": "pred4", "derives_from": ["p4"], "statement": S4, "type": "point"})
    t["test_outcomes"].append({"prediction_id": "pred4", "passed": True, "registered": "osf.io/fghij"})
    return t


def _p4_record(**changes):
    """The record of ``_with_p4(v1)`` with p3 signed: corroborated new content and the
    refuted independence lost."""
    return _record(**{"verdict": "progressive", "new_predictions": ["pred4"],
                      "corroborated_new": ["pred4"], "corroborated_new_registered": ["pred4"],
                      "theoretically_progressive": True, "empirically_progressive": True,
                      "implications_lost": [LOST], **changes})


def test_the_record_keeps_its_fields_in_order(fixtures_dir):
    # D6: identical versions add nothing, lose nothing and are neutral.
    v1 = _v1(fixtures_dir)
    result = tf.appraise_amendment(copy.deepcopy(v1), v1)
    assert result == EMPTY
    assert list(result) == list(EMPTY)


def test_the_shipped_amendment_answers_a_refuted_independence(fixtures_dir):
    # v2 drops pred_indep, which a test refuted, and adds p4 and pred4. The
    # independence p4 withdraws is the refuted one. But p3 states no sign, so
    # p4 opens a route from threat to avoidance through arousal whose sign is
    # open, and v2 no longer entails the positive effect of threat on
    # avoidance that v1 entails. That is content lost.
    v1 = _v1(fixtures_dir)
    v2 = tf.read(fixtures_dir / "panic-network-2026-v2.theory.yaml").data
    assert tf.appraise_amendment(v2, v1) == _p4_record(
        verdict="neutral", dropped=["pred_indep"], signs_lost=[SIGN])
    # With p3 stated as increases in both versions, no sign is lost and the
    # amendment is progressive.
    v1, v2 = _signed_p3(v1), _signed_p3(v2)
    assert tf.appraise_amendment(v2, v1) == _p4_record(dropped=["pred_indep"])
    # Had the test of pred_indep passed, v2 would give up a corroborated
    # prediction and an unrefuted implication.
    passed = copy.deepcopy(v1)
    passed["test_outcomes"][1]["passed"] = True
    assert tf.appraise_amendment(v2, passed) == _p4_record(
        verdict="neutral", dropped=["pred_indep"], dropped_corroborated=["pred_indep"],
        implications_lost_unrefuted=[LOST])
    # Untested, pred_indep and the implication would both be content lost.
    del passed["test_outcomes"][1]
    assert tf.appraise_amendment(v2, passed) == _p4_record(
        verdict="neutral", dropped=["pred_indep"], content_lost=["pred_indep"],
        implications_lost_unrefuted=[LOST])


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


def test_a_claim_the_prior_graph_entails_is_an_articulation(fixtures_dir):
    # h3 cites the new p3 but claims that c1 raises c3, which the prior's chain
    # c1 -> c2 -> c3 already entails. Without the claim, h3 is new content.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-unresolved")
    new["predictions"][2]["derives_from"] = ["p3"]
    new["predictions"][2]["claim"] = {"kind": "effect", "x": "c1", "y": "c3", "sign": "positive"}
    gained = ["c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3"]
    assert tf.appraise_amendment(new, prior) == _record(
        new_predictions=["h3"], corroborated_new=["h3"], articulated=["h3"],
        implications_gained=gained)
    # A claim about c4, which the prior does not name, is not evaluated there.
    new["predictions"][2]["claim"] = {"kind": "effect", "x": "c3", "y": "c4", "sign": "positive"}
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="progressive", new_predictions=["h3"], corroborated_new=["h3"],
        theoretically_progressive=True, empirically_progressive=True, implications_gained=gained)


def test_failed_replications_leave_a_new_prediction_mixed(fixtures_dir):
    # D1: one pass and two failures make pred4 mixed, which is not corroborated.
    v1 = _signed_p3(_v1(fixtures_dir))
    new = _with_p4(v1)
    new["test_outcomes"] += [{"prediction_id": "pred4", "passed": False} for _ in range(2)]
    assert prediction_status("pred4", new["test_outcomes"]) == "mixed"
    assert tf.appraise_amendment(new, v1) == _p4_record(
        verdict="neutral", corroborated_new=[], corroborated_new_registered=[],
        empirically_progressive=False, refuted_new=["pred4"])


def test_a_renamed_prediction_is_not_new(fixtures_dir):
    # D2: pred1 under a new id, its statement reflowed, is the same content.
    v1 = _v1(fixtures_dir)
    new = copy.deepcopy(v1)
    statement = new["predictions"][0]["statement"]
    new["predictions"][0]["id"] = "pred1_v2"
    new["predictions"][0]["statement"] = "  " + statement.replace(" ", "  \n ", 1) + "\t"
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
        assumptions=[{"id": "aux_rescue", "added_for": "pred2", "class": "ad_hoc1", "independent": [],
                      "added_for_inferred": False, "change": "new"}])


def test_an_old_corroborated_prediction_cannot_clear_a_rescue(fixtures_dir):
    # I16 case B: pred1 passed before the amendment, so listing it in protects
    # lends the assumption no support.
    prior = _with_failed_pred2(fixtures_dir)
    new = copy.deepcopy(prior)
    new["auxiliary_assumptions"].append({
        "id": "aux_rescue", "statement": "s", "added_for": "pred2", "protects": ["pred2", "pred1"]})
    result = tf.appraise_amendment(new, prior)
    assert result["assumptions"] == [
        {"id": "aux_rescue", "added_for": "pred2", "class": "ad_hoc1", "independent": [],
         "added_for_inferred": False, "change": "new"}]
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
        {"id": "aux_rescue", "added_for": "a subgroup explanation", "class": "ad_hoc1", "independent": [],
         "added_for_inferred": False, "change": "new"}]
    assert result["ad_hoc_assumptions"] == ["aux_rescue"]
    assert result["verdict"] == "degenerating"


def test_a_corroborated_new_prediction_clears_the_assumption_that_yields_it(fixtures_dir):
    # I16 case C. pred5 derives from the unchanged p2 but needs the new
    # assumption, so it is new content and not an articulation, and its
    # novelty rests on that declaration (protected_only). While pred5 is
    # untested, the assumption is pending, not ad hoc, and the amendment is
    # neutral. Its corroboration clears the assumption, and its failure makes
    # it ad hoc (ad_hoc2).
    prior = _with_failed_pred2(fixtures_dir)
    new = copy.deepcopy(prior)
    new["predictions"].append({
        "id": "pred5", "statement": "Exposure lowers avoidance only where baseline avoidance is high.",
        "type": "directional", "derives_from": ["p2"]})
    new["auxiliary_assumptions"].append({
        "id": "aux_baseline", "statement": "Exposure works through habituation of high avoidance.",
        "added_for": "pred2", "protects": ["pred2", "pred5", "pred5"]})

    def rescue(cls, status):
        return [{"id": "aux_baseline", "added_for": "pred2", "class": cls,
                 "independent": [{"id": "pred5", "status": status}], "added_for_inferred": False,
                 "change": "new"}]

    assert tf.appraise_amendment(new, prior) == _record(
        new_predictions=["pred5"], assumptions=rescue("pending", "untested"),
        theoretically_progressive=True, protected_only=["pred5"])
    passed = copy.deepcopy(new)
    passed["test_outcomes"].append({"prediction_id": "pred5", "passed": True, "registered": "osf.io/x"})
    assert tf.appraise_amendment(passed, prior) == _record(
        verdict="progressive", new_predictions=["pred5"], corroborated_new=["pred5"],
        corroborated_new_registered=["pred5"],
        assumptions=rescue("independently_corroborated", "corroborated"),
        theoretically_progressive=True, empirically_progressive=True, protected_only=["pred5"])
    failed = copy.deepcopy(new)
    failed["test_outcomes"].append({"prediction_id": "pred5", "passed": False})
    assert tf.appraise_amendment(failed, prior) == _record(
        verdict="degenerating", new_predictions=["pred5"], ad_hoc_assumptions=["aux_baseline"],
        assumptions=rescue("ad_hoc2", "refuted"), theoretically_progressive=True,
        protected_only=["pred5"], refuted_new=["pred5"])


def test_only_an_assumption_added_for_an_anomaly_is_appraised(fixtures_dir):
    # A null, blank or non-text added_for marks a core assumption when the
    # assumption protects nothing that failed in the prior, and added_for is
    # read as text, so a one-element list names its element.
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
        {"id": "listed", "added_for": "pred2", "class": "ad_hoc1", "independent": [],
         "added_for_inferred": False, "change": "new"}]
    assert result["ad_hoc_assumptions"] == ["listed"]


def test_an_assumption_that_protects_a_failed_prediction_answers_it(fixtures_dir):
    # amend-inferred: x1 protects h2, untested in the prior, and the refuted
    # h1, and names no anomaly. h1 is taken as its anomaly.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-inferred")
    rescue = [{"id": "x1", "added_for": "h1", "class": "ad_hoc1", "independent": [],
               "added_for_inferred": True, "change": "new"}]
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="degenerating", ad_hoc_assumptions=["x1"], assumptions=rescue)
    # A mixed status in the prior counts as failed too.
    mixed = copy.deepcopy(prior)
    mixed["test_outcomes"].append({"prediction_id": "h1", "passed": True})
    assert tf.appraise_amendment(new, mixed)["assumptions"] == rescue
    # The anomaly is found under the new id of a renamed prediction.
    renamed = copy.deepcopy(new)
    renamed["predictions"][0]["id"] = "h1_v2"
    renamed["test_outcomes"][0]["prediction_id"] = "h1_v2"
    renamed["auxiliary_assumptions"][0]["protects"] = ["h2", "h1_v2"]
    result = tf.appraise_amendment(renamed, prior)
    assert result["renamed"] == [{"prior": "h1", "new": "h1_v2"}]
    assert result["assumptions"] == [{**rescue[0], "added_for": "h1_v2"}]
    # Protecting only untested content, the assumption is a core one.
    untested = copy.deepcopy(new)
    untested["auxiliary_assumptions"][0]["protects"] = ["h2"]
    assert tf.appraise_amendment(untested, prior) == EMPTY


@pytest.mark.parametrize(("change", "expected"), [
    ({}, None),
    ({"statement": "c2 rises with c1 by half an SD, within 0.1."}, "reworded"),
    ({"statement": "  c2 rises 0.5 SD per SD of c1,\n within 0.1. "}, None),
    ({"type": "interval"}, "changed"),
    ({"type": "interval", "bounds": {"lower": 0.3, "upper": 0.7}}, "weakened"),
    ({"type": "existence", "bounds": None}, "weakened"),
    ({"type": "directional", "bounds": None, "claim": None}, "weakened"),
    ({"type": "banana"}, "changed"),
    ({"bounds": {"lower": 0.3, "upper": 0.7}}, "weakened"),
    ({"bounds": {"lower": 0.45, "upper": 0.55}}, "strengthened"),
    ({"bounds": {"lower": 0.5, "upper": 0.7}}, "changed"),
    ({"bounds": {"lower": 0.4}}, "weakened"),
    ({"bounds": {"lower": 0.4, "upper": None}}, "weakened"),
    ({"bounds": {"lower": 0.4, "upper": float("inf")}}, "weakened"),
    ({"bounds": {"lower": "0.4", "upper": 0.6}}, "weakened"),
    ({"bounds": {"lower": 0.4, "upper": 0.6, "note": "ignored"}}, None),
    ({"claim": {"kind": "effect", "x": "c1", "y": "c2", "sign": "nonzero"}}, "weakened"),
    ({"claim": {"kind": "effect", "x": "c1", "y": "c2", "sign": "negative"}}, "changed"),
    ({"claim": {"kind": "effect", "x": "c2", "y": "c1", "sign": "positive"}}, "changed"),
    ({"claim": {"kind": "effect", "x": "c1", "y": "c2", "sign": "upward"}}, "weakened"),
    ({"claim": None}, "weakened"),
    ({"type": "directional", "bounds": {"lower": 0.45, "upper": 0.55}}, "strengthened"),
    ({"type": "interval", "claim": {"kind": "effect", "x": "c1", "y": "c2", "sign": "negative"}}, "changed"),
])
def test_a_retained_prediction_is_compared_by_type_bounds_and_claim(fixtures_dir, change, expected):
    # Each case revises h1 of amend-prior, a point prediction with the region
    # [0.4, 0.6] and a positive effect of c1 on c2. A None in `change` removes
    # the field. Since h1 states a region, its type label alone neither
    # weakens nor strengthens it, so relabelling cannot hide a wider region.
    prior = _edge(fixtures_dir, "amend-prior")
    new = copy.deepcopy(prior)
    for key, value in change.items():
        if value is None:
            del new["predictions"][0][key]
        else:
            new["predictions"][0][key] = value
    revised = [{"id": "h1", "change": expected}] if expected else []
    assert tf.appraise_amendment(new, prior)["revised"] == revised


@pytest.mark.parametrize(("before", "after", "expected"), [
    ({"lower": 20}, {"lower": 100, "upper": 200}, "strengthened"),
    ({"lower": 20, "upper": 60}, {"lower": 100}, "weakened"),
    ({"lower": 20}, {"upper": 20}, "changed"),
    (None, {"upper": 20}, "strengthened"),
    ({"lower": None, "upper": 20}, {"lower": float("-inf"), "upper": 20}, None),
])
def test_a_two_sided_region_is_narrower_than_a_one_sided_one(before, after, expected):
    def theory(bounds):
        p = {"id": "h", "statement": "S", "type": "interval"}
        return {"predictions": [p if bounds is None else {**p, "bounds": bounds}]}

    revised = [{"id": "h", "change": expected}] if expected else []
    assert tf.appraise_amendment(theory(after), theory(before))["revised"] == revised


@pytest.mark.parametrize(("before", "after", "expected"), [
    ({"kind": "association", "x": "a", "y": "b", "sign": "positive"},
     {"kind": "association", "x": "b", "y": "a", "sign": "positive"}, None),
    ({"kind": "association", "x": "a", "y": "b", "given": ["c", "d"], "sign": "zero"},
     {"kind": "association", "x": "a", "y": "b", "given": ["d", "c"], "sign": "zero"}, None),
    ({"kind": "association", "x": "a", "y": "b", "given": ["c"], "sign": "zero"},
     {"kind": "association", "x": "a", "y": "b", "given": ["c"], "sign": "nonzero"}, "weakened"),
    ({"kind": "association", "x": "a", "y": "b", "sign": "nonzero"},
     {"kind": "association", "x": "a", "y": "b", "sign": "negative"}, "strengthened"),
    ({"kind": "association", "x": "a", "y": "b", "sign": "positive"},
     {"kind": "association", "x": "a", "y": "c", "sign": "nonzero"}, "changed"),
    ({"kind": "association", "x": "a", "y": "b", "sign": "positive"},
     {"kind": "effect", "x": "a", "y": "b", "sign": "positive"}, "changed"),
    (None, {"kind": "effect", "x": "a", "y": "b", "sign": "nonzero"}, "strengthened"),
])
def test_a_claim_is_stronger_than_none_and_a_fixed_sign_than_nonzero(before, after, expected):
    def theory(claim):
        p = {"id": "h", "statement": "S", "type": "directional"}
        return {"predictions": [p if claim is None else {**p, "claim": claim}]}

    revised = [{"id": "h", "change": expected}] if expected else []
    assert tf.appraise_amendment(theory(after), theory(before))["revised"] == revised


@pytest.mark.parametrize(("before", "after", "expected"), [
    ("point", "existence", "weakened"),
    ("existence", "directional", "strengthened"),
    ("interval", "banana", "changed"),
])
def test_the_type_ranks_only_when_neither_version_states_a_region(before, after, expected):
    def theory(kind):
        return {"predictions": [{"id": "h", "statement": "S", "type": kind}]}

    assert tf.appraise_amendment(theory(after), theory(before))["revised"] == [
        {"id": "h", "change": expected}]


def test_a_refuted_prediction_weakened_after_its_test_degenerates(fixtures_dir):
    # amend-weakened rewrites the refuted h1 as an existence claim.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-weakened")
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="degenerating", revised=[{"id": "h1", "change": "weakened"}], weakened_refuted=["h1"])
    # Widening the region after the failed test is enough, and so is a rename
    # that widens it.
    widened = copy.deepcopy(prior)
    widened["predictions"][0]["bounds"] = {"lower": 0.2, "upper": 0.8}
    assert tf.appraise_amendment(widened, prior) == _record(
        verdict="degenerating", revised=[{"id": "h1", "change": "weakened"}], weakened_refuted=["h1"])
    widened["predictions"][0]["id"] = "h1_wide"
    widened["test_outcomes"][0]["prediction_id"] = "h1_wide"
    assert tf.appraise_amendment(widened, prior) == _record(
        verdict="degenerating", renamed=[{"prior": "h1", "new": "h1_wide"}],
        revised=[{"id": "h1_wide", "change": "weakened"}], weakened_refuted=["h1_wide"])
    # D14: relabelling the widened region as an interval does not hide it.
    relabelled = copy.deepcopy(prior)
    relabelled["predictions"][0]["bounds"] = {"lower": 0.2, "upper": 0.8}
    relabelled["predictions"][0]["type"] = "interval"
    assert tf.appraise_amendment(relabelled, prior) == _record(
        verdict="degenerating", revised=[{"id": "h1", "change": "weakened"}], weakened_refuted=["h1"])


def test_weakening_an_untested_prediction_loses_content(fixtures_dir):
    # amend-unresolved with p3 cited correctly is progressive. Weakening the
    # untested h2 to an existence claim makes it neutral.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-unresolved")
    new["predictions"][2]["derives_from"] = ["p3"]
    new["predictions"][1]["type"] = "existence"
    assert tf.appraise_amendment(new, prior) == _record(
        new_predictions=["h3"], corroborated_new=["h3"], content_lost=["h2"],
        theoretically_progressive=True, empirically_progressive=True,
        revised=[{"id": "h2", "change": "weakened"}],
        implications_gained=["c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3"])


def test_weakening_a_corroborated_prediction_loses_content(fixtures_dir):
    # As above, with h2 corroborated in the prior. Corroborated content is
    # unrefuted content, so weakening it loses content, as dropping it does.
    prior = _edge(fixtures_dir, "amend-prior")
    prior["test_outcomes"].append({"prediction_id": "h2", "passed": True})
    new = _edge(fixtures_dir, "amend-unresolved")
    new["predictions"][2]["derives_from"] = ["p3"]
    gained = ["c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3"]
    record = _record(new_predictions=["h3"], corroborated_new=["h3"],
                     theoretically_progressive=True, empirically_progressive=True,
                     implications_gained=gained)
    assert tf.appraise_amendment(new, prior) == {**record, "verdict": "progressive"}
    new["predictions"][1]["type"] = "existence"
    assert tf.appraise_amendment(new, prior) == {
        **record, "content_lost": ["h2"], "revised": [{"id": "h2", "change": "weakened"}]}


def test_a_new_prediction_citing_a_missing_proposition_is_unresolved(fixtures_dir):
    # amend-unresolved cites p33 for p3. Citing p3 makes the amendment progressive.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-unresolved")
    gained = ["c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3"]
    assert tf.appraise_amendment(new, prior) == _record(
        new_predictions=["h3"], corroborated_new=["h3"], unresolved=["h3"], implications_gained=gained)
    new["predictions"][2]["derives_from"] = ["p3", "p99"]
    assert tf.appraise_amendment(new, prior)["unresolved"] == ["h3"]
    new["predictions"][2]["derives_from"] = ["p3"]
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="progressive", new_predictions=["h3"], corroborated_new=["h3"],
        theoretically_progressive=True, empirically_progressive=True, implications_gained=gained)


def test_an_unrefuted_implication_lost_blocks_a_progressive_verdict(fixtures_dir):
    # amend-lost-implication joins c1 to c3 and gives up c1 _||_ c3 | c2.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-lost-implication")
    record = _record(new_predictions=["h3"], corroborated_new=["h3"],
                     theoretically_progressive=True, empirically_progressive=True,
                     implications_lost=["c1 _||_ c3 | c2"])
    assert tf.appraise_amendment(new, prior) == {
        **record, "implications_lost_unrefuted": ["c1 _||_ c3 | c2"]}
    # A refuted or mixed prediction of the prior that states the independence,
    # with any given and either order, refutes the implication.
    for outcomes in ([False], [True, False]):
        refuted = copy.deepcopy(prior)
        refuted["predictions"].append({
            "id": "h0", "statement": "c1 and c3 are unrelated.", "type": "interval",
            "claim": {"kind": "association", "x": "c3", "y": "c1", "sign": "zero"}})
        refuted["test_outcomes"] += [{"prediction_id": "h0", "passed": p} for p in outcomes]
        new["predictions"].append(copy.deepcopy(refuted["predictions"][-1]))
        assert tf.appraise_amendment(new, refuted) == {**record, "verdict": "progressive"}
        new["predictions"].pop()


def test_an_assumption_rewritten_under_its_id_is_appraised(fixtures_dir):
    # amend-revised-assumption rewrites the core assumption a1 of the prior
    # for the refuted h1.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-revised-assumption")
    record = _record(new_predictions=["h3"], corroborated_new=["h3"],
                     theoretically_progressive=True, empirically_progressive=True,
                     implications_gained=["c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3"])
    rescue = {"id": "a1", "added_for": "h1", "class": "ad_hoc1", "independent": [],
              "added_for_inferred": False, "change": "revised"}
    assert tf.appraise_amendment(new, prior) == {
        **record, "ad_hoc_assumptions": ["a1"], "assumptions": [rescue]}
    # The same rewrite under a new id is appraised the same way, as new.
    moved = copy.deepcopy(new)
    moved["auxiliary_assumptions"][0]["id"] = "a2"
    assert tf.appraise_amendment(moved, prior)["assumptions"] == [
        {**rescue, "id": "a2", "change": "new"}]
    # Without added_for, the refuted h1 it protects is taken as its anomaly.
    inferred = copy.deepcopy(new)
    inferred["auxiliary_assumptions"][0]["added_for"] = None
    assert tf.appraise_amendment(inferred, prior)["assumptions"] == [
        {**rescue, "added_for_inferred": True}]
    # A new prediction that the rewritten assumption protects needs it, so it
    # articulates nothing, though it derives from p1 alone.
    h4 = {"id": "h4", "statement": "c2 rises with c1 in samples of students.",
          "type": "directional", "derives_from": ["p1"]}
    needs = copy.deepcopy(new)
    needs["predictions"].append(h4)
    needs["auxiliary_assumptions"][0]["protects"] = ["h1", "h4"]
    result = tf.appraise_amendment(needs, prior)
    assert (result["articulated"], result["protected_only"], result["ad_hoc_assumptions"]) == (
        [], ["h4"], [])
    assert result["assumptions"][0]["class"] == "pending"
    assert result["assumptions"][0]["independent"] == [{"id": "h4", "status": "untested"}]
    # Whitespace, added_for and protects alone do not revise an assumption.
    kept = copy.deepcopy(needs)
    kept["auxiliary_assumptions"][0]["statement"] = "  The c2 scale measures\n c2 in every sample. "
    result = tf.appraise_amendment(kept, prior)
    assert (result["articulated"], result["assumptions"]) == (["h4"], [])


def test_an_assumption_moved_to_a_new_id_is_not_appraised(fixtures_dir):
    # amend-renamed-assumption moves the core assumption a1, unchanged, to a_scale.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-renamed-assumption")
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="progressive", new_predictions=["h3"], corroborated_new=["h3"],
        theoretically_progressive=True, empirically_progressive=True,
        implications_gained=["c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3"])
    # While the new version keeps a1, a copy under another id is new, and so
    # is a second copy, since each prior assumption is taken once.
    both = copy.deepcopy(new)
    both["auxiliary_assumptions"].insert(0, copy.deepcopy(prior["auxiliary_assumptions"][0]))
    assert tf.appraise_amendment(both, prior)["ad_hoc_assumptions"] == ["a_scale"]
    twice = copy.deepcopy(new)
    twice["auxiliary_assumptions"].append({**new["auxiliary_assumptions"][0], "id": "a_copy"})
    assert tf.appraise_amendment(twice, prior)["ad_hoc_assumptions"] == ["a_copy"]
    # A blank statement matches nothing.
    blank_prior = copy.deepcopy(prior)
    blank_prior["auxiliary_assumptions"][0]["statement"] = " "
    blank = copy.deepcopy(new)
    blank["auxiliary_assumptions"][0]["statement"] = ""
    assert tf.appraise_amendment(blank, blank_prior)["ad_hoc_assumptions"] == ["a_scale"]
    # Kept under its id, the core assumption a1 is not appraised. Any change of
    # wording, even one that keeps the meaning, makes it revised and appraised,
    # and it is then read as answering the refuted h1 it protects.
    kept = copy.deepcopy(new)
    kept["auxiliary_assumptions"][0]["id"] = "a1"
    assert tf.appraise_amendment(kept, prior)["assumptions"] == []
    kept["auxiliary_assumptions"][0]["statement"] = "The c2 scale measures c2 in each sample."
    result = tf.appraise_amendment(kept, prior)
    assert result["assumptions"] == [{"id": "a1", "added_for": "h1", "class": "ad_hoc1", "independent": [],
                                      "added_for_inferred": True, "change": "revised"}]
    assert result["verdict"] == "neutral"


def test_a_version_whose_graph_is_refused_is_not_compared(fixtures_dir):
    # A repeated construct id makes implications() refuse the new version.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-lost-implication")
    new["constructs"].append(copy.deepcopy(new["constructs"][0]))
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="progressive", new_predictions=["h3"], corroborated_new=["h3"],
        theoretically_progressive=True, empirically_progressive=True,
        implications_compared=False)


def test_dropping_untested_predictions_loses_content(fixtures_dir):
    # D4: refuted pred2 and untested pred3 are dropped. Losing untested content
    # blocks a progressive verdict.
    prior = _with_failed_pred2(fixtures_dir)
    new = _with_p4(prior)
    new["predictions"] = [p for p in new["predictions"] if p["id"] not in ("pred2", "pred3")]
    new["test_outcomes"] = [t for t in new["test_outcomes"] if t["prediction_id"] != "pred2"]
    assert tf.appraise_amendment(new, prior) == _p4_record(
        verdict="neutral", dropped=["pred2", "pred3"], content_lost=["pred3"])


def test_dropping_a_corroborated_prediction_blocks_a_progressive_verdict(fixtures_dir):
    v1 = _signed_p3(_v1(fixtures_dir))
    new = _with_p4(v1)
    new["predictions"] = [p for p in new["predictions"] if p["id"] != "pred1"]
    new["test_outcomes"] = [t for t in new["test_outcomes"] if t["prediction_id"] != "pred1"]
    assert tf.appraise_amendment(new, v1) == _p4_record(
        verdict="neutral", dropped=["pred1"], dropped_corroborated=["pred1"])


def test_a_failed_replication_of_retained_content_is_a_new_anomaly(fixtures_dir):
    # D5. An anomaly is reported and never decides the verdict.
    v1 = _signed_p3(_v1(fixtures_dir))
    new = copy.deepcopy(v1)
    new["test_outcomes"].append({"prediction_id": "pred1", "passed": False, "registered": "osf.io/klmno"})
    assert tf.appraise_amendment(new, v1) == _record(new_anomalies=["pred1"])
    result = tf.appraise_amendment(_with_p4(new), v1)
    assert (result["verdict"], result["new_anomalies"]) == ("progressive", ["pred1"])
    # A renamed prediction is retained content too.
    new["predictions"][0]["id"] = "pred1_v2"
    for t in new["test_outcomes"]:
        if t["prediction_id"] == "pred1":
            t["prediction_id"] = "pred1_v2"
    result = tf.appraise_amendment(new, v1)
    assert result["renamed"] == [{"prior": "pred1", "new": "pred1_v2"}]
    assert result["new_anomalies"] == ["pred1_v2"]


def test_an_unregistered_pass_corroborates_but_is_not_reported_as_registered(fixtures_dir):
    # D7: registered is read for the report key alone.
    v1 = _signed_p3(_v1(fixtures_dir))
    for registered in (None, " "):
        new = _with_p4(v1)
        new["test_outcomes"][-1]["registered"] = registered
        assert tf.appraise_amendment(new, v1) == _p4_record(corroborated_new_registered=[])


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
    # Reversing p2 makes pred5 new content, and gives up the positive effects
    # of arousal and threat on avoidance that v1 entails, so content is lost.
    changed = copy.deepcopy(v1)
    changed["propositions"][1]["relation"] = "decreases"
    changed["predictions"].append({**pred5, "derives_from": ["p2"]})
    changed["test_outcomes"].append({"prediction_id": "pred5", "passed": True})
    result = tf.appraise_amendment(changed, v1)
    assert (result["verdict"], result["articulated"], result["signs_lost"]) == (
        "neutral", [], ["effect of c_arousal on c_avoidance: positive", SIGN])


# -- What the amendment gives up and what its new content rests on -------------
# The cases below amend amend-prior and amend-prior-corroborated in
# fixtures/edge. GAINED is what adding c4 and p3 from c3 to c4 adds.

GAINED = ["c1 _||_ c4 | c3", "c2 _||_ c4 | c1, c3"]


def _new_h3(**changes):
    """The record of an amendment that adds c4, p3 and a corroborated h3 derived from it."""
    return _record(**{"new_predictions": ["h3"], "corroborated_new": ["h3"],
                      "theoretically_progressive": True, "empirically_progressive": True,
                      "implications_gained": GAINED, **changes})


def test_a_reversed_proposition_loses_the_entailment_of_a_corroborated_claim(fixtures_dir):
    # amend-sign-flip (c1b): p1 now lowers c2, so the new graph contradicts the
    # corroborated h1, which states that c1 raises c2.
    prior = _edge(fixtures_dir, "amend-prior-corroborated")
    new = _edge(fixtures_dir, "amend-sign-flip")
    signs = ["effect of c1 on c2: positive", "effect of c1 on c3: positive"]
    assert tf.appraise_amendment(new, prior) == _new_h3(
        verdict="neutral", content_lost=["h1"], signs_lost=signs,
        entailments_lost=[{"id": "h1", "prior": "entailed", "new": "contradicted"}])
    # Under a new id, h1 is renamed and listed under that id.
    renamed = copy.deepcopy(new)
    renamed["predictions"][0]["id"] = "h1_v2"
    renamed["test_outcomes"][0]["prediction_id"] = "h1_v2"
    result = tf.appraise_amendment(renamed, prior)
    assert (result["content_lost"], result["entailments_lost"]) == (
        ["h1_v2"], [{"id": "h1_v2", "prior": "entailed", "new": "contradicted"}])
    # Untested in the prior, h1 is unrefuted content too.
    untested = copy.deepcopy(prior)
    untested["test_outcomes"] = []
    assert tf.appraise_amendment(new, untested)["content_lost"] == ["h1"]
    # Refuted in the prior, its claim was refuted content, and so was the sign
    # of the effect of c1 on c2 that it states. Only the sign of the effect of
    # c1 on c3 is then lost.
    refuted = copy.deepcopy(prior)
    refuted["test_outcomes"][0]["passed"] = False
    result = tf.appraise_amendment(new, refuted)
    assert (result["content_lost"], result["entailments_lost"], result["signs_lost"]) == (
        [], [], ["effect of c1 on c3: positive"])
    # A failed claim that the effect is nonzero refutes either sign of it.
    nonzero = copy.deepcopy(refuted)
    nonzero["predictions"][0]["claim"]["sign"] = "nonzero"
    assert tf.appraise_amendment(new, nonzero)["signs_lost"] == ["effect of c1 on c3: positive"]


def test_a_retained_prediction_is_counted_once_in_content_lost(fixtures_dir):
    # h1 is both weakened, from a directional claim to an existence claim with
    # its region dropped, and no longer entailed.
    prior = _edge(fixtures_dir, "amend-prior-corroborated")
    new = _edge(fixtures_dir, "amend-sign-flip")
    new["predictions"][0]["type"] = "existence"
    del new["predictions"][0]["bounds"]
    result = tf.appraise_amendment(new, prior)
    assert (result["content_lost"], result["revised"]) == (["h1"], [{"id": "h1", "change": "weakened"}])
    assert result["entailments_lost"] == [{"id": "h1", "prior": "entailed", "new": "contradicted"}]


def test_an_unsigned_proposition_leaves_a_corroborated_claim_undetermined(fixtures_dir):
    # amend-weakened-sign (V2): p1 restated as causes.
    prior = _edge(fixtures_dir, "amend-prior-corroborated")
    new = _edge(fixtures_dir, "amend-weakened-sign")
    assert tf.appraise_amendment(new, prior) == _new_h3(
        verdict="neutral", content_lost=["h1"],
        signs_lost=["effect of c1 on c2: positive", "effect of c1 on c3: positive"],
        entailments_lost=[{"id": "h1", "prior": "entailed", "new": "undetermined"}])
    # Without p1, the new graph no longer relates c1, so the claim is not evaluated.
    dropped = copy.deepcopy(new)
    dropped["propositions"] = dropped["propositions"][1:]
    assert tf.appraise_amendment(dropped, prior)["entailments_lost"] == [
        {"id": "h1", "prior": "entailed", "new": "not_evaluated"}]


def test_a_sign_no_prediction_states_is_content(fixtures_dir):
    # amend-lost-sign (C4): reversing p2 gives up the positive effects of c1
    # and c2 on c3, which no prediction states.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-lost-sign")
    assert tf.appraise_amendment(new, prior) == _new_h3(
        verdict="neutral", signs_lost=["effect of c1 on c3: positive", "effect of c2 on c3: positive"])
    # A sign the new graph cannot derive, because no proposition relates c3
    # once p2 is dropped, is lost too.
    dropped = copy.deepcopy(prior)
    dropped["propositions"] = dropped["propositions"][:1]
    result = tf.appraise_amendment(dropped, prior)
    assert result["signs_lost"] == ["effect of c1 on c3: positive", "effect of c2 on c3: positive"]
    assert result["implications_lost_unrefuted"] == ["c1 _||_ c3 | c2"]


def test_a_version_whose_graph_is_refused_compares_no_signs(fixtures_dir):
    # As in amend-lost-sign, with a repeated construct id: the graphs are not
    # compared, so no sign is lost.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-lost-sign")
    new["constructs"].append(copy.deepcopy(new["constructs"][0]))
    assert tf.appraise_amendment(new, prior) == _new_h3(
        verdict="progressive", implications_compared=False, implications_gained=[])


def test_novelty_that_rests_on_protects_is_reported(fixtures_dir):
    # amend-protects-only (C3): a replication of old content is new content
    # only because the core assumption a2 lists it in protects.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-protects-only")
    assert tf.appraise_amendment(new, prior) == _record(
        verdict="progressive", new_predictions=["h4"], corroborated_new=["h4"],
        theoretically_progressive=True, empirically_progressive=True, protected_only=["h4"])
    # Without a2, h4 articulates old content and the amendment is neutral.
    without = copy.deepcopy(new)
    without["auxiliary_assumptions"] = without["auxiliary_assumptions"][:1]
    assert tf.appraise_amendment(without, prior) == _record(
        new_predictions=["h4"], corroborated_new=["h4"], articulated=["h4"])
    # A claim the prior's graph entails is old content whatever protects it.
    entailed = copy.deepcopy(new)
    entailed["predictions"][2]["claim"] = {"kind": "effect", "x": "c2", "y": "c3", "sign": "positive"}
    result = tf.appraise_amendment(entailed, prior)
    assert (result["articulated"], result["protected_only"], result["verdict"]) == (["h4"], [], "neutral")


def test_refuted_new_predictions_are_reported(fixtures_dir):
    # amend-refuted-new: one corroborated new prediction is enough, and the
    # refuted one is reported beside the verdict.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-refuted-new")
    assert tf.appraise_amendment(new, prior) == _new_h3(
        verdict="progressive", new_predictions=["h3", "h4"], refuted_new=["h4"])
    # A new prediction both passed and failed is mixed, and reported too.
    new["test_outcomes"].append({"prediction_id": "h4", "passed": True})
    assert tf.appraise_amendment(new, prior)["refuted_new"] == ["h4"]


def test_the_severity_of_each_corroborating_pass_is_reported(fixtures_dir):
    # amend-low-severity: h3 passed with an estimate below its region.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-low-severity")
    assert tf.appraise_amendment(new, prior) == _new_h3(
        verdict="progressive", corroborated_new_severity=[{"id": "h3", "severity": 0.001}])
    assert tf.post_data_severity(new)[0]["severity"] == 0.001
    # The smallest severity over the passes is reported.
    more = copy.deepcopy(new)
    more["test_outcomes"].append({"prediction_id": "h3", "passed": True, "estimate": 0.3, "se": 0.05})
    assert tf.appraise_amendment(more, prior)["corroborated_new_severity"] == [
        {"id": "h3", "severity": 0.001}]
    more["test_outcomes"][1] = {"prediction_id": "h3", "passed": True}
    assert tf.appraise_amendment(more, prior)["corroborated_new_severity"] == [
        {"id": "h3", "severity": 0.977}]
    # An outcome that post_data_severity() would refuse gives no value, and
    # neither does a prediction without bounds.
    refused = copy.deepcopy(new)
    refused["test_outcomes"][1]["se"] = 0
    assert tf.appraise_amendment(refused, prior)["corroborated_new_severity"] == [
        {"id": "h3", "severity": None}]
    unbounded = copy.deepcopy(new)
    del unbounded["predictions"][2]["bounds"]
    assert tf.appraise_amendment(unbounded, prior)["corroborated_new_severity"] == [
        {"id": "h3", "severity": None}]


def test_an_assumption_whose_independent_prediction_is_untested_is_pending(fixtures_dir):
    # amend-pending (C5): a2 answers the refuted h1 and yields the untested h4.
    prior = _edge(fixtures_dir, "amend-prior")
    new = _edge(fixtures_dir, "amend-pending")
    pending = {"id": "a2", "added_for": "h1", "class": "pending",
               "independent": [{"id": "h4", "status": "untested"}],
               "added_for_inferred": False, "change": "new"}
    assert tf.appraise_amendment(new, prior) == _record(
        new_predictions=["h4"], assumptions=[pending], theoretically_progressive=True,
        protected_only=["h4"])
    # With one independent prediction tested and failed, a2 is ad hoc.
    new["predictions"].append({**new["predictions"][2], "id": "h5"})
    new["predictions"][3]["statement"] = "c2 rises with c1 only in a quiet room."
    new["auxiliary_assumptions"][1]["protects"] = ["h1", "h4", "h5"]
    new["test_outcomes"].append({"prediction_id": "h5", "passed": False})
    result = tf.appraise_amendment(new, prior)
    assert (result["assumptions"][0]["class"], result["ad_hoc_assumptions"], result["verdict"]) == (
        "ad_hoc2", ["a2"], "degenerating")
