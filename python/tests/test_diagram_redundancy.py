import warnings

import pytest

import theoryforge as tf
import theoryforge.rigor
from theoryforge.redundancy import jaccard, tokens


def test_nomological_net_format(panic_path):
    dot = tf.read(panic_path).diagram("nomological_net")
    assert dot.startswith("digraph nomological_net {\n")
    assert dot.endswith("}\n")
    assert ('  "c_arousal" [label="Physiological\\narousal", '
            'fillcolor="#E4F1F1", color="#1E7B7B"];') in dot
    # Each edge names its proposition, so that the ids a hypothesis derives
    # from in the preregistration can be found on the figure.
    assert '  "c_arousal" -> "c_perceived_threat" [label="p1: increases"];' in dot
    assert '  "c_perceived_threat" -> "c_arousal" [label="p3: causes"];' in dot


def test_nomological_net_draws_an_association_without_arrowheads(weak_path):
    # An association states covariance with no direction (API_SPEC.md section
    # 28), so its edge has no arrowhead. A directed relation keeps its arrow.
    dot = tf.read(weak_path).diagram("nomological_net")
    assert '  "k_motivation" -> "k_drive" [label="q1: associates", dir=none];' in dot


def test_causal_dag(panic_path):
    dag = tf.read(panic_path).diagram("causal_dag")
    assert dag.startswith("dag {\n") and dag.endswith("}\n")
    assert "  c_perceived_threat -> c_arousal" in dag  # the 'causes' edge


def test_causal_dag_exports_the_graph_implications_reads():
    # Every directed relation is an edge, and an association between two
    # constructs that a directed relation names is a bidirected edge (API_SPEC.md
    # sections 5 and 27). An association touching any other construct, or joining
    # a construct to itself, is left out, as implications() leaves it out.
    t = tf.new_theory("mixed", "Mixed relations")
    for n in ("a", "b", "c", "d", "k"):
        t.add_construct(n, n.upper(), "d")
    t.add_proposition("p1", "a", "b", "mediates")
    t.add_proposition("p2", "c", "b", "moderates")
    t.add_proposition("p3", "a", "c", "associates")
    t.add_proposition("p4", "k", "a", "associates")
    t.add_proposition("p5", "b", "d", "decreases")
    t.add_proposition("p6", "d", "d", "associates")
    assert t.diagram("causal_dag") == "dag {\n  a -> b\n  c -> b\n  a <-> c\n  b -> d\n}\n"


def test_labels_keep_a_trailing_space():
    # R's strsplit() dropped the empty field after a final space, which
    # Python's str.split(" ") keeps, so the twins' DOT differed by a space. The
    # R suite asserts the same lines.
    T = {"title": "Text that ends in spaces   ",
         "boundary_conditions": ["adults  "],
         "constructs": [{"id": "c1", "label": "Physiological arousal  ", "definition": "d"}],
         "provenance": [{"step": "1", "action": "tf_construct", "detail": "Two constructs added.  "}]}
    context = tf.diagram(T, "context")
    assert '  "theory" [shape=ellipse, label="Text that ends in\\nspaces   ", ' in context
    assert '  "c1" [label="Physiological\\narousal  ", ' in context
    assert '  "scope1" [shape=note, style="filled", label="adults  ", ' in context
    assert '  "n1" [label="tf_construct\\nTwo constructs added.  "];' in tf.diagram(T, "provenance")


def test_provenance(panic_path):
    dot = tf.read(panic_path).diagram("provenance")
    assert '"n1" [label="tf_add_construct\\nRegistered three\\nconstructs."];' in dot
    assert '"n1" -> "n2";' in dot


def test_context(panic_path):
    dot = tf.read(panic_path).diagram("context")
    assert dot.startswith("digraph context {\n") and dot.endswith("}\n")
    assert ('"theory" [shape=ellipse, label="Network theory of\\npanic disorder", '
            'fillcolor="#12283A", color="#12283A", fontcolor="#FFFFFF"];') in dot
    assert '"theory" -> "c_arousal";' in dot
    assert '"scope1" -> "theory" [style=dotted, label="holds within"];' in dot
    assert '"theory" -> "alt_cognitive" [style=dashed, label="contrasts with"];' in dot


def test_workflow(panic_path):
    dot = tf.read(panic_path).diagram("workflow")
    assert dot.startswith("digraph workflow {\n") and dot.endswith("}\n")
    assert '"prop_p1" [label="p1\\nincreases", fillcolor="#FBF1DC", color="#9C6B14"];' in dot
    assert '"prop_p1" -> "pred_pred1";' in dot   # pred1 derives_from p1
    assert '"pred_pred1" -> "outcome_pred1";' in dot
    # Each proposition leads on to the construct it acts on, so the feedback
    # loop of arousal and threat shows and no outcome construct is left alone.
    assert ('  "c_arousal" -> "prop_p1";\n'
            '  "prop_p1" -> "c_perceived_threat" [style=dashed, constraint=false];\n') in dot
    assert '  "prop_p2" -> "c_avoidance" [style=dashed, constraint=false];\n' in dot
    assert '  "prop_p3" -> "c_arousal" [style=dashed, constraint=false];\n' in dot


def test_workflow_draws_an_association_without_arrowheads(weak_path):
    dot = tf.read(weak_path).diagram("workflow")
    assert '  "prop_q1" -> "k_drive" [style=dashed, constraint=false, dir=none];\n' in dot


def test_pipeline_lists_the_predictions_from_the_top_in_file_order(modality_path):
    # Under rankdir=LR, Graphviz stacks a rank from the bottom up, so the
    # predictions read upwards until an invisible chain set their order.
    dot = tf.read(modality_path).diagram("pipeline")
    assert ('  "pred4" [label="pred4\\ninterval", fillcolor="#E7EDF5", color="#33567A"];\n'
            '  { rank=same; "pred1" -> "pred2" -> "pred3" -> "pred4" [style=invis]; }\n'
            '  "result_pred2" [') in dot
    # A repeated id joins the chain once, and one prediction needs no chain.
    t = (tf.new_theory("dup", "A repeated prediction id")
         .add_prediction("h1", "Alpha.", "directional")
         .add_prediction("h2", "Beta.", "directional")
         .add_prediction("h1", "Gamma.", "directional"))
    assert '  { rank=same; "h1" -> "h2" [style=invis]; }\n' in t.diagram("pipeline")
    one = tf.new_theory("one", "One prediction").add_prediction("h1", "Alpha.", "directional")
    assert "rank=same" not in one.diagram("pipeline")


def test_venn(panic_path):
    svg = tf.read(panic_path).diagram("venn")
    assert svg.startswith("<svg ") and svg.endswith("</svg>\n")
    assert svg.count("<circle ") == 3   # three constructs
    # "Physiological arousal" takes two lines, so the circles sit a line lower.
    assert ('  <text x="110" y="45" text-anchor="middle"><tspan x="110" y="45">Physiological</tspan>'
            '<tspan x="110" y="61">arousal</tspan></text>\n') in svg
    # "adults" is the only boundary condition shared by all three constructs
    assert '<text x="190" y="176" text-anchor="middle" font-weight="bold">1</text>' in svg
    assert "constructs</tspan>" not in svg   # every construct is drawn


def test_venn_wraps_names_and_says_when_constructs_are_left_out(modality_path):
    # The names ran into each other and off the 380-pixel canvas, and the
    # figure did not say that it drew three of the five constructs.
    svg = tf.read(modality_path).diagram("venn")
    assert svg.startswith('<svg xmlns="http://www.w3.org/2000/svg" width="380" height="382" ')
    assert ('  <text x="190" y="24" text-anchor="middle" font-size="15">Construct scope overlap'
            '<tspan x="190" y="42" font-size="13">first three of 5 constructs</tspan></text>\n') in svg
    assert ('  <text x="110" y="63" text-anchor="middle"><tspan x="110" y="63">Sensorimotor</tspan>'
            '<tspan x="110" y="79">experience with a</tspan><tspan x="110" y="95">concept</tspan>'
            '</text>\n') in svg
    assert ('  <text x="190" y="340" text-anchor="middle"><tspan x="190" y="340">Cost of switching</tspan>'
            '<tspan x="190" y="356">modality between</tspan>'
            '<tspan x="190" y="372">consecutive trials</tspan></text>\n') in svg
    # A name is wrapped as written and then escaped line by line.
    t = tf.new_theory("amp", "An ampersand").add_construct("c1", "Fear & avoidance <acute>", "d")
    assert ('<tspan x="190" y="55">Fear &amp; avoidance</tspan>'
            '<tspan x="190" y="71">&lt;acute&gt;</tspan>') in t.diagram("venn")


def test_rigour(panic_path):
    svg = tf.read(panic_path).diagram("rigour")
    assert svg.startswith("<svg ") and svg.endswith("</svg>\n")
    assert "Rigour checklist" in svg and "gate pass" in svg
    assert svg.count("<rect ") == 12          # one swatch per checklist item
    assert 'fill="#4caf50"' in svg            # at least one pass (green)


def test_rigour_escapes_the_gate(panic_path, monkeypatch):
    # The gate is one of three plain words, but the grid escapes it as it
    # escapes every other value, as R's grid does.
    check = theoryforge.rigor.check
    monkeypatch.setattr(theoryforge.rigor, "check", lambda T: {**check(T), "gate": "<a & b>"})
    svg = tf.read(panic_path).diagram("rigour")
    assert '<text x="20" y="46">aggregate score 88.0, gate &lt;a &amp; b&gt;</text>' in svg


def test_severity_chart(panic_path):
    svg = tf.read(panic_path).diagram("severity")
    assert svg.startswith("<svg ") and svg.endswith("</svg>\n")
    # The bars rank the form of each claim before any data and do not measure
    # how severely a claim was tested.
    assert '<text x="20" y="26" font-size="15">Pre-data riskiness</text>' in svg
    assert "Prediction severity" not in svg
    assert svg.count("<rect ") == 4           # one bar per prediction
    assert ">pred1<" in svg


def test_unknown_diagram_raises(panic_path):
    with pytest.raises(ValueError):
        tf.read(panic_path).diagram("nope")


def test_the_engine_argument_is_deprecated(panic_path):
    t = tf.read(panic_path)
    msg = (r"the 'engine' argument of diagram\(\) has no effect and will be removed "
           r"in the next minor release")
    with pytest.warns(FutureWarning, match=msg) as rec:
        out = tf.diagram(t, "context", engine="graphviz")
    assert rec[0].filename == __file__
    with pytest.warns(FutureWarning, match=msg) as rec:
        assert t.diagram("context", engine="graphviz") == out
    assert rec[0].filename == __file__
    with warnings.catch_warnings():
        warnings.simplefilter("error")
        assert tf.diagram(t, "context") == t.diagram("context") == out


def test_tokens_and_jaccard():
    assert jaccard(tokens("the cat sat"), tokens("the cat sat")) == 1.0
    assert jaccard(tokens(""), tokens("")) == 0.0


def test_redundancy_flags_near_duplicates(weak_path):
    rows = tf.read(weak_path).redundancy_check()
    assert len(rows) == 1
    top = rows[0]
    # The Jaccard similarity, 0.8, is under 0.85, but one definition is
    # contained in the other: the overlap coefficient is 1.
    assert (top["similarity"], top["overlap"], top["flag"]) == (0.8, 1.0, "review")
