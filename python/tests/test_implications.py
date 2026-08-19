import math
import random

import pytest

import theoryforge as tf


def chain_theory():
    """A chain, arousal -> threat -> avoidance, whose single implication is the
    textbook mediation claim."""
    t = tf.new_theory("mediation", "A mediated chain")
    t.add_construct("c_arousal", "Arousal", "Bodily activation.")
    t.add_construct("c_threat", "Perceived threat", "Appraised danger.")
    t.add_construct("c_avoidance", "Avoidance", "Withdrawal from the trigger.")
    t.add_proposition("p1", "c_arousal", "c_threat", "increases")
    t.add_proposition("p2", "c_threat", "c_avoidance", "increases")
    return t


def dag_theory(nodes, edges):
    """Build a theory from a node list and an edge list, for the property tests."""
    t = tf.new_theory("generated", "Generated")
    for n in nodes:
        t.add_construct(n, n, n)
    for i, (a, b) in enumerate(edges, start=1):
        t.add_proposition(f"p{i}", a, b, "causes")
    return t


def random_dag(rng, kmin=2, kmax=7, p=0.45):
    k = rng.randint(kmin, kmax)
    nodes = [f"v{i}" for i in range(k)]
    edges = [(nodes[i], nodes[j]) for i in range(k) for j in range(i + 1, k)
             if rng.random() < p]
    order = nodes[:]
    rng.shuffle(order)  # declaration order differs from topological order
    return order, edges


def test_implications_of_a_mediated_chain():
    res = chain_theory().implications()
    assert list(res) == ["theory_id", "acyclic", "constructs", "n_edges",
                         "implications", "n_implications"]
    assert res["theory_id"] == "mediation"
    assert res["acyclic"] is True
    assert res["constructs"] == ["c_arousal", "c_threat", "c_avoidance"]
    assert res["n_edges"] == 2
    assert res["n_implications"] == 1
    assert res["implications"] == [{
        "a": "c_arousal", "b": "c_avoidance", "given": ["c_threat"],
        "statement": "c_arousal _||_ c_avoidance | c_threat",
    }]


def test_collider_pair_is_left_unconditioned():
    # a -> c <- b: the two causes are marginally independent, and conditioning on
    # the collider would create the dependence rather than test it.
    t = tf.new_theory("collider", "A collider")
    t.add_construct("a", "A", "d").add_construct("b", "B", "d").add_construct("c", "C", "d")
    t.add_proposition("p1", "a", "c", "causes").add_proposition("p2", "b", "c", "causes")
    res = t.implications()
    assert res["n_implications"] == 1
    assert res["implications"][0]["given"] == []
    assert res["implications"][0]["statement"] == "a _||_ b"


def test_pairs_and_conditioning_sets_follow_construct_file_order():
    # Declaration order alone decides the order of the records and of each
    # conditioning set, so the twin comparison has something stable to compare.
    t = tf.new_theory("order", "Declaration order")
    for n in ("z", "y", "x", "w"):
        t.add_construct(n, n.upper(), "d")
    t.add_proposition("p1", "z", "x", "causes")
    t.add_proposition("p2", "y", "x", "causes")
    t.add_proposition("p3", "x", "w", "causes")
    res = t.implications()
    assert res["constructs"] == ["z", "y", "x", "w"]
    assert [i["statement"] for i in res["implications"]] == [
        "z _||_ y", "z _||_ w | x", "y _||_ w | x"]


def test_repeated_causal_edge_counts_once():
    t = tf.new_theory("dup-edge", "A repeated edge")
    for n in ("a", "b", "c"):
        t.add_construct(n, n.upper(), "d")
    t.add_proposition("p1", "a", "b", "causes")
    t.add_proposition("p2", "a", "b", "increases")
    t.add_proposition("p3", "b", "c", "causes")
    res = t.implications()
    assert res["n_edges"] == 2
    assert res["n_implications"] == 1


def test_non_causal_relations_are_not_edges():
    # `associates` and `moderates` state no direction, so they are not edges of a
    # causal graph and cannot carry a d-separation claim.
    t = tf.new_theory("assoc", "Associative only")
    t.add_construct("a", "A", "d").add_construct("b", "B", "d")
    t.add_proposition("p1", "a", "b", "associates")
    res = t.implications()
    assert res["n_edges"] == 0
    assert res["constructs"] == []
    assert res["n_implications"] == 0


def test_theory_without_causal_relations_has_an_empty_basis_set(weak_path):
    res = tf.read(weak_path).implications()
    assert res["theory_id"] == "weak-demo"
    assert res["acyclic"] is True
    assert res["constructs"] == []
    assert res["n_edges"] == 0
    assert res["implications"] == []
    assert res["n_implications"] == 0


def test_degenerate_graphs():
    assert tf.new_theory("empty", "No constructs at all").implications()["n_implications"] == 0

    single = tf.new_theory("single", "One construct")
    single.add_construct("a", "A", "d")
    assert single.implications()["n_implications"] == 0

    # Two constructs with the one edge between them: every pair is adjacent,
    # which is the boundary at which the basis set becomes empty.
    single.add_construct("b", "B", "d").add_proposition("p1", "a", "b", "causes")
    res = single.implications()
    assert res["constructs"] == ["a", "b"]
    assert res["n_edges"] == 1
    assert res["n_implications"] == 0


def test_basis_set_of_the_shipped_acyclic_example(modality_path):
    # The worked example for this function: five constructs, four causal
    # propositions, a fork at modality activation and a collider at conceptual
    # access. Asserted literally, so a change to the derivation or to the file
    # is caught rather than absorbed.
    t = tf.read(modality_path)
    assert t.validate(full=True) is True
    res = t.implications()
    assert res["theory_id"] == "modality-switching-2026"
    assert res["acyclic"] is True
    assert res["constructs"] == [
        "c_sensorimotor_experience", "c_modality_activation", "c_switch_cost",
        "c_conceptual_access", "c_lexical_familiarity"]
    assert res["n_edges"] == 4
    # k(k-1)/2 - m with k = 5 and m = 4
    assert res["n_implications"] == 6
    assert res["implications"] == [
        {"a": "c_sensorimotor_experience", "b": "c_switch_cost",
         "given": ["c_modality_activation"],
         "statement": "c_sensorimotor_experience _||_ c_switch_cost | c_modality_activation"},
        {"a": "c_sensorimotor_experience", "b": "c_conceptual_access",
         "given": ["c_modality_activation", "c_lexical_familiarity"],
         "statement": "c_sensorimotor_experience _||_ c_conceptual_access | "
                      "c_modality_activation, c_lexical_familiarity"},
        {"a": "c_sensorimotor_experience", "b": "c_lexical_familiarity",
         "given": [],
         "statement": "c_sensorimotor_experience _||_ c_lexical_familiarity"},
        {"a": "c_modality_activation", "b": "c_lexical_familiarity",
         "given": ["c_sensorimotor_experience"],
         "statement": "c_modality_activation _||_ c_lexical_familiarity | c_sensorimotor_experience"},
        {"a": "c_switch_cost", "b": "c_conceptual_access",
         "given": ["c_modality_activation", "c_lexical_familiarity"],
         "statement": "c_switch_cost _||_ c_conceptual_access | "
                      "c_modality_activation, c_lexical_familiarity"},
        {"a": "c_switch_cost", "b": "c_lexical_familiarity",
         "given": ["c_modality_activation"],
         "statement": "c_switch_cost _||_ c_lexical_familiarity | c_modality_activation"},
    ]


def test_shipped_acyclic_example_carries_a_fork_and_a_collider(modality_path):
    # What makes the example instructive rather than a straight chain. The two
    # children of the fork are independent given their shared parent, and the
    # two parents of the collider are independent with nothing held fixed, which
    # is the pair a study would look at to distinguish this account from one
    # that ties word statistics to perceptual experience.
    res = tf.read(modality_path).implications()
    by_pair = {(i["a"], i["b"]): i["given"] for i in res["implications"]}
    assert by_pair[("c_switch_cost", "c_conceptual_access")] == [
        "c_modality_activation", "c_lexical_familiarity"]
    assert by_pair[("c_sensorimotor_experience", "c_lexical_familiarity")] == []


def test_refuses_a_cyclic_causal_graph_naming_the_cycle(panic_path):
    with pytest.raises(ValueError) as exc:
        tf.read(panic_path).implications()
    assert str(exc.value) == (
        "implications requires an acyclic causal graph; "
        "cycle found: c_arousal -> c_perceived_threat -> c_arousal")


def test_refuses_a_self_loop():
    t = tf.new_theory("loop", "A self loop")
    t.add_construct("a", "A", "d").add_proposition("p1", "a", "a", "causes")
    with pytest.raises(ValueError) as exc:
        t.implications()
    assert str(exc.value) == "implications requires an acyclic causal graph; cycle found: a -> a"


def test_refuses_duplicate_construct_ids():
    t = tf.new_theory("dupe", "Duplicated ids")
    t.add_construct("c1", "One", "d").add_construct("c1", "One again", "d")
    with pytest.raises(ValueError) as exc:
        t.implications()
    assert str(exc.value) == (
        "implications requires unique construct ids; duplicate construct id: c1")


def test_refuses_an_undeclared_endpoint():
    # Dropping the edge would shrink the graph and so claim independencies the
    # theory does not imply.
    t = tf.new_theory("dangling", "A dangling endpoint")
    t.add_construct("a", "A", "d").add_construct("b", "B", "d")
    t.add_proposition("p1", "a", "ghost", "causes")
    with pytest.raises(ValueError) as exc:
        t.implications()
    assert str(exc.value) == (
        "implications requires causal propositions between declared constructs; "
        "proposition 'p1' refers to unknown construct 'ghost'")


def test_basis_set_cardinality_identity():
    # The identity k(k-1)/2 - m is analytic: one statement per non-adjacent pair,
    # and each edge removes exactly one pair from the k(k-1)/2 available.
    rng = random.Random(4242)
    checked = 0
    for _ in range(200):
        order, edges = random_dag(rng)
        if not edges:
            continue
        res = dag_theory(order, edges).implications()
        k, m = len(res["constructs"]), res["n_edges"]
        assert res["n_implications"] == k * (k - 1) // 2 - m
        checked += 1
    assert checked > 150


def _corr(x, y):
    n = len(x)
    mx, my = sum(x) / n, sum(y) / n
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y, strict=True))
    sxx = sum((a - mx) ** 2 for a in x)
    syy = sum((b - my) ** 2 for b in y)
    return sxy / math.sqrt(sxx * syy)


def _pcor(x, y, z):
    """Partial correlation of x and y given one variable z."""
    rxy, rxz, ryz = _corr(x, y), _corr(x, z), _corr(y, z)
    return (rxy - rxz * ryz) / math.sqrt((1 - rxz ** 2) * (1 - ryz ** 2))


def test_derived_independence_holds_in_simulated_data():
    # The semantics rather than the syntax: linear-Gaussian data generated from
    # the DAG must satisfy the implication, and must not satisfy the same claim
    # made about an adjacent pair.
    rng = random.Random(20260818)
    n = 8000
    arousal = [rng.gauss(0, 1) for _ in range(n)]
    threat = [0.8 * a + rng.gauss(0, 1) for a in arousal]
    avoidance = [0.8 * t + rng.gauss(0, 1) for t in threat]
    res = chain_theory().implications()
    assert res["implications"][0]["given"] == ["c_threat"]
    assert abs(_pcor(arousal, avoidance, threat)) < 0.05
    # the same pair without the conditioning set is strongly dependent, so the
    # near-zero value above is the conditioning at work and not a flat dataset
    assert abs(_corr(arousal, avoidance)) > 0.2
    # an adjacent pair is not implied independent, and is not independent here
    assert abs(_pcor(threat, avoidance, arousal)) > 0.2
