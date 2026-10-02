import pytest

import theoryforge as tf


def test_simulate_records_every_knob(panic_path):
    # Two runs differing only in k produce different numbers, so a record that
    # omitted k could not be reproduced from what it reports.
    t = tf.read(panic_path)
    r = t.simulate(steps=3, dt=0.2, k=0.75, damping=0.25, init=2.0)
    assert list(r) == ["states", "dt", "steps", "k", "damping", "init", "method", "ignored",
                       "opposed", "trajectory"]
    assert (r["dt"], r["steps"], r["k"], r["damping"], r["init"]) == (0.2, 3, 0.75, 0.25, 2.0)
    # At k = 1.5 the feedback loop grows fast enough for three Euler steps of
    # 0.2 to fall short of the exact solution by more than 5 per cent.
    with pytest.warns(UserWarning, match="depart from the exact solution"):
        other = t.simulate(steps=3, dt=0.2, k=1.5, damping=0.25, init=2.0)
    assert other["trajectory"] != r["trajectory"]


def test_simulate_refuses_duplicate_construct_ids():
    # R indexed the first occurrence and Python the last, so the same file gave
    # two different trajectories.
    t = tf.new_theory("dupe", "Duplicated ids")
    t.add_construct("c1", "One", "d").add_construct("c1", "One again", "d")
    with pytest.raises(ValueError) as exc:
        t.simulate()
    assert str(exc.value) == "simulate requires unique construct ids; duplicate construct id: c1"


_STEPS_MSG = "simulate requires steps to be a whole number of at least 0"


@pytest.mark.parametrize("knobs, message", [
    # R ran two steps for 2.5 and echoed 2.5, Python raised TypeError; R
    # stopped on -1 while Python returned one row; True ran one step in both.
    ({"steps": 2.5}, _STEPS_MSG),
    ({"steps": -1}, _STEPS_MSG),
    ({"steps": True}, _STEPS_MSG),
    ({"steps": float("nan")}, _STEPS_MSG),
    ({"steps": float("inf")}, _STEPS_MSG),
    ({"steps": "3"}, _STEPS_MSG),
    # A negative dt was accepted by both; NaN gave NaN rows in R and a raw
    # ValueError from rnd() in Python.
    ({"dt": 0}, "simulate requires dt to be a finite number greater than 0"),
    ({"dt": -0.1}, "simulate requires dt to be a finite number greater than 0"),
    ({"dt": float("nan")}, "simulate requires dt to be a finite number greater than 0"),
    ({"dt": float("inf")}, "simulate requires dt to be a finite number greater than 0"),
    ({"dt": True}, "simulate requires dt to be a finite number greater than 0"),
    ({"k": float("nan")}, "simulate requires k to be a finite number"),
    ({"k": float("-inf")}, "simulate requires k to be a finite number"),
    ({"k": "1"}, "simulate requires k to be a finite number"),
    ({"damping": float("nan")}, "simulate requires damping to be a finite number"),
    ({"damping": None}, "simulate requires damping to be a finite number"),
    # R recycled init = c(1, 2, 3) into nine-value rows; Python raised TypeError.
    ({"init": [1.0, 2.0, 3.0]}, "simulate requires init to be a single finite number"),
    ({"init": float("nan")}, "simulate requires init to be a single finite number"),
    ({"init": False}, "simulate requires init to be a single finite number"),
])
def test_simulate_refuses_invalid_knobs(panic_path, knobs, message):
    # The R suite asserts the same messages for the same knobs.
    t = tf.read(panic_path)
    with pytest.raises(ValueError) as exc:
        t.simulate(**knobs)
    assert str(exc.value) == message


def test_simulate_accepts_whole_steps_of_any_integral_type(panic_path):
    np = pytest.importorskip("numpy")
    t = tf.read(panic_path)
    ref = t.simulate(steps=3)["trajectory"]
    # An integral float runs as many steps as the integer and is echoed as given.
    r = t.simulate(steps=3.0)
    assert r["trajectory"] == ref and r["steps"] == 3.0 and isinstance(r["steps"], float)
    # numpy integers are not int but are numbers.Integral.
    assert t.simulate(steps=np.int64(3))["trajectory"] == ref
    assert t.simulate(steps=0)["trajectory"] == [[1.0, 1.0, 1.0]]


def test_simulate_stops_with_the_step_and_state_where_it_diverges(panic_path):
    # Within the app's own ranges. Python raised OverflowError from rnd() at
    # step 228, where 1e6 times the state first exceeds the double range, and
    # R returned rows of Inf and then NaN. Both twins now stop at that step.
    t = tf.read(panic_path)
    with pytest.raises(ValueError) as exc:
        t.simulate(steps=240, dt=2, k=10, damping=0, init=10)
    assert str(exc.value) == (
        "simulate diverged at step 228: state 'c_arousal' is not finite; reduce dt or k"
    )
    # One step fewer runs to completion with every value finite, and warns
    # that the Euler steps have left the exact solution.
    with pytest.warns(UserWarning, match="depart from the exact solution"):
        r = t.simulate(steps=227, dt=2, k=10, damping=0, init=10)
    assert len(r["trajectory"]) == 228


def test_simulate_sums_each_product_left_to_right():
    # CPython 3.12+'s sum() compensates rounding error, while R adds the
    # products left to right, so in fast-growing regimes the twins drifted
    # apart beyond the 1e-9 parity tolerance (421 of this run's values). R and
    # a left fold give -69972264.681408 here, compensated sum() ...409. The R
    # suite asserts the same value with expect_identical().
    t = tf.new_theory("fb", "Feedback")
    for c in "abcde":
        t.add_construct(c, c.upper(), "d")
    edges = [("a", "b", "increases"), ("b", "c", "causes"), ("c", "a", "increases"),
             ("a", "c", "increases"), ("a", "d", "increases"), ("b", "d", "increases"),
             ("c", "d", "decreases"), ("e", "d", "increases"), ("d", "a", "decreases"),
             ("d", "e", "increases")]
    for i, (f, to, rel) in enumerate(edges, 1):
        t.add_proposition(f"p{i}", f, to, rel)
    with pytest.warns(UserWarning, match="depart from the exact solution"):
        r = t.simulate(steps=500, k=1, dt=0.1)
    assert r["trajectory"][341][3] == -69972264.681408


def test_simulate_deterministic(panic_path):
    r = tf.read(panic_path).simulate(steps=5, dt=0.1)
    assert r["states"] == ["c_arousal", "c_perceived_threat", "c_avoidance"]
    assert len(r["trajectory"]) == 6  # steps + 1
    assert r["trajectory"][0] == [1.0, 1.0, 1.0]
    assert tf.read(panic_path).simulate(steps=5, dt=0.1) == r  # deterministic


def test_simulate_inert_when_uncoupled(weak_path):
    # weak-demo's only proposition is associative (sign 0) -> pure damping decay, equal states
    r = tf.read(weak_path).simulate(steps=3)
    last = r["trajectory"][-1]
    assert last[0] == last[1]  # both constructs decay identically


def test_embedding_redundancy_with_fake_embedder(weak_path):
    vocab = ["drive", "internal", "goals", "act", "person"]

    def embed(s):
        s = s.lower()
        return [float(s.count(w)) for w in vocab]

    rows = tf.read(weak_path).embedding_redundancy(embed)
    assert rows and "cosine" in rows[0]
    assert {rows[0]["a"], rows[0]["b"]} == {"k_motivation", "k_drive"}


def test_embedding_redundancy_refuses_unequal_length_vectors():
    # R recycled the shorter vector and Python truncated the longer, two
    # confident wrong cosines from the same embedder. The R suite asserts the
    # same message.
    t = tf.new_theory("t", "T")
    t.add_construct("c1", "One", "one two").add_construct("c2", "Two", "three")
    vecs = {"one two": [1.0, 2.0], "three": [1.0, 2.0, 3.0]}
    with pytest.raises(ValueError) as exc:
        t.embedding_redundancy(lambda d: vecs[d])
    assert str(exc.value) == (
        "embedding_redundancy requires equal-length nonempty embedding vectors; "
        "constructs c1 and c2 have lengths 2 and 3"
    )


def test_osf_push_dry_run(panic_path):
    out = tf.read(panic_path).osf_push()
    assert out["dry_run"] is True
    assert out["request"]["filename"] == "panic-network-2026.dossier.md"
    assert out["request"]["method"] == "PUT"


def test_osf_push_filename_falls_back_when_id_is_null_or_empty():
    # A null id must not stringify into 'None.dossier.md' (nor an empty one
    # into '.dossier.md'); R falls back to 'theory.dossier.md' in both cases.
    for d in ({"id": None, "title": "T"}, {"id": "", "title": "T"}, {"title": "T"}):
        out = tf.Theory(dict(d)).osf_push()
        assert out["request"]["filename"] == "theory.dossier.md"


def test_osf_push_percent_encodes_filename(panic_path):
    # Mirrors the R tf_osf_push test so the dry-run request dicts stay
    # parity-identical for filenames with reserved characters.
    out = tf.read(panic_path).osf_push(node="abc12", filename="my theory&notes.md")
    assert "name=my%20theory%26notes.md" in out["request"]["url"]
    assert out["request"]["filename"] == "my theory&notes.md"


def test_render_report_writes_qmd(panic_path, tmp_path):
    p = tf.read(panic_path).render_report(tmp_path / "report")
    assert p.endswith(".qmd")
    text = open(p, encoding="utf-8").read()
    assert text.startswith("---\ntitle:")
    assert "## Rigour checklist" in text
    assert "# Preregistration:" in text
