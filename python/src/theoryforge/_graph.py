"""Graph routines behind implications() (API_SPEC.md section 27).

A graph has the vertices 0 to k - 1. ``directed[u][v]`` is True for an edge
u -> v, and ``bidirected[u][v]``, kept symmetric, for an edge u <-> v. R's
``graph.R`` holds the same routines.

References:
    Bongers, S., Forré, P., Peters, J., & Mooij, J. M. (2021). Foundations of
    structural causal models with cycles and latent variables. The Annals of
    Statistics, 49(5), 2885-2915. https://doi.org/10.1214/21-AOS2064
    Richardson, T. (2003). Markov properties for acyclic directed mixed graphs.
    Scandinavian Journal of Statistics, 30(1), 145-157.
    https://doi.org/10.1111/1467-9469.00323
"""
from __future__ import annotations

from itertools import compress


def first_cycle(directed: list[list[bool]], k: int) -> list[int] | None:
    """Indices of the first cycle found, or None when the graph is acyclic.

    A depth-first search that takes start vertices and successors in vertex
    order, so the cycle reported for a given theory is the same one in both
    engines. The returned path repeats its first vertex at the end, and a self
    loop comes back as that vertex twice.
    """
    colour = [0] * k  # 0 unvisited, 1 on the current path, 2 finished
    for start in range(k):
        if colour[start] != 0:
            continue
        colour[start] = 1
        path = [start]
        stack = [[start, 0]]  # vertex, successors already examined
        while stack:
            top = stack[-1]
            v, nxt = top[0], top[1]
            if nxt < k:
                top[1] = nxt + 1
                if directed[v][nxt]:
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


def reach(directed: list[list[bool]], k: int) -> list[list[bool]]:
    """``r[u][v]`` is True when a directed path leads from u to v.

    A path may have no edges, so every vertex reaches itself, and ``r[u][v]``
    then reads "u is v or an ancestor of v".
    """
    succ = [list(compress(range(k), row)) for row in directed]
    r = [[False] * k for _ in range(k)]
    for s in range(k):
        row = r[s]
        row[s] = True
        stack = [s]
        while stack:
            for v in succ[stack.pop()]:
                if not row[v]:
                    row[v] = True
                    stack.append(v)
    return r


def strong_components(r: list[list[bool]]) -> list[list[int]]:
    """The strongly connected components of a graph whose ``reach()`` is ``r``.

    Two vertices share a component when each reaches the other. The members of
    a component come in vertex order and the components in the order of their
    first members, so both engines list them alike. A vertex on no cycle is a
    component of its own.
    """
    k = len(r)
    seen = [False] * k
    out = []
    for i in range(k):
        if seen[i]:
            continue
        comp = [j for j in range(k) if r[i][j] and r[j][i]]
        for j in comp:
            seen[j] = True
        out.append(comp)
    return out


def acyclify(directed: list[list[bool]], bidirected: list[list[bool]],
             comps: list[list[int]]) -> tuple[list[list[bool]], list[list[bool]]]:
    """The acyclification of a directed mixed graph (Bongers et al., 2021, Def. A.13).

    ``comps`` are the strongly connected components of ``directed``. In the
    result, j -> i when j is a parent of some member of i's component and lies
    outside it, so every member of a feedback loop shares the loop's outside
    parents. i <-> j, for i and j distinct, when the two share a component or
    some member of i's component and some member of j's are joined by a
    bidirected edge. Sigma-separation in the original graph is m-separation in
    this acyclic one (Proposition A.19).
    """
    k = len(directed)
    comp_of = [0] * k
    for c, comp in enumerate(comps):
        for v in comp:
            comp_of[v] = c
    # Whether some member of component c has the parent j, and whether some
    # members of components c and d are joined by a bidirected edge.
    parent_of_comp = [[False] * k for _ in comps]
    joined = [[False] * len(comps) for _ in comps]
    for u in range(k):
        for v in range(k):
            if directed[u][v]:
                parent_of_comp[comp_of[v]][u] = True
            if bidirected[u][v]:
                joined[comp_of[u]][comp_of[v]] = True
    d_acy = [[parent_of_comp[comp_of[i]][j] and comp_of[j] != comp_of[i] for i in range(k)]
             for j in range(k)]
    b_acy = [[i != j and (comp_of[i] == comp_of[j] or joined[comp_of[i]][comp_of[j]])
              for j in range(k)] for i in range(k)]
    return d_acy, b_acy


class MixedGraph:
    """A directed mixed graph prepared for m-separation queries.

    ``parents[v]`` lists the parents of v in vertex order, and ``ends[v]`` the
    edges at v as (w, arrowhead at v, arrowhead at w). Both are built once, so
    that a query reads the edges at a vertex without scanning every vertex.
    """

    __slots__ = ("k", "parents", "ends")

    def __init__(self, directed: list[list[bool]], bidirected: list[list[bool]]) -> None:
        k = len(directed)
        self.k = k
        children = [list(compress(range(k), row)) for row in directed]
        self.parents: list[list[int]] = [[] for _ in range(k)]
        for u in range(k):
            for v in children[u]:
                self.parents[v].append(u)
        self.ends: list[list[tuple[int, bool, bool]]] = [
            [(w, False, True) for w in children[v]]
            + [(w, True, False) for w in self.parents[v]]
            + [(w, True, True) for w in compress(range(k), bidirected[v])]
            for v in range(k)]

    def without_edges(self, u: int, targets: list[int]) -> MixedGraph:
        """The same graph without the directed edges from u to the vertices in ``targets``."""
        out = MixedGraph.__new__(MixedGraph)
        out.k = self.k
        out.parents = list(self.parents)
        out.ends = list(self.ends)
        drop = set(targets)
        out.ends[u] = [e for e in self.ends[u] if not (e[0] in drop and not e[1] and e[2])]
        for v in drop:
            out.parents[v] = [p for p in self.parents[v] if p != u]
            out.ends[v] = [e for e in self.ends[v] if not (e[0] == u and e[1] and not e[2])]
        return out


def reached(adjacent: list[list[int]], seeds, k: int, base: bytearray | None = None) -> bytearray:
    """Marks the seeds and every vertex the lists in ``adjacent`` lead to from one.

    With each vertex's parents in ``adjacent``, the marks are the seeds and
    their ancestors, and with its children, the seeds and their descendants.
    The marks in ``base`` are kept, and every vertex they lead to must be
    marked there too, as in a result of this function.
    """
    mark = bytearray(k) if base is None else bytearray(base)
    stack = [s for s in seeds if not mark[s]]
    for s in stack:
        mark[s] = 1
    while stack:
        for u in adjacent[stack.pop()]:
            if not mark[u]:
                mark[u] = 1
                stack.append(u)
    return mark


def m_separated(g: MixedGraph, x: int, y: int, given: list[int]) -> bool:
    """Whether x and y are m-separated in ``g`` given the vertices in ``given``.

    A path between x and y connects them given Z when every collider on it, a
    vertex into which both of its edges on the path point, is in Z or an
    ancestor of a member of Z, and no other vertex on it is in Z (Richardson,
    2003). Without bidirected edges, this is d-separation. ``given`` holds
    neither x nor y.

    The search walks the graph over the states (vertex, whether the walk
    arrived through an arrowhead), so each state is visited once and no path
    is enumerated. A walk that passes the tests at every step can be shortened,
    and detoured through Z at each collider outside Z, into a path that passes
    them, so the walk reaches y exactly when a connecting path exists. Every
    vertex of a connecting path is an ancestor of x, y or a member of Z, since
    from a vertex that is not a collider the path leads along its edges'
    directions to x, y or a collider. The walk therefore keeps to those
    ancestors, which leaves its result unchanged.
    """
    k, ends = g.k, g.ends
    in_z = bytearray(k)
    for z in given:
        in_z[z] = 1
    ancestor_of_z = reached(g.parents, given, k)
    region = reached(g.parents, (x, y), k, ancestor_of_z)
    seen = (bytearray(k), bytearray(k))  # arrived by a tail, by an arrowhead
    stack = [(w, head_w) for w, _, head_w in ends[x] if region[w]]
    while stack:
        v, head_in = stack.pop()
        if seen[head_in][v]:
            continue
        seen[head_in][v] = 1
        if v == y:
            return False
        collider_open = head_in and ancestor_of_z[v]
        passes = not in_z[v]
        if not (collider_open or passes):
            continue
        for w, head_v, head_w in ends[v]:
            # A walk that returns to x can start from x afresh, and those starts
            # are already on the stack.
            if w == x or not region[w] or seen[head_w][w]:
                continue
            if collider_open if head_in and head_v else passes:
                stack.append((w, head_w))
    return True
