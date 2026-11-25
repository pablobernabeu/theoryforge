"""simulate(method = ...): the exact propagator, the Euler departure warning and the
record of what the coupling matrix leaves out (API_SPEC section 22).

The R suite (test-simulate.R) asserts the same values and messages.
"""
import math
import warnings

import pytest

import theoryforge as tf

EULER_WARNING = ("simulate: the Euler steps depart from the exact solution by more than "
                 "5 per cent; use method 'exact' or a smaller dt")


def _regulation():
    # The example of workflow-modes.md: J has eigenvalues -1.5 and +-0.866i,
    # a sustained oscillation with period 7.26.
    return (tf.new_theory("regulation_demo", "Arousal regulated by avoidance")
            .add_construct("arousal", "Physiological arousal", "bodily activation")
            .add_construct("threat", "Perceived threat", "appraised danger")
            .add_construct("avoidance", "Avoidance behaviour", "protective withdrawal")
            .add_proposition("p1", "arousal", "threat", "increases")
            .add_proposition("p2", "threat", "avoidance", "increases")
            .add_proposition("p3", "avoidance", "arousal", "decreases"))


def _feedback():
    t = tf.new_theory("fb", "Feedback")
    for c in "abcde":
        t.add_construct(c, c.upper(), "d")
    edges = [("a", "b", "increases"), ("b", "c", "causes"), ("c", "a", "increases"),
             ("a", "c", "increases"), ("a", "d", "increases"), ("b", "d", "increases"),
             ("c", "d", "decreases"), ("e", "d", "increases"), ("d", "a", "decreases"),
             ("d", "e", "increases")]
    for i, (f, to, rel) in enumerate(edges, 1):
        t.add_proposition(f"p{i}", f, to, rel)
    return t


@pytest.mark.parametrize("method", ["rk4", "Exact", "", None, 1, ["exact"]])
def test_simulate_refuses_an_unknown_method(panic_path, method):
    with pytest.raises(ValueError) as exc:
        tf.read(panic_path).simulate(method=method)
    assert str(exc.value) == "simulate requires method to be one of: euler, exact"


def test_simulate_records_the_method_and_what_it_leaves_out(panic_path):
    t = tf.read(panic_path)
    r = t.simulate(steps=2)
    assert list(r) == ["states", "dt", "steps", "k", "damping", "init", "initial_state", "method",
                       "ignored", "assumed_positive", "opposed", "trajectory"]
    assert (r["method"], r["ignored"], r["opposed"]) == ("euler", [], [])
    # p3 states that perceived threat causes arousal, without a sign. The
    # coupling is positive by assumption, and that alone makes the loop grow.
    assert r["assumed_positive"] == ["p3"]
    assert t.simulate(steps=2, method="exact")["method"] == "exact"


def _fan():
    # a reaches each of b to e by one relation, and three propositions couple
    # nothing.
    t = tf.new_theory("signs", "Signs")
    for c in "abcde":
        t.add_construct(c, c.upper(), "d")
    for pid, to, rel in [("p1", "b", "increases"), ("p2", "c", "decreases"), ("p3", "d", "causes"),
                         ("p4", "e", "mediates"), ("p5", "zz", "causes"), ("p6", "b", "moderates")]:
        t.add_proposition(pid, "a", to, rel)
    return t.add_proposition("p7", "b", "c", "associates")


def test_simulate_reads_the_signs_from_the_relation_table():
    # increases and decreases carry the table's signs. causes and mediates
    # carry none and are coupled at +k, and the record lists them in file
    # order. A coupling to an undeclared construct is ignored and assumes
    # nothing.
    from theoryforge._relations import PATHS

    assert PATHS == frozenset({"increases", "decreases", "causes", "mediates"})
    r = _fan().simulate(steps=1, dt=1, damping=0, init={"a": 1})
    assert r["trajectory"][1] == [1.0, 1.0, -1.0, 1.0, 1.0]
    assert r["assumed_positive"] == ["p3", "p4"]
    assert r["ignored"] == ["p5", "p6", "p7"]


def test_simulate_starts_from_a_mapping_for_an_impulse_response(panic_path):
    # A construct the mapping leaves out starts from 0, so one entry gives the
    # response to an impulse in that construct. The mapping is echoed as given
    # and initial_state holds every starting value, in the order of states.
    t = tf.read(panic_path)
    r = t.simulate(steps=2, init={"c_avoidance": 2, "c_arousal": 0.5}, method="exact")
    assert r["init"] == {"c_avoidance": 2, "c_arousal": 0.5}
    assert r["initial_state"] == [0.5, 0.0, 2.0]
    assert r["trajectory"][0] == [0.5, 0.0, 2.0]
    # Constructs with the same incoming couplings now part: arousal and
    # threat no longer follow one path.
    impulse = t.simulate(steps=5, init={"c_arousal": 1}, method="exact")["trajectory"]
    assert impulse[5][0] != impulse[5][1]
    assert t.simulate(steps=1, init={})["trajectory"] == [[0.0, 0.0, 0.0]] * 2


def test_simulate_refuses_a_mapping_that_names_an_unknown_construct(panic_path):
    # Checked once the theory is read, after the duplicate ids, in the order
    # of the mapping. The R suite asserts the same message.
    with pytest.raises(ValueError) as exc:
        tf.read(panic_path).simulate(init={"c_arousal": 1, "arousal": 1, "zz": 2})
    assert str(exc.value) == ("simulate requires init to name declared constructs; unknown "
                              "construct id: arousal")


def test_exact_decays_where_euler_explodes(weak_path):
    # weak-demo decays at rate 2.5. With dt = 1 the Euler step multiplies each
    # state by 1 - 2.5 = -1.5, so it explodes with alternating sign, while the
    # exact solution is exp(-2.5 t).
    t = tf.read(weak_path)
    exact = t.simulate(steps=3, dt=1, damping=2.5, method="exact")["trajectory"]
    assert [row[0] for row in exact] == [1.0, 0.082085, 0.006738, 0.000553]
    with pytest.warns(UserWarning) as rec:
        euler = t.simulate(steps=3, dt=1, damping=2.5)["trajectory"]
    assert [str(w.message) for w in rec] == [EULER_WARNING]
    assert [row[0] for row in euler] == [1.0, -1.5, 2.25, -3.375]


def test_exact_keeps_the_oscillation_that_euler_inflates():
    # dt * ||J||_inf is 0.15 here, so a step-size rule would not have caught
    # it, but Euler inflates the oscillatory mode by 1.0037 per step: 8.54
    # against 1.33 over the last period of 500 steps.
    t = _regulation()
    exact = t.simulate(steps=500, method="exact")["trajectory"]
    assert max(abs(x) for row in exact[-73:] for x in row) < 1.4
    with pytest.warns(UserWarning, match="depart from the exact solution"):
        euler = t.simulate(steps=500)["trajectory"]
    assert max(abs(x) for row in euler[-73:] for x in row) > 8


def test_euler_does_not_warn_when_it_tracks_the_exact_solution(panic_path):
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        tf.read(panic_path).simulate()
        _regulation().simulate(steps=5)


def test_the_euler_warning_does_not_depend_on_the_unit_of_init(weak_path, panic_path):
    # With dt = 1, the Euler run of weak-demo is 18 per cent off the exact one
    # at the first step and a factor of 7 off at the tenth, whatever init is.
    # The departure is measured against the largest absolute starting value
    # as well as the exact state, so a start at 0.2 warns as a start at 1 does.
    t = tf.read(weak_path)
    for init in (1.0, 0.2, -0.01):
        with pytest.warns(UserWarning) as rec:
            t.simulate(steps=10, dt=1, init=init)
        assert [str(w.message) for w in rec] == [EULER_WARNING]
    # A run that tracks the exact solution stays silent at any scale.
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        for init in (100.0, 0.01):
            tf.read(panic_path).simulate(init=init)


def test_exact_ignores_the_step_size_for_stability(weak_path):
    # Inside the app's ranges (dt 2, damping 5), where Euler multiplies by -9.
    r = tf.read(weak_path).simulate(steps=4, dt=2, damping=5, method="exact")
    assert r["trajectory"][1][0] == round(math.exp(-10), 6) == 4.5e-05
    assert r["trajectory"][4] == [0.0, 0.0]


def test_exact_trajectory_is_pinned_bit_for_bit():
    # The R suite asserts the same numbers with expect_identical(), so the
    # two twins' propagators agree to the last bit after rounding.
    r = _feedback().simulate(steps=40, dt=0.5, method="exact")
    assert r["trajectory"][40] == EXACT_FB_ROW_40
    assert r["trajectory"][7][3] == EXACT_FB_ROW_7_D


def test_exact_stops_where_the_system_itself_diverges(panic_path):
    t = tf.read(panic_path)
    with pytest.raises(ValueError) as exc:
        t.simulate(steps=240, dt=2, k=10, damping=0, init=10, method="exact")
    assert str(exc.value) == EXACT_DIVERGENCE
    # Damping beyond the largest eigenvalue of A, the remedy the message names
    # first, makes the same run decay to zero.
    r = t.simulate(steps=240, dt=2, k=10, damping=11, init=10, method="exact")
    assert r["trajectory"][240] == [0.0, 0.0, 0.0]


def test_exact_handles_steps_zero_and_an_empty_theory(panic_path):
    assert tf.read(panic_path).simulate(steps=0, method="exact")["trajectory"] == [[1.0, 1.0, 1.0]]
    empty = tf.new_theory("empty", "No constructs").simulate(steps=2, method="exact")
    assert empty["trajectory"] == [[], [], []]


def test_simulate_names_ignored_propositions_and_opposed_pairs():
    t = (tf.new_theory("rec", "Record")
         .add_construct("a", "A", "d").add_construct("b", "B", "d").add_construct("c", "C", "d")
         .add_proposition("p1", "a", "b", "increases")
         .add_proposition("p2", "a", "b", "decreases")
         .add_proposition("p3", "a", "c", "moderates")
         .add_proposition("p4", "b", "c", "associates")
         .add_proposition("p5", "a", "zz", "increases")
         .add_proposition("p6", "b", "c", "causes")
         .add_proposition("p7", "b", "c", "decreases")
         .add_proposition("p8", "a", "b", "increases")
         .add_proposition("p9", "c", "b", "mediates"))
    r = t.simulate(steps=1)
    assert r["ignored"] == ["p3", "p4", "p5"]
    assert r["opposed"] == [["a", "b"], ["b", "c"]]


def test_propagator_agrees_with_scipy():
    from theoryforge.simulate import _propagator

    np = pytest.importorskip("numpy")
    linalg = pytest.importorskip("scipy.linalg")
    J = [[-0.5, 0.0, -1.0], [1.0, -0.5, 0.0], [0.0, 1.0, -0.5]]
    for dt in (0.001, 0.1, 2.0, 37.0):
        E = np.array(_propagator(J, dt))
        ref = linalg.expm(np.array(J) * dt)
        assert np.abs(E - ref).max() / max(1.0, np.abs(ref).max()) < 1e-13


def test_propagator_of_a_non_finite_matrix_is_nan():
    from theoryforge.simulate import _propagator

    # dt * k beyond the double range: no halving brings the norm down, so the
    # propagator is NaN and the first step diverges.
    E = _propagator([[0.0, 1e308], [1e308, 0.0]], 10.0)
    assert all(math.isnan(x) for row in E for x in row)


# Pinned from this implementation. The R suite asserts the same values, so the
# twins agree to the last bit after rounding.
EXACT_FB_ROW_40 = [-60572.780936, -56901.703303, -110132.328974, -45888.470406, -42217.392773]
EXACT_FB_ROW_7_D = 3.837653
# The panic network at k = 10 has an eigenvalue of +10, so the exact solution
# itself grows by exp(20) per step and leaves the double range at step 35.
EXACT_DIVERGENCE = ("simulate diverged at step 35: state 'c_arousal' is not finite; "
                    "raise damping, reduce k or take fewer steps")


def _triple_loop(A, B):
    """A times B by the loop over i, j and m that API_SPEC section 22 states."""
    n = len(A)
    out = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(n):
            acc = 0.0
            for m in range(n):
                acc = acc + A[i][m] * B[m][j]
            out[i][j] = acc
    return out


def test_the_matrix_product_gives_the_triple_loops_bits():
    # The product skips a term only when one factor is 0 and the other finite,
    # which leaves a sum unchanged. Zeros of both signs, infinities and NaN
    # check that nothing else is skipped. The R suite makes the same check.
    import random
    import struct

    from theoryforge.simulate import _matmul

    rng = random.Random(5)
    special = [0.0, -0.0, math.inf, -math.inf, math.nan, 5e-324, 1e308]
    for _ in range(300):
        n = rng.randint(1, 7)
        A, B = ([[rng.choice(special) if rng.random() < 0.15 else
                  (rng.uniform(-2, 2) if rng.random() < 0.4 else 0.0) for _ in range(n)]
                 for _ in range(n)] for _ in range(2))
        got, want = _matmul(A, B), _triple_loop(A, B)
        assert [[struct.pack("<d", x) for x in row] for row in got] == \
            [[struct.pack("<d", x) for x in row] for row in want]


def test_a_theory_of_400_constructs_simulates():
    # A chain: the first state has no couplings into it, so it decays at the
    # damping rate, exactly with method "exact" and by 1 - dt * damping per step
    # with Euler.
    t = tf.new_theory("chain", "Chain")
    for i in range(400):
        t = t.add_construct(f"c{i}", f"C{i}", "A state.")
    for i in range(399):
        t = t.add_proposition(f"p{i}", f"c{i}", f"c{i + 1}", "increases")
    exact = t.simulate(method="exact")["trajectory"]
    assert [row[0] for row in exact] == pytest.approx([math.exp(-0.05 * s) for s in range(11)],
                                                      abs=1e-6)
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        euler = t.simulate()["trajectory"]
    assert [row[0] for row in euler] == pytest.approx([0.95 ** s for s in range(11)], abs=1e-6)
    assert len(euler) == 11 and len(euler[10]) == 400


def test_numpy_float32_knobs_give_the_trajectory_of_the_equal_floats():
    # The knobs are computed with as doubles, as R holds them, so a float32
    # gives the bits of the double it equals, with either method. They are
    # echoed as given.
    np = pytest.importorskip("numpy")
    import struct

    t = (tf.new_theory("f32", "Float32").add_construct("a", "A", "d").add_construct("b", "B", "d")
         .add_construct("c", "C", "d").add_proposition("p1", "a", "b", "increases")
         .add_proposition("p2", "b", "c", "decreases"))
    for method in ("euler", "exact"):
        for knobs in ({"dt": 0.3, "k": 1.7, "damping": 0.0}, {"dt": 0.5, "k": 1.0, "damping": 0.2}):
            given = {name: np.float32(value) for name, value in knobs.items()}
            equal = {name: float(value) for name, value in given.items()}
            with warnings.catch_warnings():
                warnings.simplefilter("ignore")
                a = tf.simulate(t, steps=8, init=1234.56789, method=method, **given)
                b = tf.simulate(t, steps=8, init=1234.56789, method=method, **equal)
            assert [[struct.pack("<d", x) for x in row] for row in a["trajectory"]] == \
                [[struct.pack("<d", x) for x in row] for row in b["trajectory"]]
            assert a["dt"] is given["dt"]
