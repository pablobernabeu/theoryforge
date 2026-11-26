"""The causal reading of API_SPEC.md Part J: entailments, equivalent models and rivals."""
from __future__ import annotations

import copy
import itertools
import math
import random

import pytest

import theoryforge as tf
from theoryforge._causal import causal_graph
from theoryforge._graph import MixedGraph, m_separated
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


def test_under_refuse_only_a_claim_behind_a_feedback_loop_is_left_unread():
    # c0 -> c1 -> c2 -> c3 <-> c4 -> c5: the loop of c3 and c4 reaches c3, c4
    # and c5. A claim naming one of them, as x, y or in given, is left unread
    # under "refuse", and any other claim is read, with the record "sigma"
    # gives it. The R suite asserts the same records.
    props = [("c0", "c1", "causes"), ("c1", "c2", "increases"), ("c2", "c3", "increases"),
             ("c3", "c4", "increases"), ("c4", "c3", "increases"), ("c4", "c5", "increases")]
    claims = [_claim("effect", "c1", "c2", "positive"),
              _claim("association", "c1", "c2", "positive"),
              _claim("association", "c0", "c1", "nonzero", given=["c2"]),
              _claim("effect", "c2", "c3", "positive"),
              _claim("effect", "c4", "c5", "positive"),
              _claim("association", "c0", "c2", "nonzero", given=["c5"]),
              _claim("effect", "c5", "c1", "zero")]
    t = _theory(props, claims=claims, k=6)
    refuse, sigma = t.entailments()["claims"], t.entailments(cycles="sigma")["claims"]
    assert [c["basis"] == "feedback_loop" for c in refuse] == [False] * 3 + [True] * 4
    for r, g in zip(refuse, sigma, strict=True):
        if r["basis"] != "feedback_loop":
            assert r == g
        else:
            assert (r["verdict"], r["derived"], r["via"]) == ("not_evaluated", "", [])
    # The trek of c1 and c2 shares the edge c0 -> c1 with the walks from c0,
    # so the association is positive under both readings, as on a graph
    # without the loop, though c0 causes c1 with no sign.
    assert (refuse[1]["derived"], refuse[1]["verdict"]) == ("positive", "entailed")
    acyclic = _theory(props[:3] + props[5:], claims=claims, k=6).entailments()["claims"]
    assert [(c["derived"], c["verdict"]) for c in acyclic[:3]] == \
        [(c["derived"], c["verdict"]) for c in refuse[:3]]
    # The checklist then reads them alike.
    chain = next(i for i in t.check()["items"] if i["id"] == "derivation_chain")
    assert chain["not_checked"] == ["q3", "q4", "q5", "q6"]


def test_a_claim_behind_a_loop_reads_in_words_why_it_is_not_evaluated():
    t = _theory([("c0", "c1", "increases"), ("c1", "c0", "increases"), ("c2", "c3", "increases")],
                claims=[_claim("effect", "c0", "c1", "positive"), _claim("effect", "c2", "c3", "positive")])
    lines = [tf.entailment.claim_line(c) for c in t.entailments()["claims"]]
    assert lines == [
        "the effect of c0 on c1 is positive; not evaluated, since a construct it names is on a "
        "feedback loop or downstream of one",
        "the effect of c2 on c3 is positive; entailed by the causal graph through p2"]


def test_an_empty_claim_is_no_claim():
    t = _theory([("c0", "c1", "increases")], claims=[{}, []])
    assert t.entailments()["claims"] == []
    assert t.validate(full=True)


def test_cycles_is_checked_first():
    for f in (tf.entailments, lambda T, cycles: tf.discriminate(T, "a", cycles=cycles)):
        with pytest.raises(ValueError, match="requires cycles to be 'refuse' or 'sigma'"):
            f({}, cycles="loops")


def _stable(rng, g):
    """The total effects and covariances of a stable linear model with the graph, or None."""
    m = _coefficients(rng, g)
    if m is None:
        return None
    B, Om = m
    T = np.linalg.inv(np.eye(g.k) - B)
    return T, T @ Om @ T.T


def _coefficients(rng, g):
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
    return B, Om


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
        projected = MixedGraph(*_project(g, keep))
        for i, j in itertools.combinations(range(len(keep)), 2):
            rest = [z for z in range(len(keep)) if z not in (i, j)]
            for n in range(len(rest) + 1):
                for z in itertools.combinations(rest, n):
                    full = m_separated(g.sep, g.index[keep[i]], g.index[keep[j]],
                                       [g.index[keep[w]] for w in z])
                    assert full == m_separated(projected, i, j, list(z))


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
    assert ("- Derivation references resolve, the causal graph entails every claim a prediction "
            "states and contradicts no claim a phenomenon states: yes") in doc
    assert ("   - Claim: the effect of c_modality_activation on c_conceptual_access is positive; "
            "entailed by the causal graph through p3") in doc
    assert ("   - Rivals it is declared to discriminate: alt_grounding_by_interaction "
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
    # The preregistration sits under its own level-two heading, its title a
    # level below it.
    assert "\n## Preregistration\n\n### Preregistration: Modality switching" in doc
    assert "\n# Preregistration" not in doc and "\n## Preregistration:" not in doc


def test_the_dossier_lists_the_claims_a_rival_discriminates_when_its_graph_is_not_compared():
    # Under refuse, a loop elsewhere leaves the independencies and the signs of
    # the two graphs uncompared, but the claim that no loop reaches is read
    # under both, and the dossier says that it discriminates, as its
    # preregistration does. The R suite asserts the same lines.
    rival = {"id": "alt1", "label": "x lowers y",
             "propositions": [{"id": "r0", "from": "c0", "to": "c1", "relation": "decreases"},
                              {"id": "r1", "from": "c2", "to": "c3", "relation": "increases"},
                              {"id": "r2", "from": "c3", "to": "c2", "relation": "increases"}]}
    t = _theory([("c0", "c1", "increases"), ("c2", "c3", "increases"), ("c3", "c2", "increases")],
                claims=[_claim("effect", "c0", "c1", "positive")], alternatives=[rival])
    t.data["predictions"][0]["diagnostic_vs"] = ["alt1"]
    d = t.discriminate("alt1")
    assert (d["evaluated"], d["counts"]["discriminating_claims"]) == (False, 1)
    doc = t.dossier()
    assert ("- alt1: claims it discriminates: q0; independencies and signs not compared, since a "
            "causal graph has a feedback loop\n") in doc
    assert "   - Rivals it is declared to discriminate: alt1 (its propositions contradict the claim)" in doc
    assert "alt1: not compared" not in doc
    assert ("- alt1: claims it discriminates: q0; independencies one implies and the other does "
            "not: 0; decisive differences in sign: 1 effects, 1 associations\n") in t.dossier(cycles="sigma")


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


def test_an_effect_that_no_loop_reaches_has_its_adjustment_set():
    # c0 confounds c1 -> c2, and the loop of c3 and c4 lies downstream of c2.
    # The effect of c1 on c2 keeps the adjustment set it has without the loop,
    # under either value of cycles, and the effect of c1 on c3, which the loop
    # reaches, has none. The R suite asserts the same records.
    props = [("c0", "c1", "increases"), ("c0", "c2", "increases"), ("c1", "c2", "increases"),
             ("c2", "c3", "increases"), ("c3", "c4", "increases"), ("c4", "c3", "increases")]
    claims = [_claim("effect", "c1", "c2", "positive"), _claim("effect", "c1", "c3", "positive")]
    t = _theory(props, claims=claims, k=5)
    without = _theory(props[:5], claims=claims, k=5).entailments()["claims"]
    for cycles in ("refuse", "sigma"):
        near, far = t.entailments(cycles=cycles)["claims"]
        assert (near["identified"], near["adjustment"]) == (True, ["c0"])
        assert near == without[0]
        assert (far["identified"], far["adjustment"]) == (None, None)
    assert "   - Adjustment for an observational test: c0\n" in t.preregister()


def test_a_claim_that_no_loop_reaches_gets_the_record_of_the_graph_without_its_loops():
    # On random graphs whose loops lie late in the causal order, every claim
    # whose constructs no loop reaches gets, field for field, the record it
    # gets once the edges inside the loops are removed, under either value of
    # cycles. The R suite asserts the same of its own random graphs.
    rng = random.Random(80)
    relations = ["increases", "decreases", "causes", "associates"]
    checked = identified = 0
    for _ in range(120):
        k = rng.randint(5, 8)
        order = [f"c{i}" for i in rng.sample(range(k), k)]
        props = []
        for i in range(k):
            for j in range(i + 1, k):
                if rng.random() < 0.35:
                    props.append((order[i], order[j], rng.choice(relations)))
        # A loop among the last three constructs, and sometimes a second one.
        a, b = sorted(rng.sample(range(k - 3, k), 2))
        props.append((order[a], order[b], rng.choice(relations[:3])))
        props.append((order[b], order[a], rng.choice(relations[:3])))
        if rng.random() < 0.3:
            c = order[rng.randrange(k - 3, k)]
            props.append((c, c, rng.choice(relations[:3])))
        claims = []
        for _ in range(10):
            x, y = rng.sample(order, 2)
            if rng.random() < 0.5:
                claims.append(_claim("effect", x, y, rng.choice(["positive", "negative", "zero"])))
            else:
                rest = [n for n in order if n not in (x, y)]
                given = rng.sample(rest, rng.randint(0, 2))
                claims.append(_claim("association", x, y, "nonzero" if given else "positive",
                                     given=given or None))
        t = _theory(props, claims=claims, k=k)
        g = _Graph(causal_graph(t.data, "test"), "refuse", t.data["propositions"])
        inside = {(a, b) for a, b, rel in props if rel != "associates"
                  and g.r[g.index[a]][g.index[b]] and g.r[g.index[b]][g.index[a]]}
        data = copy.deepcopy(t.data)
        data["propositions"] = [p for p in data["propositions"] if (p["from"], p["to"]) not in inside]
        plain = tf.Theory(data).entailments()["claims"]
        for cycles in ("refuse", "sigma"):
            for c, d in zip(t.entailments(cycles=cycles)["claims"], plain, strict=True):
                names = [c["x"], c["y"], *c["given"]]
                if c["basis"] == "not_in_graph" or d["basis"] == "not_in_graph":
                    continue
                if any(g.behind[g.index[n]] for n in names):
                    assert (c["identified"], c["adjustment"]) == (None, None)
                    continue
                assert c == d
                checked += 1
                identified += c["identified"] is not None
    assert checked > 400 and identified > 200


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


def test_an_association_of_a_construct_with_itself_adds_nothing_though_no_other_proposition_names_it():
    # c2 is related to no other construct, so it is no vertex. Looking it up
    # anyway raised KeyError before the association was skipped. The R suite
    # asserts the same records.
    rival = {"id": "r", "label": "r", "propositions": [
        {"id": "r1", "from": "c0", "to": "c1", "relation": "increases"},
        {"id": "r2", "from": "c2", "to": "c2", "relation": "associates"}]}
    t = _theory([("c0", "c1", "increases"), ("c2", "c2", "associates")],
                claims=[_claim("effect", "c0", "c1", "negative")], alternatives=[rival], k=3)
    t.data["predictions"][0]["diagnostic_vs"] = ["r"]
    imp = t.implications()
    assert (imp["constructs"], imp["n_bidirected"], imp["n_implications"]) == (["c0", "c1"], 0, 0)
    assert t.entailments()["claims"][0]["verdict"] == "contradicted"
    assert t.equivalent_models()["computed"] is True
    assert t.discriminate("r")["markov_equivalent"] is True

    def status(t, item):
        it = next(i for i in t.check()["items"] if i["id"] == item)
        return it["status"], it["score"]

    assert status(t, "derivation_chain") == ("fail", 0)
    assert status(t, "diagnosticity") == ("warn", 0)
    assert "contradicted by the causal graph" in t.preregister()
    assert "- r: claims it discriminates: none" in t.dossier()
    assert tf.appraise_amendment(t, t.copy())["implications_compared"] is True
    # The same association stated by the rival alone.
    del t.data["propositions"][1]
    assert status(t, "diagnosticity") == ("warn", 0)


def test_a_marginal_association_takes_the_signs_of_the_simple_treks_alone():
    # c0 -> c1 -> c2 is also the trek c1 <- c0 -> c1 -> c2, whose two paths
    # share c0 -> c1. Its term holds that coefficient squared, so it adds no
    # sign, and the association of c1 and c2 is positive whatever c0 does to c1
    # (Wright, 1934). The R suite asserts the same records.
    def read(props, claim):
        rec = _theory(props, claims=[claim]).entailments()["claims"][0]
        return rec["derived"], rec["verdict"], rec["basis"]

    pos = _claim("association", "c1", "c2", "positive")
    fixed = ("positive", "entailed", "paths_agree")
    assert read([("c0", "c1", "causes"), ("c1", "c2", "increases")], pos) == fixed
    assert read([("c0", "c1", "causes"), ("c1", "c2", "increases")],
                _claim("association", "c2", "c1", "positive")) == fixed
    assert read([("c0", "c1", "increases"), ("c0", "c3", "increases"), ("c3", "c1", "decreases"),
                 ("c1", "c2", "increases")], pos) == fixed
    assert read([("c0", "c1", "causes"), ("c1", "c2", "increases"), ("c1", "c3", "associates")],
                pos) == fixed
    # Here c1 <- c0 -> c2 is a simple trek of no fixed sign.
    assert read([("c0", "c1", "causes"), ("c0", "c2", "increases"), ("c1", "c2", "increases")],
                pos) == ("undetermined", "undetermined", "unsigned")
    rival = {"id": "r", "label": "r", "propositions": [
        {"id": "r1", "from": "c1", "to": "c2", "relation": "increases"},
        {"id": "r2", "from": "c0", "to": "c2", "relation": "causes"}]}
    t = _theory([("c0", "c1", "causes"), ("c1", "c2", "increases")], claims=[pos], alternatives=[rival])
    assert next(i for i in t.check()["items"] if i["id"] == "derivation_chain")["status"] == "pass"
    assert not [a for a in t.discriminate("r")["associations"] if (a["a"], a["b"]) == ("c1", "c2")]


def test_a_feedback_loop_that_is_one_simple_cycle_leaves_the_signs_of_the_paths_through_it():
    # The loop of c1 and c2 has a negative gain g, and the effects through it
    # are those of the paths times 1 / (1 - g) > 0. So are those through the
    # negative self loop of c4. When c2 and c3 also raise each other, the walks
    # from c0 to c2 take both signs, and the reading stays conservative. The R
    # suite asserts the same records.
    t = _theory([("c0", "c1", "increases"), ("c1", "c2", "increases"), ("c2", "c1", "decreases"),
                 ("c3", "c4", "increases"), ("c4", "c4", "decreases")],
                claims=[_claim("effect", "c0", "c2", "positive"), _claim("effect", "c0", "c1", "positive"),
                        _claim("association", "c0", "c2", "positive"),
                        _claim("association", "c1", "c2", "positive"),
                        _claim("effect", "c3", "c4", "positive"), _claim("effect", "c2", "c1", "negative")],
                k=5)
    got = [(c["derived"], c["basis"]) for c in t.entailments(cycles="sigma")["claims"]]
    assert got == [("positive", "paths_agree"), ("positive", "paths_agree"), ("positive", "paths_agree"),
                   ("undetermined", "opposite_signs"), ("positive", "paths_agree"),
                   ("negative", "paths_agree")]
    shared = _theory([("c0", "c1", "increases"), ("c1", "c2", "increases"), ("c2", "c1", "decreases"),
                      ("c2", "c3", "increases"), ("c3", "c2", "increases")],
                     claims=[_claim("effect", "c0", "c2", "positive")])
    assert shared.entailments(cycles="sigma")["claims"][0]["basis"] == "opposite_signs"


def test_a_sign_read_through_a_self_loop_or_a_simple_cycle_holds_in_every_stable_linear_model():
    # Graphs with self loops and two-cycles, each effect taken in the graph
    # without the edges into the intervened construct, as an intervention
    # leaves it.
    rng = random.Random(41)
    for _ in range(40):
        k = rng.randint(2, 5)
        props = []
        for i, j in itertools.product(range(k), repeat=2):
            if rng.random() < (0.45 if i < j else 0.12 if i == j else 0.15):
                props.append((f"c{i}", f"c{j}", rng.choice(["increases", "decreases", "causes"])))
        t = _theory(props, k=k)
        g = _Graph(causal_graph(t.data, "t"), "sigma", t.data["propositions"])
        if g.k < 2:
            continue
        for _ in range(25):
            m = _coefficients(rng, g)
            if m is None:
                continue
            B = m[0]
            for x, y in itertools.permutations(range(g.k), 2):
                cut = B.copy()
                cut[x, :] = 0
                if max(abs(np.linalg.eigvals(cut))) >= 0.999:
                    continue
                value = np.linalg.inv(np.eye(g.k) - cut)[y, x]
                derived = g.effect(x, y)[0]
                if derived == "positive":
                    assert value > 0
                elif derived == "negative":
                    assert value < 0
                elif derived == "zero":
                    assert abs(value) < 1e-9


def test_a_construct_marked_latent_is_never_adjusted_for():
    # dagitty finds no adjustment set for the first graph and {w} for the
    # second. The R suite asserts the same records.
    def read(text):
        t = tf.read_dagitty(text)
        t.add_prediction("h1", "x raises y.", "directional",
                         claim={"kind": "effect", "x": "x", "y": "y", "sign": "positive"})
        return t, t.entailments()["claims"][0]

    first, rec = read("dag { u [latent]; u -> x; u -> y; x -> y }")
    assert (rec["identified"], rec["adjustment"]) == (False, None)
    assert "   - Adjustment for an observational test: none suffices\n" in first.preregister()
    assert read("dag { u [latent]; u -> w -> x; u -> y; x -> y }")[1]["adjustment"] == ["w"]


def test_a_canonical_set_of_more_than_12_constructs_is_pruned_to_a_minimal_one():
    # The R suite asserts the same records.
    def many(edges):
        t = tf.new_theory("m", "M")
        for n in [f"a{i}" for i in range(1, 14)] + ["c", "x", "y"]:
            t.add_construct(n, n, "A construct.")
        for i, (a, b) in enumerate(edges, start=1):
            t.add_proposition(f"p{i}", a, b, "increases")
        t.add_prediction("h1", "x raises y.", "directional", derives_from=["p1"],
                         claim={"kind": "effect", "x": "x", "y": "y", "sign": "positive"})
        return t

    direct = many([(f"a{i}", "x") for i in range(1, 14)] + [("x", "y")])
    rec = direct.entailments()["claims"][0]
    assert (rec["identified"], rec["adjustment"]) == (True, [])
    assert "   - Adjustment for an observational test: none needed\n" in direct.preregister()
    confounded = many([(f"a{i}", "c") for i in range(1, 14)] + [("c", "x"), ("c", "y"), ("x", "y")])
    assert confounded.entailments()["claims"][0]["adjustment"] == ["c"]


# -- large theories -------------------------------------------------------------

def _large_theory(k, associate_every=0, effects=0, associations=0):
    """A sparse DAG over the constructs c0001 to c<k>, as the R suite builds it.

    Construct j has the parent j // 2, which increases it when j is even and
    decreases it otherwise, and also j - 2 when j is a multiple of 3 above 3.
    With ``associate_every``, every such multiple j is associated with j - 8.
    Effect claim i is that c<3i> lowers c<6i + 1>, whose one parent it is, and
    association claim i concerns c<5i> and c<5i + 2>.
    """
    ids = [f"c{j:04d}" for j in range(1, k + 1)]
    props = []

    def add(a, b, relation):
        props.append({"id": f"p{len(props) + 1}", "from": ids[a - 1], "to": ids[b - 1],
                      "relation": relation})

    for j in range(2, k + 1):
        relation = "increases" if j % 2 == 0 else "decreases"
        add(j // 2, j, relation)
        if j % 3 == 0 and j > 3:
            add(j - 2, j, relation)
    if associate_every:
        for j in range(associate_every, k + 1, associate_every):
            add(j, j - 8, "associates")
    claims = ([_claim("effect", ids[3 * i - 1], ids[6 * i], "negative") for i in range(1, effects + 1)]
              + [_claim("association", ids[5 * i - 1], ids[5 * i + 1], "positive")
                 for i in range(1, associations + 1)])
    rival = [{**p, "id": "r" + p["id"]} for n, p in enumerate(props, start=1) if n % 10]
    t = _theory([], claims=claims, alternatives=[{"id": "rival", "label": "Rival",
                                                  "key_constructs": ["x"], "propositions": rival}])
    t.data["constructs"] = [{"id": c, "label": c, "definition": "d"} for c in ids]
    t.data["propositions"] = props
    return t


def test_the_causal_reading_finds_the_reachability_of_each_graph_once(monkeypatch):
    # Finding the reachability of the whole graph again for each claim, or
    # searching each pair of a DAG, made the causal reading of a large theory
    # take minutes. The calls are counted, so the test does not depend on the
    # speed of the machine. The R suite counts the same calls.
    import importlib

    import theoryforge.entailment as entailment
    implications = importlib.import_module("theoryforge.implications")

    k = 120
    t = _large_theory(k, effects=15, associations=10)
    sizes = []
    searches = []

    def reach(directed, n):
        sizes.append(n)
        return real_reach(directed, n)

    def m_separated(*args):
        searches.append(args[1:3])
        return real_m_separated(*args)

    real_reach, real_m_separated = entailment.reach, implications.m_separated
    monkeypatch.setattr(entailment, "reach", reach)
    monkeypatch.setattr(implications, "m_separated", m_separated)

    e = t.entailments()
    assert e["counts"]["not_evaluated"] == 0
    assert sizes.count(k) == 1
    sizes.clear()
    # R reads the ancestors of the two views compared from their reachability
    # too, so the twins share a bound of four closures of a large graph here.
    d = t.discriminate("rival")
    assert d["evaluated"] and d["effects"]
    assert len([n for n in sizes if n > 100]) <= 4
    res = t.implications()
    assert searches == []
    m = len(t.data["propositions"])
    assert res["n_implications"] == k * (k - 1) // 2 - m


def test_a_theory_of_several_hundred_constructs_is_read_in_full():
    # Before the search kept to the ancestors and the claims to the reachability
    # found once, each of these calls took minutes. The R suite asserts the
    # same records.
    t = _large_theory(300, associate_every=9)
    res = t.implications()
    joined = {frozenset((p["from"], p["to"])) for p in t.data["propositions"]}
    assert res["n_bidirected"] == 33
    assert res["n_implications"] + len(res["inseparable"]) == 300 * 299 // 2 - len(joined)
    big = _large_theory(1000, effects=30, associations=20)
    claims = big.entailments()["claims"]
    effects = [c for c in claims if c["kind"] == "effect"]
    assert len(effects) == 30
    for c in effects:
        edge = next(p["id"] for p in big.data["propositions"] if p["to"] == c["y"])
        assert (c["derived"], c["verdict"], c["via"]) == ("negative", "entailed", [edge])
        assert (c["identified"], c["adjustment"]) == (True, [])
    assert all(c["verdict"] != "not_evaluated" for c in claims)
    eq = big.equivalent_models()
    # Every multiple j of 3 from 6 on is the collider of c<j // 2> and c<j - 2>.
    assert len(eq["v_structures"]) == 1000 // 3 - 1
    assert eq["n_compelled"] + eq["n_reversible"] == len(big.data["propositions"])
    compelled = {(e["from"], e["to"]) for e in eq["edges"] if e["status"] == "compelled"}
    for v in eq["v_structures"]:
        assert {(v["a"], v["collider"]), (v["b"], v["collider"])} <= compelled
