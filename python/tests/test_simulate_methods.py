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
    assert list(r) == ["states", "dt", "steps", "k", "damping", "init", "method", "ignored",
                       "opposed", "trajectory"]
    assert (r["method"], r["ignored"], r["opposed"]) == ("euler", [], [])
    assert t.simulate(steps=2, method="exact")["method"] == "exact"


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
