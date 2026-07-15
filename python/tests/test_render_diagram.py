"""render_diagram() is a language-native convenience over the deterministic IR,
so these tests cover the wrapper contract (dispatch, guard rails), not the
rendering engine itself. The graphviz library is optional, so engine-dependent
tests skip where it is absent; the SVG and error paths need nothing."""

import pytest

import theoryforge as tf
from theoryforge.render import SVGString, render_diagram


def demo_theory():
    return (
        tf.new_theory("demo", "Demo theory")
        .add_construct("a", "Alpha", "the first thing")
        .add_construct("b", "Beta", "the second different thing")
        .add_proposition("p1", "a", "b", "increases")
    )


def test_digraph_views_wrap_the_ir_in_a_graphviz_source():
    graphviz = pytest.importorskip("graphviz")
    t = demo_theory()
    src = render_diagram(t, "nomological_net")
    assert isinstance(src, graphviz.Source)
    assert t.diagram("nomological_net").strip() in src.source


def test_the_theory_method_matches_the_function():
    graphviz = pytest.importorskip("graphviz")
    t = demo_theory()
    assert isinstance(t.render_diagram("workflow"), graphviz.Source)


def test_a_raw_dot_string_renders_so_literature_diagrams_render_too():
    graphviz = pytest.importorskip("graphviz")
    dot = demo_theory().diagram("pipeline")
    assert isinstance(render_diagram(dot), graphviz.Source)


def test_svg_chart_views_come_back_as_a_displayable_string():
    t = demo_theory()
    svg = render_diagram(t, "venn")
    assert isinstance(svg, SVGString)
    assert svg == t.diagram("venn")
    # A raw SVG string passes through the same way.
    assert render_diagram(t.diagram("rigour")) == t.diagram("rigour")


def test_causal_dag_and_unknown_types_are_refused_with_guidance():
    t = demo_theory()
    with pytest.raises(ValueError, match="dagitty"):
        render_diagram(t, "causal_dag")
    with pytest.raises(ValueError, match="dagitty"):
        render_diagram(t.diagram("causal_dag"))
    with pytest.raises(ValueError):
        render_diagram(t, "no_such_view")


def test_missing_graphviz_is_reported_with_install_guidance(monkeypatch):
    import builtins

    real_import = builtins.__import__

    def no_graphviz(name, *args, **kwargs):
        if name == "graphviz":
            raise ImportError("No module named 'graphviz'")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", no_graphviz)
    with pytest.raises(ImportError, match=r"theoryforge\[render\]"):
        render_diagram(demo_theory(), "workflow")
