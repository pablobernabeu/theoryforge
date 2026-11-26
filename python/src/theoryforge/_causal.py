"""The causal graph a theory's propositions state (API_SPEC.md sections 27 and 31).

``implications()``, ``entailments()``, ``equivalent_models()`` and
``discriminate()`` read the same graph, built here once. R's ``causal.R`` holds
the same routine.
"""
from __future__ import annotations

from ._access import RELATION, enum, field, items, text
from ._relations import BIDIRECTED, DIRECTED, RELATIONS


def declared_constructs(T: dict, caller: str) -> list[str]:
    """The construct ids in file order, refusing a repeated id.

    A construct without an id cannot be the endpoint of a proposition, so it
    is skipped, and two of them are no repeat.
    """
    declared: list[str] = []
    seen: set[str] = set()
    for c in items(T, "constructs"):
        cid = text(field(c, "id"))
        if cid == "":
            continue
        if cid in seen:
            raise ValueError(f"{caller} requires unique construct ids; duplicate construct id: {cid}")
        seen.add(cid)
        declared.append(cid)
    return declared


def causal_graph(T: dict, caller: str, propositions=None) -> dict:
    """The directed mixed graph of a theory's propositions.

    ``propositions`` replaces the theory's own propositions when given, which
    is how a rival stated inside an alternative is read over the theory's
    constructs. Returns ``nodes``, the ``directed`` and ``bidirected`` adjacency
    matrices, ``sign`` (for each directed edge, +1, -1 or None when its
    propositions fix no single sign), ``edge_props`` and ``assoc_props`` (the
    proposition ids behind each edge, in file order), the counts
    ``n_edges`` and ``n_bidirected`` and ``edges``, the kept ordered pairs in
    the order first stated. The vertices are the constructs that some
    proposition relates to another, in construct file order. ``latent`` is
    True for a vertex whose construct has ``x_latent: true``, the mark
    ``read_dagitty()`` keeps for an unobserved variable.
    """
    declared = declared_constructs(T, caller)
    position = {cid: i for i, cid in enumerate(declared)}
    props = items(T, "propositions") if propositions is None else propositions

    edges: list[tuple[int, int]] = []
    pair_sign: dict[tuple[int, int], int | None] = {}
    pair_props: dict[tuple[int, int], list[str]] = {}
    associations: list[tuple[str, str, str]] = []
    for p in props:
        rel = enum(field(p, "relation"), RELATION)
        frm, to = text(field(p, "from")), text(field(p, "to"))
        pid = text(field(p, "id"))
        if rel not in DIRECTED and rel not in BIDIRECTED:
            continue
        # Dropping an edge whose endpoint was never declared would shrink the
        # graph and so add independencies the theory does not imply.
        for endpoint in (frm, to):
            if endpoint not in position:
                kind = "causal propositions" if rel in DIRECTED else "associations"
                raise ValueError(
                    f"{caller} requires {kind} between declared constructs; "
                    f"proposition '{pid}' refers to unknown construct '{endpoint}'")
        if rel in BIDIRECTED:
            associations.append((frm, to, pid))
            continue
        e = (position[frm], position[to])
        s = RELATIONS[rel][1]
        if e not in pair_sign:
            edges.append(e)
            pair_sign[e] = s
            pair_props[e] = [pid]
        else:
            # Two propositions on one ordered pair fix a sign only when they agree.
            if pair_sign[e] != s:
                pair_sign[e] = None
            pair_props[e].append(pid)

    # Every construct a proposition relates to another is a vertex. A construct
    # no proposition names is left out, since silence about it is no claim.
    used = sorted({i for e in edges for i in e}
                  | {position[c] for frm, to, _ in associations if frm != to for c in (frm, to)})
    nodes = [declared[i] for i in used]
    k = len(nodes)
    latent_ids = {text(field(c, "id")) for c in items(T, "constructs") if field(c, "x_latent") is True}
    rank = {i: r for r, i in enumerate(used)}
    directed = [[False] * k for _ in range(k)]
    sign: list[list[int | None]] = [[None] * k for _ in range(k)]
    edge_props: dict[tuple[int, int], list[str]] = {}
    for u, v in edges:
        directed[rank[u]][rank[v]] = True
        sign[rank[u]][rank[v]] = pair_sign[(u, v)]
        edge_props[(rank[u], rank[v])] = pair_props[(u, v)]
    vertex = {cid: r for r, cid in enumerate(nodes)}
    bidirected = [[False] * k for _ in range(k)]
    assoc_props: dict[tuple[int, int], list[str]] = {}
    n_bidirected = 0
    for frm, to, pid in associations:
        # An association of a construct with itself adds nothing, and its
        # construct is a vertex only when another proposition relates it to another.
        if frm == to:
            continue
        a, b = vertex[frm], vertex[to]
        key = (min(a, b), max(a, b))
        if not bidirected[a][b]:
            bidirected[a][b] = bidirected[b][a] = True
            n_bidirected += 1
            assoc_props[key] = []
        assoc_props[key].append(pid)

    return {
        "nodes": nodes,
        "directed": directed,
        "bidirected": bidirected,
        "sign": sign,
        "edges": [(rank[u], rank[v]) for u, v in edges],
        "edge_props": edge_props,
        "assoc_props": assoc_props,
        "n_edges": len(edges),
        "n_bidirected": n_bidirected,
        "latent": [cid in latent_ids for cid in nodes],
    }
