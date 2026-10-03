import itertools
import math
import random
from pathlib import Path

import pytest

import theoryforge as tf
from theoryforge._relations import DIRECTED

APP_EXAMPLES = Path(__file__).resolve().parents[2] / "apps" / "examples"


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


def relation_theory(name, nodes, props):
    """A theory over `nodes` with one proposition per (from, relation, to)."""
    t = tf.new_theory(name, name)
    for n in nodes:
        t.add_construct(n, n, f"definition of {n}")
    for i, (a, rel, b) in enumerate(props, start=1):
        t.add_proposition(f"p{i}", a, b, rel)
    return t


def statements(res):
    return [i["statement"] for i in res["implications"]]


def app_example(name):
    path = APP_EXAMPLES / name
    if not path.exists():
        pytest.skip("apps/examples is not reachable from this test run")
    return tf.read(path)


def test_implications_of_a_mediated_chain():
    res = chain_theory().implications()
    assert list(res) == ["theory_id", "criterion", "acyclic", "constructs", "n_edges",
                         "n_bidirected", "feedback", "implications", "n_implications",
                         "inseparable"]
    assert res["theory_id"] == "mediation"
    assert res["criterion"] == "m"
    assert res["acyclic"] is True
    assert res["constructs"] == ["c_arousal", "c_threat", "c_avoidance"]
    assert res["n_edges"] == 2
    assert res["n_bidirected"] == 0
    assert res["feedback"] == []
    assert res["n_implications"] == 1
    assert res["implications"] == [{
        "a": "c_arousal", "b": "c_avoidance", "given": ["c_threat"],
        "statement": "c_arousal _||_ c_avoidance | c_threat",
    }]
    assert res["inseparable"] == []


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


@pytest.mark.parametrize("relation", sorted(DIRECTED))
def test_every_directed_relation_is_an_edge(relation):
    # The relation table (API_SPEC.md section 28) makes mediates and moderates
    # directed edges, as the three causal relations are, so a chain through any
    # of them implies what a chain of causes does.
    res = relation_theory("chain", ["a", "b", "c"],
                          [("a", relation, "b"), ("b", "causes", "c")]).implications()
    assert res["constructs"] == ["a", "b", "c"]
    assert res["n_edges"] == 2
    assert statements(res) == ["a _||_ c | b"]


def test_an_association_between_vertices_is_a_bidirected_edge():
    # z -> x -> y with x associates y. The association is covariance the theory
    # leaves unexplained, as a latent common cause of x and y would produce, so
    # x is a collider on z -> x <-> y and holding it fixed opens that path. No
    # set separates z from y, and the pair is listed as inseparable where 0.6.0
    # declared it independent given x.
    res = relation_theory("iv", ["z", "x", "y"], [
        ("z", "increases", "x"), ("x", "increases", "y"), ("x", "associates", "y"),
    ]).implications()
    assert res["criterion"] == "m"
    assert res["constructs"] == ["z", "x", "y"]
    assert res["n_edges"] == 2
    assert res["n_bidirected"] == 1
    assert res["implications"] == []
    assert res["n_implications"] == 0
    assert res["inseparable"] == [{"a": "z", "b": "y"}]


def test_an_association_makes_its_pair_adjacent():
    # a -> c <- b with a associates b: the association is the theory's own claim
    # that a and b covary, so the two causes are no longer independent.
    res = relation_theory("collider", ["a", "b", "c"], [
        ("a", "increases", "c"), ("b", "increases", "c"), ("a", "associates", "b"),
    ]).implications()
    assert res["implications"] == []
    assert res["inseparable"] == []


def test_a_mediates_edge_makes_its_pair_adjacent():
    # x mediates m, m -> y and x -> y: every pair is joined, so nothing is
    # implied, where 0.6.0 claimed that x and m are independent.
    res = relation_theory("triangle", ["x", "m", "y"], [
        ("x", "mediates", "m"), ("m", "increases", "y"), ("x", "increases", "y"),
    ]).implications()
    assert res["n_edges"] == 3
    assert res["implications"] == []


def test_a_moderator_points_into_the_outcome():
    # z moderates y: the relation table reads a moderator as a direct effect
    # modifier, a direct cause of the outcome (VanderWeele & Robins, 2007), so z
    # and y are adjacent, and 0.6.0's claim that they are independent given x is
    # gone.
    res = relation_theory("moderation", ["z", "w", "x", "y"], [
        ("z", "increases", "w"), ("x", "increases", "y"), ("z", "moderates", "y"),
    ]).implications()
    assert res["n_edges"] == 3
    assert statements(res) == ["z _||_ x", "w _||_ x | z", "w _||_ y | z, x"]


def test_a_moderator_outside_the_causal_relations_is_a_vertex():
    # w moderates both outcomes, so y1 and y2 share a cause and are independent
    # only once w is held fixed as well. Reading only the three causal relations
    # gave 'y1 _||_ y2 | a, b', which is false.
    res = relation_theory("fork", ["a", "y1", "b", "y2", "w"], [
        ("a", "causes", "y1"), ("b", "causes", "y2"),
        ("w", "moderates", "y1"), ("w", "moderates", "y2"),
    ]).implications()
    assert statements(res) == [
        "a _||_ b", "a _||_ y2 | b, w", "a _||_ w", "y1 _||_ b | a, w",
        "y1 _||_ y2 | a, b, w", "b _||_ w"]


def test_a_mediated_chain_through_an_outside_construct_is_read_whole():
    # y1 mediates x and x mediates y2 join a and y1 to y2. Reading only the
    # three causal relations gave 'a _||_ y2 | b' and 'y1 _||_ y2 | a, b', both
    # false.
    res = relation_theory("chain", ["a", "y1", "x", "b", "y2"], [
        ("a", "causes", "y1"), ("y1", "mediates", "x"),
        ("x", "mediates", "y2"), ("b", "causes", "y2"),
    ]).implications()
    assert statements(res) == [
        "a _||_ x | y1", "a _||_ b", "a _||_ y2 | x, b", "y1 _||_ b | a",
        "y1 _||_ y2 | a, x, b", "x _||_ b | y1"]


def test_the_ancestors_separate_a_pair_that_the_parents_do_not():
    # x -> m -> w -> y with w associates y. The parents of x and y, {w}, leave
    # the collider w open on x -> m -> w <-> y, and the ancestors of the pair,
    # {m, w}, close the path at m. Nothing separates m from y, since m -> w <-> y
    # stays open whether or not w is held fixed.
    res = relation_theory("confounded-link", ["x", "m", "w", "y"], [
        ("x", "causes", "m"), ("m", "causes", "w"), ("w", "causes", "y"),
        ("w", "associates", "y"),
    ]).implications()
    assert res["implications"] == [
        {"a": "x", "b": "w", "given": ["m"], "statement": "x _||_ w | m"},
        {"a": "x", "b": "y", "given": ["m", "w"], "statement": "x _||_ y | m, w"},
    ]
    assert res["inseparable"] == [{"a": "m", "b": "y"}]


def test_a_construct_touched_only_by_associations_is_left_out():
    # Every path through k arrives and leaves by an arrowhead, so k is a collider
    # on each and, being no ancestor of anything, closes it. Leaving k out drops
    # no statement about the other constructs, and silence about k is no claim
    # that it is independent of anything (API_SPEC.md section 27).
    res = relation_theory("silence", ["k", "x", "y"], [
        ("x", "causes", "y"), ("k", "associates", "x"), ("k", "associates", "y"),
    ]).implications()
    assert res["constructs"] == ["x", "y"]
    assert res["n_bidirected"] == 0
    assert res["implications"] == []
    assert res["inseparable"] == []


def test_a_repeated_association_counts_once_and_a_self_association_not_at_all():
    res = relation_theory("repeat", ["a", "b", "c"], [
        ("a", "causes", "c"), ("b", "causes", "c"),
        ("a", "associates", "b"), ("b", "associates", "a"), ("c", "associates", "c"),
    ]).implications()
    assert res["n_bidirected"] == 1
    assert res["implications"] == []


def test_an_association_with_an_undeclared_endpoint_adds_nothing():
    # An association names no vertex unless a directed relation names both its
    # constructs, so one with an undeclared endpoint is not an edge, as one with
    # a construct touched only by associations is not. validate() reports the
    # reference.
    res = relation_theory("loose", ["a", "b"], [
        ("a", "causes", "b"), ("a", "associates", "ghost"),
    ]).implications()
    assert res["constructs"] == ["a", "b"]
    assert res["n_bidirected"] == 0


def test_theory_without_causal_relations_has_an_empty_basis_set(weak_path):
    # The weak example's one proposition is an association between two
    # constructs that no directed relation names, so there is no vertex.
    res = tf.read(weak_path).implications()
    assert res["theory_id"] == "weak-demo"
    assert res["acyclic"] is True
    assert res["constructs"] == []
    assert res["n_edges"] == 0
    assert res["n_bidirected"] == 0
    assert res["implications"] == []
    assert res["n_implications"] == 0
    assert res["inseparable"] == []


def test_the_stereotype_threat_moderation_adds_the_statements_it_implies():
    # Domain identification moderates the threat-performance link, so it is a
    # parent of test performance: it joins three statements and the conditioning
    # sets of two others.
    res = app_example("stereotype-threat.theory.yaml").implications()
    assert statements(res) == [
        "c_diagnostic_framing _||_ c_stereotype_threat | c_stereotype_salience",
        "c_diagnostic_framing _||_ c_domain_identification",
        "c_diagnostic_framing _||_ c_test_performance | c_stereotype_threat, "
        "c_domain_identification",
        "c_stereotype_salience _||_ c_domain_identification | c_diagnostic_framing",
        "c_stereotype_salience _||_ c_test_performance | c_diagnostic_framing, "
        "c_stereotype_threat, c_domain_identification",
        "c_stereotype_threat _||_ c_domain_identification | c_stereotype_salience",
    ]


def test_the_planned_behaviour_antecedents_covary():
    # Ajzen (1991) draws attitude, subjective norm and perceived control as
    # intercorrelated, so the example states the three associations, and the
    # three marginal independencies among them are no longer implied.
    res = app_example("planned-behaviour.theory.yaml").implications()
    assert res["n_bidirected"] == 3
    assert statements(res) == [
        "c_attitude _||_ c_behaviour | c_perceived_control, c_intention",
        "c_subjective_norm _||_ c_behaviour | c_perceived_control, c_intention",
    ]


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


@pytest.mark.parametrize("relation", ["mediates", "moderates"])
def test_refuses_an_undeclared_endpoint_of_every_directed_relation(relation):
    t = relation_theory("dangling", ["a", "b"], [("a", "causes", "b"), ("b", relation, "ghost")])
    with pytest.raises(ValueError) as exc:
        t.implications()
    assert str(exc.value) == (
        "implications requires causal propositions between declared constructs; "
        "proposition 'p2' refers to unknown construct 'ghost'")


def test_refuses_a_cycle_closed_by_a_moderation():
    t = relation_theory("loop", ["a", "b"], [("a", "causes", "b"), ("b", "moderates", "a")])
    with pytest.raises(ValueError) as exc:
        t.implications()
    assert str(exc.value) == "implications requires an acyclic causal graph; cycle found: a -> b -> a"


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


def _m_connected(directed, bidirected, a, b, given):
    """Brute force from the definition (Richardson, 2003): a path between a and b
    m-connects them given Z when every collider on it is Z or an ancestor of Z
    and no other vertex on it is in Z. Every simple path is enumerated, so this
    shares no code or idea with the walk the package takes."""
    z = set(given)
    anc = set(z)
    grown = True
    while grown:
        grown = False
        for u, v in directed:
            if v in anc and u not in anc:
                anc.add(u)
                grown = True
    # (from, to, arrowhead at from, arrowhead at to)
    steps = ([(u, v, False, True) for u, v in directed]
             + [(v, u, True, False) for u, v in directed]
             + [(u, v, True, True) for u, v in bidirected]
             + [(v, u, True, True) for u, v in bidirected])

    def extend(path, head_in):
        v = path[-1]
        for s, w, head_s, head_w in steps:
            if s != v or w in path:
                continue
            if len(path) > 1:
                collider = head_in and head_s
                if (collider and v not in anc) or (not collider and v in z):
                    continue
            if w == b or extend(path + [w], head_w):
                return True
        return False

    return extend([a], False)


def test_every_statement_and_inseparable_pair_agrees_with_a_brute_force_oracle():
    # Random acyclic mixed graphs, every directed relation in use, associations
    # placed anywhere (between vertices or not) and declaration order shuffled.
    # Each statement must hold by the oracle, each non-adjacent pair that some
    # set of vertices separates must be stated and every other one listed as
    # inseparable, so the derivation is checked for soundness and completeness.
    rng = random.Random(20261003)
    rels = sorted(DIRECTED)
    stated = inseparable = 0
    for _ in range(150):
        k = rng.randint(3, 6)
        nodes = [f"v{i}" for i in range(k)]
        directed = [(nodes[i], nodes[j]) for i in range(k) for j in range(i + 1, k)
                    if rng.random() < 0.35]
        bidirected = [(nodes[i], nodes[j]) for i in range(k) for j in range(i + 1, k)
                      if rng.random() < 0.25]
        order = nodes[:]
        rng.shuffle(order)
        props = ([(a, rng.choice(rels), b) for a, b in directed]
                 + [(a, "associates", b) for a, b in bidirected])
        rng.shuffle(props)
        res = relation_theory("random", order, props).implications()

        vertices = [n for n in order if any(n in e for e in directed)]
        assert res["constructs"] == vertices
        assert res["n_bidirected"] == sum(set(e) <= set(vertices) for e in bidirected)
        joined = {frozenset(e) for e in directed + bidirected}
        want_stated, want_inseparable = [], []
        for a, b in itertools.combinations(vertices, 2):
            if frozenset((a, b)) in joined:
                continue
            others = [v for v in vertices if v not in (a, b)]
            separable = any(not _m_connected(directed, bidirected, a, b, zs)
                            for r in range(len(others) + 1)
                            for zs in itertools.combinations(others, r))
            (want_stated if separable else want_inseparable).append((a, b))
        assert [(i["a"], i["b"]) for i in res["implications"]] == want_stated
        assert [(i["a"], i["b"]) for i in res["inseparable"]] == want_inseparable
        for i in res["implications"]:
            assert not _m_connected(directed, bidirected, i["a"], i["b"], i["given"])
            # given lists vertices in declaration order
            assert i["given"] == [v for v in vertices if v in i["given"]]
        stated += len(want_stated)
        inseparable += len(want_inseparable)
    assert stated > 200
    assert inseparable > 20


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
