"""Causal-structure analysis and testable implications (API_SPEC.md Part F).

The causal subgraph of a theory (propositions whose relation is causal) is analysed
deterministically: construct roles (exogenous/endogenous), acyclicity with a topological
order, an exhaustive enumeration of feedback loops, and, when the graph is acyclic, the
local-Markov basis set of implied conditional independencies (Pearl, 1988) — the claims
an empirical test can check without any statistical machinery. Everything is derived
from the theory object alone, with no graph library, so it runs unchanged in webR and
Pyodide and is parity-tested across languages.
"""
from __future__ import annotations

_CAUSAL = {"causes", "increases", "decreases"}


def _list(d: dict, key: str) -> list:
    v = d.get(key)
    return v if isinstance(v, list) else []


def _causal_edges(T: dict, nodes: list[str]) -> list[tuple[str, str]]:
    """Deduplicated (from, to) causal edges in proposition file order."""
    known = set(nodes)
    edges: list[tuple[str, str]] = []
    seen: set[tuple[str, str]] = set()
    for p in _list(T, "propositions"):
        if p.get("relation") not in _CAUSAL:
            continue
        f, t = p.get("from"), p.get("to")
        if f in known and t in known and (f, t) not in seen:
            seen.add((f, t))
            edges.append((f, t))
    return edges


def _kahn(nodes: list[str], edges: list[tuple[str, str]]) -> list[str]:
    """Topological order with file-order tie-breaking; [] when the graph is cyclic."""
    indeg = {n: 0 for n in nodes}
    for _, t in edges:
        indeg[t] += 1
    out = {n: [t for f, t in edges if f == n] for n in nodes}
    remaining = list(nodes)
    order: list[str] = []
    while remaining:
        head = next((n for n in remaining if indeg[n] == 0), None)
        if head is None:
            return []
        remaining.remove(head)
        order.append(head)
        for t in out[head]:
            indeg[t] -= 1
    return order


def _feedback_loops(nodes: list[str], edges: list[tuple[str, str]]) -> list[list[str]]:
    """Every simple cycle, each reported once, starting at its lowest-index node.

    For each start node s (ascending construct index), a depth-first search over
    nodes of index >= index(s) extends a simple path; an edge back to s closes a
    loop. Neighbours are taken in edge file order, so discovery order is
    deterministic.
    """
    idx = {n: i for i, n in enumerate(nodes)}
    out = {n: [t for f, t in edges if f == n] for n in nodes}
    loops: list[list[str]] = []

    def walk(s: str, node: str, path: list[str]) -> None:
        for t in out[node]:
            if t == s:
                loops.append(list(path))
            elif idx[t] > idx[s] and t not in path:
                path.append(t)
                walk(s, t, path)
                path.pop()

    for s in nodes:
        walk(s, s, [s])
    return loops


def _descendants(node: str, out: dict[str, list[str]]) -> set[str]:
    seen: set[str] = set()
    stack = list(out[node])
    while stack:
        n = stack.pop()
        if n not in seen:
            seen.add(n)
            stack.extend(out[n])
    return seen


def implications(T) -> dict:
    """Analyse the theory's causal structure and derive its testable implications.

    Returns ``{constructs, exogenous, endogenous, acyclic, order, feedback_loops,
    implications, n_implications}``. The implied conditional independencies are
    the local-Markov basis set — each construct is independent of its
    non-descendants given its direct causes — and are only derivable when the
    causal graph is acyclic; for cyclic (feedback) theories the loops themselves
    are enumerated instead, since each loop is a testable dynamic claim.

    References:
        Pearl, J. (1988). Probabilistic reasoning in intelligent systems.
        Morgan Kaufmann.
    """
    T = T.data if hasattr(T, "data") else T
    nodes = [c.get("id") for c in _list(T, "constructs")]
    edges = _causal_edges(T, nodes)

    incoming = {t for _, t in edges}
    exogenous = [n for n in nodes if n not in incoming]
    endogenous = [n for n in nodes if n in incoming]

    order = _kahn(nodes, edges)
    acyclic = len(order) == len(nodes)
    loops = _feedback_loops(nodes, edges)

    claims: list[dict] = []
    if acyclic:
        out = {n: [t for f, t in edges if f == n] for n in nodes}
        parents = {n: sorted({f for f, t in edges if t == n}) for n in nodes}
        emitted: set[frozenset] = set()
        for v in nodes:
            desc = _descendants(v, out)
            for u in nodes:
                if u == v or u in desc or u in parents[v]:
                    continue
                pair = frozenset((v, u))
                if pair in emitted:
                    continue
                emitted.add(pair)
                claims.append({"a": v, "b": u, "given": list(parents[v])})

    return {
        "constructs": nodes,
        "exogenous": exogenous,
        "endogenous": endogenous,
        "acyclic": acyclic,
        "order": order if acyclic else [],
        "feedback_loops": loops,
        "implications": claims,
        "n_implications": len(claims),
    }
