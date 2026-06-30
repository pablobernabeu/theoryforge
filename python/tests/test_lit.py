import theoryforge as tf


def _corpus(fixtures_dir):
    return tf.read_corpus(fixtures_dir / "panic-corpus.yaml")


def test_litmap_themes(fixtures_dir):
    lm = tf.litmap(_corpus(fixtures_dir))
    assert lm["n_records"] == 8
    theme_kw = {t["id"]: t["keywords"] for t in lm["themes"]}
    # ordered by smallest keyword: appraisal, arousal, avoidance, genetics
    assert [t["id"] for t in lm["themes"]] == ["theme_1", "theme_2", "theme_3", "theme_4"]
    assert theme_kw["theme_1"] == ["appraisal", "catastrophic misinterpretation"]
    assert theme_kw["theme_2"] == ["arousal", "interoception"]
    assert theme_kw["theme_4"] == ["genetics", "heritability"]


def test_litmap_cocitation(fixtures_dir):
    lm = tf.litmap(_corpus(fixtures_dir))
    edges = {(e["a"], e["b"]): e["count"] for e in lm["co_citation"]}
    assert edges[("barlow2002", "clark1986")] == 3
    assert edges[("bouton2001", "craske2008")] == 2


def test_landscape_statuses(fixtures_dir, panic_path):
    ls = tf.read(panic_path).landscape(_corpus(fixtures_dir))
    status = {t["id"]: t["status"] for t in ls["themes"]}
    assert status["theme_2"] == "crowded"          # focal (arousal) + alt_biological
    assert status["theme_4"] == "under_theorised"  # genetics: no theory addresses it
    assert ls["redundancy_risk"] == ["theme_2"]
    assert ls["under_theorised_fronts"] == ["theme_4"]
    th2 = next(t for t in ls["themes"] if t["id"] == "theme_2")
    assert th2["alternatives"] == ["alt_biological"]
    assert th2["focal"] is True


def test_lit_diagrams(fixtures_dir, panic_path):
    corpus = _corpus(fixtures_dir)
    lm = tf.litmap(corpus)
    kc = tf.lit_diagram(lm, "keyword_cooccurrence")
    assert kc.startswith("graph keyword_cooccurrence {\n")
    assert '"appraisal" -- "catastrophic misinterpretation" [label="2"];' in kc
    ls = tf.read(panic_path).landscape(corpus)
    tl = tf.lit_diagram(ls, "theme_landscape")
    assert tl.startswith("digraph theme_landscape {\n")
    assert '"focal" -> "theme_2";' in tl
    assert '"alt_biological" -> "theme_2";' in tl
