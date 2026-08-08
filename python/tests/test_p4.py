import pytest

import theoryforge as tf


def test_simulate_records_every_knob(panic_path):
    # Two runs differing only in k produce different numbers, so a record that
    # omitted k could not be reproduced from what it reports.
    t = tf.read(panic_path)
    r = t.simulate(steps=3, dt=0.2, k=0.75, damping=0.25, init=2.0)
    assert list(r) == ["states", "dt", "steps", "k", "damping", "init", "trajectory"]
    assert (r["dt"], r["steps"], r["k"], r["damping"], r["init"]) == (0.2, 3, 0.75, 0.25, 2.0)
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


def test_osf_push_dry_run(panic_path):
    out = tf.read(panic_path).osf_push()
    assert out["dry_run"] is True
    assert out["request"]["filename"] == "panic-network-2026.dossier.md"
    assert out["request"]["method"] == "PUT"


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
