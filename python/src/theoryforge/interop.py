"""Reading a causal diagram written for DAGitty (API_SPEC.md section 35).

R's ``interop.R`` holds the same reader, token for token.
"""
from __future__ import annotations

from .core import Theory

# The relations an arrow can take on import: the directed relations of the
# relation table that relate two constructs and need no third.
_ARROW_RELATIONS = ("causes", "increases", "decreases")
# The characters that end a name written without quotation marks, and the
# white space, ASCII only so that R reads it alike.
_SPECIAL = set('{}[]";=,<>-')
_SPACE = set(" \t\n\r\f\v")
_GRAPH_TYPES = ("dag", "pdag", "mag", "pag", "graph", "digraph")


def _fail(message: str) -> ValueError:
    return ValueError("read_dagitty " + message)


def _tokens(text: str) -> list[tuple[str, str]]:
    """The tokens of ``text`` as ``(kind, value)`` pairs.

    The kinds are ``name`` (a quoted name loses its quotation marks), ``edge``
    (``->``, ``<-``, ``<->`` or ``--``), ``{``, ``}``, ``=`` and ``attrs`` (a
    bracketed attribute list, kept whole and then ignored). A semicolon or a
    comma separates like white space.
    """
    out: list[tuple[str, str]] = []
    i, n = 0, len(text)
    while i < n:
        ch = text[i]
        if ch in _SPACE or ch in ";,":
            i += 1
        elif ch == '"':
            end = text.find('"', i + 1)
            if end < 0:
                raise _fail("found an unclosed quotation mark")
            out.append(("name", text[i + 1:end]))
            i = end + 1
        elif ch == "[":
            depth, j = 0, i
            while j < n:
                if text[j] == '"':
                    close = text.find('"', j + 1)
                    if close < 0:
                        raise _fail("found an unclosed quotation mark")
                    j = close
                elif text[j] == "[":
                    depth += 1
                elif text[j] == "]":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            if j >= n:
                raise _fail("found an unclosed attribute list")
            out.append(("attrs", text[i:j + 1]))
            i = j + 1
        elif text.startswith("<->", i):
            out.append(("edge", "<->"))
            i += 3
        elif text.startswith("->", i) or text.startswith("<-", i) or text.startswith("--", i):
            out.append(("edge", text[i:i + 2]))
            i += 2
        elif ch in "{}=":
            out.append((ch, ch))
            i += 1
        elif ch in "<>-":
            raise _fail(f"cannot read '{ch}' at character {i + 1}")
        else:
            j = i
            while j < n and text[j] not in _SPACE and text[j] not in _SPECIAL:
                j += 1
            out.append(("name", text[i:j]))
            i = j
    return out


def _body(tokens: list[tuple[str, str]]) -> list[tuple[str, str]]:
    """The statements of the graph: inside the braces after a graph type, or all of it."""
    if not (tokens and tokens[0][0] == "name" and tokens[0][1] in _GRAPH_TYPES):
        return tokens
    k = 1
    if k < len(tokens) and tokens[k][0] == "name":
        k += 1
    if k >= len(tokens) or tokens[k][0] != "{":
        return tokens
    depth = 0
    for end in range(k, len(tokens)):
        if tokens[end][0] == "{":
            depth += 1
        elif tokens[end][0] == "}":
            depth -= 1
            if depth == 0:
                if end != len(tokens) - 1:
                    raise _fail("cannot read anything after the graph's closing brace")
                return tokens[k + 1:end]
    raise _fail("found an unclosed brace")


def read_dagitty(text: str, id: str = "dagitty-import",
                 title: str = "Causal diagram imported from DAGitty",
                 relation: str = "causes") -> Theory:
    """A theory holding the constructs and relations of a DAGitty diagram.

    ``text`` is model code as DAGitty writes it, such as
    ``dag { x -> m -> y; x <-> y }``, with or without the graph type and its
    braces. Each variable becomes a construct whose id and label are its name,
    in order of first appearance, and whose definition is left empty for the
    author to write. Each arrow becomes a proposition: ``a -> b`` and
    ``b <- a`` relate ``a`` to ``b`` by ``relation``, ``causes`` by default or
    ``increases`` or ``decreases`` when every arrow has that sign, and
    ``a <-> b`` is an association, a common cause the diagram leaves
    unexplained. A chain such as ``a -> b -> c`` gives one proposition per
    arrow, and a group in braces, as in ``a -> {b c}``, one per member.
    Propositions are numbered ``p1``, ``p2`` and so on in order of
    appearance, and a repeated edge is kept once. Bracketed attributes such
    as ``[exposure]``, ``[latent]`` or ``pos="0,1"``, and graph settings such
    as ``bb="0,0,1,1"``, are read and ignored.

    The theory is at ``draft`` maturity and records the import in its
    provenance. It does not pass validation until each construct has a
    definition, which a diagram cannot supply. ``theory.diagram("causal_dag")``
    writes the propositions back as DAGitty code.

    References:
        Textor, J., van der Zander, B., Gilthorpe, M. S., Liśkiewicz, M., &
        Ellison, G. T. H. (2016). Robust causal inference using directed
        acyclic graphs: The R package 'dagitty'. International Journal of
        Epidemiology, 45(6), 1887-1894. https://doi.org/10.1093/ije/dyw341

    Raises:
        ValueError: when ``relation`` is not ``causes``, ``increases`` or
            ``decreases``, when the diagram holds an undirected edge (``--``),
            which theoryforge has no relation for, when an edge lacks a
            variable at one end, and when a quotation mark, an attribute list
            or a brace is left open.
    """
    if not isinstance(relation, str) or relation not in _ARROW_RELATIONS:
        raise _fail("requires relation to be one of " + ", ".join(_ARROW_RELATIONS))
    if not isinstance(text, str):
        raise TypeError("read_dagitty requires the model code as a string")
    tokens = _body(_tokens(text))

    names: list[str] = []
    edges: list[tuple[str, str, str]] = []

    def declare(name: str) -> None:
        if name not in names:
            names.append(name)

    def group(k: int) -> tuple[list[str], int]:
        """The variables of the group that starts at token ``k``, and the next token's index."""
        if k < len(tokens) and tokens[k][0] == "name":
            members = [tokens[k][1]]
            k += 1
        elif k < len(tokens) and tokens[k][0] == "{":
            members = []
            k += 1
            while k < len(tokens) and tokens[k][0] != "}":
                if tokens[k][0] == "name":
                    members.append(tokens[k][1])
                elif tokens[k][0] != "attrs":
                    raise _fail("can read only variables inside a group in braces")
                k += 1
            if k >= len(tokens):
                raise _fail("found an unclosed brace")
            k += 1
        else:
            raise _fail("found an edge without a variable at one end")
        while k < len(tokens) and tokens[k][0] == "attrs":
            k += 1
        for m in members:
            declare(m)
        return members, k

    k = 0
    while k < len(tokens):
        kind = tokens[k][0]
        if kind == "name" and k + 1 < len(tokens) and tokens[k + 1][0] == "=":
            # A graph setting such as bb="0,0,1,1": its value is skipped.
            k += 3
            continue
        if kind == "edge":
            raise _fail("found an edge without a variable at one end")
        if kind in ("}", "="):
            raise _fail(f"cannot read '{tokens[k][1]}' here")
        if kind == "attrs":
            k += 1
            continue
        left, k = group(k)
        while k < len(tokens) and tokens[k][0] == "edge":
            op = tokens[k][1]
            if op == "--":
                raise _fail("cannot read an undirected edge (--); theoryforge holds directed "
                            "edges (->, <-) and associations (<->)")
            right, k = group(k + 1)
            for a in left:
                for b in right:
                    edge = ((a, b, relation) if op == "->" else (b, a, relation) if op == "<-"
                            else (a, b, "associates"))
                    if edge not in edges:
                        edges.append(edge)
            left = right

    theory = Theory({
        "schema_version": "1.1",
        "id": id,
        "title": title,
        "maturity": "draft",
        "constructs": [{"id": nm, "label": nm, "definition": ""} for nm in names],
        "propositions": [{"id": f"p{i}", "from": a, "to": b, "relation": rel}
                         for i, (a, b, rel) in enumerate(edges, start=1)],
        "provenance": [{"step": "1", "action": "tf_read_dagitty",
                        "detail": f"{len(names)} constructs, {len(edges)} propositions"}],
    })
    return theory
