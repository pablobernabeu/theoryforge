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


def test_new_evidence_dois(panic_path):
    # The fixture already cites 10.1016/j.brat.2015.10.002 (evidence) and
    # 10.1016/0005-7967(86)90011-2 / 10.1176/ajp.146.2.148 (alternatives).
    candidates = [
        "10.1016/j.brat.2015.10.002",              # already cited (evidence), exact
        "https://doi.org/10.1016/0005-7967(86)90011-2",  # already cited (alternative), URL form
        "10.1176/AJP.146.2.148",                   # already cited (alternative), different case
        "10.1037/0033-2909.99.1.20",               # new
        "10.1037/0033-2909.99.1.20",               # new, duplicated in the candidate list itself
        "10.1016/j.cpr.2011.09.005",                # new
    ]
    new = tf.read(panic_path).new_evidence_dois(candidates)
    assert new == ["10.1016/j.cpr.2011.09.005", "10.1037/0033-2909.99.1.20"]


def test_new_evidence_dois_empty_theory():
    t = tf.new_theory("demo", "Demo")
    assert tf.new_evidence_dois(t.data, ["10.1000/xyz"]) == ["10.1000/xyz"]
    assert t.new_evidence_dois([]) == []
    assert t.new_evidence_dois([None, ""]) == []


def test_litmap_mixed_case_keywords_sort_by_codepoint():
    # Uppercase sorts before lowercase (Z < a). The R suite runs the same
    # corpus and asserts the same order, locking the locale-independent sort.
    corpus = {"schema_version": "1.0", "id": "mixed-case", "records": [
        {"id": "w1", "keywords": ["alpha", "Zeta"]},
        {"id": "w2", "keywords": ["Zeta", "alpha"]},
    ]}
    lm = tf.litmap(corpus)
    assert lm["keywords"] == ["Zeta", "alpha"]
    assert lm["keyword_cooccurrence"] == [{"a": "Zeta", "b": "alpha", "count": 2}]
    assert lm["themes"][0]["keywords"] == ["Zeta", "alpha"]
    assert tf.lit_diagram(lm, "keyword_cooccurrence") == (
        'graph keyword_cooccurrence {\n'
        '  graph [rankdir=LR, bgcolor="transparent", fontname="Helvetica", '
        'fontsize=11, pad="0.2", nodesep="0.3", ranksep="0.45"];\n'
        '  node [fontname="Helvetica", fontsize=11, shape=box, style="rounded,filled", '
        'color="#33567A", fillcolor="#F2F6F9", fontcolor="#12283A", penwidth=1.1, '
        'margin="0.16,0.1"];\n'
        '  edge [fontname="Helvetica", fontsize=10, color="#7B909F", '
        'fontcolor="#0F6E6E", arrowsize=0.7];\n'
        '  node [shape=ellipse, style="filled", fillcolor="#E4F1F1", color="#1E7B7B"];\n'
        '  "Zeta";\n  "alpha";\n'
        '  "Zeta" -- "alpha" [label="2"];\n}\n'
    )


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
