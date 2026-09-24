"""Testable implications derived from a theory's causal subgraph.

The causal propositions of a theory (``causes``, ``increases``, ``decreases``)
form a directed graph over the constructs they connect. When that graph is
acyclic it entails a set of conditional independencies, and the basis set is the
smallest such set from which every other implied independence follows: one
statement per non-adjacent pair of constructs, conditioning on the parents of
both (Pearl, 1988; Shipley, 2000). Those statements are what the theory commits
to and what data can refute.
"""
from __future__ import annotations

_CAUSAL = {"causes", "increases", "decreases"}


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def _str(v) -> str:
    return str(v if v is not None else "")


def _first_cycle(adj: list[list[bool]], k: int) -> list[int] | None:
    """Indices of the first cycle found, or None when the graph is acyclic.

    A depth-first search that takes start nodes and successors in construct file
    order, so the cycle reported for a given theory is the same one in both
    engines. The returned path repeats its first node at the end, and a self
    loop comes back as that node twice.
    """
    colour = [0] * k  # 0 unvisited, 1 on the current path, 2 finished
    for start in range(k):
        if colour[start] != 0:
            continue
        colour[start] = 1
        path = [start]
        stack = [[start, 0]]  # node, successors already examined
        while stack:
            top = stack[-1]
            v, nxt = top[0], top[1]
            if nxt < k:
                top[1] = nxt + 1
                if adj[v][nxt]:
                    if colour[nxt] == 1:
                        return path[path.index(nxt):] + [nxt]
                    if colour[nxt] == 0:
                        colour[nxt] = 1
                        path.append(nxt)
                        stack.append([nxt, 0])
            else:
                colour[v] = 2
                stack.pop()
                path.pop()
    return None


def _statement(a: str, b: str, given: list[str]) -> str:
    """Render one independence in the notation dagitty prints."""
    if not given:
        return f"{a} _||_ {b}"
    return f"{a} _||_ {b} | " + ", ".join(given)


def implications(T) -> dict:
    """Conditional independencies implied by a theory's causal subgraph.

    Reads the propositions whose relation is causal (``causes``, ``increases``,
    ``decreases``) as directed edges over the constructs they connect, checks
    that the resulting graph is acyclic, and returns its basis set: for every
    pair of non-adjacent constructs, the claim that the two are independent
    given the parents of both (Pearl, 1988; Shipley, 2000). A basis set implies
    every other conditional independence the graph entails, so it is the shortest
    complete statement of what the theory forbids in data.

    Returns ``{theory_id, acyclic, constructs, n_edges, implications,
    n_implications}``. ``constructs`` lists, in file order, the constructs that
    a causal proposition connects; constructs the theory says nothing causal
    about are left out, because silence about a construct is not a claim that it
    is independent of anything. ``acyclic`` is always True in a returned record,
    since a cyclic graph is refused, and is carried so that a serialised record
    states the verdict rather than leaving a reader to infer that the check ran.
    Each entry of ``implications`` is ``{a, b, given, statement}``, where
    ``statement`` renders the claim in the notation dagitty prints,
    ``a _||_ b | z1, z2``. Pairs come in construct file order, as do the members
    of ``given``, so the two engines return the same records in the same order.

    A theory with no causal propositions comes back with an empty basis set and
    no error: ``constructs`` and ``implications`` are empty and ``n_implications``
    is 0.

    Raises:
        ValueError: if two constructs share an id, if a causal proposition names
            a construct the theory has not declared, or if the causal graph has a
            cycle, in which case no basis set is defined and the message names a
            cycle that was found.

    References:
        Pearl, J. (1988). Probabilistic reasoning in intelligent systems:
        Networks of plausible inference. Morgan Kaufmann.
        Shipley, B. (2000). A new inferential test for path models based on
        directed acyclic graphs. Structural Equation Modeling, 7(2), 206-218.
        https://doi.org/10.1207/S15328007SEM0702_4

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
    """
    T = T.data if hasattr(T, "data") else T

    declared: list[str] = []
    position: dict[str, int] = {}
    for c in _list(T, "constructs"):
        cid = _str(c.get("id"))
        # Two constructs sharing an id give the same node two sets of parents,
        # and nothing in the maths says which one a proposition meant.
        if cid in position:
            raise ValueError(
                f"implications requires unique construct ids; duplicate construct id: {cid}")
        position[cid] = len(declared)
        declared.append(cid)

    edges: list[tuple[int, int]] = []
    for p in _list(T, "propositions"):
        if p.get("relation") not in _CAUSAL:
            continue
        pid = _str(p.get("id"))
        frm, to = _str(p.get("from")), _str(p.get("to"))
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
    adj = [[False] * k for _ in range(k)]
    for u, v in edges:
        adj[rank[u]][rank[v]] = True

    cycle = _first_cycle(adj, k)
    if cycle is not None:
        raise ValueError(
            "implications requires an acyclic causal graph; cycle found: "
            + " -> ".join(nodes[i] for i in cycle))

    parents = [[j for j in range(k) if adj[j][i]] for i in range(k)]
    out: list[dict] = []
    for i in range(k):
        for j in range(i + 1, k):
            if adj[i][j] or adj[j][i]:
                continue
            # In a DAG neither member of a non-adjacent pair can be a parent of
            # the other, so the union needs no further exclusion.
            given = [nodes[g] for g in sorted(set(parents[i]) | set(parents[j]))]
            out.append({"a": nodes[i], "b": nodes[j], "given": given,
                        "statement": _statement(nodes[i], nodes[j], given)})

    return {
        "theory_id": _str(T.get("id")),
        "acyclic": True,
        "constructs": nodes,
        "n_edges": len(edges),
        "implications": out,
        "n_implications": len(out),
    }
