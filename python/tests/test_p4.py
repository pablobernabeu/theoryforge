import theoryforge as tf


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


def test_render_report_writes_qmd(panic_path, tmp_path):
    p = tf.read(panic_path).render_report(tmp_path / "report")
    assert p.endswith(".qmd")
    text = open(p, encoding="utf-8").read()
    assert text.startswith("---\ntitle:")
    assert "## Rigour checklist" in text
    assert "# Preregistration:" in text
