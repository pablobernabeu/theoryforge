"""Testable implications derived from the graph a theory's propositions state.

Every proposition is read through the relation table (API_SPEC.md section 28).
The directed relations (``increases``, ``decreases``, ``causes``, ``mediates``
and ``moderates``) are edges from -> to, and ``associates`` is a bidirected
edge, covariance the theory leaves unexplained, as a latent common cause of the
two constructs would. Each pair of constructs that no edge joins is
independent given some set of other constructs whenever a set m-separates the
pair (Richardson, 2003), and those statements are what data can refute. A graph
of directed edges alone is a DAG, where m-separation is d-separation and the
statements are the basis set of Pearl (1988) and Shipley (2000).
"""
from __future__ import annotations

from ._access import RELATION, enum, field, items, text
from ._graph import first_cycle, m_separated, reach
from ._relations import BIDIRECTED, DIRECTED


def _statement(a: str, b: str, given: list[str]) -> str:
    """Render one independence in the notation dagitty prints."""
    if not given:
        return f"{a} _||_ {b}"
    return f"{a} _||_ {b} | " + ", ".join(given)


def implications(T) -> dict:
    """Conditional independencies implied by the graph a theory's propositions state.

    Reads every proposition through the relation table (API_SPEC.md section
    28). A directed relation (``increases``, ``decreases``, ``causes``,
    ``mediates`` or ``moderates``) is an edge from ``from`` to ``to``, and
    ``associates`` is a bidirected edge, covariance the theory leaves
    unexplained. The constructs that a directed relation names are the
    vertices, and an association is an edge only between two of them. The
    function checks that the directed edges form no cycle and then takes every
    pair of vertices that no edge joins. The pair is stated independent given
    the parents of both when those m-separate it (Richardson, 2003), and
    otherwise given all the other ancestors of the two when those do. A pair
    that neither set separates is separated by no set of constructs
    (Richardson & Spirtes, 2002, Theorem 4.2), so the theory implies no
    independence for it, and it is listed under ``inseparable``. When every
    relation is directed, the statements are the basis set of Pearl (1988)
    and Shipley (2000), from which every other independence the graph
    implies follows.

    Returns ``{theory_id, criterion, acyclic, constructs, n_edges,
    n_bidirected, feedback, implications, n_implications, inseparable}``.
    ``criterion`` names the separation criterion, ``"m"``. ``constructs``
    lists the vertices in file order. Constructs that no directed relation
    names are left out, because silence about a construct is not a claim that
    it is independent of anything, and so are constructs without an id, which
    no proposition can name. A construct named only by associations would be a
    collider on every path through it, so leaving it out loses no statement
    about the others. ``n_edges`` counts the directed edges and
    ``n_bidirected`` the bidirected ones, a pair stated twice counting once.
    ``acyclic`` is always True and ``feedback`` always empty in a returned
    record, since a cyclic graph is refused, and both are carried so that a
    serialised record states the verdict. Each entry of ``implications`` is
    ``{a, b, given, statement}``, where ``statement`` renders the claim in the
    notation dagitty prints, ``a _||_ b | z1, z2``, and each entry of
    ``inseparable`` is ``{a, b}``. Pairs come in construct file order, as do
    the members of ``given``, so the two engines return the same records in
    the same order.

    The statements concern constructs, and a study measures them with error.
    Error in a conditioning construct leaves part of the dependence that
    holding it fixed should remove. A conditional statement tested on observed
    scores is therefore rejected too often, and more often the larger the
    sample (Westfall & Yarkoni, 2016). Take a chain whose two paths have
    standardised coefficients of .5, with the middle construct measured at a
    reliability of .8. A partial-correlation test at the 5 per cent level then
    rejects the true statement in about 14, 29 and 51 per cent of studies of
    200, 500 and 1,000 observations. Conditional statements are better tested
    with latent-variable models, such as one built on the measurement model
    that ``compile_sem()`` writes (Thoemmes et al., 2018).

    A theory with no directed relations comes back with no vertices and no
    error: ``constructs``, ``implications`` and ``inseparable`` are empty and
    ``n_implications`` is 0.

    Raises:
        ValueError: if two constructs share an id, if a directed relation names
            a construct the theory has not declared, or if the directed edges
            form a cycle, in which case the message names a cycle that was
            found. A cyclic graph also implies independencies, under
            sigma-separation, when each feedback loop has a unique
            equilibrium (Bongers et al., 2021), but this function does not
            derive them.

    References:
        Bongers, S., Forré, P., Peters, J., & Mooij, J. M. (2021). Foundations
        of structural causal models with cycles and latent variables. The
        Annals of Statistics, 49(5), 2885-2915.
        https://doi.org/10.1214/21-AOS2064
        Pearl, J. (1988). Probabilistic reasoning in intelligent systems:
        Networks of plausible inference. Morgan Kaufmann.
        Richardson, T. (2003). Markov properties for acyclic directed mixed
        graphs. Scandinavian Journal of Statistics, 30(1), 145-157.
        https://doi.org/10.1111/1467-9469.00323
        Richardson, T., & Spirtes, P. (2002). Ancestral graph Markov models.
        The Annals of Statistics, 30(4), 962-1030.
        https://doi.org/10.1214/aos/1031689015
        Shipley, B. (2000). A new inferential test for path models based on
        directed acyclic graphs. Structural Equation Modeling, 7(2), 206-218.
        https://doi.org/10.1207/S15328007SEM0702_4
        Thoemmes, F., Rosseel, Y., & Textor, J. (2018). Local fit evaluation of
        structural equation models using graphical criteria. Psychological
        Methods, 23(1), 27-41. https://doi.org/10.1037/met0000147
        Westfall, J., & Yarkoni, T. (2016). Statistically controlling for
        confounding constructs is harder than you think. PLOS ONE, 11(3),
        e0152719. https://doi.org/10.1371/journal.pone.0152719

    Example:
        A mediated chain, arousal raising perceived threat and perceived threat
        raising avoidance, commits the theory to one thing it does not state
        directly, that arousal and avoidance are independent once perceived
        threat is held fixed.

        ```python
        import theoryforge as tf

        t = tf.new_theory("mediation", "A mediated chain")
        t.add_construct("c_arousal", "Arousal", "Bodily activation.")
        t.add_construct("c_threat", "Perceived threat", "Appraised danger.")
        t.add_construct("c_avoidance", "Avoidance", "Withdrawal from the trigger.")
        t.add_proposition("p1", "c_arousal", "c_threat", "increases")
        t.add_proposition("p2", "c_threat", "c_avoidance", "increases")

        [i["statement"] for i in t.implications()["implications"]]
        # ['c_arousal _||_ c_avoidance | c_threat']
        ```

        Stating that arousal and avoidance also covary for reasons the theory
        leaves open (``t.add_proposition("p3", "c_arousal", "c_avoidance",
        "associates")``) withdraws that claim: the pair is then joined by an
        edge, and nothing is implied.
    """
    T = T.data if hasattr(T, "data") else T

    declared: list[str] = []
    position: dict[str, int] = {}
    for c in items(T, "constructs"):
        cid = text(field(c, "id"))
        # A construct without an id cannot be the endpoint of a proposition, so
        # it takes no part in the graph, and two of them do not share an id.
        if cid == "":
            continue
        # Two constructs sharing an id give the same node two sets of parents,
        # and nothing in the maths says which one a proposition meant.
        if cid in position:
            raise ValueError(
                f"implications requires unique construct ids; duplicate construct id: {cid}")
        position[cid] = len(declared)
        declared.append(cid)

    edges: list[tuple[int, int]] = []
    associations: list[tuple[str, str]] = []
    for p in items(T, "propositions"):
        rel = enum(field(p, "relation"), RELATION)
        frm, to = text(field(p, "from")), text(field(p, "to"))
        if rel in BIDIRECTED:
            associations.append((frm, to))
            continue
        if rel not in DIRECTED:
            continue
        pid = text(field(p, "id"))
        # Dropping an edge whose endpoint was never declared would shrink the
        # graph and so add independencies the theory does not imply, which is a
        # confidently wrong answer rather than a missing one.
        for endpoint in (frm, to):
            if endpoint not in position:
                raise ValueError(
                    "implications requires causal propositions between declared constructs; "
                    f"proposition '{pid}' refers to unknown construct '{endpoint}'")
        e = (position[frm], position[to])
        if e not in edges:
            edges.append(e)

    used = sorted({i for e in edges for i in e})
    nodes = [declared[i] for i in used]
    k = len(nodes)
    rank = {i: r for r, i in enumerate(used)}
    directed = [[False] * k for _ in range(k)]
    for u, v in edges:
        directed[rank[u]][rank[v]] = True
    # An association is an edge only between two vertices. A construct that
    # only associations name is a collider on every path through it, so it
    # closes them all and leaving it out changes no statement about the others.
    vertex = {cid: r for r, cid in enumerate(nodes)}
    bidirected = [[False] * k for _ in range(k)]
    n_bidirected = 0
    for frm, to in associations:
        a, b = vertex.get(frm), vertex.get(to)
        if a is None or b is None or a == b or bidirected[a][b]:
            continue
        bidirected[a][b] = bidirected[b][a] = True
        n_bidirected += 1

    cycle = first_cycle(directed, k)
    if cycle is not None:
        raise ValueError(
            "implications requires an acyclic causal graph; cycle found: "
            + " -> ".join(nodes[i] for i in cycle))

    r = reach(directed, k)
    out: list[dict] = []
    inseparable: list[dict] = []
    for i in range(k):
        for j in range(i + 1, k):
            if directed[i][j] or directed[j][i] or bidirected[i][j]:
                continue
            # The parents of the pair separate it in every DAG, so a theory of
            # directed relations alone gets the basis set. With bidirected
            # edges, a parent can be a collider that holding it fixed opens,
            # and then the ancestors of the pair are tried. When they fail,
            # every vertex on a path that connects the two is a collider and an
            # ancestor of one of them, an inducing path, so no set separates
            # the pair (API_SPEC.md section 27).
            parents = [g for g in range(k) if directed[g][i] or directed[g][j]]
            ancestors = [g for g in range(k) if (r[g][i] or r[g][j]) and g not in (i, j)]
            given = next((s for s in (parents, ancestors)
                          if m_separated(directed, bidirected, r, i, j, s)), None)
            if given is None:
                inseparable.append({"a": nodes[i], "b": nodes[j]})
                continue
            names = [nodes[g] for g in given]
            out.append({"a": nodes[i], "b": nodes[j], "given": names,
                        "statement": _statement(nodes[i], nodes[j], names)})

    return {
        "theory_id": text(T.get("id")),
        "criterion": "m",
        "acyclic": True,
        "constructs": nodes,
        "n_edges": len(edges),
        "n_bidirected": n_bidirected,
        "feedback": [],
        "implications": out,
        "n_implications": len(out),
        "inseparable": inseparable,
    }
