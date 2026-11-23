"""read_dagitty() (API_SPEC.md section 35). The R suite (test-interop.R) mirrors these tests,
and the parity check compares the two readers on fixtures/edge/dagitty.cases.json."""
import pytest

import theoryforge as tf


def _edges(theory) -> set:
    return {(p["from"], p["to"], "associates" if p["relation"] == "associates" else "directed")
            for p in theory.data.get("propositions", [])}


def test_a_diagram_becomes_constructs_and_propositions():
    t = tf.read_dagitty('dag { a [exposure] a -> "b c" -> d; e <- a; a <-> d; f -> {a d} }')
    assert [c["id"] for c in t.data["constructs"]] == ["a", "b c", "d", "e", "f"]
    assert [(p["id"], p["from"], p["to"], p["relation"]) for p in t.data["propositions"]] == [
        ("p1", "a", "b c", "causes"), ("p2", "b c", "d", "causes"), ("p3", "a", "e", "causes"),
        ("p4", "a", "d", "associates"), ("p5", "f", "a", "causes"), ("p6", "f", "d", "causes")]
    assert t.data["maturity"] == "draft"
    assert t.data["provenance"] == [{"step": "1", "action": "tf_read_dagitty",
                                     "detail": "5 constructs, 6 propositions"}]
    # A diagram cannot supply definitions, so the theory does not validate yet.
    with pytest.raises(ValueError, match="construct\\[0\\] missing/empty definition"):
        t.validate()


@pytest.mark.parametrize("name", ["panic-network.theory.yaml", "modality-switching.theory.yaml"])
def test_the_causal_dag_export_reads_back_as_the_same_edges(name):
    t = tf.read(tf.example_path(name))
    back = tf.read_dagitty(t.diagram("causal_dag"))
    assert _edges(back) == _edges(t)


def test_arrows_take_the_relation_asked_for_and_refuse_what_theoryforge_cannot_hold():
    assert tf.read_dagitty("x -> y", relation="decreases").data["propositions"][0]["relation"] == \
        "decreases"
    with pytest.raises(ValueError, match="^read_dagitty requires relation to be one of causes, "
                                         "increases, decreases$"):
        tf.read_dagitty("x -> y", relation="mediates")
    with pytest.raises(ValueError, match=r"undirected edge \(--\)"):
        tf.read_dagitty("x -- y")
