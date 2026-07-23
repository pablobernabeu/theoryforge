"""Native rendering of the diagram intermediate representations.

The IR itself (:func:`theoryforge.diagram.diagram`) stays dependency-free and
byte-identical to the R twin; rendering is a language-native convenience layered
on top, so it sits outside the cross-language parity contract and its dependency
is an extra (``pip install theoryforge[render]``). The R twin offers the same
convenience through the DiagrammeR package (``tf_render_diagram()``).
"""

from __future__ import annotations

from .diagram import diagram as _diagram

_DOT_TYPES = ("nomological_net", "provenance", "development_roadmap",
              "pipeline", "context", "workflow")
_SVG_TYPES = ("venn", "rigour", "severity")


class SVGString(str):
    """An SVG document as a plain string that displays itself in notebooks.

    The chart views (``venn``, ``rigour``, ``severity``) are emitted directly as
    SVG, so no rendering engine is involved; this subclass only adds the
    ``_repr_svg_`` hook Jupyter uses to draw it inline.
    """

    def _repr_svg_(self) -> str:  # pragma: no cover - notebook display hook
        return str(self)


def render_diagram(x, type: str = "nomological_net"):
    """Render a digraph view without leaving Python.

    Where :func:`theoryforge.diagram.diagram` returns the deterministic Graphviz
    DOT string, ``render_diagram`` wraps it in a ``graphviz.Source``, which
    displays inline in Jupyter and renders to a file with its ``render`` method.
    Requires the optional `graphviz <https://pypi.org/project/graphviz/>`_
    library (``pip install theoryforge[render]``) and, to write image files, the
    Graphviz system binaries.

    The three chart views (``venn``, ``rigour`` and ``severity``) are already
    SVG, so they come back as an :class:`SVGString`, which also displays inline
    in Jupyter. The ``causal_dag`` view emits dagitty syntax rather than DOT, so
    it is not rendered here; paste it into a dagitty tool instead.

    Parameters
    ----------
    x:
        A :class:`~theoryforge.core.Theory`, a parsed theory mapping, or a
        diagram IR string from ``diagram()`` or ``lit_diagram()``, so literature
        diagrams render the same way.
    type:
        The diagram type, as in ``diagram()``. Ignored when ``x`` is already an
        IR string.

    Returns
    -------
    graphviz.Source or SVGString
        A ``graphviz.Source`` for the digraph views; an :class:`SVGString` for
        the chart views.
    """
    if isinstance(x, str):
        ir = x
        if ir.lstrip().startswith("<svg"):
            return SVGString(ir)
        if ir.lstrip().startswith("dag"):
            raise ValueError(
                "this is dagitty syntax (the causal_dag view), not Graphviz DOT; "
                "render it with a dagitty tool such as dagitty.net."
            )
    else:
        if type == "causal_dag":
            raise ValueError(
                "the causal_dag view emits dagitty syntax, not Graphviz DOT; "
                "render diagram(x, 'causal_dag') with a dagitty tool such as "
                "dagitty.net."
            )
        if type in _SVG_TYPES:
            return SVGString(_diagram(x, type=type))
        if type not in _DOT_TYPES:
            # Delegate to diagram() for its canonical unknown-type error.
            _diagram(x, type=type)
        ir = _diagram(x, type=type)

    try:
        import graphviz
    except ImportError as err:
        raise ImportError(
            "render_diagram() needs the optional 'graphviz' library; install it "
            "with pip install theoryforge[render], or use diagram() and render "
            "the DOT string with any Graphviz tool."
        ) from err
    return graphviz.Source(ir)
