"""Checklist 2.0 (API_SPEC.md section 4).

An item with nothing to assess is ``n/a``, with a null score, and is left out of
the aggregate, which is the weighted mean of the applicable items. The report
gains ``coverage``, the share of checklist weight that was applicable.
Parsimony fails only an assumption added for an anomaly that has no independent
corroboration, non-redundancy follows the redundancy screen's flags and mean
severity counts every prediction, using the claim-form rubric where none is
declared. The R suite (test-checklist2.R) builds the same theories and asserts
the same values.
"""
import copy

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

def test_the_checklist_is_version_2_with_five_default_thresholds():
    spec = _resources.checklist()
    assert spec["schema_version"] == "2.0"
    # parsimony_ratio_max is gone: parsimony no longer counts assumptions.
    assert spec["thresholds"] == {
        "redundancy_similarity_max": 0.85, "redundancy_overlap_max": 0.85,
        "embedding_similarity_max": 0.85, "min_precision_share": 0.5, "min_severity": 0.5,
    }
    assert [it["id"] for it in spec["items"]] == ITEM_IDS
    items = {it["id"]: it for it in spec["items"]}
    assert items["risk_severity"]["criterion"] == (
        "Mean prediction severity (declared, else the claim-form rubric) at or above threshold")
    assert items["risk_severity"]["citation"] == "Popper (1959); Meehl (1967, 1990)"
    assert items["parsimony"]["citation"] == "Lakatos (1970); Meehl (1990)"
    assert items["derivation_chain"]["criterion"] == (
        "Every prediction cites at least one proposition, and every cited id is a declared "
        "proposition (reference check only)")


def test_the_report_gives_coverage_after_the_aggregate(panic_path):
    r = tf.read(panic_path).check()
    assert list(r) == ["theory_id", "schema_version", "checklist_version", "maturity",
                       "aggregate_score", "coverage", "gate", "n_blockers_failed", "items"]
    # parsimony has nothing to assess, and the other eleven items weigh 0.92.
    assert (r["checklist_version"], r["aggregate_score"], r["coverage"]) == ("2.0", 87.3, 0.92)
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
    b.add_prediction("h1", "C equals 3.", "point", derives_from=["p1"])
    b.add_prediction("h2", "C lies in [2, 4].", "interval", derives_from=["p1"])
    assert _item(b, "risk_severity") == ("pass", 0.8)
    # A declared value is used where one is given, the rubric elsewhere.
    t = _bare(predictions=[
        {"id": "h1", "statement": "C equals 3.", "type": "point", "severity": 0.3},
        {"id": "h2", "statement": "C lies in [2, 4].", "type": "interval"},
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
        {"id": "h3", "statement": "X is 3.", "type": "point"},
    ])
    assert _item(t, "risk_severity") == ("pass", 0.783)
    d = t.dossier()
    assert ("- h1: severity 0.1, risk 0.1, declared 0.95 "
            "(declared exceeds the rubric by more than 0.2)\n") in d
    # 0.5 exceeds the directional rubric value, 0.3, by exactly 0.2: no note.
    assert "- h2: severity 0.3, risk 0.4, declared 0.5\n" in d
    assert "- h3: severity 0.9, risk 0.9\n" in d
    # The preregistration appended to the dossier keeps its own lines.
    assert "\n## Severity (pre-data rubric of claim form)\n- h1: severity 0.1, risk 0.1\n" in d


def test_add_prediction_stores_a_severity_only_when_given():
    t = (tf.new_theory("b", "B")
         .add_prediction("h1", "C equals 3.", "point", severity=0.95)
         .add_prediction("h2", "C equals 4.", "point"))
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
    # assumptions, which every derivation uses (Meehl, 1990).
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
                     "flag": "review"}]
    assert list(rows[0]) == ["a", "b", "similarity", "overlap", "flag"]
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
    assert _pair("", "Bodily arousal response.") == ((0.0, 0.0, "ok"), ("pass", 1.0))


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
    assert ("- Aggregate rigour score: 2.2/100\n- Checklist coverage: 0.92\n- Gate: blocked\n"
            "- Blockers failed: 2 (falsifiability, derivation_chain)\n") in d
    assert "| parsimony | n/a | n/a | 0.08 |\n" in d
    assert "| non_redundancy | warn | 0.0 | 0.1 |\n" in d


def test_the_views_and_the_html_report_show_not_applicable_items(weak_path):
    t = tf.read(weak_path)
    roadmap = t.diagram("development_roadmap")
    assert "score 2.2, gate blocked" in roadmap
    assert '"parsimony"' not in roadmap
    svg = t.diagram("rigour")
    # parsimony is the fourth row, at y = 60 + 24 * 3.
    assert '<rect x="20" y="132" width="16" height="16" rx="3" fill="#9e9e9e"/>' in svg
    assert '<text x="320" y="144">n/a</text>' in svg
    assert "<tr><td>parsimony</td><td>n/a</td><td>n/a</td>" in t.report(format="html")
