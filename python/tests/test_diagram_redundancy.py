import theoryforge as tf
from theoryforge.redundancy import tokens, jaccard
import pytest


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
