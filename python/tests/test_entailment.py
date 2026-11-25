"""The causal reading of API_SPEC.md Part J: entailments, equivalent models and rivals."""
from __future__ import annotations

import copy
import itertools
import math
import random

import pytest

import theoryforge as tf
from theoryforge._causal import causal_graph
from theoryforge._graph import m_separated, reach
from theoryforge.entailment import _Graph, _project

np = pytest.importorskip("numpy")


@pytest.fixture
def modality():
    return tf.read(tf.example_path("modality-switching.theory.yaml"))


def _theory(props, claims=(), phenomena=(), alternatives=(), k=4):
    return tf.Theory({
        "schema_version": "1.1", "id": "t", "title": "t", "maturity": "developing",
        "constructs": [{"id": f"c{i}", "label": f"c{i}", "definition": "d"} for i in range(k)],
        "propositions": [{"id": f"p{i}", "from": a, "to": b, "relation": r}
                         for i, (a, b, r) in enumerate(props)],
        "predictions": [{"id": f"q{i}", "statement": "s", "type": "directional",
                         "derives_from": ["p0"], "claim": c} for i, c in enumerate(claims)],
        "phenomena": [{"id": f"h{i}", "statement": "s", "claim": c} for i, c in enumerate(phenomena)],
        "alternatives": list(alternatives),
    })


def _claim(kind, x, y, sign, given=None):
    c = {"kind": kind, "x": x, "y": y, "sign": sign}
    if given is not None:
        c["given"] = given
    return c


def _read(t, **kw):
    return {(c["source"], c["id"]): c for c in t.entailments(**kw)["claims"]}


# -- the shipped example ------------------------------------------------------

def test_the_example_entails_its_four_claims(modality):
    e = modality.entailments()
    assert e["counts"] == {"entailed": 4, "contradicted": 0, "undetermined": 0, "not_evaluated": 0}
    got = {c["id"]: (c["derived"], c["basis"], c["via"]) for c in e["claims"]}
    assert got == {
        "pred1": ("positive", "paths_agree", ["p2"]),
        "pred3": ("positive", "paths_agree", ["p3"]),
        "pred4": ("zero", "no_path", []),
        "ph1": ("positive", "paths_agree", ["p1", "p3"]),
    }
    assert [c["source"] for c in e["claims"]] == ["prediction"] * 3 + ["phenomenon"]


def test_the_example_has_two_directions_no_observational_study_can_test(modality):
    eq = modality.equivalent_models()
    assert eq["computed"] and eq["reason"] is None
    assert [(e["propositions"], e["status"]) for e in eq["edges"]] == [
        (["p1"], "reversible"), (["p2"], "reversible"), (["p3"], "compelled"), (["p4"], "compelled")]
    assert eq["v_structures"] == [{"a": "c_modality_activation", "collider": "c_conceptual_access",
                                   "b": "c_lexical_familiarity"}]
    assert (eq["n_compelled"], eq["n_reversible"]) == (2, 2)


def test_each_rival_is_told_apart_by_the_claims_that_name_it(modality):
    gbi = modality.discriminate("alt_grounding_by_interaction")
    assert [c["id"] for c in gbi["claims"] if c["discriminates"]] == ["pred3", "ph1"]
    assert gbi["markov_equivalent"] is False
    assert gbi["counts"] == {"discriminating_claims": 2, "independencies": 4,
                             "decisive_effects": 6, "decisive_associations": 3}
    si = modality.discriminate("alt_symbol_interdependency")
    assert [c["id"] for c in si["claims"] if c["discriminates"]] == ["pred4"]
    # The association it states makes Markov equivalence undefined.
    assert si["markov_equivalent"] is None
    assert [i["statement"] for i in si["independencies"]] == [
        "c_sensorimotor_experience _||_ c_lexical_familiarity"]


def test_a_cyclic_example_is_read_only_under_sigma():
    t = tf.read(tf.example_path("panic-network.theory.yaml"))
    assert t.equivalent_models()["reason"] == "feedback_loop"
    e = t.entailments()
    assert e["acyclic"] is False and e["feedback"] == [["c_arousal", "c_perceived_threat"]]


# -- the sign rules ------------------------------------------------------------

def test_signs_multiply_along_a_path_and_unsigned_relations_leave_it_open():
    t = _theory([("c0", "c1", "increases"), ("c1", "c2", "decreases"), ("c2", "c3", "causes")],
                claims=[_claim("effect", "c0", "c2", "negative"), _claim("effect", "c0", "c3", "positive"),
                        _claim("effect", "c3", "c0", "zero"), _claim("effect", "c0", "c3", "nonzero")])
    got = [(c["derived"], c["verdict"], c["basis"], c["faithfulness"]) for c in t.entailments()["claims"]]
    assert got == [("negative", "entailed", "paths_agree", False),
                   ("undetermined", "undetermined", "unsigned", False),
                   ("zero", "entailed", "no_path", False),
                   ("undetermined", "entailed", "unsigned", True)]


def test_paths_of_opposite_signs_leave_an_effect_open():
    t = _theory([("c0", "c1", "increases"), ("c1", "c3", "increases"),
                 ("c0", "c2", "increases"), ("c2", "c3", "decreases")],
                claims=[_claim("effect", "c0", "c3", "positive"), _claim("effect", "c0", "c3", "zero")])
    a, b = t.entailments()["claims"]
    assert (a["derived"], a["verdict"], a["basis"]) == ("undetermined", "undetermined", "opposite_signs")
    # A zero claim is contradicted only if the two paths do not cancel exactly.
    assert (b["verdict"], b["faithfulness"]) == ("contradicted", True)
    assert a["via"] == ["p0", "p1", "p2", "p3"]


def test_a_common_cause_signs_an_association_and_a_collider_leaves_none():
    t = _theory([("c0", "c1", "increases"), ("c0", "c2", "decreases"), ("c1", "c3", "increases"),
                 ("c2", "c3", "increases")],
                claims=[_claim("association", "c1", "c2", "negative"),
                        _claim("association", "c1", "c2", "zero", given=["c0"]),
                        _claim("association", "c1", "c2", "zero", given=["c0", "c3"])])
    a, b, c = t.entailments()["claims"]
    assert (a["derived"], a["verdict"], a["via"]) == ("negative", "entailed", ["p0", "p1"])
    assert (b["derived"], b["verdict"], b["basis"]) == ("zero", "entailed", "separated")
    assert (c["derived"], c["verdict"], c["faithfulness"]) == ("nonzero", "contradicted", True)


def test_an_association_carries_no_sign():
    t = _theory([("c0", "c1", "increases"), ("c2", "c3", "increases"), ("c0", "c2", "associates")],
                claims=[_claim("association", "c1", "c3", "positive"),
                        _claim("association", "c1", "c3", "nonzero")])
    a, b = t.entailments()["claims"]
    assert (a["derived"], a["basis"], a["verdict"]) == ("undetermined", "unsigned", "undetermined")
    assert a["via"] == ["p0", "p1", "p2"]
    assert (b["verdict"], b["faithfulness"]) == ("entailed", True)


def test_a_claim_that_cannot_be_read_is_not_evaluated():
    t = _theory([("c0", "c1", "increases"), ("c1", "c0", "increases")],
                claims=[_claim("effect", "c0", "c1", "positive"),
                        _claim("effect", "c0", "c2", "positive"),
                        _claim("effect", "c0", "c0", "positive"),
                        _claim("effect", "c0", "c1", "positive", given=["c2"])])
    bases = [c["basis"] for c in t.entailments()["claims"]]
    assert bases == ["feedback_loop", "not_in_graph", "malformed_claim", "malformed_claim"]
    sigma = t.entailments(cycles="sigma")["claims"][0]
    assert (sigma["derived"], sigma["verdict"]) == ("positive", "entailed")


def test_an_empty_claim_is_no_claim():
    t = _theory([("c0", "c1", "increases")], claims=[{}, []])
    assert t.entailments()["claims"] == []
    assert t.validate(full=True)


def test_cycles_is_checked_first():
    for f in (tf.entailments, lambda T, cycles: tf.discriminate(T, "a", cycles=cycles)):
        with pytest.raises(ValueError, match="requires cycles to be 'refuse' or 'sigma'"):
            f({}, cycles="loops")


def _stable(rng, g):
    """Coefficients with the graph's signs, error covariances for its associations, or None."""
    k = g.k
    B, Om = np.zeros((k, k)), np.diag([rng.uniform(0.2, 2.0) for _ in range(k)])
    for i in range(k):
        for j in range(k):
            if g.directed[i][j]:
                s = g.sign[i][j] if g.sign[i][j] is not None else rng.choice([1, -1])
                B[j, i] = s * rng.uniform(0.05, 1.2)
    for a, b in g.assoc_props:
        Om[a, b] = Om[b, a] = rng.choice([1, -1]) * rng.uniform(0.01, 0.3) * (Om[a, a] * Om[b, b]) ** 0.5
    if max(abs(np.linalg.eigvals(B))) >= 0.95 or min(np.linalg.eigvalsh(Om)) <= 0:
        return None
    T = np.linalg.inv(np.eye(k) - B)
    return T, T @ Om @ T.T


def _random_theory(rng, k):
    props = []
    for i, j in itertools.permutations(range(k), 2):
        if rng.random() < (0.45 if i < j else 0.12):
            props.append((f"c{i}", f"c{j}", rng.choice(["increases", "decreases", "increases", "causes"])))
    for i, j in itertools.combinations(range(k), 2):
        if rng.random() < 0.12:
            props.append((f"c{i}", f"c{j}", "associates"))
    return _theory(props, k=k)


def test_a_fixed_sign_holds_in_every_stable_linear_model_with_the_graph():
    # Every effect and covariance the rules sign takes that sign whatever the
    # sizes of the coefficients, feedback loops and associations included.
    rng = random.Random(2026)
    for _ in range(60):
        t = _random_theory(rng, rng.randint(2, 5))
        g = _Graph(causal_graph(t.data, "t"), "sigma", t.data["propositions"])
        if g.k < 2:
            continue
        for _ in range(8):
            m = _stable(rng, g)
            if m is None:
                continue
            T, S = m
            for x, y in itertools.permutations(range(g.k), 2):
                for derived, value in ((g.effect(x, y)[0], T[y, x]), (g.association(x, y)[0], S[x, y])):
                    if derived == "positive":
                        assert value > 0
                    elif derived == "negative":
                        assert value < 0
                    elif derived == "zero":
                        assert abs(value) < 1e-9


def test_a_zero_association_is_separation_given_nothing():
    rng = random.Random(7)
    for _ in range(80):
        t = _random_theory(rng, rng.randint(2, 6))
        g = _Graph(causal_graph(t.data, "t"), "sigma", t.data["propositions"])
        for x, y in itertools.combinations(range(g.k), 2):
            assert (g.association(x, y)[0] == "zero") == g.separated(x, y, [])


def test_the_latent_projection_keeps_every_separation_among_the_kept_constructs():
    rng = random.Random(11)
    for _ in range(60):
        t = _random_theory(rng, rng.randint(3, 6))
        g = _Graph(causal_graph(t.data, "t"), "refuse", t.data["propositions"])
        if g.feedback or g.k < 3:
            continue
        keep = [c for c in g.nodes if rng.random() < 0.7]
        d, b = _project(g, keep)
        r = reach(d, len(keep))
        for i, j in itertools.combinations(range(len(keep)), 2):
            rest = [z for z in range(len(keep)) if z not in (i, j)]
            for n in range(len(rest) + 1):
                for z in itertools.combinations(rest, n):
                    full = m_separated(g.directed, g.bidirected, g.r, g.index[keep[i]],
                                       g.index[keep[j]], [g.index[keep[w]] for w in z])
                    assert full == m_separated(d, b, r, i, j, list(z))


# -- equivalent models and rivals --------------------------------------------

def test_a_chain_is_reversible_and_a_collider_is_compelled():
    chain = _theory([("c0", "c1", "increases"), ("c1", "c2", "increases")])
    assert [e["status"] for e in chain.equivalent_models()["edges"]] == ["reversible"] * 2
    collider = _theory([("c0", "c2", "increases"), ("c1", "c2", "increases"), ("c2", "c3", "increases")])
    # Meek's first rule compels the edge out of the collider.
    assert [e["status"] for e in collider.equivalent_models()["edges"]] == ["compelled"] * 3
    assoc = _theory([("c0", "c1", "increases"), ("c0", "c1", "associates")])
    assert assoc.equivalent_models()["reason"] == "associations"


def test_a_reversed_chain_is_markov_equivalent_but_differs_in_its_effects():
    t = _theory([("c0", "c1", "increases"), ("c1", "c2", "increases")],
                alternatives=[{"id": "a", "label": "r", "propositions": [
                    {"id": "r1", "from": "c1", "to": "c0", "relation": "increases"},
                    {"id": "r2", "from": "c2", "to": "c1", "relation": "increases"}]}])
    d = t.discriminate("a")
    assert d["markov_equivalent"] is True and d["independencies"] == []
    assert {(e["x"], e["y"], e["theory"], e["rival"]) for e in d["effects"]} >= {
        ("c0", "c2", "positive", "zero"), ("c2", "c0", "zero", "positive")}
    assert d["associations"] == []


def test_a_rival_over_other_constructs_is_projected():
    t = _theory([("c0", "c1", "increases"), ("c1", "c2", "increases")], k=4)
    rival = _theory([("c0", "c3", "increases"), ("c3", "c2", "increases"), ("c1", "c2", "increases")], k=4)
    d = t.discriminate(rival)
    assert d["independence_basis"] == "projected"
    assert (d["shared"], d["only_theory"], d["only_rival"]) == (["c0", "c1", "c2"], [], ["c3"])
    assert [(i["statement"], i["implied_by"]) for i in d["independencies"]] == [
        ("c0 _||_ c1", "rival"), ("c0 _||_ c2 | c1", "theory")]


def test_a_rival_must_state_propositions():
    t = _theory([("c0", "c1", "increases")], alternatives=[{"id": "a", "label": "r"}])
    with pytest.raises(ValueError, match="no alternative 'b'"):
        t.discriminate("b")
    with pytest.raises(ValueError, match="requires alternative 'a' to state propositions"):
        t.discriminate("a")


# -- the checklist, the preregistration and the dossier ---------------------

def _item(t, iid):
    return next((i["status"], i["score"]) for i in t.check()["items"] if i["id"] == iid)


def test_a_contradicted_or_open_claim_breaks_the_derivation_chain():
    props = [("c0", "c1", "increases"), ("c1", "c2", "causes")]
    assert _item(_theory(props, claims=[_claim("effect", "c0", "c1", "positive")]),
                 "derivation_chain") == ("pass", 1.0)
    for claim in (_claim("effect", "c0", "c1", "negative"), _claim("effect", "c0", "c2", "positive")):
        assert _item(_theory(props, claims=[claim]), "derivation_chain") == ("fail", 0.0)


def test_a_rival_that_agrees_on_the_claim_does_not_count_as_discriminated():
    props = [("c0", "c1", "increases")]
    agree = {"id": "a", "label": "r", "propositions": [
        {"id": "r1", "from": "c0", "to": "c1", "relation": "increases"}]}
    t = _theory(props, claims=[_claim("effect", "c0", "c1", "positive")], alternatives=[agree])
    t.data["predictions"][0]["diagnostic_vs"] = ["a"]
    assert _item(t, "diagnosticity") == ("warn", 0.0)
    agree["propositions"][0]["relation"] = "decreases"
    assert _item(t, "diagnosticity") == ("pass", 1.0)
    # Without the rival's propositions, the declaration counts as before.
    del agree["propositions"]
    assert _item(t, "diagnosticity") == ("pass", 1.0)


def test_the_preregistration_states_each_claim_and_how_each_rival_reads_it(modality):
    doc = modality.preregister()
    assert "- Derivations check: yes" in doc
    assert ("   - Claim: the effect of c_modality_activation on c_conceptual_access is positive; "
            "entailed by the causal graph through p3") in doc
    assert ("   - Rivals it discriminates: alt_grounding_by_interaction "
            "(its propositions contradict the claim)") in doc
    assert "   - Claim: c_sensorimotor_experience and c_lexical_familiarity are independent; " \
           "entailed by the causal graph\n" in doc


def test_the_dossier_reports_claims_equivalent_models_and_rivals(modality):
    doc = modality.dossier()
    assert ("- ph1 (phenomenon): c_sensorimotor_experience and c_conceptual_access are positively "
            "associated; entailed by the causal graph through p1, p3") in doc
    assert ("- p1: c_sensorimotor_experience -> c_modality_activation "
            "(reversed in some equivalent model)") in doc
    assert ("- alt_symbol_interdependency: claims it discriminates: pred4; independencies one implies "
            "and the other does not: 1; decisive differences in sign: 0 effects, 0 associations") in doc
    # The preregistration sits under its own level-two heading.
    assert "\n## Preregistration\n\n## Preregistration: Modality switching" in doc
    assert "\n# Preregistration" not in doc


def test_a_refused_graph_leaves_the_claims_unread():
    t = _theory([("c0", "c9", "increases")], claims=[_claim("effect", "c0", "c1", "positive")])
    doc = t.preregister()
    assert "   - Claim: the effect of c0 on c1 is positive; not evaluated, since the causal graph " \
           "cannot be built\n" in doc
    assert "_Not read: entailments requires causal propositions between declared constructs; " \
           "proposition 'p0' refers to unknown construct 'c9'._" in t.dossier()


# -- validation and builders --------------------------------------------------

def test_full_validation_reports_each_fault_of_a_claim():
    t = _theory([("c0", "c1", "increases")],
                claims=[{"kind": "effect", "x": "c0", "y": "c0", "sign": "up", "given": ["c1"], "note": 1},
                        "c0 raises c1"],
                phenomena=[{"kind": "association", "x": "c9", "y": "c1", "sign": "positive",
                            "given": ["c0"]}])
    t.data["phenomena"].append({"id": "h0"})
    with pytest.raises(ValueError) as err:
        t.validate(full=True)
    assert str(err.value).split(": ", 1)[1].split("; ") == [
        "duplicate phenomenon id: h0",
        "phenomenon[1] missing/empty statement",
        "prediction[0] claim has unknown field: note",
        "prediction[0] claim sign 'up' not allowed",
        "prediction[0] claim x and y must differ",
        "prediction[0] claim given applies only to an association",
        "prediction[1] claim must be a mapping",
        "phenomenon[0] claim x 'c9' is not a known construct",
        "phenomenon[0] claim sign must be zero or nonzero when given is not empty",
    ]


def test_full_validation_checks_a_rivals_propositions():
    t = _theory([("c0", "c1", "increases")], alternatives=[{"id": "a", "label": "r", "propositions": [
        {"id": "r1", "from": "c0", "to": "c9", "relation": "boosts"}, {"id": "r1"}]}])
    with pytest.raises(ValueError) as err:
        t.validate(full=True)
    assert str(err.value).split(": ", 1)[1].split("; ") == [
        "alternative[0] proposition[0] relation 'boosts' not allowed",
        "alternative[0] proposition[0] to 'c9' is not a known construct",
        "alternative[0] proposition[1] missing/empty from",
        "alternative[0] proposition[1] missing/empty to",
        "alternative[0] proposition[1] missing/empty relation",
        "alternative[0] duplicate proposition id: r1",
    ]


def test_the_builders_record_claims_phenomena_rivals_evidence_and_outcomes():
    t = (tf.new_theory("b", "Built")
         .add_construct("c0", "A", "a.").add_construct("c1", "B", "b.")
         .add_proposition("p1", "c0", "c1", "increases", functional_form="monotonic")
         .add_prediction("h1", "A raises B.", "directional", derives_from="p1", diagnostic_vs="r",
                         bounds={"lower": 0, "upper": None},
                         claim={"kind": "effect", "x": "c0", "y": "c1", "sign": "positive"})
         .add_alternative("r", "Reverse", source_doi="10.1/x", propositions=[
             {"id": "r1", "from": "c1", "to": "c0", "relation": "increases"}])
         .add_phenomenon("ph", "A and B covary.",
                         claim={"kind": "association", "x": "c0", "y": "c1", "sign": "positive"})
         .add_evidence("h1", "corroborates", source_doi="10.1/y")
         .add_test_outcome("h1", True, estimate=0.3, se=0.1, registered="osf.io/x"))
    assert t.validate(full=True)
    assert t.data["schema_version"] == "1.1"
    assert [p["action"] for p in t.data["provenance"]][-5:] == [
        "tf_add_prediction", "tf_add_alternative", "tf_add_phenomenon", "tf_add_evidence",
        "tf_add_test_outcome"]
    assert t.data["test_outcomes"] == [{"prediction_id": "h1", "passed": True, "estimate": 0.3,
                                        "se": 0.1, "registered": "osf.io/x"}]
    assert [c["verdict"] for c in t.entailments()["claims"]] == ["entailed", "entailed"]
    assert t.discriminate("r")["counts"]["discriminating_claims"] == 1
    assert t.post_data_severity()[0]["severity"] == pytest.approx(0.999, abs=1e-3)


# -- adjustment sets -------------------------------------------------------------

def test_an_effect_claim_names_a_smallest_adjustment_set():
    confounded = _theory([("c0", "c1", "increases"), ("c0", "c2", "increases"),
                          ("c1", "c2", "increases"), ("c3", "c1", "increases")],
                         claims=[_claim("effect", "c1", "c2", "positive"),
                                 _claim("association", "c1", "c2", "positive")])
    effect, assoc = confounded.entailments()["claims"]
    # c0 opens a back-door path, and c3, a cause of c1 alone, need not be held fixed.
    assert (effect["identified"], effect["adjustment"]) == (True, ["c0"])
    assert (assoc["identified"], assoc["adjustment"]) == (None, None)
    bow = _theory([("c0", "c1", "increases"), ("c0", "c1", "associates")],
                  claims=[_claim("effect", "c0", "c1", "positive")])
    assert [(c["identified"], c["adjustment"]) for c in bow.entailments()["claims"]] == [(False, None)]
    loop = _theory([("c0", "c1", "increases"), ("c1", "c0", "increases")],
                   claims=[_claim("effect", "c0", "c1", "positive")])
    assert loop.entailments(cycles="sigma")["claims"][0]["identified"] is None


def test_the_preregistration_says_what_an_observational_test_adjusts_for():
    t = _theory([("c0", "c1", "increases"), ("c0", "c2", "increases"), ("c1", "c2", "increases")],
                claims=[_claim("effect", "c1", "c2", "positive"), _claim("effect", "c0", "c2", "positive")])
    doc = t.preregister()
    assert "   - Adjustment for an observational test: c0\n" in doc
    assert "   - Adjustment for an observational test: none needed\n" in doc


# -- the content hash ---------------------------------------------------------------

def test_the_content_hash_is_sha256_of_the_canonical_form(modality, tmp_path):
    from theoryforge.hashing import canonical
    assert canonical({"b": 1, "a": [1e21, 1e-7, 0.1, -0.0, 100, True, None]}) == \
        '{"a":[1e+21,1e-7,0.1,0,100,true,null],"b":1}'
    assert canonical({"x": 'q"\\\né', "y": [], "z": {}}) == '{"x":"q\\"\\\\\\né","y":[],"z":[]}'
    h = modality.content_hash()
    assert h.startswith("sha256:") and len(h) == 71
    # The layout of the file does not count, and a recorded hash leaves it unchanged.
    modality.write(tmp_path / "m.json")
    assert tf.read(tmp_path / "m.json").content_hash() == h
    modality.data["version"]["content_hash"] = h
    assert modality.content_hash() == h and modality.validate(full=True)
    modality.data["constructs"].reverse()
    assert modality.content_hash() != h


SINGLETONS = """\
schema_version: "1.1"
id: singletons
title: A theory with single values in string arrays
maturity: building
boundary_conditions: adults
constructs:
  - id: c1
    label: Arousal
    definition: Bodily activation.
    measurement: self-report scale
  - id: c2
    label: Threat
    definition: Appraised danger.
propositions:
  - {id: p1, from: c1, to: c2, relation: increases}
predictions:
  - id: h1
    statement: Threat rises with arousal.
    type: directional
    derives_from: p1
"""


def test_the_content_hash_reads_a_single_string_as_a_one_element_array(tmp_path):
    # API_SPEC section 34: a single value in a field the schema types as an array
    # of strings is written as a one-element array, as the singleton rule reads
    # it, so the theory keeps its hash when R's tf_write() writes the field as an
    # array. The R suite asserts the same digest.
    scalar = tmp_path / "scalar.theory.yaml"
    scalar.write_text(SINGLETONS, encoding="utf-8")
    boxed = tmp_path / "boxed.theory.yaml"
    boxed.write_text(SINGLETONS.replace("adults", "[adults]").replace(
        "self-report scale", "[self-report scale]").replace("derives_from: p1", "derives_from: [p1]"),
        encoding="utf-8")
    h = "sha256:5974774a777a33875a5d94eeebaf466fcd7c41071991d65591d44116699ea71d"
    assert tf.read(scalar).content_hash() == tf.read(boxed).content_hash() == h
    # A null is not boxed, nor is a list or a mapping, and "[]" visits the
    # values of a collection held as a mapping, as R's .tf_box_path() does.
    from theoryforge.hashing import box_string_arrays
    data = {"constructs": {"a": {"measurement": "m"}, "b": None, "c": {"measurement": None}},
            "predictions": [{"derives_from": 1, "claim": {"given": "c1"}}, {"derives_from": {"p": 1}}],
            "boundary_conditions": [["x"]]}
    assert box_string_arrays(data) == {
        "constructs": {"a": {"measurement": ["m"]}, "b": None, "c": {"measurement": None}},
        "predictions": [{"derives_from": [1], "claim": {"given": ["c1"]}}, {"derives_from": {"p": 1}}],
        "boundary_conditions": [["x"]]}
    assert data["constructs"]["a"]["measurement"] == "m"  # the theory itself is not changed
    # Only the key version is the version, as R now reads it.
    t = tf.read(scalar)
    t.data["version_note"] = {"content_hash": "x"}
    first = t.content_hash()
    t.data["version_note"]["content_hash"] = "y"
    assert t.content_hash() != first


def test_the_canonical_form_keeps_the_shortest_digits_that_read_back_as_the_number():
    # R's twin tested its digits with a parser that reads -527.867953 one unit
    # in the last place away. The R suite asserts the same text.
    from theoryforge.hashing import canonical
    text = ["-527.867953", "1.7839211372708861e-265", "-3.06405467662112e+212",
            "3.343559332129407e-41"]
    assert canonical([float(s) for s in text]) == "[" + ",".join(text) + "]"
    # Beside a power of two the nearest 16-digit decimal of 2^-24 does not read
    # back, while the one above it does, and ECMAScript takes it.
    assert canonical([2.0 ** -24, 2.0 ** -44, 2.0 ** 89]) == \
        "[5.960464477539063e-8,5.684341886080802e-14,6.189700196426902e+26]"


def test_an_effect_under_sigma_counts_no_walk_back_through_the_intervened_construct():
    # r lowers f and f raises r. Intervening on r replaces r's own equation, so
    # the loop back through r carries nothing, and the effect is the direct,
    # negative one. Counting the walk r -> f -> r -> f gave opposite signs.
    t = tf.new_theory("rf", "RF")
    t.add_construct("r", "R", "a.").add_construct("f", "F", "b.")
    t.add_proposition("p1", "r", "f", "decreases").add_proposition("p2", "f", "r", "increases")
    t.add_prediction("h1", "R lowers F.", "directional", derives_from=["p1"],
                     claim={"kind": "effect", "x": "r", "y": "f", "sign": "negative"})
    rec = tf.entailments(t, cycles="sigma")["claims"][0]
    assert (rec["derived"], rec["verdict"], rec["via"]) == ("negative", "entailed", ["p1"])


def test_the_causal_dag_export_keeps_an_association_between_constructs_no_arrow_names():
    t = tf.new_theory("a", "A")
    for c in ("x", "y", "z", "w"):
        t.add_construct(c, c.upper(), "A construct.")
    t.add_proposition("p1", "x", "y", "causes").add_proposition("p2", "z", "w", "associates")
    assert t.diagram("causal_dag") == "dag {\n  x -> y\n  z <-> w\n}\n"
    assert t.implications()["constructs"] == ["x", "y", "z", "w"]


def test_the_content_hash_reads_an_integer_too_large_for_a_double_as_r_does():
    # R reads a 400-digit integer as Inf and writes Infinity; float() raised
    # OverflowError here, in the hash and so in the preregistration and dossier.
    t = tf.read(tf.example_path("modality-switching.theory.yaml"))
    t.data["predictions"][1]["bounds"] = {"lower": 20, "upper": 10 ** 400}
    inf = copy.deepcopy(t.data)
    inf["predictions"][1]["bounds"]["upper"] = math.inf
    assert tf.content_hash(t) == tf.content_hash(inf)
    assert t.preregister() and t.dossier()
