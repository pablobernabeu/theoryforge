"""The rigour checklist (API_SPEC.md section 4).

An item with nothing to assess is ``n/a``, with a null score, and is left out of
the aggregate, which is the weighted mean of the applicable items. The report
gives ``coverage``, the share of checklist weight that was applicable, and
``aggregate_range``, the aggregate under other weightings. Parsimony fails an
assumption that answers an anomaly without independent corroboration,
non-redundancy follows the redundancy screen's flags, precision counts bounded
point and interval claims and mean severity counts every prediction, using the
claim-form rubric where none is declared. The R suite (test-checklist.R) builds
the same theories and asserts the same values.
"""
import copy

import pytest

import theoryforge as tf
from theoryforge import _resources

ITEM_IDS = ["falsifiability", "precision", "risk_severity", "parsimony", "non_redundancy",
            "construct_clarity", "scope", "logical_why", "causal_testability",
            "diagnosticity", "formalisation", "derivation_chain"]

TWO_CONSTRUCTS = [
    {"id": "c1", "label": "Alpha", "definition": "The first construct."},
    {"id": "c2", "label": "Beta", "definition": "The second construct."},
]
P1 = [{"id": "p1", "from": "c1", "to": "c2", "relation": "increases",
       "mechanism": "Alpha drives Beta."}]


def _items(report):
    return {it["id"]: it for it in report["items"]}


def _bare(**fields):
    """A theory holding the four required fields and ``fields``."""
    return tf.Theory({"schema_version": "1.0", "id": "t", "title": "T", "maturity": "building",
                      **fields})


def _item(t, iid):
    it = _items(t.check())[iid]
    return it["status"], it["score"]


# -- the checklist file and the report ----------------------------------------

def test_the_checklist_is_version_3_with_five_default_thresholds():
    spec = _resources.checklist()
    assert spec["schema_version"] == "3.1"
    # parsimony_ratio_max is gone: parsimony no longer counts assumptions.
    assert spec["thresholds"] == {
        "redundancy_similarity_max": 0.85, "redundancy_overlap_max": 0.85,
        "embedding_similarity_max": 0.85, "min_precision_share": 0.5, "min_severity": 0.5,
    }
    assert [it["id"] for it in spec["items"]] == ITEM_IDS
    items = {it["id"]: it for it in spec["items"]}
    assert items["risk_severity"]["criterion"] == (
        "Mean prediction riskiness (declared severity, else the claim-form rubric) at or above "
        "threshold")
    # Meehl (1990a) is the Psychological Inquiry article, Meehl (1990b) the
    # Psychological Reports one, as on the methodology page.
    assert items["precision"]["citation"] == "Meehl (1967, 1990a)"
    assert items["risk_severity"]["citation"] == "Popper (1959); Meehl (1967, 1990b)"
    assert items["parsimony"]["citation"] == "Lakatos (1970); Meehl (1990a)"
    assert items["derivation_chain"]["criterion"] == (
        "Every prediction cites declared propositions, the causal graph entails any claim it "
        "states and contradicts no phenomenon's claim (a claim left unread because of a "
        "feedback loop warns)")
    # The criteria say what is checked, which the dossier and the HTML report print.
    assert items["falsifiability"]["criterion"] == (
        "At least one prediction is typed point, interval or directional; the label is the "
        "author's")
    assert items["logical_why"]["criterion"] == (
        "Every proposition's mechanism field is filled in; its text is not judged")


def test_the_report_gives_coverage_after_the_aggregate(panic_path):
    r = tf.read(panic_path).check()
    assert list(r) == ["theory_id", "schema_version", "checklist_version", "maturity",
                       "aggregate_score", "aggregate_range", "coverage", "gate",
                       "n_blockers_failed", "items"]
    # parsimony has nothing to assess, and the other eleven items weigh 0.92.
    assert (r["checklist_version"], r["aggregate_score"], r["coverage"]) == ("3.1", 85.9, 0.92)
    assert (_items(r)["parsimony"]["status"], _items(r)["parsimony"]["score"]) == ("n/a", None)


def test_the_empty_theory_scores_zero():
    # It scored 26.0: parsimony, non_redundancy and derivation_chain each
    # passed at 1.0 with nothing to assess.
    r = _bare().check()
    assert (r["aggregate_score"], r["coverage"], r["gate"]) == (0.0, 0.74, "blocked")
    it = _items(r)
    for iid in ("parsimony", "non_redundancy", "derivation_chain"):
        assert (it[iid]["status"], it[iid]["score"]) == ("n/a", None), iid
    for iid in ITEM_IDS:
        assert it[iid]["status"] in ("n/a", "warn", "fail"), iid


def test_one_prediction_never_scores_below_the_empty_theory():
    # The empty theory with one existence prediction scored 18.0, below the
    # 26.0 of the empty theory, since the prediction made derivation_chain fail.
    empty = _bare().check()["aggregate_score"]
    for typ in ("existence", "directional", "interval", "point"):
        t = _bare(predictions=[{"id": "h1", "statement": "S.", "type": typ}])
        assert t.check()["aggregate_score"] >= empty, typ
    r = _bare(predictions=[{"id": "h1", "statement": "X exists.", "type": "existence"}]).check()
    assert (r["aggregate_score"], r["coverage"]) == (1.2, 0.82)


# -- risk_severity: declared, else the claim-form rubric ----------------------

def test_mean_severity_counts_every_prediction():
    # Undeclared predictions were skipped, so a theory built without severities
    # scored warn 0.0 however risky its claims were.
    b = tf.new_theory("b", "Builder demo")
    b.add_construct("a", "A", "first thing", measurement=["m1"], boundary_conditions=["adults"])
    b.add_construct("c", "C", "second other thing", measurement=["m2"],
                    boundary_conditions=["adults"])
    b.add_proposition("p1", "a", "c", "increases", mechanism="a drives c")
    b.add_prediction("h1", "C equals 3.", "point", derives_from=["p1"],
                     bounds={"lower": 2.9, "upper": 3.1})
    b.add_prediction("h2", "C lies in [2, 4].", "interval", derives_from=["p1"],
                     bounds={"lower": 2, "upper": 4})
    assert _item(b, "risk_severity") == ("pass", 0.8)
    # A declared value is used where one is given, the rubric elsewhere.
    t = _bare(predictions=[
        {"id": "h1", "statement": "C equals 3.", "type": "point", "severity": 0.3},
        {"id": "h2", "statement": "C lies in [2, 4].", "type": "interval",
         "bounds": {"lower": 2, "upper": 4}},
    ])
    assert _item(t, "risk_severity") == ("pass", 0.5)
    # Nine undeclared existence predictions no longer leave one declared at 0.9
    # to pass on its own.
    preds = [{"id": f"e{i}", "statement": "X exists.", "type": "existence"} for i in range(9)]
    preds.append({"id": "h1", "statement": "X is 3.", "type": "point", "severity": 0.9})
    assert _item(_bare(predictions=preds), "risk_severity") == ("warn", 0.18)


def test_a_declared_severity_counts_and_the_dossier_sets_it_beside_the_rubric():
    t = _bare(predictions=[
        {"id": "h1", "statement": "X exists.", "type": "existence", "severity": 0.95},
        {"id": "h2", "statement": "X is positive.", "type": "directional", "severity": 0.5},
        {"id": "h3", "statement": "X is 3.", "type": "point", "bounds": {"lower": 2.9, "upper": 3.1}},
    ])
    assert _item(t, "risk_severity") == ("pass", 0.783)
    d = t.dossier()
    assert ("- h1: severity 0.1, risk 0.1, declared 0.95 "
            "(declared exceeds the rubric by more than 0.2)\n") in d
    # 0.5 exceeds the directional rubric value, 0.3, by exactly 0.2: no note.
    assert "- h2: severity 0.3, risk 0.4, declared 0.5\n" in d
    assert "- h3: severity 0.9, risk 0.9\n" in d
    # The preregistration appended to the dossier leaves its own severity list out.
    assert "\n### Severity" not in d


def test_add_prediction_stores_a_severity_only_when_given():
    t = (tf.new_theory("b", "B")
         .add_prediction("h1", "C equals 3.", "point", severity=0.95)
         .add_prediction("h2", "C equals 4.", "point", bounds={"lower": 3.9, "upper": 4.1}))
    assert t.data["predictions"][0] == {"id": "h1", "statement": "C equals 3.", "type": "point",
                                        "severity": 0.95}
    assert "severity" not in t.data["predictions"][1]
    assert _item(t, "risk_severity") == ("pass", 0.925)


# -- parsimony: assumptions added for an anomaly ------------------------------

def _defended(protects, outcomes):
    """x1 answers the anomaly of h1, and may protect h2 as well."""
    return _bare(
        constructs=TWO_CONSTRUCTS, propositions=P1,
        predictions=[
            {"id": "h1", "statement": "Beta rises with Alpha.", "type": "directional",
             "derives_from": ["p1"]},
            {"id": "h2", "statement": "Beta lags Alpha by a day.", "type": "directional",
             "derives_from": ["p1"]},
        ],
        auxiliary_assumptions=[{"id": "x1", "statement": "The effect needs a calm setting.",
                                "added_for": "h1", "protects": protects}],
        test_outcomes=outcomes,
    )


def test_parsimony_is_not_applicable_without_an_assumption_added_for_an_anomaly():
    # The ratio of assumptions to propositions penalised declaring core
    # assumptions, which every derivation uses (Meehl, 1990a).
    core = [{"id": "a1", "statement": "Self-report tracks arousal.", "added_for": None},
            {"id": "a2", "statement": "A blank added_for names no anomaly.", "added_for": " "}]
    assert _item(_bare(auxiliary_assumptions=core), "parsimony") == ("n/a", None)
    assert _item(_bare(), "parsimony") == ("n/a", None)


def test_parsimony_passes_an_independently_corroborated_assumption():
    t = _defended(["h1", "h2"], [{"prediction_id": "h2", "passed": True}])
    assert _item(t, "parsimony") == ("pass", 1.0)


def test_parsimony_fails_an_assumption_supported_only_by_its_anomaly():
    # A pass of h1, the prediction the assumption answers, used to clear it.
    t = _defended(["h1"], [{"prediction_id": "h1", "passed": True}])
    assert _item(t, "parsimony") == ("fail", 0.0)


def test_parsimony_fails_an_assumption_whose_other_support_is_not_corroborated():
    # A failed replication leaves h2 mixed, which used to count as a pass.
    mixed = [{"prediction_id": "h2", "passed": True}, {"prediction_id": "h2", "passed": False}]
    assert _item(_defended(["h1", "h2"], mixed), "parsimony") == ("fail", 0.0)
    assert _item(_defended(["h1", "h2"], []), "parsimony") == ("fail", 0.0)


# -- non_redundancy: the screen's flags ---------------------------------------

def test_the_screen_flags_a_definition_contained_in_another(weak_path):
    # Their Jaccard similarity, 0.8, stayed under 0.85, so the deliberately
    # redundant pair of the weak example passed.
    t = tf.read(weak_path)
    rows = t.redundancy_check()
    assert rows == [{"a": "k_motivation", "b": "k_drive", "similarity": 0.8, "overlap": 1.0,
                     "flag": "review", "reason": "contained"}]
    assert list(rows[0]) == ["a", "b", "similarity", "overlap", "flag", "reason"]
    assert _item(t, "non_redundancy") == ("warn", 0.0)


def _pair(d1, d2):
    t = _bare(constructs=[{"id": "a", "label": "A", "definition": d1},
                          {"id": "b", "label": "B", "definition": d2}])
    row = t.redundancy_check()[0]
    return (row["similarity"], row["overlap"], row["flag"]), _item(t, "non_redundancy")


def test_overlap_counts_only_between_definitions_of_three_tokens_or_more():
    assert _pair("Bodily arousal response.", "Bodily arousal response under threat.") == (
        (0.6, 1.0, "review"), ("warn", 0.0))
    assert _pair("Bodily arousal.", "Bodily arousal under threat in adults.") == (
        (0.4, 1.0, "ok"), ("pass", 1.0))
    # A construct with no definition cannot be screened, so the item cannot pass.
    assert _pair("", "Bodily arousal response.") == ((0.0, 0.0, "ok"), ("warn", 0.0))


def test_non_redundancy_is_not_applicable_to_one_construct(panic_path):
    t = _bare(constructs=TWO_CONSTRUCTS[:1])
    assert _item(t, "non_redundancy") == ("n/a", None)
    # Shared vocabulary below the thresholds no longer costs points.
    assert _item(tf.read(panic_path), "non_redundancy") == ("pass", 1.0)


# -- causal_testability, formalisation and the relation table -----------------

def test_causal_testability_counts_every_directed_relation():
    for rel, status in (("mediates", "pass"), ("moderates", "pass"), ("causes", "pass"),
                        ("decreases", "pass"), ("associates", "warn")):
        t = _bare(constructs=TWO_CONSTRUCTS,
                  propositions=[{"id": "p1", "from": "c1", "to": "c2", "relation": rel}])
        assert _item(t, "causal_testability")[0] == status, rel


def test_the_relation_table_covers_the_schema_enum():
    from theoryforge import _relations

    prop = _resources.theory_schema()["properties"]["propositions"]["items"]
    assert sorted(_relations.RELATIONS) == sorted(prop["properties"]["relation"]["enum"])
    assert _relations.RELATIONS == {
        "increases": ("directed", 1), "decreases": ("directed", -1),
        "causes": ("directed", None), "mediates": ("directed", None),
        "moderates": ("directed", None), "associates": ("bidirected", None),
    }
    assert _relations.DIRECTED == frozenset(
        {"increases", "decreases", "causes", "mediates", "moderates"})
    assert _relations.PATHS == frozenset({"increases", "decreases", "causes", "mediates"})


def test_formalisation_needs_a_recognised_model_type():
    for fm, status in (({"type": "banana"}, "warn"), ({"type": "none"}, "warn"),
                       ({"type": ""}, "warn"), ({}, "warn"), ({"type": "abm"}, "pass"),
                       ({"type": "sem"}, "pass")):
        assert _item(_bare(formal_model=fm), "formalisation")[0] == status, fm


def test_embedding_redundancy_defaults_to_its_own_threshold(monkeypatch):
    # A cosine threshold depends on the embedding model, so it is not the
    # lexical screen's Jaccard threshold.
    spec = copy.deepcopy(_resources.checklist())
    spec["thresholds"]["embedding_similarity_max"] = 0.5
    monkeypatch.setattr(_resources, "checklist", lambda: spec)
    vectors = {"The first construct.": [1.0, 0.0], "The second construct.": [0.6, 0.8]}
    rows = _bare(constructs=TWO_CONSTRUCTS).embedding_redundancy(lambda d: vectors[d])
    assert (rows[0]["cosine"], rows[0]["flag"]) == (0.6, "review")


# -- what the renderers print -------------------------------------------------

def test_the_dossier_gives_coverage_and_names_the_failed_blockers(weak_path):
    d = tf.read(weak_path).dossier()
    assert ("- Aggregate rigour score: 2.2/100 (1.1 to 3.9 under other weightings)\n"
            "- Checklist coverage: 0.92\n- Gate: blocked\n"
            "- Blockers failed: 2 (falsifiability, derivation_chain)\n") in d
    assert "| parsimony | No auxiliary assumption added for an anomaly (named in added_for) lacks " \
        "independent corroboration | n/a | n/a | 0.08 |\n" in d
    assert "| non_redundancy | Every construct is defined, and no two have near-duplicate or " \
        "contained definitions or one label, and no construct's measures are all listed for " \
        "another (lexical screen) | warn | 0.0 | 0.1 |\n" in d


def test_the_views_and_the_html_report_show_not_applicable_items(weak_path):
    t = tf.read(weak_path)
    roadmap = t.diagram("development_roadmap")
    assert "score 2.2, gate blocked" in roadmap
    assert '"parsimony"' not in roadmap
    svg = t.diagram("rigour")
    # parsimony is the fourth row, at y = 60 + 24 * 3.
    assert '<rect x="20" y="132" width="16" height="16" rx="3" fill="#9e9e9e"/>' in svg
    assert '<text x="320" y="144">n/a</text>' in svg
    assert ("<tr><td>parsimony</td><td>No auxiliary assumption added for an anomaly (named in "
            "added_for) lacks independent corroboration</td><td>n/a</td><td>n/a</td>"
            ) in t.report(format="html")


# -- checklist 3.0 --------------------------------------------------------------

def _pred(pid, typ, **fields):
    return {"id": pid, "statement": "s", "type": typ, "derives_from": ["p1"], **fields}


def test_precision_counts_point_and_interval_claims_only_with_two_finite_bounds():
    t = _bare(constructs=TWO_CONSTRUCTS, propositions=P1, predictions=[
        _pred("h1", "point"),
        _pred("h2", "interval", bounds={"lower": 20, "upper": 60}),
        _pred("h3", "point", bounds={"lower": 5, "upper": 5}),
        _pred("h4", "directional", bounds={"lower": 0}),
    ])
    assert _item(t, "precision") == ("pass", 0.5)
    t.data["predictions"][2]["bounds"] = {"lower": 5}
    assert _item(t, "precision") == ("warn", 0.25)


def test_parsimony_leaves_a_core_assumption_whose_prediction_failed_to_the_appraisal():
    # Without a prior version the checklist cannot tell an assumption made
    # before a test from one made after it, so only a declared added_for is
    # assessed, and appraise_amendment() infers undeclared additions.
    preds = [_pred("h1", "directional"), _pred("h2", "directional")]
    aux = [{"id": "a1", "statement": "Only in calm settings.", "protects": ["h1", "h2"]}]
    failed = [{"prediction_id": "h1", "passed": False}]
    t = _bare(constructs=TWO_CONSTRUCTS, propositions=P1, predictions=preds,
              auxiliary_assumptions=aux, test_outcomes=failed)
    assert _item(t, "parsimony") == ("n/a", None)
    t.data["auxiliary_assumptions"][0]["added_for"] = "h1"
    assert _item(t, "parsimony") == ("fail", 0.0)
    t.data["test_outcomes"] = failed + [{"prediction_id": "h2", "passed": True}]
    assert _item(t, "parsimony") == ("pass", 1.0)


def test_the_screen_flags_a_shared_label_and_a_shared_measure():
    t = _bare(constructs=[
        {"id": "a", "label": "Anxiety", "definition": "Worry about future threat.",
         "measurement": ["GAD-7 total score"]},
        {"id": "b", "label": " anxiety ", "definition": "Bodily arousal under danger.",
         "measurement": ["gad-7  total score", "Heart rate"]},
        {"id": "c", "label": "Fear", "definition": "An urge to escape present danger.",
         "measurement": ["Heart rate"]},
    ])
    rows = {(r["a"], r["b"]): (r["flag"], r["reason"]) for r in t.redundancy_check()}
    assert rows == {("a", "b"): ("review", "same label, shared measurement"),
                    ("a", "c"): ("ok", ""),
                    ("b", "c"): ("review", "shared measurement")}
    assert _item(t, "non_redundancy") == ("warn", 0.0)
    # Constructs that share a method but keep measures of their own are not
    # flagged, as in a multitrait-multimethod design.
    t = _bare(constructs=[
        {"id": "a", "label": "A", "definition": "Worry about future threat.",
         "measurement": ["Self-report", "Informant rating"]},
        {"id": "b", "label": "B", "definition": "Bodily arousal under danger.",
         "measurement": ["self-report", "Heart rate"]},
    ])
    assert t.redundancy_check()[0]["flag"] == "ok"


def test_non_redundancy_cannot_pass_while_a_definition_is_empty():
    defined = copy.deepcopy(TWO_CONSTRUCTS)
    assert _item(_bare(constructs=defined), "non_redundancy") == ("pass", 1.0)
    defined[1]["definition"] = "  "
    assert _item(_bare(constructs=defined), "non_redundancy") == ("warn", 0.0)


def test_the_aggregate_range_spans_the_alternative_weightings(panic_path):
    rep = tf.read(panic_path).check()
    lo, hi = rep["aggregate_range"]
    assert lo <= rep["aggregate_score"] <= hi
    assert (lo, hi) == (82.1, 87.9)
    applicable = [(it["weight"], it["score"]) for it in rep["items"] if it["score"] is not None]
    equal = round(sum(x for _, x in applicable) / len(applicable) * 100, 1)
    assert lo <= equal <= hi
    # When every applicable item has one score, no weighting can move it.
    t = _bare(constructs=TWO_CONSTRUCTS[:1])
    rep = t.check()
    assert rep["aggregate_range"] == [rep["aggregate_score"], rep["aggregate_score"]]


def test_a_severity_too_large_for_a_double_is_refused_as_non_numeric():
    t = _bare(constructs=TWO_CONSTRUCTS, predictions=[_pred("h1", "point", severity=10 ** 400)])
    try:
        t.check()
    except ValueError as err:
        assert str(err) == ("check requires numeric prediction severities; "
                            "non-numeric severity for prediction: h1")
    else:
        raise AssertionError("check() accepted an infinite severity")


def test_full_validation_checks_a_claim_form_and_sign_against_its_bounds():
    positive = {"kind": "effect", "x": "c1", "y": "c2", "sign": "positive"}
    t = _bare(constructs=TWO_CONSTRUCTS, predictions=[
        _pred("h1", "point", bounds={"lower": 1}),
        _pred("h2", "interval", bounds={"upper": 2}),
        _pred("h3", "directional", bounds={"lower": 0.2, "upper": 1}),
        _pred("h4", "existence", bounds={"lower": 0.2, "upper": 0.8}),
        _pred("h5", "interval", bounds={"lower": -1, "upper": 1}, claim=positive),
        # A sign stated with a bound at 0 on a bounded scale is accepted.
        _pred("h6", "directional", bounds={"lower": 0, "upper": 1}, claim=positive),
        # An existence claim takes no bounds, on one side or on two, and
        # without them it may state the sign nonzero.
        _pred("h7", "existence", bounds={"lower": 0.2}),
        _pred("h8", "existence", bounds={"upper": 0.5}),
        _pred("h9", "existence", claim={**positive, "sign": "nonzero"}),
    ], test_outcomes=[
        # A pass with the estimate outside the region is not invalid: a test
        # that fails to reject a predicted value passes it (Meehl, 1967).
        {"prediction_id": "h6", "passed": True, "estimate": -0.1, "se": 0.2},
    ])
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    assert str(exc.value).endswith(
        "prediction[0] is a point claim, so its bounds need a finite lower and a finite upper; "
        "prediction[1] is an interval claim, so its bounds need a finite lower and a finite upper; "
        "prediction[2] is a directional claim, so its bounds must leave one side open or end "
        "at 0; "
        "prediction[3] is an existence claim, so it takes no bounds: the region it allows, "
        "every value but 0, is not one interval; "
        "prediction[4] claims a positive sign, so its lower bound must be 0 or above; "
        "prediction[6] is an existence claim, so it takes no bounds: the region it allows, "
        "every value but 0, is not one interval; "
        "prediction[7] is an existence claim, so it takes no bounds: the region it allows, "
        "every value but 0, is not one interval")


def test_the_dossier_writes_an_extreme_severity_as_a_bound(panic_path):
    t = tf.read(panic_path)
    t.data["test_outcomes"] = [{"prediction_id": "pred1", "passed": True, "estimate": 20, "se": 0.5}]
    assert "post-data severity > 0.999 for [15, 25]" in t.dossier()
    t.data["test_outcomes"] = [{"prediction_id": "pred1", "passed": False, "estimate": 40, "se": 1}]
    assert "post-data severity < 0.001 for [15, 25]\n" in t.dossier()
    t.data["test_outcomes"] = [{"prediction_id": "pred1", "passed": True, "estimate": 26, "se": 2}]
    assert ("post-data severity 0.309 for [15, 25]; recorded as passed, with the estimate "
            "outside that region\n") in t.dossier()


def test_equal_weights_can_set_the_end_of_the_aggregate_range():
    # Two low-weight items that pass beside a heavy one that fails: equal
    # weights give the highest aggregate, doubling the heavy weight the lowest.
    from theoryforge.rigor import _aggregate_range
    assert _aggregate_range([(0.15, 0.0), (0.05, 1.0), (0.05, 1.0)]) == [25.0, 66.7]


def test_precision_does_not_count_an_infinite_bound():
    t = _bare(constructs=TWO_CONSTRUCTS, propositions=P1,
              predictions=[_pred("h1", "point", bounds={"lower": 0, "upper": float("inf")})])
    assert _item(t, "precision") == ("warn", 0.0)


def test_non_redundancy_reads_a_definition_of_stopwords_as_no_definition():
    cons = copy.deepcopy(TWO_CONSTRUCTS)
    cons[1]["definition"] = "The and of"
    assert _item(_bare(constructs=cons), "non_redundancy") == ("warn", 0.0)


def test_an_unknown_field_names_the_first_of_two_equally_close_fields():
    # 'tyet' is two edits from both 'type' and 'test'; 'type' comes first in
    # the schema. A bare 'x' and 'xnote' are not extensions, and a key three
    # edits from every field gets no suggestion. The R suite asserts the same.
    from theoryforge.core import _unknown_fields
    known = ["id", "type", "test"]
    assert _unknown_fields({"tyet": 1, "x": 1, "xnote": 1, "x_note": 1, "abcdef": 1}, "p", known) == [
        "p has unknown field: tyet (did you mean type?)",
        "p has unknown field: x (did you mean id?)",
        "p has unknown field: xnote",
        "p has unknown field: abcdef",
    ]


# -- checklist 3.1: the derivation chain, the cycles option and the labels ------

def _loop_theory(sign="positive"):
    """x -> m -> y gives the effect of x on y a negative sign, and an unrelated
    feedback loop joins u and w. fixtures/edge/derivation-unrelated-loop is the
    same theory."""
    return _bare(
        maturity="developing",
        constructs=[{"id": c, "label": c.upper(), "definition": f"Construct {c}."}
                    for c in ("x", "m", "y", "u", "w")],
        propositions=[
            {"id": "p1", "from": "x", "to": "m", "relation": "increases", "mechanism": "It does."},
            {"id": "p2", "from": "m", "to": "y", "relation": "decreases", "mechanism": "It does."},
            {"id": "q1", "from": "u", "to": "w", "relation": "increases", "mechanism": "It does."},
            {"id": "q2", "from": "w", "to": "u", "relation": "increases", "mechanism": "It does."},
        ],
        predictions=[{"id": "h1", "statement": "x raises y.", "type": "directional",
                      "derives_from": ["p1", "p2"],
                      "claim": {"kind": "effect", "x": "x", "y": "y", "sign": sign}}],
    )


def _derivation(t, cycles="refuse"):
    r = t.check(cycles=cycles)
    it = _items(r)["derivation_chain"]
    return it["status"], it["score"], it["not_checked"], r["gate"]


def test_check_refuses_an_unknown_cycles_option():
    for bad in ("acyclic", None, ["sigma"], ""):
        with pytest.raises(ValueError, match=r"^check requires cycles to be 'refuse' or 'sigma'$"):
            tf.check(_bare(), cycles=bad)
    # The option is checked before the theory is read, so a refusal of the
    # theory does not hide it.
    bad_outcome = _bare(test_outcomes=[{"prediction_id": "h1", "passed": "true"}])
    with pytest.raises(ValueError, match="^check requires cycles"):
        bad_outcome.check(cycles="x")


def test_an_unrelated_feedback_loop_leaves_the_claim_not_checked():
    # The loop u <-> w has no path to the claim, yet under cycles = "refuse"
    # every claim of the graph is left unread. The prediction is not derived,
    # the item warns and the gate stays open. It passed at 1.0 under 3.0.
    t = _loop_theory()
    assert _derivation(t) == ("warn", 0.0, ["h1"], "pass")
    assert t.check()["n_blockers_failed"] == 0
    # Read by sigma-separation, the claim is contradicted and the item fails.
    assert _derivation(t, "sigma") == ("fail", 0.0, [], "blocked")
    # A claim the sigma reading entails passes.
    assert _derivation(_loop_theory("negative"), "sigma") == ("pass", 1.0, [], "pass")
    assert _derivation(_loop_theory("negative")) == ("warn", 0.0, ["h1"], "pass")


def test_only_the_derivation_chain_record_lists_unchecked_claims(panic_path):
    r = tf.read(panic_path).check()
    for it in r["items"]:
        keys = ["id", "status", "score", "weight", "severity_if_fail", "citation"]
        assert list(it) == (keys + ["not_checked"] if it["id"] == "derivation_chain" else keys)
    assert _items(r)["derivation_chain"]["not_checked"] == ["pred_indep"]
    # A not-checked prediction whose references do not resolve still fails
    # the item, and is still listed.
    t = _loop_theory()
    t.data["predictions"][0]["derives_from"] = ["p9"]
    assert _derivation(t) == ("fail", 0.0, ["h1"], "blocked")
    # With no prediction the item is n/a and lists nothing.
    assert _items(_bare().check())["derivation_chain"]["not_checked"] == []


def test_a_claim_the_graph_cannot_place_or_read_is_not_derived():
    base = dict(constructs=TWO_CONSTRUCTS + [{"id": "c3", "label": "Gamma",
                                              "definition": "A construct no proposition relates."}],
                propositions=P1)
    entailed = {"kind": "effect", "x": "c1", "y": "c2", "sign": "positive"}
    # fixtures/edge/derivation-not-in-graph: a construct outside the graph.
    t = _bare(**base, predictions=[
        _pred("h1", "directional", claim=entailed),
        _pred("h2", "directional", claim={**entailed, "y": "c3"}),
    ])
    assert _derivation(t) == ("fail", 0.5, [], "blocked")
    # A claim that cannot be read as written.
    t = _bare(**base, predictions=[_pred("h1", "directional", claim={**entailed, "y": "c1"})])
    assert _derivation(t) == ("fail", 0.0, [], "blocked")
    # A graph that cannot be built reads no claim, so a stated claim fails,
    # while a prediction that states none is judged on its references.
    refused = dict(constructs=TWO_CONSTRUCTS,
                   propositions=P1 + [{"id": "p2", "from": "c1", "to": "c9",
                                       "relation": "increases"}])
    assert _derivation(_bare(**refused, predictions=[_pred("h1", "directional", claim=entailed)])
                       ) == ("fail", 0.0, [], "blocked")
    assert _derivation(_bare(**refused, predictions=[_pred("h1", "directional")])
                       ) == ("pass", 1.0, [], "pass")


def test_a_phenomenon_the_graph_contradicts_fails_the_derivation_chain():
    # fixtures/edge/derivation-phenomenon. A prediction with this claim failed
    # the item, and a phenomenon with it left the item and the gate as they were.
    positive = {"kind": "effect", "x": "c1", "y": "c2", "sign": "positive"}
    negative = {"kind": "association", "x": "c1", "y": "c2", "sign": "negative"}
    t = _bare(constructs=TWO_CONSTRUCTS, propositions=P1,
              predictions=[_pred("h1", "directional", claim=positive)],
              phenomena=[{"id": "ph1", "statement": "s", "claim": negative}])
    assert _derivation(t) == ("fail", 1.0, [], "blocked")
    # A phenomenon the graph leaves open or does not evaluate changes nothing.
    for claim in ({"kind": "effect", "x": "c1", "y": "c9", "sign": "positive"},
                  {"kind": "effect", "x": "c1", "y": "c2", "sign": "bogus"}):
        t.data["phenomena"][0]["claim"] = claim
        assert _derivation(t) == ("pass", 1.0, [], "pass")
    t.data["propositions"][0]["relation"] = "causes"
    t.data["predictions"][0].pop("claim")
    t.data["phenomena"][0]["claim"] = negative
    assert _derivation(t) == ("pass", 1.0, [], "pass")


def test_diagnosticity_reads_the_claims_with_the_same_cycles():
    # Under "refuse" the theory's graph leaves the claim unread, so the
    # declared rival stands. Under "sigma" both graphs entail the claim, which
    # shows the declaration false.
    t = _loop_theory("negative")
    t.data["alternatives"] = [{"id": "r", "label": "A rival",
                               "propositions": copy.deepcopy(t.data["propositions"])}]
    t.data["predictions"][0]["diagnostic_vs"] = ["r"]
    assert _item(t, "diagnosticity") == ("pass", 1.0)
    assert _items(t.check(cycles="sigma"))["diagnosticity"]["score"] == 0.0


def test_full_validation_reports_a_directional_claim_that_states_no_direction():
    nonzero = {"kind": "effect", "x": "c1", "y": "c2", "sign": "nonzero"}
    t = _bare(constructs=TWO_CONSTRUCTS + [{"id": "c3", "label": "Gamma", "definition": "c3."}],
              propositions=P1, predictions=[
                  _pred("h1", "directional", claim=nonzero),
                  # With bounds too, after the messages about the bounds.
                  _pred("h2", "directional", bounds={"lower": 0}, claim=nonzero),
                  # A conditional claim can only be zero or nonzero, so the
                  # direction stays in the statement and nothing is reported.
                  _pred("h3", "directional", claim={"kind": "association", "x": "c1", "y": "c2",
                                                    "given": ["c3"], "sign": "nonzero"}),
                  # The other types may claim nonzero.
                  _pred("h4", "existence", claim=nonzero),
                  _pred("h5", "point", bounds={"lower": 0.2, "upper": 0.3}, claim=nonzero),
              ])
    with pytest.raises(ValueError) as exc:
        t.validate(full=True)
    assert str(exc.value) == (
        "invalid theory object: "
        "prediction[0] is a directional claim, so its claim's sign cannot be nonzero, which "
        "states no direction; "
        "prediction[1] claims a nonzero sign, so its bounds must exclude 0; "
        "prediction[1] is a directional claim, so its claim's sign cannot be nonzero, which "
        "states no direction")
    # The falsifiability item still reads the label alone.
    assert _item(t, "falsifiability") == ("pass", 1.0)


def test_the_rubric_rates_a_point_or_interval_label_without_bounds_as_directional():
    # fixtures/edge/label-without-content. A point label without bounds was
    # graded 0.9, the highest value, while the precision item gave it nothing.
    t = _bare(alternatives=[{"id": "alt", "label": "A rival"}], predictions=[
        _pred("h1", "point"),
        _pred("h2", "interval", bounds={"lower": 0.2}),
        _pred("h3", "point", diagnostic_vs=["alt"]),
        _pred("h4", "point", bounds={"lower": 0.25, "upper": 0.35}),
        _pred("h5", "interval", bounds={"lower": 0.2, "upper": float("inf")}),
        _pred("h6", "interval", bounds={"lower": 0.2, "upper": 0.8}),
    ])
    assert [(r["type"], r["risk_score"], r["computed_severity"]) for r in t.severity()] == [
        ("point", 0.4, 0.3), ("interval", 0.4, 0.3), ("point", 0.4, 0.4),
        ("point", 0.9, 0.9), ("interval", 0.4, 0.3), ("interval", 0.7, 0.7)]
    assert _item(t, "precision") == ("warn", 0.333)


def test_the_html_report_states_what_the_checklist_score_describes(panic_path):
    html = tf.read(panic_path).report(format="html")
    assert ("  <p>Checklist score: <strong>85.9</strong> (82.1 to 87.9 with equal weights or one "
            "weight halved or doubled) &middot; gate: <strong>pass</strong></p>\n") in html
    assert ("  <p>The checklist score describes how completely the file states what checklist "
            "3.1 asks for. Most items read whether a field is filled in or how a prediction is "
            "labelled, and stated claims are checked against the causal graph. Test outcomes "
            "are read only by the parsimony item, the weights are conventions, and no study has "
            "established what difference between two scores is meaningful. The score does not "
            "show that the theory is true or well reasoned.</p>\n") in html
    assert ("<tr><th>item</th><th>criterion</th><th>status</th><th>score</th>"
            "<th>source of the criterion</th></tr>") in html
    assert ("<tr><td>derivation_chain</td><td>Every prediction cites declared propositions, the "
            "causal graph entails any claim it states and contradicts no phenomenon's claim (a "
            "claim left unread because of a feedback loop warns)</td><td>warn</td><td>0.75</td>"
            "<td>Scheel et al. (2021); Szollosi et al. (2020)</td></tr>") in html
    assert "igour" not in html and "grounding" not in html and "Aggregate" not in html
