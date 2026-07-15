import pytest

import theoryforge as tf
from theoryforge.redundancy import jaccard, tokens


def test_nomological_net_format(panic_path):
    dot = tf.read(panic_path).diagram("nomological_net")
    assert dot.startswith("digraph nomological_net {\n")
    assert dot.endswith("}\n")
    assert '  "c_arousal" [label="Physiological arousal"];' in dot
    assert '  "c_arousal" -> "c_perceived_threat" [label="increases"];' in dot


def test_causal_dag(panic_path):
    dag = tf.read(panic_path).diagram("causal_dag")
    assert dag.startswith("dag {\n") and dag.endswith("}\n")
    assert "  c_perceived_threat -> c_arousal" in dag  # the 'causes' edge


def test_provenance(panic_path):
    dot = tf.read(panic_path).diagram("provenance")
    assert '"n1" [label="tf_construct: Registered three constructs."];' in dot
    assert '"n1" -> "n2";' in dot


def test_context(panic_path):
    dot = tf.read(panic_path).diagram("context")
    assert dot.startswith("digraph context {\n") and dot.endswith("}\n")
    assert '"theory" [shape=ellipse, label="Network theory of panic disorder"];' in dot
    assert '"theory" -> "c_arousal";' in dot
    assert '"scope1" -> "theory" [style=dotted, label="holds within"];' in dot
    assert '"theory" -> "alt_cognitive" [style=dashed, label="contrasts with"];' in dot


def test_workflow(panic_path):
    dot = tf.read(panic_path).diagram("workflow")
    assert dot.startswith("digraph workflow {\n") and dot.endswith("}\n")
    assert '"prop_p1" [label="increases"];' in dot
    assert '"prop_p1" -> "pred_pred1";' in dot   # pred1 derives_from p1
    assert '"pred_pred1" -> "outcome_pred1";' in dot


def test_venn(panic_path):
    svg = tf.read(panic_path).diagram("venn")
    assert svg.startswith("<svg ") and svg.endswith("</svg>\n")
    assert svg.count("<circle ") == 3   # three constructs
    # "adults" is the only boundary condition shared by all three constructs
    assert '<text x="190" y="160" text-anchor="middle" font-weight="bold">1</text>' in svg


def test_rigour(panic_path):
    svg = tf.read(panic_path).diagram("rigour")
    assert svg.startswith("<svg ") and svg.endswith("</svg>\n")
    assert "Rigour checklist" in svg and "gate pass" in svg
    assert svg.count("<rect ") == 12          # one swatch per checklist item
    assert 'fill="#4caf50"' in svg            # at least one pass (green)


def test_severity_chart(panic_path):
    svg = tf.read(panic_path).diagram("severity")
    assert svg.startswith("<svg ") and svg.endswith("</svg>\n")
    assert "Prediction severity" in svg
    assert svg.count("<rect ") == 3           # one bar per prediction
    assert ">pred1<" in svg


def test_unknown_diagram_raises(panic_path):
    with pytest.raises(ValueError):
        tf.read(panic_path).diagram("nope")


def test_tokens_and_jaccard():
    assert jaccard(tokens("the cat sat"), tokens("the cat sat")) == 1.0
    assert jaccard(tokens(""), tokens("")) == 0.0


def test_redundancy_flags_near_duplicates(weak_path):
    rows = tf.read(weak_path).redundancy_check()
    assert rows  # at least one pair
    top = rows[0]
    assert top["similarity"] >= 0.5  # the two near-identical definitions
